import Cocoa

// MARK: - Data

/// Mirrors the JSON written by the statusline.sh snippet (see statusline-snippet.sh).
/// Fields are optional because the file may be stale, partially written, or absent
/// (e.g. before the first Claude Code prompt, or on non Pro/Max accounts).
struct UsageStatus: Codable {
    let five_hour: Double?
    let seven_day: Double?
    let five_hour_resets_at: Double?
    let seven_day_resets_at: Double?
}

// MARK: - Icon rendering

/// Draws the menu bar icon in code (Core Graphics via NSBezierPath) so it can be
/// regenerated on every data refresh instead of shipping static image assets.
enum IconFactory {
    private static let canvas = NSSize(width: 20, height: 20)
    private static let outerRadius: CGFloat = 8.4   // 5-hour session usage
    private static let innerRadius: CGFloat = 4.6   // 7-day usage
    private static let lineWidth: CGFloat = 2.0

    static func color(for pct: Double) -> NSColor {
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

    /// Outer ring = current session (5-hour) usage, inner ring = weekly (7-day) usage.
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

            let outer = progressPath(center: center, radius: outerRadius, pct: session)
            outer.lineWidth = lineWidth
            outer.lineCapStyle = .round
            color(for: session).setStroke()
            outer.stroke()

            let inner = progressPath(center: center, radius: innerRadius, pct: week)
            inner.lineWidth = lineWidth
            inner.lineCapStyle = .round
            color(for: week).setStroke()
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

// MARK: - Dropdown row view

/// A labeled progress bar + reset-time subtitle, used as a menu item's custom view
/// in place of a plain text row -- so usage is scannable as a bar, not just a number.
final class UsageRowView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let percentLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let track = NSView()
    private let fill = NSView()
    private var fillWidthConstraint: NSLayoutConstraint?

    init(title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 54))

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)

        percentLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        percentLabel.alignment = .right

        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor

        track.wantsLayer = true
        track.layer?.backgroundColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.3).cgColor
        track.layer?.cornerRadius = 3
        fill.wantsLayer = true
        fill.layer?.cornerRadius = 3

        for v in [titleLabel, percentLabel, subtitleLabel, track] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        fill.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(fill)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),

            percentLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            percentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            percentLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),

            track.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            track.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            track.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            track.heightAnchor.constraint(equalToConstant: 6),

            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: track.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(percent: Double?, subtitle: String) {
        fillWidthConstraint?.isActive = false
        guard let percent else {
            percentLabel.stringValue = "-"
            fill.layer?.backgroundColor = NSColor.clear.cgColor
            subtitleLabel.stringValue = subtitle
            return
        }
        percentLabel.stringValue = String(format: "%.0f%%", percent)
        fill.layer?.backgroundColor = IconFactory.color(for: percent).cgColor
        subtitleLabel.stringValue = subtitle

        let fraction = CGFloat(max(0, min(100, percent)) / 100)
        let constraint = fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: fraction)
        constraint.isActive = true
        fillWidthConstraint = constraint
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let displayModeDefaultsKey = "displayMode"

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusFilePath = NSHomeDirectory() + "/.claude/usage-status.json"
    private var watcher: StatusFileWatcher?

    private var sessionRow: UsageRowView!
    private var weekRow: UsageRowView!
    private var iconModeMenuItem: NSMenuItem!
    private var textModeMenuItem: NSMenuItem!

    // Defaults to .icon; overridden below if a valid choice was saved before.
    private var displayMode: DisplayMode = .icon

    // Last successfully parsed values, so switching modes redraws immediately
    // without waiting for the next file change, and so a field that's briefly
    // absent from one snapshot (see reload()) still has something to fall back to.
    private var lastSession: Double?
    private var lastWeek: Double?
    private var lastSessionResetsAt: Double?
    private var lastWeekResetsAt: Double?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let saved = UserDefaults.standard.string(forKey: Self.displayModeDefaultsKey),
           let mode = DisplayMode(rawValue: saved) {
            displayMode = mode
        }

        let menu = NSMenu()

        // Labels ("현재 세션" / "주간 한도") and reset-time phrasing match Claude's own
        // usage UI convention: relative countdown for the session, weekday+time for the week.
        menu.addItem(Self.headerMenuItem("사용량"))

        sessionRow = UsageRowView(title: "현재 세션")
        let sessionItem = NSMenuItem()
        sessionItem.view = sessionRow
        menu.addItem(sessionItem)

        weekRow = UsageRowView(title: "주간 한도")
        let weekItem = NSMenuItem()
        weekItem.view = weekRow
        menu.addItem(weekItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(Self.headerMenuItem("표시 방식"))
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

        // A kqueue watch held across system sleep can come back dead on wake even
        // though the process itself survives -- the menu bar then freezes on
        // whatever it last showed before sleep, silently. Re-arming the watch (it
        // reopens the directory fd) and reloading immediately on wake is cheap
        // insurance against that, whatever the exact cause turns out to be.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.watcher?.start()
            self.reload()
        }
    }

    @objc private func refresh() {
        reload()
    }

    /// Small caps-style section label; unclickable (nil action) like the info rows above.
    private static func headerMenuItem(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        return item
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
        // A missing file or unreadable JSON means we've never had anything to show --
        // that's a hard "no data", distinct from the case below.
        guard
            let data = FileManager.default.contents(atPath: statusFilePath),
            let status = try? JSONDecoder().decode(UsageStatus.self, from: data)
        else {
            lastSession = nil
            lastWeek = nil
            lastSessionResetsAt = nil
            lastWeekResetsAt = nil
            updateDetails(session: nil, week: nil, sessionResetsAt: nil, weekResetsAt: nil)
            render()
            return
        }

        // Each field falls back to its last known value independently, rather than
        // blanking the whole display, when only that one field is momentarily absent
        // from this snapshot -- e.g. right as the 5-hour window resets, Claude Code's
        // hook briefly omits rate_limits.five_hour while seven_day is still present.
        // ponytail: no staleness expiry on the fallback, so a value that's genuinely
        // gone for good (e.g. downgrading off Pro/Max) would keep showing its last
        // number instead of "-"; add an age check here if that edge case matters.
        let session = status.five_hour ?? lastSession
        let week = status.seven_day ?? lastWeek
        let sessionResetsAt = status.five_hour_resets_at ?? lastSessionResetsAt
        let weekResetsAt = status.seven_day_resets_at ?? lastWeekResetsAt

        guard let session, let week else {
            // Never had a value for one of these at all -- genuinely no data,
            // e.g. a Free-tier account with no rate_limits block ever sent.
            updateDetails(session: nil, week: nil, sessionResetsAt: nil, weekResetsAt: nil)
            render()
            return
        }

        lastSession = session
        lastWeek = week
        lastSessionResetsAt = sessionResetsAt
        lastWeekResetsAt = weekResetsAt
        updateDetails(session: session, week: week, sessionResetsAt: sessionResetsAt, weekResetsAt: weekResetsAt)
        render()
    }

    /// Tooltip and dropdown rows always show real numbers, independent of display mode.
    private func updateDetails(session: Double?, week: Double?, sessionResetsAt: Double?, weekResetsAt: Double?) {
        guard let session, let week else {
            sessionRow.update(percent: nil, subtitle: "사용량 정보 없음")
            weekRow.update(percent: nil, subtitle: "사용량 정보 없음")
            statusItem.button?.toolTip = "사용량 정보 없음 (Pro/Max 구독 및 statusline 설정을 확인하세요)"
            return
        }
        let sessionReset = relativeReset(sessionResetsAt)
        let weekReset = weekdayReset(weekResetsAt)
        sessionRow.update(percent: session, subtitle: sessionReset)
        weekRow.update(percent: week, subtitle: weekReset)
        statusItem.button?.toolTip = String(format: "현재 세션: %.0f%% · %@\n주간 한도: %.0f%% · %@", session, sessionReset, week, weekReset)
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
            statusItem.button?.needsDisplay = true
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
        // Assigning a new image/title doesn't always trigger a repaint on its own --
        // e.g. after the display wakes from sleep, AppKit has been seen to skip
        // redrawing an NSStatusItem's button until something else forces it (like
        // opening the menu). Force it explicitly so the icon can't visibly go stale
        // while the underlying data (checkable via the tooltip/dropdown) is fine.
        statusItem.button?.needsDisplay = true
    }

    /// Session reset is always within 5 hours, so a relative countdown ("22분 후 재설정")
    /// reads better than a clock time -- matches Claude's own usage UI.
    private func relativeReset(_ epochSeconds: Double?) -> String {
        guard let epochSeconds else { return "-" }
        let totalMinutes = Int((epochSeconds - Date().timeIntervalSince1970) / 60)
        if totalMinutes <= 0 { return "곧 재설정" }
        if totalMinutes < 60 { return "\(totalMinutes)분 후 재설정" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours)시간 후 재설정" : "\(hours)시간 \(minutes)분 후 재설정"
    }

    /// Weekly reset can land days out, so a weekday + time reads better than a countdown --
    /// e.g. "(수) 오전 7:00에 재설정", matching Claude's own usage UI.
    private func weekdayReset(_ epochSeconds: Double?) -> String {
        guard let epochSeconds else { return "-" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "(EEE) a h:mm"
        return formatter.string(from: Date(timeIntervalSince1970: epochSeconds)) + "에 재설정"
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
