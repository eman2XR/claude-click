# claude-click

**claude-click** is a computer use tool for macOS — a command-line tool that gives an AI agent screenshot, mouse, keyboard, and UI-element control of the Mac desktop. It drives the UI through Accessibility APIs, OCR, and synthesized mouse/keyboard events, so an agent like Claude Code can click, type, scroll, drag, and verify on-screen state. Any agent that can run CLI commands can use it.

GitHub: https://github.com/eman2XR

Currently geared towards Xcode development with features for app launching, build/run automation, and UI testing.

> **Warning:** claude-click requires Accessibility and Screen Recording permissions and can control any application on your system, sending real clicks and keystrokes to whatever is frontmost. Review the actions an agent runs with it, and consider granting autonomous control only inside a dedicated user account or VM.

## Installation

**With Claude Code:** paste this into a Claude Code session:

> Install claude-click from https://github.com/eman2XR/claude-click: clone it, run `ClaudeClick/install.sh`, then walk me through granting the macOS permissions.

**Manually:**

```bash
git clone https://github.com/eman2XR/claude-click.git ~/claude-click
cd ~/claude-click/ClaudeClick && ./install.sh
```

`install.sh` builds the tool, installs it to `~/bin/claude-click`, and installs a Claude Code skill to `~/.claude/skills/claude-click/` so every Claude session knows how to use it. Then:

1. Put `~/bin` on your PATH: add `export PATH="$HOME/bin:$PATH"` to `~/.zshrc`.
2. Grant **Accessibility** and **Screen Recording** to the app that runs Claude Code (Terminal, iTerm, VS Code, ...) in System Settings > Privacy & Security. Quit and reopen that app, then run `claude-click check-permissions`.
3. Restart Claude Code.

Optionally, let Claude Code run claude-click without asking each time, in `~/.claude/settings.json`:

```json
{ "permissions": { "allow": ["Bash(~/bin/claude-click:*)"] } }
```

Requirements: macOS 13 or later, Xcode or the Command Line Tools (Swift 5.9+). The clone is about 80 MB because it includes a small on-device text model used by `search-tasks`.

**Activity indicator:** a "claude-click active" badge appears in the top-right corner whenever claude-click is acting, so you can tell when an agent is driving the Mac. Turn it off with `claude-click indicator disable` (or set `CLAUDE_CLICK_NO_INDICATOR=1`).

## Quick Start

```bash
claude-click --help                      # Show all commands
claude-click check-permissions           # Check permissions
claude-click list-apps                   # List running apps
claude-click find-click "Close" "Safari" # Click an element
claude-click screenshot                  # Take screenshot
```

**Troubleshooting:**
- App not found? Use `list-apps` to find the exact running name
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
claude-click indicator status                   # The badge starts automatically and shows only while claude-click acts
claude-click indicator disable                  # Turn it off (indicator enable to turn it back on)
```

### For AI Agents
```bash
claude-click observe [app]                      # JSON: focused app, window title, focused field text, visible text, elements, screenshot
claude-click set-value "text"                   # Replace the focused field's text via Accessibility
claude-click select-all                         # Select all text in the focused field via Accessibility
claude-click move-to-end                        # Move the caret to the end of the focused field
claude-click wait-until-stable [timeout]        # Wait until the screen stops changing
claude-click record start [--ax] / stop         # Record observation→action trajectories to episode.jsonl
claude-click type "text" --require-frontmost TextEdit   # Refuse to type unless that app is frontmost
```
The Accessibility-based text commands are more reliable than `cmd+a` + typing: after synthetic typing, pending autocorrect can swallow the next keystroke.

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
