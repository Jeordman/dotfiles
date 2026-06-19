---
name: sim-loop
description: iOS simulator UI verification loop — take screenshots, read the accessibility tree, and interact with the running app via Maestro. Trigger this skill: (1) proactively after making any visual/UI code change to an Expo or React Native app, to confirm the change looks right in the iOS simulator; (2) when the user says "check the simulator", "what does the UI look like", "verify the UI", "test on iOS", "tap X in the app", "interact with the simulator", "screenshot the app", or "run the loop". Do NOT trigger for changes that only affect logic, data, or non-visual code where there is nothing to see.
---

# iOS Simulator UI Loop

Drive a visible (non-headless) iOS simulator using `xcrun simctl` screenshots and Maestro for element interaction. The loop: **screenshot → read → hierarchy (if needed) → interact → screenshot again**.

## Prerequisites

```bash
which maestro || echo "NOT INSTALLED — tell user: ! brew install maestro"
```

If Maestro is not installed, stop and tell the user to run `! brew install maestro` in the prompt. Do not proceed without it.

## Get context

```bash
# Booted simulator
xcrun simctl list devices | grep Booted

# Bundle ID from app.json
python3 -c "import json; d=json.load(open('app.json')); print(d['expo'].get('ios', {}).get('bundleIdentifier') or d['expo']['bundleIdentifier'])"
```

## Step 1: Screenshot

```bash
xcrun simctl io booted screenshot /tmp/sim-screenshot.png
```

Then **Read `/tmp/sim-screenshot.png`** as an image. Describe what you see — which screen is shown, what elements are visible — before deciding the next action.

## Step 2: Accessibility hierarchy

Run this when you need to find element labels, IDs, or types before interacting:

```bash
maestro hierarchy
```

Outputs the full accessibility tree of whatever is currently on screen. Look for `accessibilityLabel`, `text`, `id`, or `testID` values to use in flows.

## Step 3: Interact via Maestro

Write a flow to `/tmp/maestro-flow.yaml` and run it:

```bash
maestro test /tmp/maestro-flow.yaml
```

### Flow template

```yaml
appId: <bundle-id>
---
# actions go here
```

### Common actions

| Goal | YAML |
|------|------|
| Tap element by label/text | `- tapOn: "Button Label"` |
| Tap element by testID | `- tapOn:\n    id: "my-test-id"` |
| Type text | `- inputText: "hello world"` |
| Clear + type | `- clearAndTypeText: "new value"` |
| Scroll down | `- scroll` |
| Swipe up | `- swipe:\n    direction: UP` |
| Swipe left | `- swipe:\n    direction: LEFT` |
| Wait for animation | `- waitForAnimationToEnd` |
| Assert text visible | `- assertVisible: "Expected Text"` |
| Assert not visible | `- assertNotVisible: "Loading"` |
| Press back / escape | `- pressKey: Back` |
| Take named screenshot | `- takeScreenshot: after-tap` |

### Multi-step example

```yaml
appId: com.jeordman.topout
---
- tapOn: "Add Workout"
- waitForAnimationToEnd
- inputText: "Pull Day"
- tapOn: "Save"
- assertVisible: "Pull Day"
```

## Step 4: Screenshot again

After every meaningful interaction, take another screenshot and Read it. Describe what changed. If the UI matches the expected result, report success. If not, run `maestro hierarchy` to diagnose and adjust.

## Behavior rules

- **One action at a time.** Screenshot after each Maestro run, not just at the end.
- **Prefer label/text taps** over coordinates — they survive layout changes.
- **Run hierarchy before guessing.** Don't invent element names; get the real tree first.
- **If a flow fails,** immediately run `maestro hierarchy` to see what's actually on screen, then revise.
- **If the app isn't in the foreground,** check with the user whether to launch it. To launch: add `- launchApp` as the first action in the flow.
- **Hot reload.** Expo typically hot-reloads on file save. After making a code change, wait ~2 seconds then take a screenshot to confirm the reload landed before interacting.
- **Report visually.** Always tell the user what the screenshot shows and what you're about to do next. Never silently loop.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `maestro` not found | `! brew install maestro` |
| `xcrun simctl io booted screenshot` fails | No booted simulator — start one in Xcode or run `npx expo run:ios` |
| Maestro can't find element | Run `maestro hierarchy`, look for the real label/id |
| App not reloaded after code change | Wait 2-3s, or shake simulator to get dev menu → Reload |
| Flow runs but nothing happens | App may be on wrong screen — take screenshot to check state |
