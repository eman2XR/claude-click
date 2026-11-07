# claude-click Installation Guide

## Quick Install

```bash
cd ClaudeClick
./install.sh
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
claude-click check-permissions  # Grant accessibility and screen recording permissions
```

## Claude Code Integration

### 1. Add Permissions

Add to `~/.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(~/bin/claude-click:*)",
      "Bash(sleep * && ~/bin/claude-click:*)"
    ]
  }
}
```

### 2. Add to Global CLAUDE.md

**Important:** Add these guidelines to `~/.claude/CLAUDE.md` to prevent issues with UI automation:

```markdown
## claude-click Usage

**App Activation (CRITICAL):**
- ❌ NEVER use `osascript -e 'tell application "X" to activate'` - launches duplicates
- ✅ Use `~/bin/claude-click activate-app X` instead (safe, won't launch)
- After `wait-for-app-launch --activate`, no reactivation needed

**Xcode App Testing:**
- ❌ NEVER use `open -a AppName` after Xcode Cmd+R - creates duplicates
- ✅ Use: `shortcut cmd r` → `wait-for-app-launch "App" 60 --activate`

**Tool Priority:**
1. Accessibility API first: `find-click "Button" "App"`
2. OCR if AX fails: `find-text-ocr "Text" "App"`
3. Screenshots for verification only

**Smart Waiting:**
- Use `wait-for-app-launch App 10 --activate` for app launches
- Use `wait-for-element "Name" "App" 5` for UI loads (polls every 100ms)
- Avoid fixed `sleep` delays when possible

**Keyboard Input Safety:**
- Always verify focus with `focused-app` before `type` or `press-key`
- Or use `find-click` first (auto-activates target app)
- Safe shortcuts: cmd+r, cmd+c/v/x, cmd+z, cmd+a
- Blocked shortcuts: cmd+n, cmd+t, cmd+l, cmd+f (cause focus loss)

**Screenshot Best Practices:**
- Use .jpg for speed (default): `screenshot test.jpg`
- Use .png only when high quality needed: `screenshot test.png`
- Take screenshots after important actions for verification
```

### 3. Optional Tool Registration

Add as a tool (optional):

```bash
mkdir -p ~/.claude/tools && cat > ~/.claude/tools/claude-click.json << 'EOF'
{
  "name": "claude-click",
  "description": "macOS UI automation - clicks, types, screenshots",
  "command": "~/bin/claude-click",
  "args": []
}
EOF
```

### 4. Restart Claude Code

Restart Claude Code after making these changes.

## Verification

```bash
claude-click --help                      # Show all commands
claude-click check-permissions           # Verify permissions
claude-click list-apps                   # List running apps
claude-click find-click "Close" "Safari" # Test clicking
```

## Troubleshooting

- **App not found?** Use `list-apps` to find exact name (e.g., "Xcode3" not "Xcode")
- **Keyboard not working?** Check focus with `focused-app`, use `find-click` first
- **Testing Xcode apps?** Never use `open -a` - use `shortcut cmd r` + `wait-for-app-launch`
