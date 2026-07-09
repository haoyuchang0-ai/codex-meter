const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

function readMainSwift() {
  return fs.readFileSync(
    path.join(__dirname, "..", "FloatingWindow", "main.swift"),
    "utf8",
  );
}

test("native floating window centers the Codex title", () => {
  const source = readMainSwift();

  assert.match(
    source,
    /titleLabel\.centerXAnchor\.constraint\(equalTo:\s*view\.centerXAnchor\)/,
  );
});

test("native floating window can switch to minimalist dashboard style", () => {
  const source = readMainSwift();

  assert.match(source, /enum\s+QuotaVisualStyle/);
  assert.match(source, /minimalistDashboard/);
  assert.match(source, /colorButtonPressed/);
  assert.match(source, /applyVisualStyle/);
});

test("native floating window removes the left status cluster", () => {
  const source = readMainSwift();

  assert.doesNotMatch(source, /statusDot/);
  assert.doesNotMatch(source, /updatedLabel/);
});

test("native floating window has a circular dashboard gauge mode", () => {
  const source = readMainSwift();

  assert.match(source, /enum\s+QuotaDisplayMode/);
  assert.match(source, /circularDashboard/);
  assert.match(source, /final\s+class\s+CircularGaugeView/);
  assert.match(source, /gaugeButtonPressed/);
});

test("native floating window uses understandable quota labels instead of P and S", () => {
  const source = readMainSwift();

  assert.match(source, /CompactMeterRow\(name:\s*"主额度"/);
  assert.match(source, /CompactMeterRow\(name:\s*"周额度"/);
  assert.match(source, /CircularGaugeView\(caption:\s*"主额度"/);
  assert.match(source, /CircularGaugeView\(caption:\s*"周额度"/);
  assert.doesNotMatch(source, /name:\s*"[PS]"/);
  assert.doesNotMatch(source, /caption:\s*"[PS]"/);
});

test("native floating window keeps both display modes in the same visual stage", () => {
  const source = readMainSwift();

  assert.match(source, /private\s+let\s+contentStage\s*=\s*NSView\(\)/);
  assert.match(source, /contentStage\.heightAnchor\.constraint\(equalToConstant:\s*116\)/);
  assert.match(source, /contentStage\.addSubview\(rowStack\)/);
  assert.match(source, /contentStage\.addSubview\(gaugeStack\)/);
  assert.match(source, /let\s+stack\s*=\s*NSStackView\(views:\s*\[header,\s*contentStage\]\)/);
});

test("native floating window trims excess bottom whitespace", () => {
  const source = readMainSwift();

  assert.match(source, /compactWindowSize\s*=\s*NSSize\(width:\s*312,\s*height:\s*184\)/);
  assert.match(source, /stack\.spacing\s*=\s*8/);
  assert.match(source, /stack\.bottomAnchor\.constraint\(lessThanOrEqualTo:\s*view\.bottomAnchor,\s*constant:\s*-12\)/);
});

test("native floating window crossfades display mode changes without relayout", () => {
  const source = readMainSwift();

  assert.match(source, /applyDisplayMode\(animated:\s*true\)/);
  assert.match(source, /NSAnimationContext\.runAnimationGroup/);
  assert.match(source, /context\.duration\s*=\s*0\.18/);
  assert.match(source, /animator\(\)\.alphaValue/);
});

test("native circular dashboard has more vertical breathing room", () => {
  const source = readMainSwift();

  assert.match(source, /heightAnchor\.constraint\(equalToConstant:\s*110\)/);
  assert.match(source, /captionLabel\.topAnchor\.constraint\(equalTo:\s*topAnchor,\s*constant:\s*12\)/);
  assert.match(source, /valueLabel\.centerYAnchor\.constraint\(equalTo:\s*centerYAnchor,\s*constant:\s*5\)/);
  assert.match(source, /resetLabel\.bottomAnchor\.constraint\(equalTo:\s*bottomAnchor,\s*constant:\s*-12\)/);
  assert.match(source, /let\s+radius\s*=\s*min\(bounds\.width\s*\*\s*0\.30,\s*31\)/);
});

test("native circular dashboard matches the refined card treatment", () => {
  const source = readMainSwift();

  assert.match(source, /final\s+class\s+CircularGaugeView[\s\S]*layer\?\.borderWidth\s*=\s*0\.5/);
  assert.match(source, /case\s+\.creamBlue:[\s\S]*layer\?\.borderColor\s*=\s*NSColor\(calibratedRed:\s*0\.68,\s*green:\s*0\.80,\s*blue:\s*0\.90,\s*alpha:\s*0\.55\)\.cgColor/);
  assert.match(source, /case\s+\.minimalistDashboard:[\s\S]*layer\?\.borderColor\s*=\s*NSColor\(calibratedRed:\s*0\.82,\s*green:\s*0\.84,\s*blue:\s*0\.87,\s*alpha:\s*0\.72\)\.cgColor/);
});

test("native floating window keeps secondary controls visually quiet", () => {
  const source = readMainSwift();

  assert.match(source, /gaugeStack\.spacing\s*=\s*12/);
  assert.match(source, /button\.alphaValue\s*=\s*0\.72/);
  assert.match(source, /autoButton\.alphaValue\s*=\s*0\.64/);
  assert.match(source, /for\s+child\s+in\s+\[autoButton,\s*titleLabel,\s*gaugeButton,\s*colorButton,\s*refreshButton\]/);
  assert.match(source, /autoButton\.leadingAnchor\.constraint\(equalTo:\s*header\.leadingAnchor\)/);
});

test("native floating window hides default macOS traffic-light controls", () => {
  const source = readMainSwift();

  assert.match(source, /NSWindow\.ButtonType\.closeButton/);
  assert.match(source, /standardWindowButton\(buttonType\)\?\.isHidden\s*=\s*true/);
});
