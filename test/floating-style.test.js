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

test("native floating window defines activity states", () => {
  const source = readMainSwift();

  assert.match(source, /enum\s+ActivityStatus/);
  assert.match(source, /case\s+waiting/);
  assert.match(source, /case\s+working/);
  assert.match(source, /case\s+done/);
  assert.match(source, /case\s+idle/);
  assert.match(source, /case\s+unknown/);
  assert.match(source, /return\s+"待确认"/);
  assert.match(source, /return\s+"工作中"/);
  assert.match(source, /return\s+"已完成"/);
  assert.match(source, /return\s+"空闲"/);
  assert.match(source, /return\s+"状态未知"/);
  assert.match(source, /calibratedRed:\s*0\.88,\s*green:\s*0\.35,\s*blue:\s*0\.35/);
  assert.match(source, /calibratedRed:\s*0\.85,\s*green:\s*0\.64,\s*blue:\s*0\.11/);
  assert.match(source, /calibratedRed:\s*0\.18,\s*green:\s*0\.75,\s*blue:\s*0\.44/);
  assert.match(source, /calibratedRed:\s*0\.54,\s*green:\s*0\.58,\s*blue:\s*0\.64/);
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

  assert.match(source, /expandedWindowSize\s*=\s*NSSize\(width:\s*312,\s*height:\s*184\)/);
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
  assert.match(source, /valueLabel\.centerYAnchor\.constraint\(equalTo:\s*centerYAnchor,\s*constant:\s*2\)/);
  assert.match(source, /resetLabel\.font\s*=\s*\.monospacedDigitSystemFont\(ofSize:\s*10,\s*weight:\s*\.semibold\)/);
  assert.match(source, /resetLabel\.bottomAnchor\.constraint\(equalTo:\s*bottomAnchor,\s*constant:\s*-14\)/);
  assert.match(source, /let\s+radius\s*=\s*min\(bounds\.width\s*\*\s*0\.30,\s*31\)/);
});

test("native circular dashboard matches the refined card treatment", () => {
  const source = readMainSwift();

  assert.match(source, /final\s+class\s+CircularGaugeView[\s\S]*layer\?\.borderWidth\s*=\s*0\.5/);
  assert.match(source, /case\s+\.creamBlue:[\s\S]*layer\?\.borderColor\s*=\s*NSColor\(calibratedRed:\s*0\.68,\s*green:\s*0\.80,\s*blue:\s*0\.90,\s*alpha:\s*0\.55\)\.cgColor/);
  assert.match(source, /case\s+\.minimalistDashboard:[\s\S]*layer\?\.borderColor\s*=\s*NSColor\(calibratedRed:\s*0\.82,\s*green:\s*0\.84,\s*blue:\s*0\.87,\s*alpha:\s*0\.72\)\.cgColor/);
});

test("native circular dashboard removes decorative tick marks that crowd reset time", () => {
  const source = readMainSwift();

  assert.doesNotMatch(source, /drawTicks/);
  assert.doesNotMatch(source, /for\s+index\s+in\s+0\.\.\.6/);
});

test("native floating window keeps secondary controls visually quiet", () => {
  const source = readMainSwift();

  assert.match(source, /gaugeStack\.spacing\s*=\s*12/);
  assert.match(source, /button\.alphaValue\s*=\s*0\.72/);
  assert.match(source, /private\s+let\s+activitySignal\s*=\s*ActivitySignalView\(\)/);
  assert.match(source, /for\s+child\s+in\s+\[activitySignal,\s*titleLabel,\s*shrinkButton,\s*gaugeButton,\s*colorButton,\s*refreshButton\]/);
  assert.match(source, /activitySignal\.leadingAnchor\.constraint\(equalTo:\s*header\.leadingAnchor\)/);
  assert.doesNotMatch(source, /for\s+child\s+in\s+\[autoButton/);
});

test("native floating window hides default macOS traffic-light controls", () => {
  const source = readMainSwift();

  assert.match(source, /NSWindow\.ButtonType\.closeButton/);
  assert.match(source, /standardWindowButton\(buttonType\)\?\.isHidden\s*=\s*true/);
});

test("native floating window supports a small capsule mode", () => {
  const source = readMainSwift();

  assert.match(source, /capsuleWindowSize\s*=\s*NSSize\(width:\s*156,\s*height:\s*44\)/);
  assert.match(source, /final\s+class\s+CapsuleViewController/);
  assert.match(source, /activityCapsuleSignal/);
  assert.match(source, /quotaCapsuleLabel/);
  assert.match(source, /NSClickGestureRecognizer/);
  assert.match(source, /showCapsule/);
});

test("native activity signal uses three persistent lamps without layout shift", () => {
  const source = readMainSwift();

  assert.match(source, /final\s+class\s+SignalLampView/);
  assert.match(source, /final\s+class\s+ActivitySignalView/);
  assert.match(source, /redLamp/);
  assert.match(source, /yellowLamp/);
  assert.match(source, /greenLamp/);
  assert.match(source, /widthAnchor\.constraint\(equalToConstant:\s*84\)/);
  assert.match(source, /heightAnchor\.constraint\(equalToConstant:\s*22\)/);
  assert.match(source, /widthAnchor\.constraint\(equalToConstant:\s*8\)/);
  assert.match(source, /shadowRadius\s*=\s*4/);
  assert.match(source, /accessibilityDisplayShouldReduceMotion/);
  assert.match(source, /CATransaction\.setAnimationDuration\(0\.2\)/);
  assert.doesNotMatch(source, /ActivityPillView/);
  assert.match(source, /statusItem\.button\?\.attributedTitle/);
  assert.match(source, /NSAttributedString\(string:\s*"● "/);
});

test("capsule reuses the three-lamp activity signal", () => {
  const source = readMainSwift();

  assert.match(source, /private\s+let\s+activityCapsuleSignal\s*=\s*ActivitySignalView/);
  assert.match(source, /quotaCapsuleLabel\.widthAnchor\.constraint\(equalToConstant:\s*52\)/);
  assert.match(source, /let\s+stack\s*=\s*NSStackView\(views:\s*\[activityCapsuleSignal,\s*quotaCapsuleLabel\]\)/);
  assert.match(source, /stack\.spacing\s*=\s*6/);
  assert.doesNotMatch(source, /dotCapsuleLabel/);
});

test("native activity status polls independently from quota refresh", () => {
  const source = readMainSwift();

  assert.match(source, /activityEndpoint/);
  assert.match(source, /activityRefreshInterval:\s*TimeInterval\s*=\s*1/);
  assert.match(source, /refreshActivityNow\(\)/);
  assert.match(source, /private\s+var\s+activityTimer:\s*Timer\?/);
  assert.doesNotMatch(source, /refreshNow[\s\S]{0,220}setActivityStatus\(\.working\)/);
  assert.doesNotMatch(source, /render\(_\s+snapshot:\s*QuotaSnapshot\)[\s\S]{0,500}setActivityStatus\(\.done\)/);
  assert.doesNotMatch(source, /idleStatusTimer/);
  assert.match(source, /onActivityIntegrationChanged/);
  assert.match(source, /状态监听：需安装 Hooks/);
});

test("native floating window can recover when the local quota service is not running", () => {
  const source = readMainSwift();

  assert.match(source, /final\s+class\s+LocalQuotaService/);
  assert.match(source, /Bundle\.main\.bundleURL\.deletingLastPathComponent\(\)/);
  assert.match(source, /server\.js/);
  assert.match(source, /quota-window\.log/);
  assert.match(source, /quota-window\.pid/);
  assert.match(source, /ensureRunning/);
  assert.match(source, /refreshNow\(allowServiceStart:\s*false\)/);
  assert.match(source, /handleRefreshFailure\(allowServiceStart:/);
});

test("native floating window can hide safely into the macOS menu bar", () => {
  const source = readMainSwift();

  assert.match(source, /NSStatusBar\.system\.statusItem\(withLength:\s*NSStatusItem\.variableLength\)/);
  assert.match(source, /显示窗口/);
  assert.match(source, /收起为胶囊/);
  assert.match(source, /隐藏到菜单栏/);
  assert.match(source, /手动刷新/);
  assert.match(source, /状态：空闲/);
  assert.match(source, /退出/);
});

test("closing the floating window hides it instead of making it hard to recover", () => {
  const source = readMainSwift();

  assert.match(source, /func\s+windowShouldClose\(_\s+sender:\s*NSWindow\)\s*->\s*Bool\s*\{[\s\S]*hideToMenuBar/);
  assert.match(source, /return\s+false/);
  assert.doesNotMatch(source, /func\s+windowWillClose[\s\S]*NSApp\.terminate/);
});
