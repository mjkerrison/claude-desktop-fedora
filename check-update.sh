#!/bin/bash
# Check for Claude Desktop updates by comparing installed version with upstream

set -e

CLAUDE_DOWNLOAD_URL="https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-x64/Claude-Setup-x64.exe"
DEBIAN_RELEASES_API="https://api.github.com/repos/aaddrick/claude-desktop-debian/releases/latest"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Apply the custom launcher script that uses standalone Electron
apply_launcher_fix() {
    echo "Applying custom launcher script..."
    sudo tee /usr/bin/claude-desktop > /dev/null << 'LAUNCHER_EOF'
#!/usr/bin/bash
LOG_FILE="$HOME/claude-desktop-launcher.log"

# Set environment to avoid GTK conflicts
export GDK_BACKEND=x11
export GTK_USE_PORTAL=0
export ELECTRON_DISABLE_SECURITY_WARNINGS=true

# Use the standalone electron installation
/opt/electron/electron /usr/lib64/claude-desktop/app.asar --ozone-platform-hint=auto --enable-logging=file --log-file=$LOG_FILE --log-level=INFO --disable-gpu-sandbox --no-sandbox "$@"
LAUNCHER_EOF
    sudo chmod +x /usr/bin/claude-desktop
    echo -e "${GREEN}✓ Launcher script updated${NC}"
}

# Handle --fix-launcher flag
if [[ "$1" == "--fix-launcher" ]]; then
    apply_launcher_fix
    exit 0
fi

echo "Checking for Claude Desktop updates..."
echo

# Get installed version
if command -v claude-desktop &> /dev/null; then
    # Try to get version from rpm
    if INSTALLED=$(rpm -q --qf '%{VERSION}' claude-desktop 2>/dev/null); then
        echo -e "Installed version: ${GREEN}${INSTALLED}${NC}"
    else
        echo -e "${YELLOW}Claude Desktop is available but version couldn't be determined from rpm${NC}"
        INSTALLED="unknown"
    fi
else
    echo -e "${YELLOW}Claude Desktop is not installed${NC}"
    INSTALLED="none"
fi

# Get latest version from debian releases (they track upstream)
echo "Fetching latest version info..."
LATEST_RELEASE=$(curl -s "$DEBIAN_RELEASES_API")

if [ -z "$LATEST_RELEASE" ] || echo "$LATEST_RELEASE" | grep -q "API rate limit"; then
    echo -e "${RED}Failed to fetch release info (possible rate limit)${NC}"
    echo "You can check manually at: https://github.com/aaddrick/claude-desktop-debian/releases"
    exit 1
fi

# Extract Claude version from tag (format: v1.1.10+claude0.14.10)
TAG_NAME=$(echo "$LATEST_RELEASE" | grep -oP '"tag_name":\s*"\K[^"]+' | head -1)
LATEST=$(echo "$TAG_NAME" | grep -oP 'claude\K[0-9.]+')

if [ -z "$LATEST" ]; then
    echo -e "${RED}Failed to parse latest version from tag: ${TAG_NAME}${NC}"
    exit 1
fi

echo -e "Latest version:    ${GREEN}${LATEST}${NC}"
echo

# Compare versions
version_gt() {
    test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"
}

if [ "$INSTALLED" = "none" ]; then
    echo -e "${YELLOW}Claude Desktop is not installed.${NC}"
    echo
    echo "To install, run:"
    echo "  sudo ./build-fedora.sh"
    echo "  sudo dnf install build/electron-app/\$(uname -m)/claude-desktop-*.rpm"
elif [ "$INSTALLED" = "unknown" ]; then
    echo -e "${YELLOW}Could not determine installed version. Latest available is ${LATEST}${NC}"
elif [ "$INSTALLED" = "$LATEST" ]; then
    echo -e "${GREEN}You're running the latest version!${NC}"
elif version_gt "$LATEST" "$INSTALLED"; then
    echo -e "${YELLOW}Update available: ${INSTALLED} → ${LATEST}${NC}"
    echo
    echo "Download URL:"
    echo "  $CLAUDE_DOWNLOAD_URL"
    echo
    echo "To update, run:"
    echo "  sudo ./build-fedora.sh"
    echo "  sudo dnf install build/electron-app/\$(uname -m)/claude-desktop-*.rpm"
    echo
    read -p "Would you like to run the build script now? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Starting build..."
        sudo ./build-fedora.sh
        echo
        read -p "Build complete. Install the RPM now? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo dnf install build/electron-app/$(uname -m)/claude-desktop-*.rpm
            echo
            read -p "Apply custom launcher fix (required for standalone Electron)? [Y/n] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                apply_launcher_fix
            fi
        else
            echo "Install manually with:"
            echo "  sudo dnf install build/electron-app/\$(uname -m)/claude-desktop-*.rpm"
            echo "Then run: $0 --fix-launcher"
        fi
    fi
else
    echo -e "${GREEN}You're running a newer version than upstream (${INSTALLED} > ${LATEST})${NC}"
fi
