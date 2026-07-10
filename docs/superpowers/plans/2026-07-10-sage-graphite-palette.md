# Sage Graphite Palette Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the native floating window's blue default theme with the approved Sage Graphite palette without changing layout, behavior, or refresh logic.

**Architecture:** Add a private `SageGraphitePalette` namespace in `FloatingWindow/main.swift` so every default-theme component consumes the same named colors. Rename the default `QuotaVisualStyle` case to `sageGraphite`, keep the existing grayscale alternative, and continue routing quota and activity colors through their existing helper APIs.

**Tech Stack:** Swift/AppKit, CALayer, Node.js built-in test runner, shell build and code-sign scripts.

## Global Constraints

- Preserve `expandedWindowSize` at `312 x 184` and `capsuleWindowSize` at `156 x 44`.
- Preserve both compact-bar and circular-dashboard display modes.
- Preserve one-minute quota refresh, manual refresh, one-second activity refresh, animation, and task navigation.
- Keep the minimalist gray theme available.
- Do not add dependencies.
- Default-theme colors must match `docs/superpowers/specs/2026-07-10-sage-graphite-palette-design.md`.
- Perform a professional visual review after the native app is rebuilt.

---

### Task 1: Lock The Palette Contract With Tests

**Files:**
- Modify: `test/floating-style.test.js`
- Test: `test/floating-style.test.js`

**Interfaces:**
- Consumes: `FloatingWindow/main.swift` as source text through `readMainSwift()`.
- Produces: Assertions for `SageGraphitePalette`, `QuotaVisualStyle.sageGraphite`, semantic quota colors, and default-theme component usage.

- [ ] **Step 1: Replace blue-theme assertions with the Sage Graphite contract**

Add the following source-level test and update the existing circular-card test to match `.sageGraphite`:

```javascript
test("native floating window uses the sage graphite palette", () => {
  const source = readMainSwift();

  assert.match(source, /private\s+enum\s+SageGraphitePalette/);
  assert.match(source, /case\s+sageGraphite/);
  assert.doesNotMatch(source, /case\s+creamBlue/);
  assert.match(source, /windowBackground\s*=\s*NSColor\(calibratedRed:\s*0\.949,\s*green:\s*0\.953,\s*blue:\s*0\.937/);
  assert.match(source, /healthy\s*=\s*NSColor\(calibratedRed:\s*0\.459,\s*green:\s*0\.545,\s*blue:\s*0\.455/);
  assert.match(source, /warning\s*=\s*NSColor\(calibratedRed:\s*0\.780,\s*green:\s*0\.584,\s*blue:\s*0\.239/);
  assert.match(source, /critical\s*=\s*NSColor\(calibratedRed:\s*0\.784,\s*green:\s*0\.376,\s*blue:\s*0\.361/);
  assert.match(source, /view\.layer\?\.backgroundColor\s*=\s*SageGraphitePalette\.windowBackground\.cgColor/);
  assert.match(source, /button\.contentTintColor\s*=\s*SageGraphitePalette\.controlTint/);
});
```

Update the quota progress test to assert:

```javascript
assert.match(source, /return\s+SageGraphitePalette\.critical/);
assert.match(source, /return\s+SageGraphitePalette\.warning/);
assert.match(source, /return\s+SageGraphitePalette\.healthy/);
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
/Users/changhaoyu/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --test test/floating-style.test.js
```

Expected: FAIL because `SageGraphitePalette` and `.sageGraphite` do not exist yet.

---

### Task 2: Apply The Approved Palette

**Files:**
- Modify: `FloatingWindow/main.swift`
- Test: `test/floating-style.test.js`

**Interfaces:**
- Consumes: Existing `quotaFillColor(for:)`, `ActivityStatus.color`, and `applyVisualStyle(_:)` call sites.
- Produces: `SageGraphitePalette` static `NSColor` tokens and `QuotaVisualStyle.sageGraphite`.

- [ ] **Step 1: Define the named color tokens**

Insert this namespace above `quotaFillColor(for:)`:

```swift
private enum SageGraphitePalette {
    static let windowBackground = NSColor(calibratedRed: 0.949, green: 0.953, blue: 0.937, alpha: 1)
    static let cardSurface = NSColor(calibratedRed: 0.980, green: 0.984, blue: 0.973, alpha: 1)
    static let cardBorder = NSColor(calibratedRed: 0.851, green: 0.863, blue: 0.835, alpha: 0.90)
    static let progressTrack = NSColor(calibratedRed: 0.894, green: 0.906, blue: 0.882, alpha: 1)
    static let primaryText = NSColor(calibratedRed: 0.161, green: 0.176, blue: 0.165, alpha: 1)
    static let secondaryText = NSColor(calibratedRed: 0.392, green: 0.431, blue: 0.396, alpha: 1)
    static let tertiaryText = NSColor(calibratedRed: 0.506, green: 0.533, blue: 0.502, alpha: 1)
    static let controlTint = NSColor(calibratedRed: 0.408, green: 0.475, blue: 0.416, alpha: 1)
    static let healthy = NSColor(calibratedRed: 0.459, green: 0.545, blue: 0.455, alpha: 1)
    static let warning = NSColor(calibratedRed: 0.780, green: 0.584, blue: 0.239, alpha: 1)
    static let critical = NSColor(calibratedRed: 0.784, green: 0.376, blue: 0.361, alpha: 1)
    static let completed = NSColor(calibratedRed: 0.310, green: 0.596, blue: 0.439, alpha: 1)
    static let idle = NSColor(calibratedRed: 0.525, green: 0.553, blue: 0.525, alpha: 1)
}
```

- [ ] **Step 2: Route semantic colors through the tokens**

Make `quotaFillColor(for:)` return `.critical`, `.warning`, and `.healthy` at the existing thresholds. Make `ActivityStatus.color` return `.critical` for waiting, `.warning` for working, `.completed` for done, and `.idle` for idle and unknown.

- [ ] **Step 3: Rename and apply the default style**

Rename `.creamBlue` to `.sageGraphite`, including the default `visualStyle`, toggle logic, style switches, and tooltip copy. In default-theme branches, apply:

```swift
layer?.backgroundColor = SageGraphitePalette.cardSurface.cgColor
layer?.borderColor = SageGraphitePalette.cardBorder.cgColor
nameLabel.textColor = SageGraphitePalette.secondaryText
valueLabel.textColor = SageGraphitePalette.primaryText
resetLabel.textColor = SageGraphitePalette.tertiaryText
barView.trackColor = SageGraphitePalette.progressTrack
```

Use the corresponding caption-label assignments for circular gauges. Apply `windowBackground`, `primaryText`, and `controlTint` to expanded and capsule window surfaces, title/quota labels, and header icon buttons. Set the activity capsule label to `secondaryText`.

- [ ] **Step 4: Run focused tests and verify they pass**

Run:

```bash
/Users/changhaoyu/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --test test/floating-style.test.js
```

Expected: all tests in `floating-style.test.js` PASS.

- [ ] **Step 5: Run the full automated test suite**

Run:

```bash
/Users/changhaoyu/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --test test/*.test.js
```

Expected: all Node tests PASS.

Run:

```bash
swiftc -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk -module-cache-path /private/tmp/codex-meter-swift-cache FloatingWindow/QuotaModels.swift FloatingWindowTests/QuotaModelsTests.swift -o /private/tmp/codex-meter-model-tests
/private/tmp/codex-meter-model-tests
```

Expected: Swift model tests PASS.

---

### Task 3: Build, Review, And Publish

**Files:**
- Modify only if visual review finds a palette defect: `FloatingWindow/main.swift`
- Generated locally: `CodexQuotaFloat.app`

**Interfaces:**
- Consumes: The passing Swift source and existing build script.
- Produces: A signed native application, visual review evidence, and a pushed Git commit.

- [ ] **Step 1: Build and verify the native app signature**

Run:

```bash
zsh scripts/build-floating-window.sh
codesign --verify --deep --strict --verbose=2 CodexQuotaFloat.app
```

Expected: build succeeds and code-sign verification reports that the app satisfies its designated requirement.

- [ ] **Step 2: Launch exactly one app instance**

Stop existing `CodexQuotaFloat` processes, launch the rebuilt executable, and verify `ps` shows one native app process. Keep the existing local quota service running.

- [ ] **Step 3: Perform the professional visual review**

Inspect screenshots of the expanded circular dashboard, expanded compact bars, and collapsed capsule. Review these criteria:

- The neutral background does not read as green or beige.
- Sage accents remain visible against the progress track.
- Percentage values remain the strongest visual element.
- Secondary labels and reset times are readable without competing with percentages.
- Activity colors are distinct from quota colors and remain legible inside the tinted capsule.
- No text, icon, arc, border, or animation is clipped.
- Expanding and collapsing preserves a coherent color identity.

If a defect is found, adjust only palette values, rerun the focused test, rebuild, and repeat the screenshots.

- [ ] **Step 4: Commit and push**

Run:

```bash
git add FloatingWindow/main.swift test/floating-style.test.js docs/superpowers/plans/2026-07-10-sage-graphite-palette.md
git commit -m "Replace blue theme with sage graphite palette"
git push origin main
```

Expected: `origin/main` advances to the new palette commit and the worktree is clean.
