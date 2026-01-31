#!/usr/bin/env node

/**
 * Copilot Agent Watcher
 *
 * This script monitors the GitHub Copilot Agent session state to detect when
 * the agent is waiting for user input. It watches the events.jsonl files
 * in the session-state directory.
 *
 * Usage:
 *   node copilot-watcher.mjs [--poll-interval=1000] [--notify]
 *
 * The agent is considered "waiting for user response" when:
 * 1. There's an active session with events
 * 2. The last event is "assistant.turn_end"
 * 3. No subsequent "user.message" event exists
 * 4. The assistant's last message had no toolRequests (finished its work)
 */

import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import {exec} from 'node:child_process';

const COPILOT_DIR = process.env.HOME + '/.copilot';
const SESSION_STATE_DIR = path.join(COPILOT_DIR, 'session-state');

// Configuration
const POLL_INTERVAL = parseInt(process.argv.find(a => a.startsWith('--poll-interval='))?.split('=')[1] || '2000');
const NOTIFY = process.argv.includes('--notify');
const VERBOSE = process.argv.includes('--verbose');

/**
 * Parse JSONL file and return array of events
 */
function parseJsonl(content) {
    const lines = content
        .trim()
        .split('\n')
        .filter(line => line.trim());
    const events = [];
    for (const line of lines) {
        try {
            events.push(JSON.parse(line));
        } catch (e) {
            // Skip malformed lines
        }
    }
    return events;
}

/**
 * Get the session workspace.yaml info
 */
function getWorkspaceInfo(sessionPath) {
    const workspacePath = path.join(sessionPath, 'workspace.yaml');
    if (!fs.existsSync(workspacePath)) return null;

    const content = fs.readFileSync(workspacePath, 'utf8');
    const info = {};

    // Simple YAML parsing for our needs
    const lines = content.split('\n');
    for (const line of lines) {
        const match = line.match(/^(\w+):\s*(.*)$/);
        if (match) {
            info[match[1]] = match[2].trim();
        }
    }

    return info;
}

/**
 * Analyze events to determine session state
 */
function analyzeSessionState(events) {
    if (!events || events.length === 0) {
        return {status: 'empty', reason: 'No events'};
    }

    const lastEvent = events[events.length - 1];
    const eventTypes = events.map(e => e.type);

    // Find indices of key events
    const lastUserMessageIdx = eventTypes.lastIndexOf('user.message');
    const lastTurnEndIdx = eventTypes.lastIndexOf('assistant.turn_end');
    const lastTurnStartIdx = eventTypes.lastIndexOf('assistant.turn_start');
    const lastMessageIdx = eventTypes.lastIndexOf('assistant.message');

    // Check if agent is currently processing (turn started but not ended)
    if (lastTurnStartIdx > lastTurnEndIdx) {
        return {
            status: 'processing',
            reason: 'Agent is actively working',
            turnId: events[lastTurnStartIdx]?.data?.turnId,
        };
    }

    // Check if waiting for user input
    if (lastTurnEndIdx > lastUserMessageIdx || (lastTurnEndIdx >= 0 && lastUserMessageIdx === -1)) {
        // Find the assistant message before turn_end
        let waitingForInput = false;
        let lastAssistantMessage = null;

        // Walk backwards from turn_end to find the message
        for (let i = lastTurnEndIdx - 1; i >= 0; i--) {
            if (events[i].type === 'assistant.message') {
                lastAssistantMessage = events[i];
                // If no tool requests, the agent finished and is waiting for user
                if (!events[i].data?.toolRequests?.length) {
                    waitingForInput = true;
                }
                break;
            }
            if (events[i].type === 'assistant.turn_start') {
                break; // Stop searching
            }
        }

        if (waitingForInput) {
            return {
                status: 'waiting_for_user',
                reason: 'Agent completed turn, awaiting user response',
                lastMessage: lastAssistantMessage?.data?.content?.slice(0, 200),
                timestamp: lastEvent.timestamp,
            };
        } else {
            return {
                status: 'ready',
                reason: 'Turn ended, agent ready for more input',
                timestamp: lastEvent.timestamp,
            };
        }
    }

    // User message is the last relevant event - agent should respond
    if (lastUserMessageIdx > lastTurnEndIdx) {
        return {
            status: 'user_waiting',
            reason: 'User sent message, waiting for agent',
            timestamp: events[lastUserMessageIdx]?.timestamp,
        };
    }

    return {
        status: 'unknown',
        reason: 'Unable to determine state',
        lastEventType: lastEvent.type,
    };
}

/**
 * Get all active sessions and their states
 */
function getActiveSessions() {
    const sessions = [];

    if (!fs.existsSync(SESSION_STATE_DIR)) {
        return sessions;
    }

    const entries = fs.readdirSync(SESSION_STATE_DIR, {withFileTypes: true});

    for (const entry of entries) {
        const sessionPath = path.join(SESSION_STATE_DIR, entry.name);

        // Check for folder-based sessions (with events.jsonl)
        if (entry.isDirectory()) {
            const eventsPath = path.join(sessionPath, 'events.jsonl');
            if (fs.existsSync(eventsPath)) {
                try {
                    const content = fs.readFileSync(eventsPath, 'utf8');
                    const events = parseJsonl(content);
                    const state = analyzeSessionState(events);
                    const workspaceInfo = getWorkspaceInfo(sessionPath);

                    sessions.push({
                        id: entry.name,
                        type: 'folder',
                        path: sessionPath,
                        eventsPath,
                        eventCount: events.length,
                        state,
                        workspace: workspaceInfo,
                        lastModified: fs.statSync(eventsPath).mtime,
                    });
                } catch (e) {
                    if (VERBOSE) console.error(`Error reading ${eventsPath}:`, e.message);
                }
            }
        }
        // Check for simple JSONL sessions
        else if (entry.name.endsWith('.jsonl')) {
            try {
                const content = fs.readFileSync(sessionPath, 'utf8');
                const events = parseJsonl(content);
                const state = analyzeSessionState(events);

                sessions.push({
                    id: entry.name.replace('.jsonl', ''),
                    type: 'jsonl',
                    path: sessionPath,
                    eventCount: events.length,
                    state,
                    lastModified: fs.statSync(sessionPath).mtime,
                });
            } catch (e) {
                if (VERBOSE) console.error(`Error reading ${sessionPath}:`, e.message);
            }
        }
    }

    // Sort by last modified (most recent first)
    sessions.sort((a, b) => b.lastModified - a.lastModified);

    return sessions;
}

/**
 * Send a macOS notification
 */
function sendNotification(title, message) {
    if (process.platform === 'darwin') {
        const script = `display notification "${message.replace(/"/g, '\\"')}" with title "${title.replace(/"/g, '\\"')}"`;
        exec(`osascript -e '${script}'`);
    }
}

/**
 * Format timestamp for display
 */
function formatTimestamp(ts) {
    if (!ts) return 'N/A';
    const date = new Date(ts);
    return date.toLocaleTimeString();
}

/**
 * Get status emoji
 */
function getStatusEmoji(status) {
    switch (status) {
        case 'waiting_for_user':
            return '🔔';
        case 'processing':
            return '⚙️ ';
        case 'user_waiting':
            return '⏳';
        case 'ready':
            return '✅';
        default:
            return '❓';
    }
}

/**
 * Main display loop
 */
function displayStatus() {
    const sessions = getActiveSessions();

    // Clear screen for clean display
    console.clear();

    console.log('╔════════════════════════════════════════════════════════════════════════╗');
    console.log('║               🤖 GitHub Copilot Agent Session Monitor                  ║');
    console.log('╠════════════════════════════════════════════════════════════════════════╣');
    console.log(
        `║  Poll Interval: ${POLL_INTERVAL}ms | Sessions Found: ${sessions.length.toString().padEnd(3)} | ${new Date().toLocaleTimeString()}     ║`,
    );
    console.log('╚════════════════════════════════════════════════════════════════════════╝');
    console.log('');

    if (sessions.length === 0) {
        console.log('  No active sessions found.');
        console.log('');
        console.log('  Session state directory: ' + SESSION_STATE_DIR);
        return;
    }

    // Show only most recent sessions (up to 5)
    const recentSessions = sessions.slice(0, 5);

    for (const session of recentSessions) {
        const emoji = getStatusEmoji(session.state.status);
        const project = session.workspace?.repository || session.workspace?.cwd?.split('/').pop() || 'Unknown';
        const summary = session.workspace?.summary?.slice(0, 50) || '';

        console.log(`┌─────────────────────────────────────────────────────────────────────────┐`);
        console.log(`│ ${emoji} Session: ${session.id.slice(0, 36)}...`);
        console.log(`│   Project: ${project}`);
        console.log(`│   Status:  ${session.state.status.toUpperCase().padEnd(20)} (${session.state.reason})`);
        console.log(`│   Events:  ${session.eventCount} | Modified: ${session.lastModified.toLocaleTimeString()}`);
        if (summary) {
            console.log(`│   Summary: ${summary}...`);
        }
        if (session.state.lastMessage) {
            console.log(`│   Last:    "${session.state.lastMessage.slice(0, 60)}..."`);
        }
        console.log(`└─────────────────────────────────────────────────────────────────────────┘`);
        console.log('');
    }

    // Check for waiting sessions and notify
    const waitingSessions = sessions.filter(s => s.state.status === 'waiting_for_user');
    if (waitingSessions.length > 0 && NOTIFY) {
        for (const session of waitingSessions) {
            const project = session.workspace?.repository || 'Copilot Session';
            sendNotification('Copilot Waiting', `${project}: Agent is waiting for your response`);
        }
    }

    console.log('Press Ctrl+C to exit');
}

/**
 * Single check mode - output JSON and exit
 */
function singleCheck() {
    const sessions = getActiveSessions();
    const result = {
        timestamp: new Date().toISOString(),
        sessionCount: sessions.length,
        sessions: sessions.map(s => ({
            id: s.id,
            status: s.state.status,
            reason: s.state.reason,
            project: s.workspace?.repository || s.workspace?.cwd,
            eventCount: s.eventCount,
            lastModified: s.lastModified.toISOString(),
        })),
        waitingForUser: sessions.filter(s => s.state.status === 'waiting_for_user').map(s => s.id),
    };

    console.log(JSON.stringify(result, null, 2));
}

// Main
if (process.argv.includes('--json')) {
    singleCheck();
} else {
    // Initial display
    displayStatus();

    // Set up polling
    setInterval(displayStatus, POLL_INTERVAL);

    // Handle graceful exit
    process.on('SIGINT', () => {
        console.log('\n\nExiting...');
        process.exit(0);
    });
}
