#!/bin/bash

# Build and install claude-click to ~/bin

set -e

echo "Building claude-click..."
# --disable-sandbox avoids "sandbox-exec: sandbox_apply: Operation not permitted"
# when swift build runs inside an already-sandboxed shell.
swift build -c release --disable-sandbox

echo "Installing to ~/bin/..."
mkdir -p ~/bin

# Install the binary
cp .build/release/claude-click ~/bin/claude-click
chmod +x ~/bin/claude-click

echo "✓ Installation complete!"
echo "claude-click installed to: ~/bin/claude-click"
echo ""
echo "Make sure ~/bin is in your PATH by adding this to your ~/.zshrc or ~/.bashrc:"
echo "  export PATH=\"\$HOME/bin:\$PATH\""
