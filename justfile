PROJECT := "CopilotCompanion.xcodeproj"
SCHEME := "CopilotCompanion"

# Default recipe - shows available commands
default:
    @just --list --unsorted

# Run tests
test:
    xcodebuild -project {{ PROJECT }} -scheme {{ SCHEME }} test

# Open the project in Xcode
open:
    open {{ PROJECT }}

# Build app (Xcode)
xcode-build:
    xcodebuild -project {{ PROJECT }} -scheme {{ SCHEME }} build

# Swift Package build (library)
spm-build pkgdir:
    cd {{ pkgdir }} && swift build

# Swift Package tests (library)
spm-test pkgdir:
    cd {{ pkgdir }} && swift test

# Describe Swift package
package-describe pkgdir:
    cd {{ pkgdir }} && swift package describe

# List Swift packages in repo (directories containing Package.swift)
spm-list:
    find . -type f -name Package.swift -not -path '*/.build/*' -print | sed 's|/Package.swift$||' | sort

# List Xcode schemes
list-schemes:
    xcodebuild -list -project {{ PROJECT }}

# Clean build artifacts (Xcode + SwiftPM)
clean:
    xcodebuild -project {{ PROJECT }} -scheme {{ SCHEME }} clean
    rm -rf {{ PKG_DIR }}/.build
