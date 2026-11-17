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

# Install the Claude Code skill so every Claude session knows how to use claude-click.
SKILL_SRC="$(cd "$(dirname "$0")/.." && pwd)/skill/claude-click/SKILL.md"
if [ -f "$SKILL_SRC" ]; then
  mkdir -p ~/.claude/skills/claude-click
  cp "$SKILL_SRC" ~/.claude/skills/claude-click/SKILL.md
  echo "Installed Claude Code skill to ~/.claude/skills/claude-click/"
fi

echo ""
echo "Installation complete: ~/bin/claude-click"
echo ""
echo "Next steps:"
echo "  1. Make sure ~/bin is on your PATH (add to ~/.zshrc):"
echo "       export PATH=\"\$HOME/bin:\$PATH\""
echo "  2. Grant permissions to the app that runs Claude Code (Terminal, iTerm, VS Code...):"
echo "       System Settings > Privacy & Security > Accessibility"
echo "       System Settings > Privacy & Security > Screen Recording"
echo "     Then quit and reopen that app, and run: claude-click check-permissions"
echo "  3. Optional: let Claude Code run claude-click without prompting, in ~/.claude/settings.json:"
echo "       \"permissions\": { \"allow\": [\"Bash(~/bin/claude-click:*)\"] }"
echo "  4. Restart Claude Code so it picks up the skill."
