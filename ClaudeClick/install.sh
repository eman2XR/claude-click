#!/bin/bash

# Build and install claude-click to ~/bin

set -e

echo "Building claude-click..."
# --disable-sandbox avoids "sandbox-exec: sandbox_apply: Operation not permitted"
# when swift build runs inside an already-sandboxed shell.
swift build -c release --disable-sandbox

echo "Installing to ~/bin/..."
mkdir -p ~/bin

# Stop any running instance (e.g. the indicator daemon) and remove the old file
# first. Copying over a binary that is currently mapped/running corrupts it and
# causes the kernel to SIGKILL every later launch.
pkill -f "$HOME/bin/claude-click" 2>/dev/null || true
sleep 0.3
rm -f ~/bin/claude-click

# Install the binary (fresh inode)
cp .build/release/claude-click ~/bin/claude-click
chmod +x ~/bin/claude-click

echo "✓ Installation complete!"
echo "claude-click installed to: ~/bin/claude-click"
echo ""
echo "Make sure ~/bin is in your PATH by adding this to your ~/.zshrc or ~/.bashrc:"
echo "  export PATH=\"\$HOME/bin:\$PATH\""
