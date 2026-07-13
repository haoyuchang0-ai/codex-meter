import Cocoa
import Foundation

private let refreshInterval: TimeInterval = 60
private let activityRefreshInterval: TimeInterval = 1
private let activityFailureGraceInterval: TimeInterval = 10
private let quotaEndpoint = URL(string: "http://127.0.0.1:5487/api/rate-limits")!
private let activityEndpoint = URL(string: "http://127.0.0.1:5487/api/activity")!
private let activityTasksEndpoint = URL(string: "http://127.0.0.1:5487/api/activity/tasks")!
private let expandedWindowSize = NSSize(width: 312, height: 184)
private let capsuleWindowSize = NSSize(width: 156, height: 44)

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

private func quotaFillColor(for remainingPercent: Int) -> NSColor {
    if remainingPercent < 20 {
        return SageGraphitePalette.critical
    }
    if remainingPercent < 50 {
        return SageGraphitePalette.warning
    }
    return SageGraphitePalette.healthy
}

private func subscriptionDisplayName(_ planType: String?) -> String? {
    guard let value = planType?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty else {
        return nil
    }

    switch value.lowercased() {
    case "free": return "Free"
    case "plus": return "Plus"
    case "pro": return "Pro"
    case "team": return "Team"
    case "business": return "Business"
    case "enterprise": return "Enterprise"
    case "edu", "education": return "Edu"
    default: return value.prefix(1).uppercased() + String(value.dropFirst())
    }
}

private func subscriptionBadgeText(_ planType: String?) -> String? {
    guard let name = subscriptionDisplayName(planType) else { return nil }

    switch name.lowercased() {
    case "business": return "BUS"
    case "enterprise": return "ENT"
    default: return String(name.prefix(4)).uppercased()
    }
}

enum QuotaVisualStyle {
    case sageGraphite
    case minimalistDashboard

    mutating func toggle() {
        self = self == .sageGraphite ? .minimalistDashboard : .sageGraphite
    }
}

enum QuotaDisplayMode {
    case compactBars
    case circularDashboard

    mutating func toggle() {
        self = self == .compactBars ? .circularDashboard : .compactBars
    }
}

enum ActivityStatus: Equatable {
    case waiting
    case working
    case done
    case idle
    case unknown

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
        case .unknown:
            return "状态未知"
        }
    }

    var menuTitle: String {
        "状态：\(label)"
    }

    var color: NSColor {
        switch self {
        case .waiting:
            return SageGraphitePalette.critical
        case .working:
            return SageGraphitePalette.warning
        case .done:
            return SageGraphitePalette.completed
        case .idle:
            return SageGraphitePalette.idle
        case .unknown:
            return SageGraphitePalette.idle
        }
    }

    var symbolName: String {
        switch self {
        case .waiting:
            return "exclamationmark.triangle.fill"
        case .working:
            return "waveform.path"
        case .done:
            return "checkmark.circle.fill"
        case .idle:
            return "circle.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }

    init(apiValue: String) {
        switch apiValue {
        case "waiting": self = .waiting
        case "working": self = .working
        case "done": self = .done
        case "idle": self = .idle
        default: self = .unknown
        }
    }
}

final class ActivityWaveformView: NSView {
    private let barCount = 4
    private var bars: [CALayer] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        for _ in 0..<barCount {
            let bar = CALayer()
            bar.cornerRadius = 1
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        let heights: [CGFloat] = [7, 13, 9, 11]
        let barWidth: CGFloat = 2
        let spacing: CGFloat = 1.5
        let totalWidth = (CGFloat(barCount) * barWidth) + (CGFloat(barCount - 1) * spacing)
        let startX = bounds.midX - (totalWidth / 2) + (barWidth / 2)

        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: heights[index])
            bar.position = CGPoint(
                x: startX + (CGFloat(index) * (barWidth + spacing)),
                y: bounds.midY
            )
        }
    }

    func startAnimating(color: NSColor) {
        for (index, bar) in bars.enumerated() {
            bar.backgroundColor = color.cgColor
            bar.removeAnimation(forKey: "workingWave")
            bar.transform = CATransform3DIdentity

            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { continue }

            let animation = CABasicAnimation(keyPath: "transform.scale.y")
            animation.fromValue = index.isMultiple(of: 2) ? 0.42 : 0.62
            animation.toValue = 1.08
            animation.duration = 0.52 + (Double(index) * 0.04)
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.beginTime = CACurrentMediaTime() + (Double(index) * 0.11)
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.add(animation, forKey: "workingWave")
        }
    }

    func stopAnimating() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for bar in bars {
            bar.removeAnimation(forKey: "workingWave")
            bar.transform = CATransform3DIdentity
        }
        CATransaction.commit()
    }
}

final class ActivityCapsuleView: NSView {
    private let iconView = NSImageView()
    private let waveformView = ActivityWaveformView()
    private let textLabel = NSTextField(labelWithString: ActivityStatus.idle.label)
    private var currentStatus: ActivityStatus?
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        layer?.borderWidth = 0.5
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(capsuleClicked)))

        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        waveformView.isHidden = true

        textLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        textLabel.textColor = SageGraphitePalette.secondaryText
        textLabel.alignment = .left
        textLabel.lineBreakMode = .byClipping
        textLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(waveformView)
        addSubview(textLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 96),
            heightAnchor.constraint(equalToConstant: 24),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 15),
            iconView.heightAnchor.constraint(equalToConstant: 15),
            waveformView.leadingAnchor.constraint(equalTo: iconView.leadingAnchor),
            waveformView.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            waveformView.widthAnchor.constraint(equalTo: iconView.widthAnchor),
            waveformView.heightAnchor.constraint(equalTo: iconView.heightAnchor),
            textLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        update(status: .idle, animated: false)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: NSCursor.pointingHand)
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }

    @objc private func capsuleClicked() {
        onClick?()
    }

    func update(status: ActivityStatus, animated: Bool = true) {
        guard currentStatus != status else { return }
        let hadStatus = currentStatus != nil
        currentStatus = status

        let apply = {
            let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            self.iconView.image = NSImage(
                systemSymbolName: status.symbolName,
                accessibilityDescription: status.label
            )?.withSymbolConfiguration(configuration)
            self.iconView.contentTintColor = status.color
            let isWorking = status == .working
            self.iconView.isHidden = isWorking
            self.waveformView.isHidden = !isWorking
            if isWorking {
                self.waveformView.startAnimating(color: status.color)
            } else {
                self.waveformView.stopAnimating()
            }
            self.textLabel.font = .systemFont(
                ofSize: status == .unknown ? 9 : 11,
                weight: .semibold
            )
            self.textLabel.stringValue = status.label
            self.layer?.backgroundColor = status.color.withAlphaComponent(
                status == .idle ? 0.08 : 0.13
            ).cgColor
            self.layer?.borderColor = status.color.withAlphaComponent(0.22).cgColor
            let actionLabel = "\(status.menuTitle)，点击查看进行中的任务"
            self.setAccessibilityLabel(actionLabel)
            self.toolTip = actionLabel
        }

        guard animated, hadStatus, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            apply()
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.setAffineTransform(CGAffineTransform(scaleX: 1.05, y: 1.05))
        iconView.alphaValue = 0.30
        waveformView.alphaValue = 0.30
        textLabel.alphaValue = 0.55
        apply()
        CATransaction.commit()

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        layer?.setAffineTransform(.identity)
        CATransaction.commit()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            iconView.animator().alphaValue = 1
            waveformView.animator().alphaValue = 1
            textLabel.animator().alphaValue = 1
        }
    }
}

final class SubscriptionBadgeView: NSView {
    private let textLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8.5
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        translatesAutoresizingMaskIntoConstraints = false

        textLabel.font = .systemFont(ofSize: 8, weight: .bold)
        textLabel.alignment = .center
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 34),
            heightAnchor.constraint(equalToConstant: 17),
            textLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            textLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        update(planType: nil)
        applyVisualStyle(.sageGraphite)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(planType: String?) {
        let displayName = subscriptionDisplayName(planType)
        textLabel.stringValue = subscriptionBadgeText(planType) ?? ""
        alphaValue = displayName == nil ? 0 : 1
        toolTip = displayName.map { "当前订阅：\($0)" }
        setAccessibilityLabel(displayName.map { "当前订阅 \($0)" })
    }

    func applyVisualStyle(_ style: QuotaVisualStyle) {
        switch style {
        case .sageGraphite:
            layer?.backgroundColor = SageGraphitePalette.controlTint.withAlphaComponent(0.10).cgColor
            layer?.borderColor = SageGraphitePalette.controlTint.withAlphaComponent(0.20).cgColor
            textLabel.textColor = SageGraphitePalette.controlTint
        case .minimalistDashboard:
            layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.07).cgColor
            layer?.borderColor = NSColor(calibratedWhite: 0.18, alpha: 0.14).cgColor
            textLabel.textColor = NSColor(calibratedWhite: 0.28, alpha: 1)
        }
    }
}

final class ActivityTaskMenuPresenter: NSObject {
    static let shared = ActivityTaskMenuPresenter()

    private var isLoading = false

    func present(from anchorView: NSView) {
        guard !isLoading else { return }
        isLoading = true

        var request = URLRequest(url: activityTasksEndpoint)
        request.timeoutInterval = 3
        URLSession.shared.dataTask(with: request) { [weak self, weak anchorView] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                guard let anchorView, anchorView.window != nil else { return }

                guard error == nil,
                      let data,
                      let snapshot = try? JSONDecoder().decode(ActivityTaskListSnapshot.self, from: data) else {
                    self.showMessage("暂时无法读取任务列表", from: anchorView)
                    return
                }
                self.showMenu(tasks: snapshot.tasks, from: anchorView)
            }
        }.resume()
    }

    private func showMenu(tasks: [ActivityTask], from anchorView: NSView) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = 236

        let headerTitle = "进行中的任务 · \(tasks.count)"
        if #available(macOS 14.0, *) {
            menu.addItem(NSMenuItem.sectionHeader(title: headerTitle))
        } else {
            let header = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(.separator())
        }

        if tasks.isEmpty {
            let emptyItem = NSMenuItem(title: "当前没有进行中的任务", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for task in tasks {
                let statusLabel = task.status == "waiting" ? "待确认" : "工作中"
                let symbolName = task.status == "waiting"
                    ? "exclamationmark.triangle.fill"
                    : "waveform.path"
                let item = NSMenuItem(
                    title: "\(shortTitle(task.title))  ·  \(statusLabel)",
                    action: #selector(openTask(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = task.threadId
                item.toolTip = "在 Codex 中打开"
                item.image = NSImage(
                    systemSymbolName: symbolName,
                    accessibilityDescription: statusLabel
                )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
                menu.addItem(item)
            }
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -5), in: anchorView)
    }

    private func showMessage(_ message: String, from anchorView: NSView) {
        let menu = NSMenu()
        menu.minimumWidth = 236
        let item = NSMenuItem(title: message, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -5), in: anchorView)
    }

    private func shortTitle(_ title: String) -> String {
        guard title.count > 30 else { return title }
        return "\(title.prefix(29))…"
    }

    @objc private func openTask(_ sender: NSMenuItem) {
        guard let threadId = sender.representedObject as? String,
              let url = URL(string: "codex://threads/\(threadId)") else { return }
        NSWorkspace.shared.open(url)
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
    var trackColor = SageGraphitePalette.progressTrack {
        didSet { needsDisplay = true }
    }
    var fillColor = SageGraphitePalette.healthy {
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
    private var remainingPercent: Int?

    init(name: String, accessibilityLabel: String) {
        super.init(frame: .zero)
        setAccessibilityLabel(accessibilityLabel)
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = SageGraphitePalette.cardSurface.cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = SageGraphitePalette.cardBorder.cgColor

        nameLabel.stringValue = name
        nameLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        nameLabel.textColor = SageGraphitePalette.secondaryText
        nameLabel.alignment = .left

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        valueLabel.textColor = SageGraphitePalette.primaryText
        valueLabel.alignment = .right

        resetLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        resetLabel.textColor = SageGraphitePalette.tertiaryText
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
            remainingPercent = nil
            valueLabel.stringValue = "--%"
            resetLabel.stringValue = "--"
            barView.fraction = 0
            return
        }

        let remaining = window.remainingPercent ?? 0
        remainingPercent = remaining
        valueLabel.stringValue = "\(remaining)%"
        resetLabel.stringValue = formatReset(window.resetsAtEpochSeconds)
        barView.fraction = CGFloat(remaining) / 100
        barView.fillColor = quotaFillColor(for: remaining)
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
        case .sageGraphite:
            layer?.backgroundColor = SageGraphitePalette.cardSurface.cgColor
            layer?.borderColor = SageGraphitePalette.cardBorder.cgColor
            nameLabel.textColor = SageGraphitePalette.secondaryText
            valueLabel.textColor = SageGraphitePalette.primaryText
            resetLabel.textColor = SageGraphitePalette.tertiaryText
            barView.trackColor = SageGraphitePalette.progressTrack
        case .minimalistDashboard:
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.78).cgColor
            layer?.borderColor = NSColor(calibratedRed: 0.82, green: 0.84, blue: 0.87, alpha: 0.9).cgColor
            nameLabel.textColor = NSColor(calibratedWhite: 0.28, alpha: 1)
            valueLabel.textColor = NSColor(calibratedWhite: 0.08, alpha: 1)
            resetLabel.textColor = NSColor(calibratedWhite: 0.42, alpha: 1)
            barView.trackColor = NSColor(calibratedWhite: 0.90, alpha: 1)
        }
        if let remainingPercent {
            barView.fillColor = quotaFillColor(for: remainingPercent)
        }
    }
}

final class CircularGaugeView: NSView {
    private let captionLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "--%")
    private let resetLabel = NSTextField(labelWithString: "--")

    private var fraction: CGFloat = 0
    private var trackColor = NSColor(calibratedWhite: 0.88, alpha: 1)
    private var fillColor = SageGraphitePalette.healthy
    private var remainingPercent: Int?

    init(caption: String, accessibilityLabel: String) {
        super.init(frame: .zero)
        setAccessibilityLabel(accessibilityLabel)
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = SageGraphitePalette.cardSurface.cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = SageGraphitePalette.cardBorder.cgColor

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
            remainingPercent = nil
            fraction = 0
            valueLabel.stringValue = "--%"
            resetLabel.stringValue = "--"
            needsDisplay = true
            return
        }

        let remaining = window.remainingPercent ?? 0
        remainingPercent = remaining
        fraction = CGFloat(max(0, min(100, remaining))) / 100
        fillColor = quotaFillColor(for: remaining)
        valueLabel.stringValue = "\(remaining)%"
        resetLabel.stringValue = formatReset(window.resetsAtEpochSeconds)
        toolTip = "已用 \(window.usedPercent ?? 0)%，重置 \(resetLabel.stringValue)"
        needsDisplay = true
    }

    func applyVisualStyle(_ style: QuotaVisualStyle) {
        switch style {
        case .sageGraphite:
            layer?.backgroundColor = SageGraphitePalette.cardSurface.cgColor
            layer?.borderColor = SageGraphitePalette.cardBorder.cgColor
            captionLabel.textColor = SageGraphitePalette.secondaryText
            valueLabel.textColor = SageGraphitePalette.primaryText
            resetLabel.textColor = SageGraphitePalette.tertiaryText
            trackColor = SageGraphitePalette.progressTrack
        case .minimalistDashboard:
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.78).cgColor
            layer?.borderColor = NSColor(calibratedRed: 0.82, green: 0.84, blue: 0.87, alpha: 0.72).cgColor
            captionLabel.textColor = NSColor(calibratedWhite: 0.28, alpha: 1)
            valueLabel.textColor = NSColor(calibratedWhite: 0.08, alpha: 1)
            resetLabel.textColor = NSColor(calibratedWhite: 0.42, alpha: 1)
            trackColor = NSColor(calibratedWhite: 0.88, alpha: 1)
        }
        if let remainingPercent {
            fillColor = quotaFillColor(for: remainingPercent)
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

final class CapsuleViewController: NSViewController, NSGestureRecognizerDelegate {
    private let activityStatusCapsule = ActivityCapsuleView()
    private let subscriptionLabel = NSTextField(labelWithString: "")
    private let quotaCapsuleLabel = NSTextField(labelWithString: "--/--")
    private var currentActivityStatus: ActivityStatus = .idle
    private var currentPlanType: String?
    private var primaryWindow: QuotaWindow?
    private var secondaryWindow: QuotaWindow?
    private lazy var expandGestureRecognizer = NSClickGestureRecognizer(
        target: self,
        action: #selector(capsuleClicked(_:))
    )
    var onOpenRequested: (() -> Void)?

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: capsuleWindowSize))
        view.wantsLayer = true
        view.layer?.cornerRadius = 20
        view.layer?.cornerCurve = .continuous
        view.layer?.backgroundColor = SageGraphitePalette.windowBackground.cgColor
        view.setAccessibilityLabel("Codex 额度胶囊窗口")
        view.toolTip = "点击展开 Codex Meter"
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        quotaCapsuleLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        quotaCapsuleLabel.textColor = SageGraphitePalette.primaryText
        quotaCapsuleLabel.alignment = .right

        subscriptionLabel.font = .systemFont(ofSize: 8, weight: .bold)
        subscriptionLabel.textColor = SageGraphitePalette.controlTint
        subscriptionLabel.alignment = .right

        let quotaInfoView = NSView()
        quotaInfoView.translatesAutoresizingMaskIntoConstraints = false
        for child in [subscriptionLabel, quotaCapsuleLabel] {
            child.translatesAutoresizingMaskIntoConstraints = false
            quotaInfoView.addSubview(child)
        }

        let stack = NSStackView(views: [activityStatusCapsule, quotaInfoView])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .gravityAreas
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        activityStatusCapsule.onClick = { [weak self] in
            guard let self else { return }
            ActivityTaskMenuPresenter.shared.present(from: self.activityStatusCapsule)
        }

        view.addSubview(stack)
        expandGestureRecognizer.delegate = self
        view.addGestureRecognizer(expandGestureRecognizer)

        NSLayoutConstraint.activate([
            quotaInfoView.widthAnchor.constraint(equalToConstant: 52),
            quotaInfoView.heightAnchor.constraint(equalToConstant: 24),
            subscriptionLabel.topAnchor.constraint(equalTo: quotaInfoView.topAnchor),
            subscriptionLabel.leadingAnchor.constraint(equalTo: quotaInfoView.leadingAnchor),
            subscriptionLabel.trailingAnchor.constraint(equalTo: quotaInfoView.trailingAnchor, constant: -6),
            quotaCapsuleLabel.bottomAnchor.constraint(equalTo: quotaInfoView.bottomAnchor),
            quotaCapsuleLabel.leadingAnchor.constraint(equalTo: quotaInfoView.leadingAnchor),
            quotaCapsuleLabel.trailingAnchor.constraint(equalTo: quotaInfoView.trailingAnchor, constant: -6),
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
        activityStatusCapsule.update(status: status)
        updateTooltip()
    }

    func updatePlanType(_ planType: String?) {
        currentPlanType = planType
        subscriptionLabel.stringValue = subscriptionBadgeText(planType) ?? ""
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
        let subscription = subscriptionDisplayName(currentPlanType).map { " · 订阅 \($0)" } ?? ""
        let tooltip = "\(currentActivityStatus.label)\(subscription) · 主 \(formatPercent(primaryWindow))，周 \(formatPercent(secondaryWindow))"
        view.toolTip = tooltip
        view.setAccessibilityLabel("Codex 额度胶囊窗口，\(tooltip)")
    }

    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldAttemptToRecognizeWith event: NSEvent
    ) -> Bool {
        guard gestureRecognizer === expandGestureRecognizer else { return true }
        let location = view.convert(event.locationInWindow, from: nil)
        let statusFrame = view.convert(activityStatusCapsule.bounds, from: activityStatusCapsule)
        return !statusFrame.contains(location)
    }

    @objc private func capsuleClicked(_ recognizer: NSClickGestureRecognizer) {
        let statusFrame = view.convert(activityStatusCapsule.bounds, from: activityStatusCapsule)
        guard !statusFrame.contains(recognizer.location(in: view)) else { return }
        onOpenRequested?()
    }
}

final class QuotaViewController: NSViewController {
    private let titleLabel = NSTextField(labelWithString: "Codex")
    private let subscriptionBadge = SubscriptionBadgeView()
    private let primaryMeter = CompactMeterRow(name: "主额度", accessibilityLabel: "主额度")
    private let secondaryMeter = CompactMeterRow(name: "周额度", accessibilityLabel: "周额度")
    private let primaryGauge = CircularGaugeView(caption: "主额度", accessibilityLabel: "主额度圆形仪表盘")
    private let secondaryGauge = CircularGaugeView(caption: "周额度", accessibilityLabel: "周额度圆形仪表盘")
    private let shrinkButton = NSButton()
    private let gaugeButton = NSButton()
    private let colorButton = NSButton()
    private let refreshButton = NSButton()
    private let activityCapsule = ActivityCapsuleView()
    private let contentStage = NSView()
    private lazy var rowStack = NSStackView(views: [primaryMeter, secondaryMeter])
    private lazy var gaugeStack = NSStackView(views: [primaryGauge, secondaryGauge])
    private var visualStyle: QuotaVisualStyle = .sageGraphite
    private var displayMode: QuotaDisplayMode = .circularDashboard
    private var isAutoRefreshEnabled = true
    private var refreshTimer: Timer?
    private var activityTimer: Timer?
    private var lastActivitySuccessAt: Date?
    private var activityFailureStartedAt: Date?
    var onCapsuleRequested: (() -> Void)?
    var onQuotaWindowsChanged: ((QuotaWindow?, QuotaWindow?) -> Void)?
    var onStatusTextChanged: ((String) -> Void)?
    var onActivityStatusChanged: ((ActivityStatus) -> Void)?
    var onActivityIntegrationChanged: ((Bool) -> Void)?
    var onPlanTypeChanged: ((String?) -> Void)?

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: expandedWindowSize))
        view.wantsLayer = true
        view.layer?.cornerRadius = 22
        view.layer?.cornerCurve = .continuous
        view.layer?.backgroundColor = SageGraphitePalette.windowBackground.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        refreshNow()
        refreshActivityNow()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            guard let self, self.isAutoRefreshEnabled else { return }
            self.refreshNow()
        }
        activityTimer = Timer.scheduledTimer(withTimeInterval: activityRefreshInterval, repeats: true) { [weak self] _ in
            self?.refreshActivityNow()
        }
    }

    private func buildUI() {
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = SageGraphitePalette.primaryText

        configureIconButton(shrinkButton, symbolName: "rectangle.compress.vertical", toolTip: "收起为胶囊", action: #selector(shrinkButtonPressed))
        configureIconButton(gaugeButton, symbolName: "gauge.medium", toolTip: "切换条形/圆形仪表盘", action: #selector(gaugeButtonPressed))
        configureIconButton(colorButton, symbolName: "paintpalette", toolTip: "切换颜色风格", action: #selector(colorButtonPressed))
        configureIconButton(refreshButton, symbolName: "arrow.clockwise", toolTip: "刷新", action: #selector(refreshButtonPressed))
        activityCapsule.onClick = { [weak self] in
            guard let self else { return }
            ActivityTaskMenuPresenter.shared.present(from: self.activityCapsule)
        }

        let brandGroup = NSStackView(views: [titleLabel, subscriptionBadge])
        brandGroup.orientation = .horizontal
        brandGroup.alignment = .centerY
        brandGroup.spacing = 5
        brandGroup.translatesAutoresizingMaskIntoConstraints = false

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        for child in [activityCapsule, brandGroup, shrinkButton, gaugeButton, colorButton, refreshButton] {
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
            activityCapsule.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            activityCapsule.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            brandGroup.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            brandGroup.centerYAnchor.constraint(equalTo: header.centerYAnchor),

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
        subscriptionBadge.update(planType: snapshot.planType)
        onQuotaWindowsChanged?(windows["primary"], windows["secondary"])
        onStatusTextChanged?(statusText(primary: windows["primary"], secondary: windows["secondary"]))
        onPlanTypeChanged?(snapshot.planType)
        titleLabel.stringValue = "Codex"
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
    }

    private func refreshActivityNow() {
        URLSession.shared.dataTask(with: activityEndpoint) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard error == nil,
                      let data,
                      let snapshot = try? JSONDecoder().decode(ActivitySnapshot.self, from: data) else {
                    self.handleActivityFailure()
                    return
                }

                self.lastActivitySuccessAt = Date()
                self.activityFailureStartedAt = nil
                self.setActivityStatus(ActivityStatus(apiValue: snapshot.status))
                self.onActivityIntegrationChanged?(snapshot.hooksInstalled)
            }
        }.resume()
    }

    private func handleActivityFailure() {
        if activityFailureStartedAt == nil {
            activityFailureStartedAt = Date()
        }

        guard let activityFailureStartedAt,
              Date().timeIntervalSince(activityFailureStartedAt) >= activityFailureGraceInterval else {
            return
        }

        setActivityStatus(.unknown)
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
        activityCapsule.update(status: status)
        onActivityStatusChanged?(status)
    }

    private func applyVisualStyle() {
        primaryMeter.applyVisualStyle(visualStyle)
        secondaryMeter.applyVisualStyle(visualStyle)
        primaryGauge.applyVisualStyle(visualStyle)
        secondaryGauge.applyVisualStyle(visualStyle)
        subscriptionBadge.applyVisualStyle(visualStyle)

        switch visualStyle {
        case .sageGraphite:
            view.layer?.backgroundColor = SageGraphitePalette.windowBackground.cgColor
            titleLabel.textColor = SageGraphitePalette.primaryText
            for button in [shrinkButton, gaugeButton, colorButton, refreshButton] {
                button.contentTintColor = SageGraphitePalette.controlTint
            }
            colorButton.toolTip = "切换到简约灰白配色"
        case .minimalistDashboard:
            view.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 0.94).cgColor
            titleLabel.textColor = NSColor(calibratedWhite: 0.08, alpha: 1)
            for button in [shrinkButton, gaugeButton, colorButton, refreshButton] {
                button.contentTintColor = NSColor(calibratedWhite: 0.18, alpha: 1)
            }
            colorButton.toolTip = "切换到鼠尾草配色"
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
    private var activityIntegrationMenuItem: NSMenuItem?
    private var subscriptionMenuItem: NSMenuItem?
    private var currentActivityStatus: ActivityStatus = .idle
    private var currentPlanName: String?
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
        controller.onActivityIntegrationChanged = { [weak self] installed in
            self?.updateActivityIntegration(installed)
        }
        controller.onPlanTypeChanged = { [weak self] planType in
            self?.updatePlanType(planType)
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

        let integrationItem = NSMenuItem(title: "状态监听：检查中", action: nil, keyEquivalent: "")
        menu.addItem(integrationItem)
        activityIntegrationMenuItem = integrationItem

        let subscriptionItem = NSMenuItem(title: "订阅：读取中", action: nil, keyEquivalent: "")
        menu.addItem(subscriptionItem)
        subscriptionMenuItem = subscriptionItem

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

    private func updateActivityIntegration(_ installed: Bool) {
        activityIntegrationMenuItem?.title = installed
            ? "状态监听：完整"
            : "状态监听：需安装 Hooks"
        activityIntegrationMenuItem?.toolTip = installed
            ? "Codex Meter 正在读取完整本地任务状态"
            : "在项目目录运行 npm run install:hooks，然后重启 Codex"
    }

    private func updatePlanType(_ planType: String?) {
        currentPlanName = subscriptionDisplayName(planType)
        capsuleController?.updatePlanType(planType)
        subscriptionMenuItem?.title = "订阅：\(currentPlanName ?? "未知")"
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
        let subscription = currentPlanName.map { " · 订阅 \($0)" } ?? ""
        statusItem.button?.toolTip = "\(currentActivityStatus.label)\(subscription) · \(quotaStatusText)"
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
