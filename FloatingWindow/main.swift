import Cocoa
import Foundation

private let refreshInterval: TimeInterval = 60
private let quotaEndpoint = URL(string: "http://127.0.0.1:5487/api/rate-limits")!
private let compactWindowSize = NSSize(width: 312, height: 184)

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

        resetLabel.font = .monospacedDigitSystemFont(ofSize: 9, weight: .medium)
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
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 5),

            resetLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
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
        drawTicks(center: center, radius: radius)
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

    private func drawTicks(center: NSPoint, radius: CGFloat) {
        NSColor(calibratedWhite: 0.55, alpha: 0.45).setStroke()
        for index in 0...6 {
            let angle = (205 + CGFloat(index) * (130 / 6)) * .pi / 180
            let outer = NSPoint(x: center.x + cos(angle) * (radius + 8), y: center.y - sin(angle) * (radius + 8))
            let inner = NSPoint(x: center.x + cos(angle) * (radius + 3), y: center.y - sin(angle) * (radius + 3))
            let tick = NSBezierPath()
            tick.move(to: inner)
            tick.line(to: outer)
            tick.lineWidth = index == 0 || index == 6 ? 1.4 : 1
            tick.stroke()
        }
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

final class QuotaViewController: NSViewController {
    private let titleLabel = NSTextField(labelWithString: "Codex")
    private let primaryMeter = CompactMeterRow(name: "主额度", accessibilityLabel: "主额度")
    private let secondaryMeter = CompactMeterRow(name: "周额度", accessibilityLabel: "周额度")
    private let primaryGauge = CircularGaugeView(caption: "主额度", accessibilityLabel: "主额度圆形仪表盘")
    private let secondaryGauge = CircularGaugeView(caption: "周额度", accessibilityLabel: "周额度圆形仪表盘")
    private let gaugeButton = NSButton()
    private let colorButton = NSButton()
    private let refreshButton = NSButton()
    private let autoButton = NSButton(checkboxWithTitle: "自动", target: nil, action: nil)
    private let contentStage = NSView()
    private lazy var rowStack = NSStackView(views: [primaryMeter, secondaryMeter])
    private lazy var gaugeStack = NSStackView(views: [primaryGauge, secondaryGauge])
    private var visualStyle: QuotaVisualStyle = .creamBlue
    private var displayMode: QuotaDisplayMode = .circularDashboard
    private var refreshTimer: Timer?

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: compactWindowSize))
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
            guard let self, self.autoButton.state == .on else { return }
            self.refreshNow()
        }
    }

    private func buildUI() {
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = NSColor(calibratedRed: 0.09, green: 0.15, blue: 0.22, alpha: 1)

        configureIconButton(gaugeButton, symbolName: "gauge.medium", toolTip: "切换条形/圆形仪表盘", action: #selector(gaugeButtonPressed))
        configureIconButton(colorButton, symbolName: "paintpalette", toolTip: "切换颜色风格", action: #selector(colorButtonPressed))
        configureIconButton(refreshButton, symbolName: "arrow.clockwise", toolTip: "刷新", action: #selector(refreshButtonPressed))

        autoButton.state = .on
        autoButton.controlSize = .mini
        autoButton.font = .systemFont(ofSize: 10, weight: .medium)
        autoButton.toolTip = "每 60 秒自动更新"
        autoButton.alphaValue = 0.64
        autoButton.translatesAutoresizingMaskIntoConstraints = false

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        for child in [autoButton, titleLabel, gaugeButton, colorButton, refreshButton] {
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
            autoButton.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            autoButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),

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

    @objc private func gaugeButtonPressed() {
        displayMode.toggle()
        applyDisplayMode(animated: true)
    }

    @objc private func colorButtonPressed() {
        visualStyle.toggle()
        applyVisualStyle()
    }

    private func refreshNow() {
        refreshButton.isEnabled = false

        URLSession.shared.dataTask(with: quotaEndpoint) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshButton.isEnabled = true

                if error != nil {
                    self.titleLabel.stringValue = "Codex !"
                    return
                }

                guard let data else {
                    self.titleLabel.stringValue = "Codex !"
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
        titleLabel.stringValue = "Codex"
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
            autoButton.contentTintColor = NSColor(calibratedRed: 0.18, green: 0.44, blue: 0.62, alpha: 1)
            for button in [gaugeButton, colorButton, refreshButton] {
                button.contentTintColor = NSColor(calibratedRed: 0.18, green: 0.44, blue: 0.62, alpha: 1)
            }
            colorButton.toolTip = "切换到简约灰白配色"
        case .minimalistDashboard:
            view.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 0.94).cgColor
            titleLabel.textColor = NSColor(calibratedWhite: 0.08, alpha: 1)
            autoButton.contentTintColor = NSColor(calibratedWhite: 0.18, alpha: 1)
            for button in [gaugeButton, colorButton, refreshButton] {
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = QuotaViewController()
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: compactWindowSize),
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
        placePanel(panel)
        panel.orderFrontRegardless()

        self.panel = panel
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
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
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
