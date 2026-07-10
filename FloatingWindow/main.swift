import Cocoa
import Foundation

private let refreshInterval: TimeInterval = 60
private let quotaEndpoint = URL(string: "http://127.0.0.1:5487/api/rate-limits")!
private let expandedWindowSize = NSSize(width: 312, height: 184)
private let capsuleWindowSize = NSSize(width: 156, height: 44)

enum QuotaVisualStyle {
    case creamBlue
    case minimalistDashboard

    mutating func toggle() {
        self = self == .creamBlue ? .minimalistDashboard : .creamBlue
    }
}

enum QuotaDisplayMode {
    case compactBars
    case circularDashboard

    mutating func toggle() {
        self = self == .compactBars ? .circularDashboard : .compactBars
    }
}

enum ActivityStatus {
    case waiting
    case working
    case done
    case idle

    var label: String {
        switch self {
        case .waiting:
            return "待确认"
        case .working:
            return "工作中"
        case .done:
            return "已完成"
        case .idle:
            return "空闲"
        }
    }

    var menuTitle: String {
        "状态：\(label)"
    }

    var color: NSColor {
        switch self {
        case .waiting:
            return NSColor(calibratedRed: 0.88, green: 0.35, blue: 0.35, alpha: 1)
        case .working:
            return NSColor(calibratedRed: 0.85, green: 0.64, blue: 0.11, alpha: 1)
        case .done:
            return NSColor(calibratedRed: 0.18, green: 0.75, blue: 0.44, alpha: 1)
        case .idle:
            return NSColor(calibratedRed: 0.54, green: 0.58, blue: 0.64, alpha: 1)
        }
    }
}

final class ActivityPillView: NSView {
    private let dotLabel = NSTextField(labelWithString: "●")
    private let textLabel = NSTextField(labelWithString: ActivityStatus.idle.label)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.44).cgColor
        setAccessibilityLabel("状态：\(ActivityStatus.idle.label)")

        dotLabel.font = .systemFont(ofSize: 8, weight: .bold)
        dotLabel.alignment = .center

        textLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        textLabel.textColor = NSColor(calibratedRed: 0.27, green: 0.36, blue: 0.46, alpha: 1)
        textLabel.lineBreakMode = .byClipping

        for child in [dotLabel, textLabel] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 68),
            heightAnchor.constraint(equalToConstant: 20),
            dotLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            dotLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotLabel.widthAnchor.constraint(equalToConstant: 8),
            textLabel.leadingAnchor.constraint(equalTo: dotLabel.trailingAnchor, constant: 5),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        update(status: .idle)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(status: ActivityStatus) {
        dotLabel.textColor = status.color
        textLabel.stringValue = status.label
        setAccessibilityLabel(status.menuTitle)
        toolTip = status.menuTitle
    }
}

final class LocalQuotaService {
    static let shared = LocalQuotaService()

    private let projectRootURL: URL
    private let serverScriptURL: URL
    private let logURL: URL
    private let pidURL: URL
    private var isStarting = false

    private init() {
        projectRootURL = Bundle.main.bundleURL.deletingLastPathComponent()
        serverScriptURL = projectRootURL.appendingPathComponent("server.js")
        logURL = projectRootURL.appendingPathComponent("quota-window.log")
        pidURL = projectRootURL.appendingPathComponent("quota-window.pid")
    }

    func ensureRunning(completion: @escaping (Bool) -> Void) {
        guard !isStarting else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                completion(true)
            }
            return
        }

        isStarting = true
        DispatchQueue.global(qos: .utility).async {
            let didLaunch = self.launchServerIfPossible()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                self.isStarting = false
                completion(didLaunch)
            }
        }
    }

    private func launchServerIfPossible() -> Bool {
        guard FileManager.default.fileExists(atPath: serverScriptURL.path) else {
            return false
        }

        guard let nodeURL = nodeExecutableURL() else {
            return false
        }

        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try? FileHandle(forWritingTo: logURL)
        if let logHandle {
            do {
                try logHandle.seekToEnd()
            } catch {
                return false
            }
        }

        let process = Process()
        process.executableURL = nodeURL
        process.arguments = ["server.js"]
        process.currentDirectoryURL = projectRootURL
        process.standardOutput = logHandle
        process.standardError = logHandle

        do {
            try process.run()
            try "\(process.processIdentifier)\n".write(to: pidURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    private func nodeExecutableURL() -> URL? {
        let environmentNode = ProcessInfo.processInfo.environment["NODE"]
        let candidates = [
            environmentNode,
            "\(NSHomeDirectory())/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node",
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node"
        ].compactMap { $0 }

        return candidates
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

final class MeterBarView: NSView {
    var fraction: CGFloat = 0 {
        didSet {
            fraction = max(0, min(1, fraction))
            needsDisplay = true
        }
    }
    var trackColor = NSColor(calibratedRed: 0.90, green: 0.94, blue: 0.98, alpha: 1) {
        didSet { needsDisplay = true }
    }
    var fillColor = NSColor(calibratedRed: 0.31, green: 0.62, blue: 0.86, alpha: 1) {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        let track = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        trackColor.setFill()
        track.fill()

        guard fraction > 0 else { return }
        let fillWidth = max(bounds.height, bounds.width * fraction)
        let fillRect = NSRect(x: 0, y: 0, width: fillWidth, height: bounds.height)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius)
        fillColor.setFill()
        fill.fill()
    }
}

final class CompactMeterRow: NSView {
    private let nameLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "--%")
    private let resetLabel = NSTextField(labelWithString: "--")
    private let barView = MeterBarView()

    init(name: String, accessibilityLabel: String) {
        super.init(frame: .zero)
        setAccessibilityLabel(accessibilityLabel)
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.62).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor(calibratedRed: 0.68, green: 0.80, blue: 0.90, alpha: 0.7).cgColor

        nameLabel.stringValue = name
        nameLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        nameLabel.textColor = NSColor(calibratedRed: 0.27, green: 0.36, blue: 0.46, alpha: 1)
        nameLabel.alignment = .left

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        valueLabel.textColor = NSColor(calibratedRed: 0.09, green: 0.15, blue: 0.22, alpha: 1)
        valueLabel.alignment = .right

        resetLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        resetLabel.textColor = NSColor(calibratedRed: 0.42, green: 0.48, blue: 0.55, alpha: 1)
        resetLabel.alignment = .right

        for child in [nameLabel, valueLabel, resetLabel, barView] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 42),

            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.widthAnchor.constraint(equalToConstant: 42),

            valueLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 56),

            resetLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            resetLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            resetLabel.widthAnchor.constraint(equalToConstant: 70),

            barView.leadingAnchor.constraint(equalTo: valueLabel.trailingAnchor, constant: 8),
            barView.trailingAnchor.constraint(equalTo: resetLabel.leadingAnchor, constant: -8),
            barView.centerYAnchor.constraint(equalTo: centerYAnchor),
            barView.heightAnchor.constraint(equalToConstant: 6)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(with window: QuotaWindow?) {
        guard let window, window.status == "ok" else {
            valueLabel.stringValue = "--%"
            resetLabel.stringValue = "--"
            barView.fraction = 0
            return
        }

        let remaining = window.remainingPercent ?? 0
        valueLabel.stringValue = "\(remaining)%"
        resetLabel.stringValue = formatReset(window.resetsAtEpochSeconds)
        barView.fraction = CGFloat(remaining) / 100
        toolTip = "已用 \(window.usedPercent ?? 0)%，重置 \(resetLabel.stringValue)"
    }

    private func formatReset(_ epochSeconds: Int?) -> String {
        guard let epochSeconds else {
            return "--"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epochSeconds)))
    }

    func applyVisualStyle(_ style: QuotaVisualStyle) {
        switch style {
        case .creamBlue:
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.62).cgColor
            layer?.borderColor = NSColor(calibratedRed: 0.68, green: 0.80, blue: 0.90, alpha: 0.7).cgColor
            nameLabel.textColor = NSColor(calibratedRed: 0.27, green: 0.36, blue: 0.46, alpha: 1)
            valueLabel.textColor = NSColor(calibratedRed: 0.09, green: 0.15, blue: 0.22, alpha: 1)
            resetLabel.textColor = NSColor(calibratedRed: 0.42, green: 0.48, blue: 0.55, alpha: 1)
            barView.trackColor = NSColor(calibratedRed: 0.90, green: 0.94, blue: 0.98, alpha: 1)
            barView.fillColor = NSColor(calibratedRed: 0.31, green: 0.62, blue: 0.86, alpha: 1)
        case .minimalistDashboard:
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.78).cgColor
            layer?.borderColor = NSColor(calibratedRed: 0.82, green: 0.84, blue: 0.87, alpha: 0.9).cgColor
            nameLabel.textColor = NSColor(calibratedWhite: 0.28, alpha: 1)
            valueLabel.textColor = NSColor(calibratedWhite: 0.08, alpha: 1)
            resetLabel.textColor = NSColor(calibratedWhite: 0.42, alpha: 1)
            barView.trackColor = NSColor(calibratedWhite: 0.90, alpha: 1)
            barView.fillColor = NSColor(calibratedRed: 0.16, green: 0.62, blue: 0.39, alpha: 1)
        }
    }
}

final class CircularGaugeView: NSView {
    private let captionLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "--%")
    private let resetLabel = NSTextField(labelWithString: "--")

    private var fraction: CGFloat = 0
    private var trackColor = NSColor(calibratedWhite: 0.88, alpha: 1)
    private var fillColor = NSColor(calibratedRed: 0.31, green: 0.62, blue: 0.86, alpha: 1)

    init(caption: String, accessibilityLabel: String) {
        super.init(frame: .zero)
        setAccessibilityLabel(accessibilityLabel)
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.58).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor(calibratedRed: 0.68, green: 0.80, blue: 0.90, alpha: 0.55).cgColor

        captionLabel.stringValue = caption
        captionLabel.font = .systemFont(ofSize: 10, weight: .bold)
        captionLabel.alignment = .center

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        valueLabel.alignment = .center

        resetLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        resetLabel.alignment = .center

        for child in [captionLabel, valueLabel, resetLabel] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 110),

            captionLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            captionLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            valueLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 2),

            resetLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            resetLabel.centerXAnchor.constraint(equalTo: centerXAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let center = NSPoint(x: bounds.midX, y: bounds.midY + 7)
        let radius = min(bounds.width * 0.30, 31)
        drawArc(center: center, radius: radius, percent: 1, color: trackColor, width: 6)
        drawArc(center: center, radius: radius, percent: fraction, color: fillColor, width: 6)
    }

    func update(with window: QuotaWindow?) {
        guard let window, window.status == "ok" else {
            fraction = 0
            valueLabel.stringValue = "--%"
            resetLabel.stringValue = "--"
            needsDisplay = true
            return
        }

        let remaining = window.remainingPercent ?? 0
        fraction = CGFloat(max(0, min(100, remaining))) / 100
        valueLabel.stringValue = "\(remaining)%"
        resetLabel.stringValue = formatReset(window.resetsAtEpochSeconds)
        toolTip = "已用 \(window.usedPercent ?? 0)%，重置 \(resetLabel.stringValue)"
        needsDisplay = true
    }

    func applyVisualStyle(_ style: QuotaVisualStyle) {
        switch style {
        case .creamBlue:
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.58).cgColor
            layer?.borderColor = NSColor(calibratedRed: 0.68, green: 0.80, blue: 0.90, alpha: 0.55).cgColor
            captionLabel.textColor = NSColor(calibratedRed: 0.27, green: 0.36, blue: 0.46, alpha: 1)
            valueLabel.textColor = NSColor(calibratedRed: 0.09, green: 0.15, blue: 0.22, alpha: 1)
            resetLabel.textColor = NSColor(calibratedRed: 0.42, green: 0.48, blue: 0.55, alpha: 1)
            trackColor = NSColor(calibratedRed: 0.88, green: 0.94, blue: 0.99, alpha: 1)
            fillColor = NSColor(calibratedRed: 0.31, green: 0.62, blue: 0.86, alpha: 1)
        case .minimalistDashboard:
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.78).cgColor
            layer?.borderColor = NSColor(calibratedRed: 0.82, green: 0.84, blue: 0.87, alpha: 0.72).cgColor
            captionLabel.textColor = NSColor(calibratedWhite: 0.28, alpha: 1)
            valueLabel.textColor = NSColor(calibratedWhite: 0.08, alpha: 1)
            resetLabel.textColor = NSColor(calibratedWhite: 0.42, alpha: 1)
            trackColor = NSColor(calibratedWhite: 0.88, alpha: 1)
            fillColor = NSColor(calibratedRed: 0.16, green: 0.62, blue: 0.39, alpha: 1)
        }
        needsDisplay = true
    }

    private func drawArc(center: NSPoint, radius: CGFloat, percent: CGFloat, color: NSColor, width: CGFloat) {
        guard percent > 0 else { return }
        let startAngle: CGFloat = 205
        let endAngle = startAngle + (130 * max(0, min(1, percent)))
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.lineWidth = width
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    private func formatReset(_ epochSeconds: Int?) -> String {
        guard let epochSeconds else {
            return "--"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epochSeconds)))
    }
}

final class CapsuleViewController: NSViewController {
    private let dotCapsuleLabel = NSTextField(labelWithString: "●")
    private let activityCapsuleLabel = NSTextField(labelWithString: ActivityStatus.idle.label)
    private let quotaCapsuleLabel = NSTextField(labelWithString: "--/--")
    private var currentActivityStatus: ActivityStatus = .idle
    private var primaryWindow: QuotaWindow?
    private var secondaryWindow: QuotaWindow?
    var onOpenRequested: (() -> Void)?

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: capsuleWindowSize))
        view.wantsLayer = true
        view.layer?.cornerRadius = 20
        view.layer?.cornerCurve = .continuous
        view.layer?.backgroundColor = NSColor(calibratedRed: 0.96, green: 0.98, blue: 1.0, alpha: 0.94).cgColor
        view.setAccessibilityLabel("Codex 额度胶囊窗口")
        view.toolTip = "点击展开 Codex Meter"
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        dotCapsuleLabel.font = .systemFont(ofSize: 8, weight: .bold)
        dotCapsuleLabel.alignment = .center

        activityCapsuleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        activityCapsuleLabel.textColor = NSColor(calibratedRed: 0.27, green: 0.36, blue: 0.46, alpha: 1)
        activityCapsuleLabel.alignment = .left

        quotaCapsuleLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        quotaCapsuleLabel.textColor = NSColor(calibratedRed: 0.09, green: 0.15, blue: 0.22, alpha: 1)
        quotaCapsuleLabel.alignment = .right

        let stack = NSStackView(views: [dotCapsuleLabel, activityCapsuleLabel, quotaCapsuleLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .gravityAreas
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        view.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(capsuleClicked)))

        NSLayoutConstraint.activate([
            dotCapsuleLabel.widthAnchor.constraint(equalToConstant: 8),
            activityCapsuleLabel.widthAnchor.constraint(equalToConstant: 42),
            quotaCapsuleLabel.widthAnchor.constraint(equalToConstant: 52),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        updateActivityStatus(.idle)
    }

    func update(primary: QuotaWindow?, secondary: QuotaWindow?) {
        primaryWindow = primary
        secondaryWindow = secondary
        quotaCapsuleLabel.stringValue = "\(formatNumber(primary))/\(formatNumber(secondary))"
        updateTooltip()
    }

    func updateActivityStatus(_ status: ActivityStatus) {
        currentActivityStatus = status
        dotCapsuleLabel.textColor = status.color
        activityCapsuleLabel.stringValue = status.label
        updateTooltip()
    }

    private func formatPercent(_ window: QuotaWindow?) -> String {
        guard let window, window.status == "ok", let remaining = window.remainingPercent else {
            return "--%"
        }

        return "\(remaining)%"
    }

    private func formatNumber(_ window: QuotaWindow?) -> String {
        guard let window, window.status == "ok", let remaining = window.remainingPercent else {
            return "--"
        }

        return "\(remaining)"
    }

    private func updateTooltip() {
        let tooltip = "\(currentActivityStatus.label) · 主 \(formatPercent(primaryWindow))，周 \(formatPercent(secondaryWindow))"
        view.toolTip = tooltip
        view.setAccessibilityLabel("Codex 额度胶囊窗口，\(tooltip)")
    }

    @objc private func capsuleClicked() {
        onOpenRequested?()
    }
}

final class QuotaViewController: NSViewController {
    private let titleLabel = NSTextField(labelWithString: "Codex")
    private let primaryMeter = CompactMeterRow(name: "主额度", accessibilityLabel: "主额度")
    private let secondaryMeter = CompactMeterRow(name: "周额度", accessibilityLabel: "周额度")
    private let primaryGauge = CircularGaugeView(caption: "主额度", accessibilityLabel: "主额度圆形仪表盘")
    private let secondaryGauge = CircularGaugeView(caption: "周额度", accessibilityLabel: "周额度圆形仪表盘")
    private let shrinkButton = NSButton()
    private let gaugeButton = NSButton()
    private let colorButton = NSButton()
    private let refreshButton = NSButton()
    private let activityPill = ActivityPillView()
    private let contentStage = NSView()
    private lazy var rowStack = NSStackView(views: [primaryMeter, secondaryMeter])
    private lazy var gaugeStack = NSStackView(views: [primaryGauge, secondaryGauge])
    private var visualStyle: QuotaVisualStyle = .creamBlue
    private var displayMode: QuotaDisplayMode = .circularDashboard
    private var isAutoRefreshEnabled = true
    private var refreshTimer: Timer?
    private var idleStatusTimer: Timer?
    var onCapsuleRequested: (() -> Void)?
    var onQuotaWindowsChanged: ((QuotaWindow?, QuotaWindow?) -> Void)?
    var onStatusTextChanged: ((String) -> Void)?
    var onActivityStatusChanged: ((ActivityStatus) -> Void)?

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: expandedWindowSize))
        view.wantsLayer = true
        view.layer?.cornerRadius = 22
        view.layer?.cornerCurve = .continuous
        view.layer?.backgroundColor = NSColor(calibratedRed: 0.96, green: 0.98, blue: 1.0, alpha: 0.92).cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        refreshNow()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            guard let self, self.isAutoRefreshEnabled else { return }
            self.refreshNow()
        }
    }

    private func buildUI() {
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = NSColor(calibratedRed: 0.09, green: 0.15, blue: 0.22, alpha: 1)

        configureIconButton(shrinkButton, symbolName: "rectangle.compress.vertical", toolTip: "收起为胶囊", action: #selector(shrinkButtonPressed))
        configureIconButton(gaugeButton, symbolName: "gauge.medium", toolTip: "切换条形/圆形仪表盘", action: #selector(gaugeButtonPressed))
        configureIconButton(colorButton, symbolName: "paintpalette", toolTip: "切换颜色风格", action: #selector(colorButtonPressed))
        configureIconButton(refreshButton, symbolName: "arrow.clockwise", toolTip: "刷新", action: #selector(refreshButtonPressed))

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        for child in [activityPill, titleLabel, shrinkButton, gaugeButton, colorButton, refreshButton] {
            child.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(child)
        }

        rowStack.orientation = .vertical
        rowStack.alignment = .leading
        rowStack.distribution = .gravityAreas
        rowStack.spacing = 8
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        primaryMeter.widthAnchor.constraint(equalTo: rowStack.widthAnchor).isActive = true
        secondaryMeter.widthAnchor.constraint(equalTo: rowStack.widthAnchor).isActive = true

        gaugeStack.orientation = .horizontal
        gaugeStack.alignment = .centerY
        gaugeStack.distribution = .fillEqually
        gaugeStack.spacing = 12
        gaugeStack.translatesAutoresizingMaskIntoConstraints = false

        contentStage.translatesAutoresizingMaskIntoConstraints = false
        contentStage.addSubview(rowStack)
        contentStage.addSubview(gaugeStack)

        let stack = NSStackView(views: [header, contentStage])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .gravityAreas
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        for subview in stack.views {
            subview.translatesAutoresizingMaskIntoConstraints = false
            subview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: 24),
            contentStage.heightAnchor.constraint(equalToConstant: 116),
            activityPill.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            activityPill.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            shrinkButton.trailingAnchor.constraint(equalTo: gaugeButton.leadingAnchor, constant: -2),
            shrinkButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            shrinkButton.widthAnchor.constraint(equalToConstant: 22),
            shrinkButton.heightAnchor.constraint(equalToConstant: 22),

            gaugeButton.trailingAnchor.constraint(equalTo: colorButton.leadingAnchor, constant: -2),
            gaugeButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            gaugeButton.widthAnchor.constraint(equalToConstant: 22),
            gaugeButton.heightAnchor.constraint(equalToConstant: 22),

            colorButton.trailingAnchor.constraint(equalTo: refreshButton.leadingAnchor, constant: -2),
            colorButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            colorButton.widthAnchor.constraint(equalToConstant: 22),
            colorButton.heightAnchor.constraint(equalToConstant: 22),

            refreshButton.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            refreshButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            refreshButton.widthAnchor.constraint(equalToConstant: 24),
            refreshButton.heightAnchor.constraint(equalToConstant: 22),

            rowStack.leadingAnchor.constraint(equalTo: contentStage.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: contentStage.trailingAnchor),
            rowStack.centerYAnchor.constraint(equalTo: contentStage.centerYAnchor),
            rowStack.heightAnchor.constraint(equalToConstant: 92),

            gaugeStack.leadingAnchor.constraint(equalTo: contentStage.leadingAnchor),
            gaugeStack.trailingAnchor.constraint(equalTo: contentStage.trailingAnchor),
            gaugeStack.centerYAnchor.constraint(equalTo: contentStage.centerYAnchor),
            gaugeStack.heightAnchor.constraint(equalToConstant: 110),

            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12)
        ])

        applyVisualStyle()
        applyDisplayMode(animated: false)
    }

    private func configureIconButton(_ button: NSButton, symbolName: String, toolTip: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: toolTip)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.toolTip = toolTip
        button.target = self
        button.action = action
        button.alphaValue = 0.72
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    @objc private func refreshButtonPressed() {
        refreshNow()
    }

    @objc private func shrinkButtonPressed() {
        onCapsuleRequested?()
    }

    @objc private func gaugeButtonPressed() {
        displayMode.toggle()
        applyDisplayMode(animated: true)
    }

    @objc private func colorButtonPressed() {
        visualStyle.toggle()
        applyVisualStyle()
    }

    func refreshNow(allowServiceStart: Bool = true) {
        setActivityStatus(.working)
        refreshButton.isEnabled = false

        URLSession.shared.dataTask(with: quotaEndpoint) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshButton.isEnabled = true

                if error != nil {
                    self.handleRefreshFailure(allowServiceStart: allowServiceStart)
                    return
                }

                guard let data else {
                    self.handleRefreshFailure(allowServiceStart: allowServiceStart)
                    return
                }

                do {
                    let snapshot = try JSONDecoder().decode(QuotaSnapshot.self, from: data)
                    self.render(snapshot)
                } catch {
                    self.titleLabel.stringValue = "Codex !"
                    self.setActivityStatus(.waiting)
                }
            }
        }.resume()
    }

    private func render(_ snapshot: QuotaSnapshot) {
        let windows = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.key, $0) })
        primaryMeter.update(with: windows["primary"])
        secondaryMeter.update(with: windows["secondary"])
        primaryGauge.update(with: windows["primary"])
        secondaryGauge.update(with: windows["secondary"])
        onQuotaWindowsChanged?(windows["primary"], windows["secondary"])
        onStatusTextChanged?(statusText(primary: windows["primary"], secondary: windows["secondary"]))
        titleLabel.stringValue = "Codex"
        setActivityStatus(.done)
    }

    private func handleRefreshFailure(allowServiceStart: Bool) {
        guard allowServiceStart else {
            markRefreshFailed()
            return
        }

        LocalQuotaService.shared.ensureRunning { [weak self] didLaunch in
            guard let self else { return }
            if didLaunch {
                self.refreshNow(allowServiceStart: false)
            } else {
                self.markRefreshFailed()
            }
        }
    }

    private func markRefreshFailed() {
        titleLabel.stringValue = "Codex !"
        setActivityStatus(.waiting)
    }

    func toggleAutoRefresh() -> Bool {
        isAutoRefreshEnabled.toggle()
        return isAutoRefreshEnabled
    }

    func toggleVisualStyleFromMenu() {
        visualStyle.toggle()
        applyVisualStyle()
    }

    func toggleDisplayModeFromMenu() {
        displayMode.toggle()
        applyDisplayMode(animated: true)
    }

    private func statusText(primary: QuotaWindow?, secondary: QuotaWindow?) -> String {
        "\(statusPercent(primary))/\(statusPercent(secondary))"
    }

    private func statusPercent(_ window: QuotaWindow?) -> String {
        guard let window, window.status == "ok", let remaining = window.remainingPercent else {
            return "--"
        }

        return "\(remaining)"
    }

    private func setActivityStatus(_ status: ActivityStatus) {
        idleStatusTimer?.invalidate()
        activityPill.update(status: status)
        onActivityStatusChanged?(status)

        guard status == .done else { return }
        idleStatusTimer = Timer.scheduledTimer(withTimeInterval: 2.8, repeats: false) { [weak self] _ in
            self?.setActivityStatus(.idle)
        }
    }

    private func applyVisualStyle() {
        primaryMeter.applyVisualStyle(visualStyle)
        secondaryMeter.applyVisualStyle(visualStyle)
        primaryGauge.applyVisualStyle(visualStyle)
        secondaryGauge.applyVisualStyle(visualStyle)

        switch visualStyle {
        case .creamBlue:
            view.layer?.backgroundColor = NSColor(calibratedRed: 0.96, green: 0.98, blue: 1.0, alpha: 0.92).cgColor
            titleLabel.textColor = NSColor(calibratedRed: 0.09, green: 0.15, blue: 0.22, alpha: 1)
            for button in [shrinkButton, gaugeButton, colorButton, refreshButton] {
                button.contentTintColor = NSColor(calibratedRed: 0.18, green: 0.44, blue: 0.62, alpha: 1)
            }
            colorButton.toolTip = "切换到简约灰白配色"
        case .minimalistDashboard:
            view.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 0.94).cgColor
            titleLabel.textColor = NSColor(calibratedWhite: 0.08, alpha: 1)
            for button in [shrinkButton, gaugeButton, colorButton, refreshButton] {
                button.contentTintColor = NSColor(calibratedWhite: 0.18, alpha: 1)
            }
            colorButton.toolTip = "切换到奶油蓝配色"
        }
    }

    private func applyDisplayMode(animated: Bool) {
        let incoming: NSView
        let outgoing: NSView

        switch displayMode {
        case .compactBars:
            incoming = rowStack
            outgoing = gaugeStack
            gaugeButton.toolTip = "切换到圆形仪表盘"
        case .circularDashboard:
            incoming = gaugeStack
            outgoing = rowStack
            gaugeButton.toolTip = "切换到条形视图"
        }

        guard animated else {
            incoming.isHidden = false
            incoming.alphaValue = 1
            outgoing.isHidden = true
            outgoing.alphaValue = 0
            return
        }

        incoming.isHidden = false
        incoming.alphaValue = 0
        outgoing.isHidden = false
        outgoing.alphaValue = 1

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            incoming.animator().alphaValue = 1
            outgoing.animator().alphaValue = 0
        } completionHandler: {
            outgoing.isHidden = true
            incoming.alphaValue = 1
            outgoing.alphaValue = 0
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: NSPanel?
    private var capsulePanel: NSPanel?
    private var controller: QuotaViewController?
    private var capsuleController: CapsuleViewController?
    private var statusItem: NSStatusItem?
    private var autoRefreshMenuItem: NSMenuItem?
    private var activityMenuItem: NSMenuItem?
    private var currentActivityStatus: ActivityStatus = .idle
    private var quotaStatusText = "--/--"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = QuotaViewController()
        let capsuleController = CapsuleViewController()
        let panel = makePanel(
            size: expandedWindowSize,
            controller: controller
        )
        let capsulePanel = makePanel(
            size: capsuleWindowSize,
            controller: capsuleController
        )

        controller.onCapsuleRequested = { [weak self] in
            self?.showCapsule(nil)
        }
        controller.onQuotaWindowsChanged = { [weak self] primary, secondary in
            self?.capsuleController?.update(primary: primary, secondary: secondary)
        }
        controller.onStatusTextChanged = { [weak self] text in
            self?.updateStatusItemTitle(text)
        }
        controller.onActivityStatusChanged = { [weak self] status in
            self?.updateActivityStatus(status)
        }
        capsuleController.onOpenRequested = { [weak self] in
            self?.showExpanded(nil)
        }

        placePanel(panel)
        placePanel(capsulePanel)
        capsulePanel.orderOut(nil)
        panel.orderFrontRegardless()

        self.panel = panel
        self.capsulePanel = capsulePanel
        self.controller = controller
        self.capsuleController = capsuleController

        configureStatusItem()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideToMenuBar(sender)
        return false
    }

    private func makePanel(size: NSSize, controller: NSViewController) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = ""
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for buttonType in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(buttonType)?.isHidden = true
        }
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentViewController = controller
        panel.delegate = self

        return panel
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = nil

        let menu = NSMenu()
        menu.addItem(menuItem("显示窗口", action: #selector(showExpanded(_:))))
        menu.addItem(menuItem("收起为胶囊", action: #selector(showCapsule(_:))))
        menu.addItem(menuItem("隐藏到菜单栏", action: #selector(hideToMenuBar(_:))))
        menu.addItem(.separator())

        let activityItem = NSMenuItem(title: "状态：空闲", action: nil, keyEquivalent: "")
        menu.addItem(activityItem)
        activityMenuItem = activityItem

        menu.addItem(menuItem("手动刷新", action: #selector(refreshFromMenu(_:))))

        let autoItem = menuItem("自动更新", action: #selector(toggleAutoRefreshFromMenu(_:)))
        autoItem.state = .on
        menu.addItem(autoItem)
        autoRefreshMenuItem = autoItem

        menu.addItem(menuItem("切换颜色风格", action: #selector(toggleVisualStyleFromMenu(_:))))
        menu.addItem(menuItem("切换显示模式", action: #selector(toggleDisplayModeFromMenu(_:))))
        menu.addItem(.separator())
        menu.addItem(menuItem("退出", action: #selector(quitApp(_:))))

        statusItem.menu = menu
        self.statusItem = statusItem
        renderStatusItemTitle()
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func showExpanded(_ sender: Any?) {
        guard let panel else { return }

        if let capsulePanel, capsulePanel.isVisible {
            alignPanel(panel, toUpperRightOf: capsulePanel, size: expandedWindowSize)
        }

        capsulePanel?.orderOut(nil)
        panel.orderFrontRegardless()
    }

    @objc private func showCapsule(_ sender: Any?) {
        guard let panel, let capsulePanel else { return }

        alignPanel(capsulePanel, toUpperRightOf: panel, size: capsuleWindowSize)
        panel.orderOut(nil)
        capsulePanel.orderFrontRegardless()
    }

    @objc private func hideToMenuBar(_ sender: Any?) {
        panel?.orderOut(nil)
        capsulePanel?.orderOut(nil)
    }

    @objc private func refreshFromMenu(_ sender: Any?) {
        controller?.refreshNow()
    }

    @objc private func toggleAutoRefreshFromMenu(_ sender: Any?) {
        let isEnabled = controller?.toggleAutoRefresh() ?? false
        autoRefreshMenuItem?.state = isEnabled ? .on : .off
    }

    @objc private func toggleVisualStyleFromMenu(_ sender: Any?) {
        controller?.toggleVisualStyleFromMenu()
    }

    @objc private func toggleDisplayModeFromMenu(_ sender: Any?) {
        controller?.toggleDisplayModeFromMenu()
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func updateStatusItemTitle(_ text: String) {
        quotaStatusText = text
        renderStatusItemTitle()
    }

    private func updateActivityStatus(_ status: ActivityStatus) {
        currentActivityStatus = status
        capsuleController?.updateActivityStatus(status)
        activityMenuItem?.title = status.menuTitle
        renderStatusItemTitle()
    }

    private func renderStatusItemTitle() {
        let title = NSMutableAttributedString(attributedString: NSAttributedString(string: "● ",
            attributes: [
                .foregroundColor: currentActivityStatus.color,
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
            ]
        ))
        title.append(NSAttributedString(
            string: quotaStatusText,
            attributes: [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            ]
        ))
        guard let statusItem else { return }
        statusItem.button?.attributedTitle = title
        statusItem.button?.toolTip = "\(currentActivityStatus.label) · \(quotaStatusText)"
    }

    private func placePanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else {
            panel.center()
            return
        }

        let frame = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: frame.maxX - size.width - 24,
            y: frame.maxY - size.height - 24
        )
        panel.setFrameOrigin(origin)
    }

    private func alignPanel(_ panel: NSPanel, toUpperRightOf source: NSWindow, size: NSSize) {
        let sourceFrame = source.frame
        let origin = NSPoint(
            x: sourceFrame.maxX - size.width,
            y: sourceFrame.maxY - size.height
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: true)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
