# claude-click Installation Guide (for Claude Code)

Follow these steps when a user asks to install claude-click.

## 1. Clone and build

```bash
git clone https://github.com/eman2XR/claude-click.git ~/claude-click
cd ~/claude-click/ClaudeClick && ./install.sh
```

`install.sh` builds a release binary (needs Xcode or the Command Line Tools), installs it to
`~/bin/claude-click`, and installs the usage skill to `~/.claude/skills/claude-click/SKILL.md`.

## 2. PATH

If `~/bin` is not on the PATH, add it:

```bash
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
```

## 3. macOS permissions (the user must do this)

The app that runs Claude Code (Terminal, iTerm, VS Code, ...) needs both:

- System Settings > Privacy & Security > Accessibility
- System Settings > Privacy & Security > Screen Recording

Open the panes for the user:

```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
```

After granting, the user must quit and reopen that app. Then verify:

```bash
~/bin/claude-click check-permissions
```

## 4. Optional: allow without prompts

Add to `~/.claude/settings.json`:

```json
{ "permissions": { "allow": ["Bash(~/bin/claude-click:*)"] } }
```

## 5. Restart Claude Code

New sessions load the claude-click skill automatically.

## Verify

```bash
~/bin/claude-click --help
~/bin/claude-click observe
~/bin/claude-click list-apps
```

An on-screen "claude-click active" badge appears while commands run; `claude-click indicator disable` turns it off.

## Troubleshooting

- Commands do nothing or report missing permissions: re-check step 3 and restart the terminal app.
- `swift build` fails with "sandbox_apply: Operation not permitted": `install.sh` already passes `--disable-sandbox`; run it from a normal terminal.
- App not found: `claude-click list-apps` shows exact running names.
