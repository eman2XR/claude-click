# claude-click - Claude AI Integration Guide

## CRITICAL: Read This First

**Before using claude-click, read these files completely:**

1. **This file (CLAUDE.md)** - Commands, syntax, and workflow patterns
2. **learned-patterns.md** - Atomic interaction patterns learned from building workflows (MUST READ - prevents common mistakes)

**Key requirements:**
- Available commands and syntax
- Required workflow patterns
- App focus verification requirements
- Learned interaction patterns (in learned-patterns.md)

**Never assume command syntax.** Always verify first.

## Installation

Tool is installed at: `~/bin/claude-click`

**Agent Tool Allowlist (Required for AppleScript):**
Allow both `osascript` and `claude-click` in your AI agent's command/tool allowlist so AppleScript automation works:
- `osascript`
- `claude-click`

## Automation Method Priority

**Always use this order:**

1. **AppleScript (FASTEST & MOST RELIABLE)** - Direct app control, no visual parsing
   - `osascript -e 'tell application "Safari" to make new tab'`
   - `~/bin/claude-click applescript 'tell application "Finder" to open home'`

2. **Accessibility API** - When AppleScript doesn't support the operation
   - `claude-click find-click "Button" "App"`

3. **OCR (LAST RESORT)** - Only when above methods fail
   - `claude-click find-text-ocr "Text" "App"`

**Why AppleScript First:**
- No visual parsing or element searching required
- Works even if UI is off-screen or obscured
- Instant execution, no waiting for elements
- More reliable than UI automation

## Essential Commands

**AppleScript (PREFERRED)**
- `osascript -e '<script>'` - Direct AppleScript execution
- `claude-click applescript '<script>'` - Wrapper for AppleScript

**Element Interaction (Fallback)**
- `claude-click find-click "name" "app"` - Click element
- `claude-click find-double-click "name" "app"` - Double-click element
- `claude-click find-text-ocr "text" "app"` - Find via OCR (last resort)

**Keyboard**
- `claude-click type "text"` - Type text (uses real key codes so apps reliably receive it)
- `claude-click type "text" --delay-ms 170` - Type with a per-key delay in ms (default 40; ~170 is human speed)
- `claude-click press-key <key>` - Press a key (return, tab, escape, delete, forward-delete, arrows, home, end, pageup, pagedown, f1-f12, or any single character)

**Focus & Screen**
- `claude-click focus-click <x> <y>` - Click twice (0.4s apart) to focus a text field before typing
- `claude-click screen-info` - Print screen size in points and pixels and the backing scale factor (convert screenshot pixel coordinates to click points)

**Mouse (pointer control)**
- `claude-click click <x> <y> [--double] [--right] [--pixels] [--mods <combo>]` - Click; `--mods` accepts shift, ctrl, alt, cmd (or ctrl+shift)
- `claude-click mouse-move <x> <y> [--pixels]` - Move cursor without clicking (hover)
- `claude-click mouse-down [x y]` / `mouse-up [x y]` - Press/release left button (for manual drags)
- `claude-click drag <x1> <y1> <x2> <y2> [--pixels] [--mods <combo>]` - Press, drag and release
- `claude-click scroll <up|down|left|right> [amount] [--at <x> <y>] [--pixels]` - Scroll the wheel
- `claude-click cursor-position` - Report the cursor position in points and pixels
- Coordinates are in screen points. Add `--pixels` to pass screenshot pixel coordinates; they are divided by the backing scale factor (2.0 on Retina).

**Activity Indicator**
- `claude-click indicator start [--label "text"]` - Run a click-through "claude-click active" badge in the top-right that appears only while claude-click is acting
- `claude-click indicator stop` - Stop the indicator
- `claude-click indicator status` - Report whether the indicator is running
- Once started, the badge shows only while a claude-click command ran in the last ~2.5s and hides when idle. It also hides during claude-click screenshots so it does not appear in captured images.

**Settle Detection**
- `claude-click wait-until-stable [timeout] [--threshold t] [--interval ms]` - Block until the screen stops changing (two consecutive frames below the difference threshold) or the timeout elapses. Use after an action that triggers animation, before the next screenshot or action. Exit 0 if settled, 1 on timeout.

**Recording (observation/action trajectories)**
- `claude-click record start [--label name] [--dir path] [--ax]` - Begin recording. While active, every claude-click action logs a step to `episode.jsonl`: the pre-action observation (screenshot, focused app, cursor, screen geometry, and the accessibility tree when `--ax` is set) plus the action and its arguments.
- `claude-click record stop` - Finish and write `session.json`.
- `claude-click record status` - Show whether a recording is active and the step count.
- Default output directory: `~/.claude-click/recordings/<timestamp>/`. Built entirely from claude-click's own primitives.

**Timing**
- `claude-click wait <seconds>` - Wait (supports decimals) - USE SPARINGLY
- `claude-click wait-for-element <name> <app> [timeout]` - Wait for element (PREFERRED - faster and more reliable)
- `claude-click wait-for-app-launch <app> <timeout>` - Wait for app

**App Focus**
- `claude-click focused-app` - Show currently focused app
- `claude-click activate-app <app>` - Activate running app (SAFE - won't launch duplicates)

**Verification**
- `claude-click verify-element "name" "app"` - Check if exists
- `claude-click list-elements` - List all elements
- `claude-click check-permissions` - Check permissions

**Screenshots**
- `claude-click screenshot file.jpg` - Fast low-res JPEG (DEFAULT - use this first)
- `claude-click screenshot file.png` - High-res PNG (only if JPEG quality insufficient)
- `claude-click app-screenshot "app" file.jpg` - Fast app window JPEG (DEFAULT)
- `claude-click app-screenshot "app" file.png` - High-res app window PNG (only if needed)

**Monitoring**
- Start daemon manually: `~/bin/claude-click start-monitor 0.5 &`
- Check current focus: `~/bin/claude-click focused-app`
- Stop daemon: `~/bin/claude-click stop-daemon`

**Task Learning & Workflow Management**
- `claude-click teach-task "name" <app> <step1> <step2> ...` - Save a new workflow
- `claude-click search-tasks "query" [--json]` - Search learned workflows by similarity
- `claude-click list-tasks [--json]` - List all learned tasks with stats
- `claude-click forget-task "name"` - Delete a learned task
- `claude-click record-success "name" [duration]` - Mark task execution as successful

**Examples:**
```bash
# Teach a workflow
claude-click teach-task "create keynote slide" Keynote \
  activate-app Keynote \
  find-click "New Document" \
  type "My Presentation"

# Search for similar workflows
claude-click search-tasks "make presentation" --json

# List all workflows
claude-click list-tasks

# Remove a workflow
claude-click forget-task "create keynote slide"

# Record successful execution
claude-click record-success "create keynote slide"
```

## Critical: App Focus Verification

**Before ANY keyboard command** (`type`, `press-key`), verify the target app is active:

```bash
# Method 1: Check focused app (fastest)
~/bin/claude-click focused-app

# Method 2: Activate explicitly with wait-for-app-launch
open -a "Safari"
~/bin/claude-click wait-for-app-launch "Safari" 10 --activate

# Method 3: Use find-click (safest - auto-activates)
claude-click find-click "Address Bar" "Safari"
```

## CRITICAL: App Activation Safety

**NEVER use `osascript -e 'tell application "..." to activate'`** - Launches DUPLICATE instances!

**Rules:**
1. ❌ NEVER: `osascript activate` (causes duplicates)
2. ✅ ALWAYS: `activate-app AppName` (safe, won't launch)
3. ✅ After `wait-for-app-launch --activate`, app is already focused (no reactivation needed)

**CORRECT:**
```bash
osascript -e 'tell application "Xcode" to activate' && \
~/bin/claude-click shortcut cmd r && \
~/bin/claude-click wait-for-app-launch "MyApp" 60 --activate && \
~/bin/claude-click app-screenshot "MyApp" test.png  # No reactivation needed
```

**WRONG (causes duplicates):**
```bash
~/bin/claude-click wait-for-app-launch "MyApp" 60 --activate && \
osascript -e 'tell application "MyApp" to activate' && \  # DUPLICATE!
~/bin/claude-click app-screenshot "MyApp" test.png
```

## Workflow Patterns

**Opening folders (AppleScript preferred):**
```bash
osascript -e 'tell application "Finder" to open folder "Desktop" of home'
# Fallback: claude-click find-double-click "folder-name" "Finder"
```

**Browser automation (AppleScript preferred):**
```bash
# Create new tab
osascript -e 'tell application "Safari" to make new tab at end of tabs of window 1'

# Navigate to URL
osascript -e 'tell application "Safari" to set URL of current tab of window 1 to "https://example.com"'

# Get current URL
osascript -e 'tell application "Safari" to get URL of current tab of window 1'
```

**Testing UI:**
```bash
# Note: Use the running app name (e.g. "Xcode"), not the app file name (e.g. "Xcode3.app")
claude-click find-click "Run" "Xcode"
claude-click wait-for-app-launch "MyApp" 60  # 60s allows time for compilation
claude-click wait 2  # Brief wait for UI to be ready
claude-click find-click "Button" "MyApp"
```

**Form input:**
```bash
claude-click find-click "Username" "App"
claude-click type "testuser"
claude-click press-key tab
claude-click type "password"
claude-click press-key return
```

## Best Practices

1. **Try AppleScript first** - Fastest and most reliable
2. Use Accessibility API when AppleScript doesn't support the operation
3. OCR as last resort only
4. Use `wait-for-app-launch` to detect app launches (faster and more reliable than sleep)
5. **Use `wait-for-element` instead of fixed `wait`** - polls every 100ms, exits as soon as element appears
6. **Verify app focus before keyboard commands** (only needed if `wait-for-app-launch` was not used, since it already verifies focus)
7. **Use screenshots to verify steps after important actions**
8. Use `focused-app` command to check current focus
9. **Minimize wait times**: Use smart waits (`wait-for-element`, `wait-for-app-launch`) instead of fixed delays

## Screenshot Verification

**Always take screenshots after important steps to verify state:**

```bash
# After clicking save
claude-click find-click "Save" "MyApp"
claude-click wait 0.5
claude-click screenshot myapp.jpg  # Fast JPEG verification (default choice)

# Before and after comparisons
claude-click screenshot before.jpg  # Before state
claude-click find-click "Delete" "MyApp"
claude-click wait 0.5
claude-click screenshot after.jpg  # After state
```

**Screenshot format guidelines:**
- **Always use .jpg extension first** - Fast, small file size, sufficient for most verification
- Only use .png if:
  - JPEG quality is insufficient for verification
  - Need to verify fine details (small text, exact colors, pixel-perfect layout)
  - Performing OCR or visual analysis requiring high precision

**When to use screenshots:**
- After form submissions
- After save/delete operations
- When debugging element finding issues
- Before proceeding to next test step
- When verifying dialog boxes appeared

## Performance Optimization

**Speed up workflows by replacing fixed waits with smart polling:**

❌ **Slow (6+ seconds of waiting):**
```bash
claude-click find-click "New Document" "Keynote"
claude-click wait 2  # Fixed wait
claude-click find-click "Create" "Keynote"
claude-click wait 2  # Fixed wait
claude-click type "My Title"
```

✅ **Fast (~0.5-1s total wait, auto-exits when ready):**
```bash
claude-click find-click "New Document" "Keynote"
claude-click wait-for-element "Create" "Keynote" 5  # Polls every 100ms, exits when found
claude-click find-click "Create" "Keynote"
claude-click wait-for-element "Presentation Title" "Keynote" 5
claude-click find-text-ocr "Presentation Title" "Keynote"
claude-click type "My Title"
```

**Key optimizations:**
- `wait-for-element` typically finds elements in 100-500ms vs 2000ms fixed wait
- Polls every 100ms and exits immediately when element appears
- Use timeout parameter (default 10s) to handle slow operations
- No need for extra waits after `find-click` or typing - only when UI needs to load

## Troubleshooting

- Permission issues: `claude-click check-permissions`
  - The Accessibility pane is named "Device Control and Data Access" on recent macOS. Open it directly with: `open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"`
- Can't find element: `claude-click list-elements`
- Wrong app getting input: Verify app focus first
- Typing lands in the wrong place: wait ~1s after anything that changes the frontmost window before typing, and never type while Terminal is frontmost
- Screenshot coordinates are off: run `claude-click screen-info` and divide screenshot pixel coordinates by the backing scale factor to get click points
