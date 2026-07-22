import AppKit
import CoreGraphics
import Foundation

struct UsageMetric: Equatable {
    let usedPercent: Double
    let resetsAt: Date?
    let observedAt: Date
    let source: String

    var remainingPercent: Int {
        Int((100 - usedPercent).rounded().clamped(to: 0...100))
    }

    var usedDisplay: Int {
        Int(usedPercent.rounded().clamped(to: 0...100))
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

enum UsageReader {
    private static let cocoaEpochOffset = 978_307_200.0
    private static let targetWindowMinutes = 10_080.0

    static func current() -> UsageMetric? {
        [readCodexBar(), readRecentSessions()]
            .compactMap { $0 }
            .max { $0.observedAt < $1.observedAt }
    }

    static func readCodexBar() -> UsageMetric? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexBar/codex-account-snapshots.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = root["records"] as? [[String: Any]] else { return nil }

        return records.compactMap { record -> UsageMetric? in
            guard let snapshot = record["snapshot"] as? [String: Any],
                  let lane = preferredLane(in: snapshot),
                  let used = number(lane["usedPercent"]) else { return nil }
            let observedRaw = number(snapshot["updatedAt"]) ?? 0
            let observed = date(fromPossiblyCocoaSeconds: observedRaw)
            let reset = number(lane["resetsAt"]).map(date(fromPossiblyCocoaSeconds:))
            return UsageMetric(usedPercent: used, resetsAt: reset, observedAt: observed, source: "CodexBar")
        }.max { $0.observedAt < $1.observedAt }
    }

    static func readRecentSessions() -> UsageMetric? {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var candidates: [(URL, Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate else { continue }
            candidates.append((url, modified))
        }

        for (url, _) in candidates.sorted(by: { $0.1 > $1.1 }).prefix(40) {
            if let metric = readSession(url) { return metric }
        }
        return nil
    }

    private static func readSession(_ url: URL) -> UsageMetric? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let length = (try? handle.seekToEnd()) ?? 0
        let start = length > 524_288 ? length - 524_288 : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return nil }

        for line in text.split(separator: "\n").reversed() {
            guard let data = String(line).data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = event["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let limits = payload["rate_limits"] as? [String: Any],
                  let lane = preferredLane(in: limits),
                  let used = number(lane["used_percent"]) else { continue }
            let timestamp = (event["timestamp"] as? String).flatMap(isoDate) ?? Date.distantPast
            let reset = number(lane["resets_at"]).map { Date(timeIntervalSince1970: $0) }
            return UsageMetric(usedPercent: used, resetsAt: reset, observedAt: timestamp, source: "Codex")
        }
        return nil
    }

    private static func preferredLane(in object: [String: Any]) -> [String: Any]? {
        let lanes = ["primary", "secondary", "tertiary"].compactMap { object[$0] as? [String: Any] }
        return lanes.min {
            abs((number($0["windowMinutes"]) ?? number($0["window_minutes"]) ?? 0) - targetWindowMinutes)
                < abs((number($1["windowMinutes"]) ?? number($1["window_minutes"]) ?? 0) - targetWindowMinutes)
        }
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func date(fromPossiblyCocoaSeconds value: Double) -> Date {
        value < 1_200_000_000
            ? Date(timeIntervalSince1970: value + cocoaEpochOffset)
            : Date(timeIntervalSince1970: value)
    }

    private static func isoDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

final class BalanceView: NSView {
    private enum Layout {
        static let compactHorizontalPadding: CGFloat = 2
        static let compactTextGap: CGFloat = 8
        static let compactTextY: CGFloat = 7
        static let compactFontSize: CGFloat = 14
    }

    var metric: UsageMetric? { didSet { needsDisplay = true } }
    var expanded = false
    var onToggle: (() -> Void)?

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        expanded.toggle()
        onToggle?()
        needsDisplay = true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if expanded {
            let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
            cardFillColor.setFill()
            card.fill()
            borderColor.setStroke()
            card.lineWidth = 1
            card.stroke()
        }

        expanded ? drawExpanded() : drawCompact()
    }

    private func drawCompact() {
        let remaining = metric.map { "\($0.remainingPercent)%" } ?? "–"
        let label = "weekly"
        let labelFont = NSFont.systemFont(ofSize: Layout.compactFontSize, weight: .regular)
        let labelWidth = ceil((label as NSString).size(withAttributes: [.font: labelFont]).width)
        drawText(
            label,
            at: NSPoint(x: Layout.compactHorizontalPadding, y: Layout.compactTextY),
            size: Layout.compactFontSize,
            color: secondaryColor
        )
        drawText(
            remaining,
            at: NSPoint(
                x: Layout.compactHorizontalPadding + labelWidth + Layout.compactTextGap,
                y: Layout.compactTextY
            ),
            size: Layout.compactFontSize,
            weight: .medium,
            color: primaryColor
        )
    }

    private func drawExpanded() {
        let remaining = metric.map { "\($0.remainingPercent)%" } ?? "–"
        drawText("weekly", at: NSPoint(x: 14, y: 13), size: 14, color: primaryColor)
        drawRightAlignedText(remaining, rightInset: 14, y: 13, size: 14, weight: .medium, monospacedDigits: false, color: primaryColor)

        if let metric {
            drawText("\(metric.usedDisplay)% used", at: NSPoint(x: 14, y: 39), size: 14, color: secondaryColor)
            let reset = metric.resetsAt.map { Self.resetFormatter.string(from: $0) } ?? "unknown"
            drawText("Resets \(reset)", at: NSPoint(x: 14, y: 62), size: 13, color: secondaryColor)
            drawProgress(remaining: Double(metric.remainingPercent) / 100)
        } else {
            drawText("No usage data yet", at: NSPoint(x: 14, y: 42), size: 14, color: secondaryColor)
            drawText("Complete one Codex turn to refresh", at: NSPoint(x: 14, y: 65), size: 12, color: secondaryColor)
            drawProgress(remaining: 0)
        }
    }

    private func drawProgress(remaining: Double) {
        let rect = NSRect(x: 14, y: bounds.height - 15, width: bounds.width - 28, height: 5)
        let track = NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5)
        progressTrackColor.setFill()
        track.fill()
        let filled = NSRect(x: rect.minX, y: rect.minY, width: max(5, rect.width * remaining.clamped(to: 0...1)), height: rect.height)
        progressFillColor.setFill()
        NSBezierPath(roundedRect: filled, xRadius: 2.5, yRadius: 2.5).fill()
    }

    private func drawText(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) {
        text.draw(at: point, withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color
        ])
    }

    private func drawRightAlignedText(
        _ text: String,
        rightInset: CGFloat,
        y: CGFloat,
        size: CGFloat,
        weight: NSFont.Weight,
        monospacedDigits: Bool,
        color: NSColor
    ) {
        let font = monospacedDigits
            ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let width = ceil((text as NSString).size(withAttributes: attributes).width)
        text.draw(at: NSPoint(x: bounds.width - rightInset - width, y: y), withAttributes: attributes)
    }

    private var cardFillColor: NSColor {
        NSColor(calibratedWhite: 0.18, alpha: 0.96)
    }

    private var borderColor: NSColor {
        NSColor(calibratedWhite: 1, alpha: 0.10)
    }

    private var primaryColor: NSColor {
        NSColor(calibratedWhite: 0.94, alpha: 1)
    }

    private var secondaryColor: NSColor {
        NSColor(calibratedWhite: 0.70, alpha: 1)
    }

    private var progressTrackColor: NSColor {
        NSColor(calibratedWhite: 1, alpha: 0.10)
    }

    private var progressFillColor: NSColor {
        NSColor(calibratedWhite: 0.72, alpha: 1)
    }

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEE, MMM d, h:mm a"
        return formatter
    }()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let compactSize = NSSize(width: 96, height: 32)
    private let expandedSize = NSSize(width: 318, height: 112)
    private let panel: NSPanel
    private let balanceView: BalanceView
    private var timer: Timer?
    private var refreshCounter = 0

    override init() {
        balanceView = BalanceView(frame: NSRect(origin: .zero, size: compactSize))
        panel = NSPanel(
            contentRect: balanceView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        balanceView.onToggle = { [weak self] in self?.resizeAndPosition() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel.contentView = balanceView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        refreshCounter += 1
        if refreshCounter % 5 == 0 { refresh() }
        positionOrHide()
    }

    private func refresh() {
        balanceView.metric = UsageReader.current()
        positionOrHide()
    }

    private func resizeAndPosition() {
        let size = balanceView.expanded ? expandedSize : compactSize
        panel.hasShadow = balanceView.expanded
        panel.setContentSize(size)
        balanceView.frame = NSRect(origin: .zero, size: size)
        positionOrHide()
    }

    private func positionOrHide() {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.bundleIdentifier == "com.openai.codex",
              let codexFrame = frontmostCodexWindowFrame() else {
            panel.orderOut(nil)
            return
        }

        let origin = balanceView.expanded
            ? NSPoint(x: codexFrame.minX + 16, y: codexFrame.minY + 51)
      : NSPoint(x: codexFrame.minX + 110, y: codexFrame.minY + 7)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    private func frontmostCodexWindowFrame() -> NSRect? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }

        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        return windows.compactMap { info -> NSRect? in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"],
                  width > 500, height > 350 else { return nil }
            return NSRect(x: x, y: primaryTop - y - height, width: width, height: height)
        }.max { $0.width * $0.height < $1.width * $1.height }
    }
}

func printCurrentUsage() {
    guard let metric = UsageReader.current() else {
        print("{\"weekly\":null,\"status\":\"no-data\"}")
        exit(2)
    }
    let reset = metric.resetsAt.map { ISO8601DateFormatter().string(from: $0) } ?? ""
    let payload: [String: Any] = [
        "weekly": true,
        "usedPercent": metric.usedDisplay,
        "remainingPercent": metric.remainingPercent,
        "resetsAt": reset,
        "source": metric.source
    ]
    let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8)!)
}

if CommandLine.arguments.contains("--print") {
    printCurrentUsage()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
