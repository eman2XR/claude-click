# claude-click

**claude-click** is a computer use tool for macOS — a command-line tool that gives an AI agent screenshot, mouse, keyboard, and UI-element control of the Mac desktop. It drives the UI through Accessibility APIs, OCR, and synthesized mouse/keyboard events, so an agent like Claude Code can click, type, scroll, drag, and verify on-screen state. Any agent that can run CLI commands can use it.

GitHub: https://github.com/eman2XR

Currently geared towards Xcode development with features for app launching, build/run automation, and UI testing.

> **Warning:** claude-click requires Accessibility and Screen Recording permissions and can control any application on your system, sending real clicks and keystrokes to whatever is frontmost. Review the actions an agent runs with it, and consider granting autonomous control only inside a dedicated user account or VM.

## Installation

**Option 1: Use Claude Code (Recommended)**

Ask Claude Code to install claude-click for you - it should handle everything automatically based on the `.claude/INSTALLATION.md` file.

**Option 2: Manual Installation**

```bash
cd ClaudeClick
./install.sh
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
claude-click check-permissions  # Grant accessibility and screen recording permissions
```

## Claude Code Integration

Add permissions to `~/.claude/settings.json`:

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

Optionally, add as a tool with this one-liner:

```bash
mkdir -p ~/.claude/tools && cat > ~/.claude/tools/claude-click.json << 'EOF'
{
  "name": "claude-click",
  "description": "macOS computer use tool - can click, type, scroll, drag, screenshot, and verify UI state",
  "command": "~/bin/claude-click",
  "args": []
}
EOF
```

Restart Claude Code after updating.

## Quick Start

```bash
claude-click --help                      # Show all commands
claude-click check-permissions           # Check permissions
claude-click list-apps                   # List running apps
claude-click find-click "Close" "Safari" # Click an element
claude-click screenshot                  # Take screenshot
```

**Troubleshooting:**
- App not found? Use `list-apps` to find exact name (e.g., "Xcode3" not "Xcode")
- Keyboard not working? Check focus with `focused-app`, use `find-click` first
- Testing Xcode apps? Never use `open -a` - use `shortcut Xcode cmd r` + `wait-for-app-launch "App" 60 --activate`

## Commands

### UI Interaction
```bash
claude-click find-click "Button" "AppName"      # Click element by label
claude-click find-text-ocr "Text" "AppName"     # Find via OCR
claude-click element-exists "Button" "App"      # Check if exists (exit 0/1)
claude-click get-value "Field" "App"            # Read element value
claude-click clear-field "Input" "App"          # Clear text field
```

### Keyboard & Mouse
```bash
claude-click type "Hello World"                 # Type text (real key codes; --delay-ms N for speed)
claude-click press-key return                   # Press a key (arrows, home, end, pageup/down, ...)
claude-click shortcut Safari cmd r              # App-scoped keyboard shortcut
claude-click click 100 200 [--double --right --mods cmd]   # Click, optionally with modifiers
claude-click drag 100 200 400 200               # Press, drag and release
claude-click scroll down 5                      # Scroll (up/down/left/right)
claude-click mouse-move 400 300                 # Hover (also: mouse-down/up, cursor-position)
# Add --pixels to any of these to pass screenshot pixel coordinates (Retina-aware)
```

### Activity Indicator
```bash
claude-click indicator start                    # Badge that appears top-right only while claude-click acts
claude-click indicator stop                     # Turn it off
```

### App Management
```bash
claude-click wait-for-app-launch "App" 10 --activate   # Wait for launch + activate
claude-click app-running "Safari"                      # Check if running (exit 0/1)
claude-click list-apps --filter "Xcode"                # List running apps
claude-click focused-app                               # Show focused app
```

### Screenshots & Debugging
```bash
claude-click screenshot out.png                 # Screenshot (.jpg = fast, .png = full quality)
claude-click screenshot Safari out.png          # App window only
claude-click screen-info                        # Screen size in points/pixels + scale factor
claude-click dump Safari output                 # Dump elements to JSON + annotated PNG
claude-click check-permissions                  # Verify Accessibility/Screen Recording permissions
```

## Usage Examples

```bash
# Automated testing
claude-click shortcut Xcode cmd r
claude-click wait-for-app-launch "MyApp" 60 --activate
claude-click find-click "Login" "MyApp"
claude-click type "username" && claude-click press-key tab
claude-click type "password" && claude-click press-key return
claude-click element-exists "Dashboard" "MyApp" && echo "Success"

# Conditional logic
if claude-click element-exists "Error" "MyApp"; then
    claude-click find-click "OK" "MyApp"
fi

# Fallback to OCR
claude-click find-click "Submit" "App" || claude-click find-text-ocr "Submit" "App"
```

## Best Practices

- Use `--activate` flag for reliable app launching
- Try Accessibility API first, fallback to OCR
- Use `find-click` to focus before keyboard input
- Never use `open -a` for Xcode apps


## Requirements

macOS 13+ • Swift 5.9+ • Accessibility and Screen Recording permissions

See **PROJECT.md** for detailed technical documentation.
