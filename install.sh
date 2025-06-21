#!/bin/bash
set -euo pipefail

# zqlite Installation Script
# Usage: curl -sSL https://raw.githubusercontent.com/yourusername/zqlite/main/install.sh | bash

REPO="ghostkellz/zqlite"
INSTALL_DIR="${HOME}/.local/bin"
BINARY_NAME="zqlite"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Detect OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "${ARCH}" in
    x86_64) ARCH="x86_64" ;;
    arm64|aarch64) ARCH="aarch64" ;;
    *) echo -e "${RED}Unsupported architecture: ${ARCH}${NC}" && exit 1 ;;
esac

case "${OS}" in
    linux) OS="linux" ;;
    darwin) OS="macos" ;;
    *) echo -e "${RED}Unsupported OS: ${OS}${NC}" && exit 1 ;;
esac

echo -e "${BLUE}🟦 zqlite Installation Script${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Check if Zig is installed
if ! command -v zig &> /dev/null; then
    echo -e "${YELLOW}⚠️  Zig not found. Installing from source...${NC}"
    
    # Create temporary directory
    TMP_DIR=$(mktemp -d)
    cd "${TMP_DIR}"
    
    # Clone and build zqlite
    echo -e "${BLUE}📦 Cloning zqlite repository...${NC}"
    git clone "https://github.com/${REPO}.git"
    cd zqlite
    
    # Download and install Zig
    echo -e "${BLUE}🔧 Installing Zig...${NC}"
    ZIG_VERSION="0.13.0"
    ZIG_URL="https://ziglang.org/download/${ZIG_VERSION}/zig-${OS}-${ARCH}-${ZIG_VERSION}.tar.xz"
    curl -L "${ZIG_URL}" | tar -xJ
    export PATH="${PWD}/zig-${OS}-${ARCH}-${ZIG_VERSION}:${PATH}"
else
    echo -e "${GREEN}✅ Zig found: $(zig version)${NC}"
    
    # Create temporary directory and clone
    TMP_DIR=$(mktemp -d)
    cd "${TMP_DIR}"
    
    echo -e "${BLUE}📦 Cloning zqlite repository...${NC}"
    git clone "https://github.com/${REPO}.git"
    cd zqlite
fi

# Build zqlite
echo -e "${BLUE}🔨 Building zqlite...${NC}"
zig build -Doptimize=ReleaseFast

# Create install directory
mkdir -p "${INSTALL_DIR}"

# Copy binary
echo -e "${BLUE}📦 Installing to ${INSTALL_DIR}...${NC}"
cp "zig-out/bin/${BINARY_NAME}" "${INSTALL_DIR}/"

# Make executable
chmod +x "${INSTALL_DIR}/${BINARY_NAME}"

# Add to PATH if not already there
if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
    echo -e "${YELLOW}⚠️  ${INSTALL_DIR} not in PATH${NC}"
    echo -e "${BLUE}💡 Add this to your shell profile:${NC}"
    echo -e "   export PATH=\"${INSTALL_DIR}:\$PATH\""
fi

# Cleanup
cd /
rm -rf "${TMP_DIR}"

# Test installation
echo -e "${BLUE}🧪 Testing installation...${NC}"
if "${INSTALL_DIR}/${BINARY_NAME}" version &> /dev/null; then
    echo -e "${GREEN}✅ zqlite installed successfully!${NC}"
    echo -e "${BLUE}📖 Usage:${NC}"
    echo -e "   ${BINARY_NAME} shell              # Interactive shell"
    echo -e "   ${BINARY_NAME} exec db.sqlite \"SELECT * FROM users;\""
    echo -e "   ${BINARY_NAME} version            # Show version"
else
    echo -e "${RED}❌ Installation failed${NC}"
    exit 1
fi

echo -e "${GREEN}🎉 Welcome to zqlite - the Zig-native SQLite alternative!${NC}"