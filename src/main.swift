import Cocoa

// MARK: - Data

/// Mirrors the JSON written by the statusline.sh snippet (see statusline-snippet.sh).
/// Fields are optional because the file may be stale, partially written, or absent
/// (e.g. before the first Claude Code prompt, or on non Pro/Max accounts).
struct UsageStatus: Codable {
    let five_hour: Double?
    let seven_day: Double?
    let updated_at: Double?
}

// MARK: - Icon rendering

/// Draws the menu bar icon in code (Core Graphics via NSBezierPath) so it can be
/// regenerated on every data refresh instead of shipping static image assets.
enum IconFactory {
    private static let canvas = NSSize(width: 20, height: 20)
    private static let outerRadius: CGFloat = 8.4   // 7-day usage
    private static let innerRadius: CGFloat = 4.6   // 5-hour session usage
    private static let lineWidth: CGFloat = 2.0

    private static func color(for pct: Double) -> NSColor {
        if pct >= 90 { return .systemRed }
        if pct >= 70 { return .systemYellow }
        return .systemGreen
    }

    private static func trackPath(center: NSPoint, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                     width: radius * 2, height: radius * 2))
    }

    /// Progress arc starting at 12 o'clock, sweeping clockwise proportional to pct.
    private static func progressPath(center: NSPoint, radius: CGFloat, pct: Double) -> NSBezierPath {
        let clamped = max(0, min(100, pct))
        let path = NSBezierPath()
        guard clamped > 0 else { return path }
        let end: CGFloat = 90 - 360 * CGFloat(clamped / 100)
        path.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: end, clockwise: true)
        return path
    }

    /// Outer ring = weekly (7-day) usage, inner ring = current session (5-hour) usage.
    /// Colored (not template) so the green/yellow/red threshold is visible without
    /// reading numbers -- see README "Design notes" for the template-vs-color tradeoff.
    static func dualRingIcon(session: Double, week: Double) -> NSImage {
        let image = NSImage(size: canvas, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)

            NSColor.tertiaryLabelColor.setStroke()
            for radius in [outerRadius, innerRadius] {
                let track = trackPath(center: center, radius: radius)
                track.lineWidth = lineWidth
                track.stroke()
            }

            let outer = progressPath(center: center, radius: outerRadius, pct: week)
            outer.lineWidth = lineWidth
            outer.lineCapStyle = .round
            color(for: week).setStroke()
            outer.stroke()

            let inner = progressPath(center: center, radius: innerRadius, pct: session)
            inner.lineWidth = lineWidth
            inner.lineCapStyle = .round
            color(for: session).setStroke()
            inner.stroke()

            return true
        }
        image.isTemplate = false
        return image
    }

    /// Shown when the status file is missing/unreadable/stale -- distinct from a
    /// real 0% ring so "no data" is never mistaken for "no usage".
    static func unknownIcon() -> NSImage {
        let base = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "사용량 정보 없음")
            ?? NSImage(size: canvas)
        let configured = base.withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) ?? base
        configured.isTemplate = true
        return configured
    }
}

// MARK: - File watching

/// Watches the *directory* containing the status file instead of the file itself.
///
/// usage-status.json is replaced atomically (write to .tmp, then `mv`), which gives
/// it a new inode on every update. A watch on the file's own descriptor would need
/// to be closed and re-opened on every single replace to avoid going stale. Watching
/// the parent directory sidesteps that entirely: the directory's inode never changes,
/// so one long-lived kqueue registration sees every create/rename/delete of children
/// (including our file being swapped in) for as long as the app runs.
final class StatusFileWatcher {
    private let dirPath: String
    private var source: DispatchSourceFileSystemObject?
    private var dirFD: Int32 = -1
    private var pendingReload: DispatchWorkItem?
    private let onChange: () -> Void

    init(watchedFilePath: String, onChange: @escaping () -> Void) {
        self.dirPath = (watchedFilePath as NSString).deletingLastPathComponent
        self.onChange = onChange
    }

    func start() {
        stop()
        let fd = open(dirPath, O_EVTONLY)
        guard fd >= 0 else { return }
        dirFD = fd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        src.setEventHandler { [weak self] in self?.scheduleReload() }
        src.setCancelHandler { [weak self] in
            guard let self, self.dirFD >= 0 else { return }
            close(self.dirFD)
            self.dirFD = -1
        }
        src.resume()
        source = src
    }

    func stop() {
        pendingReload?.cancel()
        pendingReload = nil
        source?.cancel()
        source = nil
    }

    /// Directory events fire once per changed child, and a single `mv` can surface
    /// as more than one event; coalesce bursts into a single reload.
    private func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    deinit { stop() }
}

// MARK: - Display mode

/// User-chosen menu bar presentation, persisted across launches.
enum DisplayMode: String {
    case icon   // dual-ring gauge (default)
    case text   // "54%/29%", the original text-only presentation
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let displayModeDefaultsKey = "displayMode"

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusFilePath = NSHomeDirectory() + "/.claude/usage-status.json"
    private var watcher: StatusFileWatcher?

    private var sessionMenuItem: NSMenuItem!
    private var weekMenuItem: NSMenuItem!
    private var updatedMenuItem: NSMenuItem!
    private var iconModeMenuItem: NSMenuItem!
    private var textModeMenuItem: NSMenuItem!

    // Defaults to .icon; overridden below if a valid choice was saved before.
    private var displayMode: DisplayMode = .icon

    // Last successfully parsed values, so switching modes redraws immediately
    // without waiting for the next file change.
    private var lastSession: Double?
    private var lastWeek: Double?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let saved = UserDefaults.standard.string(forKey: Self.displayModeDefaultsKey),
           let mode = DisplayMode(rawValue: saved) {
            displayMode = mode
        }

        let menu = NSMenu()

        sessionMenuItem = NSMenuItem(title: "세션(5시간): -", action: nil, keyEquivalent: "")
        weekMenuItem = NSMenuItem(title: "주간(7일): -", action: nil, keyEquivalent: "")
        updatedMenuItem = NSMenuItem(title: "갱신: -", action: nil, keyEquivalent: "")
        for item in [sessionMenuItem, weekMenuItem, updatedMenuItem] {
            item?.isEnabled = false
            menu.addItem(item!)
        }

        menu.addItem(NSMenuItem.separator())
        iconModeMenuItem = NSMenuItem(title: "아이콘으로 보기", action: #selector(selectDisplayMode(_:)), keyEquivalent: "")
        iconModeMenuItem.target = self
        iconModeMenuItem.tag = 0
        textModeMenuItem = NSMenuItem(title: "숫자로 보기", action: #selector(selectDisplayMode(_:)), keyEquivalent: "")
        textModeMenuItem.target = self
        textModeMenuItem.tag = 1
        menu.addItem(iconModeMenuItem)
        menu.addItem(textModeMenuItem)
        updateModeMenuState()

        menu.addItem(NSMenuItem.separator())
        let refresh = NSMenuItem(title: "새로고침", action: #selector(refresh), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        reload()
        let watcher = StatusFileWatcher(watchedFilePath: statusFilePath) { [weak self] in self?.reload() }
        watcher.start()
        self.watcher = watcher
    }

    @objc private func refresh() {
        reload()
    }

    @objc private func selectDisplayMode(_ sender: NSMenuItem) {
        let mode: DisplayMode = sender.tag == 0 ? .icon : .text
        guard mode != displayMode else { return }
        displayMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.displayModeDefaultsKey)
        updateModeMenuState()
        render()
    }

    private func updateModeMenuState() {
        iconModeMenuItem.state = displayMode == .icon ? .on : .off
        textModeMenuItem.state = displayMode == .text ? .on : .off
    }

    private func reload() {
        // A missing file, unreadable JSON, or a Free-tier account (no rate_limits
        // block at all) are all treated the same: show "no data" rather than an
        // error dialog -- there's nothing actionable for the user to do about any
        // of them from this app.
        guard
            let data = FileManager.default.contents(atPath: statusFilePath),
            let status = try? JSONDecoder().decode(UsageStatus.self, from: data),
            let session = status.five_hour,
            let week = status.seven_day
        else {
            lastSession = nil
            lastWeek = nil
            updateDetails(session: nil, week: nil, updatedAt: nil)
            render()
            return
        }
        lastSession = session
        lastWeek = week
        updateDetails(session: session, week: week, updatedAt: status.updated_at)
        render()
    }

    /// Tooltip and dropdown text always show real numbers, independent of display mode.
    private func updateDetails(session: Double?, week: Double?, updatedAt: Double?) {
        guard let session, let week else {
            sessionMenuItem.title = "세션(5시간): -"
            weekMenuItem.title = "주간(7일): -"
            updatedMenuItem.title = "갱신: -"
            statusItem.button?.toolTip = "사용량 정보 없음 (Pro/Max 구독 및 statusline 설정을 확인하세요)"
            return
        }
        let sessionText = String(format: "세션(5시간): %.0f%%", session)
        let weekText = String(format: "주간(7일): %.0f%%", week)
        sessionMenuItem.title = sessionText
        weekMenuItem.title = weekText
        updatedMenuItem.title = "갱신: \(formattedTime(updatedAt))"
        statusItem.button?.toolTip = "\(sessionText)\n\(weekText)"
    }

    /// Draws the button from lastSession/lastWeek according to the current mode.
    private func render() {
        guard let session = lastSession, let week = lastWeek else {
            switch displayMode {
            case .icon:
                statusItem.button?.image = IconFactory.unknownIcon()
                statusItem.button?.title = ""
            case .text:
                statusItem.button?.image = nil
                statusItem.button?.title = "Claude: -"
            }
            return
        }
        switch displayMode {
        case .icon:
            statusItem.button?.image = IconFactory.dualRingIcon(session: session, week: week)
            statusItem.button?.title = ""
        case .text:
            statusItem.button?.image = nil
            statusItem.button?.title = String(format: "%.0f%%/%.0f%%", session, week)
        }
    }

    private func formattedTime(_ epochSeconds: Double?) -> String {
        guard let epochSeconds else { return "-" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSince1970: epochSeconds))
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
