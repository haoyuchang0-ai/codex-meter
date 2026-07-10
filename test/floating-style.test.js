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

function swiftClassSource(source, className, nextClassName) {
  const match = source.match(
    new RegExp(
      `final\\s+class\\s+${className}[\\s\\S]*?(?=final\\s+class\\s+${nextClassName})`,
    ),
  );
  assert.ok(match, `expected ${className} before ${nextClassName}`);
  return match[0];
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
  assert.match(source, /sageGraphite/);
  assert.match(source, /minimalistDashboard/);
  assert.match(source, /colorButtonPressed/);
  assert.match(source, /applyVisualStyle/);
});

test("native floating window uses the sage graphite palette", () => {
  const source = readMainSwift();

  assert.match(source, /private\s+enum\s+SageGraphitePalette/);
  assert.match(source, /case\s+sageGraphite/);
  assert.doesNotMatch(source, /case\s+creamBlue/);
  assert.match(source, /windowBackground\s*=\s*NSColor\(calibratedRed:\s*0\.949,\s*green:\s*0\.953,\s*blue:\s*0\.937,\s*alpha:\s*1\)/);
  assert.match(source, /cardSurface\s*=\s*NSColor\(calibratedRed:\s*0\.980,\s*green:\s*0\.984,\s*blue:\s*0\.973,\s*alpha:\s*1\)/);
  assert.match(source, /cardBorder\s*=\s*NSColor\(calibratedRed:\s*0\.851,\s*green:\s*0\.863,\s*blue:\s*0\.835/);
  assert.match(source, /progressTrack\s*=\s*NSColor\(calibratedRed:\s*0\.894,\s*green:\s*0\.906,\s*blue:\s*0\.882/);
  assert.match(source, /primaryText\s*=\s*NSColor\(calibratedRed:\s*0\.161,\s*green:\s*0\.176,\s*blue:\s*0\.165/);
  assert.match(source, /secondaryText\s*=\s*NSColor\(calibratedRed:\s*0\.392,\s*green:\s*0\.431,\s*blue:\s*0\.396/);
  assert.match(source, /tertiaryText\s*=\s*NSColor\(calibratedRed:\s*0\.506,\s*green:\s*0\.533,\s*blue:\s*0\.502/);
  assert.match(source, /controlTint\s*=\s*NSColor\(calibratedRed:\s*0\.408,\s*green:\s*0\.475,\s*blue:\s*0\.416/);
  assert.match(source, /healthy\s*=\s*NSColor\(calibratedRed:\s*0\.459,\s*green:\s*0\.545,\s*blue:\s*0\.455/);
  assert.match(source, /warning\s*=\s*NSColor\(calibratedRed:\s*0\.780,\s*green:\s*0\.584,\s*blue:\s*0\.239/);
  assert.match(source, /critical\s*=\s*NSColor\(calibratedRed:\s*0\.784,\s*green:\s*0\.376,\s*blue:\s*0\.361/);
  assert.match(source, /completed\s*=\s*NSColor\(calibratedRed:\s*0\.310,\s*green:\s*0\.596,\s*blue:\s*0\.439/);
  assert.match(source, /idle\s*=\s*NSColor\(calibratedRed:\s*0\.525,\s*green:\s*0\.553,\s*blue:\s*0\.525/);
  assert.doesNotMatch(source, /calibratedRed:\s*0\.31,\s*green:\s*0\.62,\s*blue:\s*0\.86/);
  assert.doesNotMatch(source, /calibratedRed:\s*0\.96,\s*green:\s*0\.98,\s*blue:\s*1\.0/);
  assert.doesNotMatch(source, /calibratedRed:\s*0\.18,\s*green:\s*0\.44,\s*blue:\s*0\.62/);
});

test("sage graphite tokens are applied to every default-theme surface", () => {
  const source = readMainSwift();
  const compactMeter = swiftClassSource(source, "CompactMeterRow", "CircularGaugeView");
  const circularGauge = swiftClassSource(source, "CircularGaugeView", "CapsuleViewController");
  const capsule = swiftClassSource(source, "CapsuleViewController", "QuotaViewController");
  const expanded = swiftClassSource(source, "QuotaViewController", "AppDelegate");

  assert.match(compactMeter, /case\s+\.sageGraphite:[\s\S]*SageGraphitePalette\.cardSurface/);
  assert.match(compactMeter, /SageGraphitePalette\.cardBorder/);
  assert.match(compactMeter, /SageGraphitePalette\.secondaryText/);
  assert.match(compactMeter, /SageGraphitePalette\.primaryText/);
  assert.match(compactMeter, /SageGraphitePalette\.tertiaryText/);
  assert.match(compactMeter, /SageGraphitePalette\.progressTrack/);

  assert.match(circularGauge, /case\s+\.sageGraphite:[\s\S]*SageGraphitePalette\.cardSurface/);
  assert.match(circularGauge, /SageGraphitePalette\.cardBorder/);
  assert.match(circularGauge, /SageGraphitePalette\.secondaryText/);
  assert.match(circularGauge, /SageGraphitePalette\.primaryText/);
  assert.match(circularGauge, /SageGraphitePalette\.tertiaryText/);
  assert.match(circularGauge, /SageGraphitePalette\.progressTrack/);

  assert.match(capsule, /view\.layer\?\.backgroundColor\s*=\s*SageGraphitePalette\.windowBackground\.cgColor/);
  assert.match(capsule, /quotaCapsuleLabel\.textColor\s*=\s*SageGraphitePalette\.primaryText/);

  assert.match(expanded, /private\s+var\s+visualStyle:\s*QuotaVisualStyle\s*=\s*\.sageGraphite/);
  assert.match(expanded, /case\s+\.sageGraphite:[\s\S]*view\.layer\?\.backgroundColor\s*=\s*SageGraphitePalette\.windowBackground\.cgColor/);
  assert.match(expanded, /titleLabel\.textColor\s*=\s*SageGraphitePalette\.primaryText/);
  assert.match(expanded, /button\.contentTintColor\s*=\s*SageGraphitePalette\.controlTint/);
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
  assert.match(source, /case\s+\.waiting:\s*return\s+SageGraphitePalette\.critical/);
  assert.match(source, /case\s+\.working:\s*return\s+SageGraphitePalette\.warning/);
  assert.match(source, /case\s+\.done:\s*return\s+SageGraphitePalette\.completed/);
  assert.match(source, /case\s+\.idle:\s*return\s+SageGraphitePalette\.idle/);
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

test("quota progress colors reflect remaining percentage in both views", () => {
  const source = readMainSwift();

  assert.match(source, /func\s+quotaFillColor\(for\s+remainingPercent:\s*Int\)/);
  assert.match(source, /if\s+remainingPercent\s*<\s*20/);
  assert.match(source, /if\s+remainingPercent\s*<\s*50/);
  assert.match(source, /return\s+SageGraphitePalette\.critical/);
  assert.match(source, /return\s+SageGraphitePalette\.warning/);
  assert.match(source, /return\s+SageGraphitePalette\.healthy/);
  assert.match(source, /barView\.fillColor\s*=\s*quotaFillColor\(for:\s*remaining\)/);
  assert.match(source, /fillColor\s*=\s*quotaFillColor\(for:\s*remaining\)/);
  assert.doesNotMatch(source, /barView\.fillColor\s*=\s*NSColor\(calibratedRed:\s*0\.16,\s*green:\s*0\.62/);
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
  const circularGauge = swiftClassSource(source, "CircularGaugeView", "CapsuleViewController");

  assert.match(circularGauge, /layer\?\.borderWidth\s*=\s*0\.5/);
  assert.match(circularGauge, /case\s+\.sageGraphite:[\s\S]*layer\?\.borderColor\s*=\s*SageGraphitePalette\.cardBorder\.cgColor/);
  assert.match(circularGauge, /case\s+\.minimalistDashboard:[\s\S]*layer\?\.borderColor\s*=\s*NSColor\(calibratedRed:\s*0\.82,\s*green:\s*0\.84,\s*blue:\s*0\.87,\s*alpha:\s*0\.72\)\.cgColor/);
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
  assert.match(source, /private\s+let\s+activityCapsule\s*=\s*ActivityCapsuleView\(\)/);
  assert.match(source, /for\s+child\s+in\s+\[activityCapsule,\s*titleLabel,\s*shrinkButton,\s*gaugeButton,\s*colorButton,\s*refreshButton\]/);
  assert.match(source, /activityCapsule\.leadingAnchor\.constraint\(equalTo:\s*header\.leadingAnchor\)/);
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
  assert.match(source, /activityStatusCapsule/);
  assert.match(source, /quotaCapsuleLabel/);
  assert.match(source, /NSClickGestureRecognizer/);
  assert.match(source, /showCapsule/);
});

test("native activity uses a fixed dynamic capsule without layout shift", () => {
  const source = readMainSwift();

  assert.match(source, /final\s+class\s+ActivityCapsuleView/);
  assert.match(source, /private\s+let\s+iconView\s*=\s*NSImageView\(\)/);
  assert.match(source, /private\s+let\s+waveformView\s*=\s*ActivityWaveformView\(\)/);
  assert.match(source, /private\s+var\s+currentStatus:\s*ActivityStatus\?/);
  assert.match(source, /widthAnchor\.constraint\(equalToConstant:\s*96\)/);
  assert.match(source, /heightAnchor\.constraint\(equalToConstant:\s*24\)/);
  assert.match(source, /waveform\.path/);
  assert.match(source, /exclamationmark\.triangle\.fill/);
  assert.match(source, /checkmark\.circle\.fill/);
  assert.match(source, /circle\.fill/);
  assert.match(source, /guard\s+currentStatus\s*!=\s*status/);
  assert.match(source, /accessibilityDisplayShouldReduceMotion/);
  assert.match(source, /CATransaction\.setAnimationDuration\(0\.2\)/);
  assert.doesNotMatch(source, /ActivityPillView/);
  assert.doesNotMatch(source, /SignalLampView/);
  assert.match(source, /statusItem\.button\?\.attributedTitle/);
  assert.match(source, /NSAttributedString\(string:\s*"● "/);
});

test("working capsule continuously animates a four-bar waveform", () => {
  const source = readMainSwift();

  assert.match(source, /final\s+class\s+ActivityWaveformView/);
  assert.match(source, /private\s+let\s+barCount\s*=\s*4/);
  assert.match(source, /repeatCount\s*=\s*\.infinity/);
  assert.match(source, /beginTime\s*=\s*CACurrentMediaTime\(\)\s*\+\s*\(Double\(index\)\s*\*\s*0\.11\)/);
  assert.match(source, /accessibilityDisplayShouldReduceMotion/);
  assert.match(source, /waveformView\.startAnimating\(color:\s*status\.color\)/);
  assert.match(source, /waveformView\.stopAnimating\(\)/);
  assert.match(source, /bar\.removeAnimation\(forKey:\s*"workingWave"\)/);
});

test("small window reuses the dynamic activity capsule", () => {
  const source = readMainSwift();

  assert.match(source, /private\s+let\s+activityStatusCapsule\s*=\s*ActivityCapsuleView/);
  assert.match(source, /quotaCapsuleLabel\.widthAnchor\.constraint\(equalToConstant:\s*52\)/);
  assert.match(source, /let\s+stack\s*=\s*NSStackView\(views:\s*\[activityStatusCapsule,\s*quotaCapsuleLabel\]\)/);
  assert.match(source, /stack\.spacing\s*=\s*4/);
  assert.doesNotMatch(source, /dotCapsuleLabel/);
  assert.match(source, /NSGestureRecognizerDelegate/);
  assert.match(source, /shouldAttemptToRecognizeWith\s+event:\s*NSEvent/);
  assert.match(source, /expandGestureRecognizer\.delegate\s*=\s*self/);
});

test("activity capsule opens a compact task menu with Codex deep links", () => {
  const source = readMainSwift();

  assert.match(source, /activityTasksEndpoint/);
  assert.match(source, /final\s+class\s+ActivityTaskMenuPresenter/);
  assert.match(source, /var\s+onClick:\s*\(\(\)\s*->\s*Void\)\?/);
  assert.match(source, /NSClickGestureRecognizer\(target:\s*self,\s*action:\s*#selector\(capsuleClicked\)\)/);
  assert.match(source, /NSCursor\.pointingHand/);
  assert.match(source, /setAccessibilityElement\(true\)/);
  assert.match(source, /override\s+func\s+accessibilityPerformPress\(\)\s*->\s*Bool/);
  assert.match(source, /menu\.minimumWidth\s*=\s*236/);
  assert.match(source, /NSMenuItem\.sectionHeader\(title:/);
  assert.match(source, /进行中的任务/);
  assert.match(source, /当前没有进行中的任务/);
  assert.match(source, /codex:\/\/threads\//);
  assert.match(source, /activityCapsule\.onClick/);
  assert.match(source, /activityStatusCapsule\.onClick/);
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
