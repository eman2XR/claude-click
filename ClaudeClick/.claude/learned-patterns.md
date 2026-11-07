# Learned Interaction Patterns

This file contains atomic interaction patterns learned from building workflows. These patterns help avoid common pitfalls and ensure reliable UI automation.

## Safari

### Opening New Tabs
**✅ Correct:**
```
find-click "New Tab" Safari
```

**❌ Avoid:**
```
shortcut Safari cmd t
```

**Reason:** Keyboard shortcuts like Cmd+T can cause the search/address field to lose focus, requiring additional clicks to refocus. Using `find-click "New Tab"` ensures the new tab opens with the search field already focused and ready for input.

---

### Clicking Images Tab in Google Search
**✅ Correct:**
```
find-text-ocr "Images" Safari
```

**❌ Less reliable:**
```
find-click "Images" Safari
```

**Reason:** The "Images" tab in Google search results is often not accessible via the Accessibility API. OCR text finding is more reliable for web content that changes dynamically.

---

### Downloading Images from Google Images
**✅ Correct approach:**
1. Right-click on the **center of the image thumbnail** (not the text link below)
2. Find the image element bounds using `dump` command
3. Calculate center coordinates: `x + width/2, y + height/2`
4. Use `click <x> <y> --right`

**❌ Avoid:**
- Clicking on the text link below the image (opens page instead of showing context menu)
- Clicking edges of image thumbnail (may miss the element)

**Reason:** Image thumbnails in Google Images are clickable elements, but the associated text links below them perform different actions. Right-clicking the image center ensures the context menu shows image-specific options like "Save Image to Downloads".

---

## Save Dialogs

### Saving Files
**✅ Correct:**
```
type "filename"
press-key return
```

**Alternative (if needed):**
```
find-click "Save" <app>
```

**Reason:** Most save dialogs accept Enter/Return to confirm, which is faster and more reliable than finding and clicking the Save button. The filename field is typically auto-focused when the dialog opens.

---

## General Principles

1. **Prefer Accessibility API over OCR**: Use `find-click` first, fall back to `find-text-ocr` only when accessibility elements are not available.

2. **Avoid keyboard shortcuts that change focus**: Shortcuts like Cmd+T, Cmd+L, Cmd+N can unpredictably change focus. Use explicit clicking instead.

3. **Use wait-for-app-launch with --activate**: After opening apps, always use `wait-for-app-launch <app> <timeout> --activate` to ensure the app is ready and in focus.

4. **Take screenshots to verify state**: When teaching new workflows, take screenshots at key steps to verify the UI state before proceeding.

5. **Right-click positioning matters**: For context menus on images or specific elements, click the center of the element, not its edges or associated text.

---

## Xcode

### Project Navigator - find-click Works!
**✅ Correct:**
```
find-click "Assets" Xcode              # Searches value field
find-click "ContentView" Xcode         # Works for any file
```

**⚠️ OCR still reliable as fallback:**
```
find-text-ocr "Assets" Xcode           # Still works if AX fails
```

**Reason:** Project Navigator items have their names in the AXValue field (not title/description). The find-click command searches the `value` field in addition to `title`, `description`, and `placeholder`, making it work reliably for Project Navigator file/folder navigation.

**Important:** Text fields opened via keyboard shortcuts often lose focus immediately and require an explicit click before typing will work.

---

### App Activation for Xcode-Launched Apps
**✅ Correct:**
```
wait-for-app-launch AppName 60 --activate
```

**❌ NEVER:**
```
osascript -e 'tell application "AppName" to activate'
open -a AppName
```

**Reason:** When an app is launched from Xcode (Cmd+R), using `osascript` or `open -a` will launch a DUPLICATE instance instead of activating the Xcode-launched instance. Always use `wait-for-app-launch` with `--activate` flag, which safely activates the already-running instance. If you need to reactivate later, use `activate-app AppName` which is safe and won't launch duplicates.

---

### Xcode App Names
**✅ Correct:**
```
activate-app Xcode
shortcut Xcode cmd r
```

**❌ May fail:**
```
activate-app Xcode3
```

**Reason:** Xcode's running app name may differ from the app bundle name. The app bundle might be "Xcode3.app" but the running process name is "Xcode". Always use `focused-app` or `list-apps` to check the actual running app name. When commands fail, verify the app name first.

---

### Building and Running Apps from Xcode
**✅ Correct approach:**
```
activate-app Xcode
shortcut Xcode cmd r
wait-for-app-launch MyApp 60 --activate
```

**Important notes:**
- Use timeout of 60s or more for `wait-for-app-launch` to allow time for compilation
- **First-time builds may take 90s+ (use longer timeout like 120s if needed)**
- The `--activate` flag ensures the app is brought to focus once launched
- After `wait-for-app-launch --activate`, the app is already focused (no need to reactivate)

---

### Stopping Running Apps from Xcode
**✅ Correct:**
```
activate-app Xcode
find-click "Stop" Xcode
```

**❌ Avoid:**
```
shortcut Xcode cmd period
```

**Reason:** The period (`.`) key is not available in the `shortcut` command's key list. Use the accessible "Stop" button instead via `find-click`.

---

### Reading Xcode Console Output
**✅ Correct:**
```
activate-app Xcode
shortcut Xcode cmd shift y          # Show console if hidden
read-xcode-console
```

**Important notes:**
- Console MUST be visible for `read-xcode-console` to work
- Use Cmd+Shift+Y to toggle console visibility
- For continuous monitoring, use `watch-xcode-console`

---

### Checking Build Errors
**✅ Correct:**
```
activate-app Xcode
shortcut Xcode cmd 5                # Switch to Issue Navigator
xcode-get-build-errors
```

**Important notes:**
- Error detection works best when Issue Navigator (Cmd+5) is visible
- Xcode must be running and not minimized
- Use after build failures to get error details

---

## AppleScript Automation

### Using applescript Command
**✅ Correct:**
```
~/bin/claude-click applescript 'tell application "Finder" to get name of every window'
~/bin/claude-click applescript 'tell application "Safari" to get URL of current tab of window 1'
```

**Important - Agent Tool Allowlist:**
Both `claude-click` and `osascript` must be allowed in your AI agent's command/tool allowlist:
1. Add tool name: `osascript`
2. Add tool name: `claude-click`

**Reason:** When `claude-click applescript` executes, it spawns `osascript` as a subprocess. macOS checks permissions for both the parent process (`claude-click`) and the child process (`osascript`). Both must be in the allowlist for AppleScript automation to work through Claude Code.

**Alternative:** You can also run `osascript` directly without the wrapper:
```
osascript -e 'tell application "Finder" to get name of every window'
```

---

### App Activation via AppleScript
**❌ Does NOT work reliably:**
```
osascript -e 'tell application "AppName" to activate'
```

**✅ Correct approach:**
```bash
# Option 1: Make new document (launches app if needed)
osascript -e 'tell application "Keynote" to make new document'

# Option 2: Use open command
open -a "AppName"
~/bin/claude-click wait-for-app-launch "AppName" 10 --activate

# Option 3: Activate already-running app
~/bin/claude-click activate-app AppName
```

**Reason:** `tell application to activate` doesn't reliably launch apps that aren't already running. It only activates already-running applications. Always use `make new document` or `open -a` to ensure the app launches.

---

### Safari: Handling Missing Windows
**❌ Common Error:**
```
~/bin/claude-click applescript 'tell application "Safari" to get URL of current tab of window 1'
# Error: Can't get window 1. Invalid index. (-1719)
```

**✅ Correct approach:**
```bash
# Check if windows exist first, create if needed
~/bin/claude-click applescript 'tell application "Safari" to make new document'
# Then proceed with window operations
~/bin/claude-click applescript 'tell application "Safari" to get URL of current tab of window 1'
```

**Reason:** AppleScript doesn't automatically create windows when activating Safari. If Safari has no windows open, accessing `window 1` fails. Always create a document/window first or check window count before operations.

---

### System Events: Menu Item Clicking
**✅ Works reliably:**
```
~/bin/claude-click applescript 'tell application "System Events" to click menu item "New Window" of menu "File" of menu bar 1 of process "Safari"'
```

**Important:** System Events menu clicking is faster and more reliable than find-click for menu items. Use this instead of navigating the menu bar with the Accessibility API.

---

### Keynote: Reading Slide Content
**✅ Use `every text item` (works with all layouts):**
```bash
osascript -e 'tell application "Keynote" to get object text of every text item of slide 1 of front document'
```

**❌ Avoid `default title item` / `default body item` (only works with standard layouts)**

**Reason:** Custom text boxes won't be captured by `default title/body item`. Using `every text item` works regardless of slide layout.

---

### Keynote: Working with Slides
**Navigation and Comments:**
- Navigate: `osascript -e 'tell application "Keynote" to set current slide of front document to slide N'`
- Get slide count: `osascript -e 'tell application "Keynote" to get count of slides of front document'`
- Read presenter notes: `osascript -e 'tell application "Keynote" to get presenter notes of slide N'`

**Adding Comments (Pure AppleScript):**
```bash
osascript <<'EOF'
tell application "Keynote"
    activate
    set current slide of front document to slide N of front document
end tell

tell application "System Events"
    tell process "Keynote"
        click menu item "Comment" of menu "Insert" of menu bar 1
        keystroke "Your comment text here"
        key code 53
    end tell
end tell
EOF
```

**Important:**
- No delays needed - System Events handles timing automatically
- `key code 53` is Escape key to close comment
- AppleScript doesn't support `make new comment` - must use System Events menu clicking
- Replace `N` with slide number and change comment text as needed

---

## Adding New Patterns

When you discover a new reliable pattern or common pitfall:

1. Test the pattern multiple times to ensure reliability
2. Document both the correct approach and what to avoid
3. Explain the reason (helps understand when to apply the pattern)
4. Add it to this file with clear examples
