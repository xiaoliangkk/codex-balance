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

struct ContextMetric: Equatable {
    let usedTokens: Int
    let windowTokens: Int
    let observedAt: Date

    var usedPercent: Int {
        guard windowTokens > 0 else { return 0 }
        return Int((Double(usedTokens) / Double(windowTokens) * 100).rounded().clamped(to: 0...100))
    }
}

struct UsageSnapshot: Equatable {
    let session: UsageMetric?
    let weekly: UsageMetric?
    let context: ContextMetric?

    var observedAt: Date {
        [session?.observedAt, weekly?.observedAt, context?.observedAt].compactMap { $0 }.max() ?? .distantPast
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

enum UsageReader {
    private static let cocoaEpochOffset = 978_307_200.0

    static func current() -> UsageSnapshot? {
        let codexBar = readCodexBar()
        let codex = readRecentSessions()
        let quota = [codexBar, codex].compactMap { $0 }.max { $0.observedAt < $1.observedAt }
        guard quota != nil || codex?.context != nil else { return nil }
        return UsageSnapshot(
            session: quota?.session,
            weekly: quota?.weekly,
            context: codex?.context
        )
    }

    static func readCodexBar() -> UsageSnapshot? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexBar/codex-account-snapshots.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = root["records"] as? [[String: Any]] else { return nil }

        return records.compactMap { record -> UsageSnapshot? in
            guard let snapshot = record["snapshot"] as? [String: Any],
                  snapshot["primary"] != nil || snapshot["secondary"] != nil else { return nil }
            let observedRaw = number(snapshot["updatedAt"]) ?? 0
            let observed = date(fromPossiblyCocoaSeconds: observedRaw)
            return UsageSnapshot(
                session: metric(from: snapshot["primary"], observedAt: observed, source: "CodexBar", cocoaDates: true),
                weekly: metric(from: snapshot["secondary"], observedAt: observed, source: "CodexBar", cocoaDates: true),
                context: nil
            )
        }.max { $0.observedAt < $1.observedAt }
    }

    static func readRecentSessions() -> UsageSnapshot? {
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

    private static func readSession(_ url: URL) -> UsageSnapshot? {
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
                  payload["type"] as? String == "token_count" else { continue }
            let timestamp = (event["timestamp"] as? String).flatMap(isoDate) ?? Date.distantPast
            let limits = payload["rate_limits"] as? [String: Any]
            let result = UsageSnapshot(
                session: metric(from: limits?["primary"], observedAt: timestamp, source: "Codex", cocoaDates: false),
                weekly: metric(from: limits?["secondary"], observedAt: timestamp, source: "Codex", cocoaDates: false),
                context: contextMetric(from: payload["info"], observedAt: timestamp)
            )
            if result.session != nil || result.weekly != nil || result.context != nil { return result }
        }
        return nil
    }

    private static func metric(from value: Any?, observedAt: Date, source: String, cocoaDates: Bool) -> UsageMetric? {
        guard let lane = value as? [String: Any],
              let used = number(lane["usedPercent"]) ?? number(lane["used_percent"]) else { return nil }
        let resetRaw = number(lane["resetsAt"]) ?? number(lane["resets_at"])
        let reset = resetRaw.map { cocoaDates ? date(fromPossiblyCocoaSeconds: $0) : Date(timeIntervalSince1970: $0) }
        return UsageMetric(usedPercent: used, resetsAt: reset, observedAt: observedAt, source: source)
    }

    private static func contextMetric(from value: Any?, observedAt: Date) -> ContextMetric? {
        guard let info = value as? [String: Any],
              let usage = info["last_token_usage"] as? [String: Any],
              let used = number(usage["total_tokens"]),
              let window = number(info["model_context_window"]),
              used >= 0, window > 0 else { return nil }
        return ContextMetric(usedTokens: Int(used), windowTokens: Int(window), observedAt: observedAt)
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
        static let compactHorizontalPadding: CGFloat = 4
        static let compactFontSize: CGFloat = 10
        static let compactBarY: CGFloat = 59
        static let compactBarWidth: CGFloat = 36
    }

    var snapshot: UsageSnapshot? { didSet { needsDisplay = true } }
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
        drawCompactMetric(label: "5h", metric: snapshot?.session, labelY: 0, valueY: 12)
        drawCompactMetric(label: "7d", metric: snapshot?.weekly, labelY: 29, valueY: 41)
        drawContextProgress(
            percent: snapshot?.context?.usedPercent,
            rect: NSRect(x: Layout.compactHorizontalPadding, y: Layout.compactBarY, width: Layout.compactBarWidth, height: 6)
        )
        let contextText = snapshot?.context.map { "\($0.usedPercent)%" } ?? "–"
        drawCenteredText(contextText, y: 68, size: 10, weight: .semibold, color: contextColor(percent: snapshot?.context?.usedPercent))
    }

    private func drawCompactMetric(label: String, metric: UsageMetric?, labelY: CGFloat, valueY: CGFloat) {
        let remaining = metric.map { "\($0.remainingPercent)%" } ?? "–"
        drawCenteredText(label, y: labelY, size: 9, weight: .regular, color: secondaryColor)
        drawCenteredText(remaining, y: valueY, size: Layout.compactFontSize, weight: .medium, color: primaryColor)
    }

    private func drawExpanded() {
        drawExpandedMetric(label: "session", metric: snapshot?.session, y: 13)
        drawExpandedMetric(label: "weekly", metric: snapshot?.weekly, y: 78)
        drawExpandedContext(y: 143)
    }

    private func drawExpandedContext(y: CGFloat) {
        let percent = snapshot?.context?.usedPercent
        drawText("context", at: NSPoint(x: 14, y: y), size: 14, color: primaryColor)
        drawRightAlignedText(percent.map { "\($0)%" } ?? "–", rightInset: 14, y: y, size: 14, weight: .medium, monospacedDigits: false, color: contextColor(percent: percent))
        let detail = snapshot?.context.map { "\(formatTokens($0.usedTokens)) / \(formatTokens($0.windowTokens)) tokens" } ?? "No context data yet"
        drawText(detail, at: NSPoint(x: 14, y: y + 23), size: 13, color: secondaryColor)
        drawContextProgress(percent: percent, rect: NSRect(x: 14, y: y + 49, width: bounds.width - 28, height: 8))
    }

    private func drawContextProgress(percent: Int?, rect: NSRect) {
        let track = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        progressTrackColor.setFill()
        track.fill()
        guard let percent, percent > 0 else { return }
        let filled = NSRect(x: rect.minX, y: rect.minY, width: rect.width * CGFloat(percent) / 100, height: rect.height)
        contextColor(percent: percent).setFill()
        NSBezierPath(roundedRect: filled, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
    }

    private func contextColor(percent: Int?) -> NSColor {
        guard let percent else { return secondaryColor }
        if percent >= 85 { return NSColor.systemRed }
        if percent >= 70 { return NSColor.systemYellow }
        return NSColor.systemGreen
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000 { return String(format: "%.1fk", Double(tokens) / 1_000) }
        return "\(tokens)"
    }

    private func drawExpandedMetric(label: String, metric: UsageMetric?, y: CGFloat) {
        let remaining = metric.map { "\($0.remainingPercent)%" } ?? "–"
        drawText(label, at: NSPoint(x: 14, y: y), size: 14, color: primaryColor)
        drawRightAlignedText(remaining, rightInset: 14, y: y, size: 14, weight: .medium, monospacedDigits: false, color: primaryColor)
        let detail = metric.map { "\($0.usedDisplay)% used" } ?? "No usage data yet"
        drawText(detail, at: NSPoint(x: 14, y: y + 23), size: 13, color: secondaryColor)
        let reset = metric?.resetsAt.map { Self.resetFormatter.string(from: $0) } ?? "unknown"
        drawText("Resets \(reset)", at: NSPoint(x: 104, y: y + 23), size: 13, color: secondaryColor)
        drawProgress(remaining: Double(metric?.remainingPercent ?? 0) / 100, y: y + 49)
    }

    private func drawProgress(remaining: Double, y: CGFloat) {
        let rect = NSRect(x: 14, y: y, width: bounds.width - 28, height: 5)
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

    private func drawCenteredText(_ text: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let width = ceil((text as NSString).size(withAttributes: attributes).width)
        text.draw(at: NSPoint(x: (bounds.width - width) / 2, y: y), withAttributes: attributes)
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
    private let compactSize = NSSize(width: 44, height: 84)
    private let expandedSize = NSSize(width: 318, height: 221)
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
        balanceView.snapshot = UsageReader.current()
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
            : NSPoint(x: codexFrame.minX + 4, y: codexFrame.minY + 128)
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
    guard let snapshot = UsageReader.current() else {
        print("{\"session\":null,\"weekly\":null,\"status\":\"no-data\"}")
        exit(2)
    }
    func payload(for metric: UsageMetric?) -> Any {
        guard let metric else { return NSNull() }
        return [
            "usedPercent": metric.usedDisplay,
            "remainingPercent": metric.remainingPercent,
            "resetsAt": metric.resetsAt.map { ISO8601DateFormatter().string(from: $0) } ?? "",
            "source": metric.source
        ] as [String: Any]
    }
    let context: Any = snapshot.context.map {
        ["usedTokens": $0.usedTokens, "windowTokens": $0.windowTokens, "usedPercent": $0.usedPercent]
    } ?? NSNull()
    let payload: [String: Any] = ["session": payload(for: snapshot.session), "weekly": payload(for: snapshot.weekly), "context": context]
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
