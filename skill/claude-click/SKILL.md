---
name: claude-click
description: |
  Control the Mac with the claude-click CLI (~/bin/claude-click): open and switch apps, click,
  type, scroll, drag, take screenshots, read on-screen state, and build and run Xcode apps.
  Use whenever a task needs interacting with macOS apps or checking what is on screen.
---

# claude-click

`~/bin/claude-click` is a computer use tool for macOS. It drives apps through the
Accessibility API, OCR and synthesized mouse and keyboard events. Run `claude-click --help`
for every command and flag.

## Work in a loop: observe, act, verify

1. **Observe**: `claude-click observe [app]` prints JSON with the focused app, window title,
   the focused field's text, visible text (for example a calculator result), clickable
   elements with frames, screen geometry, and a screenshot path.
2. **Act** with one command at a time.
3. **Verify** with `observe` again, or `screenshot file.jpg` for visual checks.

Prefer, in order: AppleScript (`osascript`) when the app supports it, Accessibility
commands (`find-click`, `observe`, `set-value`), then OCR (`find-text-ocr`), then raw
coordinates.

## Safety

- Keystrokes go to the frontmost app. Before `type`, `press-key` or `shortcut`, bring the
  target forward with `activate-app <App>` and check it with `focused-app`.
- Use `type "text" --require-frontmost <App>`: it refuses to type if another app is in front.
  Never type while Terminal (or the app running Claude) is frontmost; Return would submit
  a prompt.
- Use `activate-app` instead of `osascript -e 'tell application "X" to activate'`, which can
  launch a second instance.
- An on-screen "claude-click active" badge appears while commands run.
  `claude-click indicator disable` turns it off.

## Commands

**Apps and windows**
- `activate-app <App>`, `focused-app`, `list-apps [--filter name]`, `app-running <App>`
- `wait-for-app-launch <App> [timeout] [--activate]`

**Finding and clicking**
- `find-click "label" [App] [--double] [--right]`: click an element by its accessibility label
- `find-text-ocr "text" <App>`: find text with OCR and click it
- `element-exists "label" <App> [--timeout s]` (exit 0 or 1), `get-value "label" <App>`
- `wait-for-element "label" <App> [timeout]`
- `click <x> <y> [--double] [--right] [--mods cmd|shift|alt|ctrl] [--pixels]`
- `mouse-move`, `mouse-down`, `mouse-up`, `drag <x1> <y1> <x2> <y2>`, `cursor-position`
- `scroll <up|down|left|right> [amount] [--at x y]`

**Keyboard and text**
- `type "text" [--require-frontmost App] [--app App] [--delay-ms n]`
- `press-key <key>` (return, tab, escape, delete, arrows, home, end, pageup, pagedown, f1 to f12)
- `shortcut <App> <modifiers...> <key>`, for example `shortcut Safari cmd t`
- `set-value "text"`: replace the focused field's text through Accessibility
- `select-all`, `move-to-end`: Accessibility selection and caret control

To replace text, use `set-value`, or `select-all` then `type`. After synthetic typing,
pending autocorrect can swallow the next keystroke, so `cmd+a` followed by typing may
append instead of replacing.

**Screen**
- `screenshot [App] file.jpg` (`.jpg` is fast, `.png` is full quality)
- `screen-info`: points, pixels and scale factor. Clicks use points; screenshots are in
  pixels. Pass `--pixels` to use screenshot coordinates directly.
- `dump <App|screen> <output-base>`: element JSON plus an annotated image
- `wait-until-stable [timeout]`: wait until the screen stops changing

**Xcode**
- `xcode-build-run-app <project> <target> [timeout] [--xcode <XcodeAppName>]`: build, report
  errors, wait for launch. Exit 0 on success.
- `xcode-get-build-errors`, `xcode-test-results [--json]`, `read-xcode-console`

**Recording and learned workflows**
- `record start [--ax]` and `record stop`: log observation and action trajectories
- `teach-task`, `search-tasks`, `list-tasks`, `forget-task`

## Troubleshooting

- Nothing happens or clicks miss: run `claude-click check-permissions`. The app running
  Claude Code (Terminal, iTerm, VS Code) needs Accessibility and Screen Recording, and must
  be restarted after granting them.
- App not found: use `list-apps` for the exact running name.
- Element not found: `observe` or `dump` to see the real labels, then fall back to OCR.
