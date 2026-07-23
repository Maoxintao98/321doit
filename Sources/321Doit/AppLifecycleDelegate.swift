import AppKit
import SwiftUI

@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var current: AppLifecycleDelegate?
    private static let internalUpdateKeepAndQuitKey = "321doit.lifecycle.internalUpdateKeepAndQuit"

    var language: AppLanguage = .system

    private(set) var pendingProjectURL: URL?
    private var independentModeActive = false
    private var retainIndependentWorkspaceForUpdate: (() throws -> Void)?
    private var saveIndependentWorkspaceAsProject: (() throws -> Bool)?
    private var discardIndependentWorkspace: (() throws -> Void)?

    private weak var mainWindow: NSWindow?
    private var eventMonitor: Any?
    private var quitHoldWorkItem: DispatchWorkItem?
    private var isQuitShortcutHeld = false
    private var isTerminating = false
    private var quitNoticeWindow: NSPanel?

    override init() {
        super.init()
        Self.current = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installApplicationIcon()
        installQuitShortcutMonitor()
        FocusRingSuppressor.shared.install()
    }

    /// Finder reads the icon declaration from Info.plist; explicitly loading
    /// the same bundled image also makes the Dock and AppKit alerts reliable
    /// on a newly installed copy before LaunchServices has rebuilt its cache.
    private func installApplicationIcon() {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: url) else {
            AppLogger.log(.error, category: "lifecycle", "Could not load bundled AppIcon.icns")
            return
        }
        NSApp.applicationIconImage = icon
    }

    func applicationWillTerminate(_ notification: Notification) {
        MiraWindowPresenter.shared.shutdown()
        AppLogger.log(.info, category: "lifecycle", "Application will terminate")
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let path = filenames.first else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        pendingProjectURL = url
        NotificationCenter.default.post(name: .open321DoitProject, object: url)
        sender.reply(toOpenOrPrint: .success)
    }

    func consumePendingProjectURL() -> URL? {
        defer { pendingProjectURL = nil }
        return pendingProjectURL
    }

    func configureIndependentWorkspaceLifecycle(
        isActive: Bool,
        retainForUpdate: @escaping () throws -> Void,
        saveAsProject: @escaping () throws -> Bool,
        discard: @escaping () throws -> Void
    ) {
        independentModeActive = isActive
        retainIndependentWorkspaceForUpdate = retainForUpdate
        saveIndependentWorkspaceAsProject = saveAsProject
        discardIndependentWorkspace = discard
    }

    func setIndependentModeActive(_ active: Bool) {
        independentModeActive = active
    }

    func registerMainWindow(_ window: NSWindow) {
        guard mainWindow !== window else { return }
        mainWindow = window
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 1360, height: 820)
        window.delegate = self
        FocusRingSuppressor.shared.suppress(in: window)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === mainWindow, !isTerminating else { return true }
        sender.orderOut(nil)
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
            sender.activate(ignoringOtherApps: true)
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isTerminating {
            isTerminating = true
            return .terminateNow
        }
        if isQuitShortcutHeld {
            showQuitNotice()
            return .terminateCancel
        }
        if let event = NSApp.currentEvent, event.type == .keyDown, isCommandQ(event) {
            beginQuitHold()
            return .terminateCancel
        }
        guard confirmIndependentWorkspaceDisposition() else {
            return .terminateCancel
        }
        isTerminating = true
        return .terminateNow
    }

    func requestGuardedQuit() {
        beginQuitHold()
    }

    private func installQuitShortcutMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .keyDown where self.isCommandQ(event):
                self.beginQuitHold()
                return nil
            case .keyDown where self.routeArrowNavigationIfAppropriate(event):
                return nil
            case .keyUp where self.isQKey(event):
                self.cancelQuitHold()
                return nil
            case .flagsChanged where self.isQuitShortcutHeld && !self.isCommandPressed(event):
                self.cancelQuitHold()
                return event
            default:
                return event
            }
        }
    }

    /// Arrow keys retain their editing meaning whenever an editable native
    /// text control owns the first responder. Outside text editing, retain the
    /// Script Log's established four-direction navigation behavior.
    private func routeArrowNavigationIfAppropriate(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard modifiers.isEmpty, !isEditingText() else { return false }

        let command: AppMenuCommand
        switch event.keyCode {
        case 123: command = .previousTake
        case 124: command = .nextTake
        case 126: command = .previousScene
        case 125: command = .nextScene
        default: return false
        }
        NotificationCenter.default.post(name: command.notificationName, object: nil)
        return true
    }

    private func isEditingText() -> Bool {
        var responder = NSApp.keyWindow?.firstResponder
        while let current = responder {
            if let textView = current as? NSTextView, textView.isEditable {
                return true
            }
            if let textField = current as? NSTextField, textField.isEditable {
                return true
            }
            responder = current.nextResponder
        }
        return false
    }

    private func isCommandQ(_ event: NSEvent) -> Bool {
        isCommandPressed(event) && isQKey(event)
    }

    private func isCommandPressed(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
    }

    private func isQKey(_ event: NSEvent) -> Bool {
        event.keyCode == 12 || event.charactersIgnoringModifiers?.lowercased() == "q"
    }

    private func beginQuitHold() {
        guard !isTerminating else { return }
        isQuitShortcutHeld = true
        showQuitNotice()
        guard quitHoldWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isQuitShortcutHeld else { return }
            self.finishGuardedQuit()
        }
        quitHoldWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func cancelQuitHold() {
        isQuitShortcutHeld = false
        quitHoldWorkItem?.cancel()
        quitHoldWorkItem = nil
    }

    private func finishGuardedQuit() {
        isQuitShortcutHeld = false
        quitHoldWorkItem?.cancel()
        quitHoldWorkItem = nil
        guard confirmIndependentWorkspaceDisposition() else { return }
        isTerminating = true
        NSApp.terminate(nil)
    }

    private func confirmIndependentWorkspaceDisposition() -> Bool {
        if UserDefaults.standard.bool(forKey: Self.internalUpdateKeepAndQuitKey) {
            UserDefaults.standard.removeObject(forKey: Self.internalUpdateKeepAndQuitKey)
            do {
                if independentModeActive { try retainIndependentWorkspaceForUpdate?() }
                AppLogger.log(.info, category: "lifecycle", "Retained workspace automatically for an internal app update")
                return true
            } catch {
                AppLogger.log(.error, category: "lifecycle", "Could not retain workspace for internal update: \(error.localizedDescription)")
                return false
            }
        }
        guard independentModeActive else { return true }

        let alert = NSAlert()
        alert.alertStyle = .informational
        // NSAlert does not reliably infer the bundle icon for a modal shown
        // during termination, so provide the running app's image explicitly.
        alert.icon = NSApp.applicationIconImage
        alert.messageText = L10n.t(
            "是否保留当前独立项目？",
            "Keep This Independent Project?",
            language: language
        )
        alert.informativeText = L10n.t(
            "保留后，下次启动会继续当前分镜、拍摄统筹和场记；不保留则清空独立项目，下次从空白工作区开始。",
            "Keep it to continue the current storyboard, production plan, and script log next time. Discard it to start with a blank workspace on the next launch.",
            language: language
        )
        alert.addButton(withTitle: L10n.t("保留并退出", "Keep & Quit", language: language))
        alert.addButton(withTitle: L10n.t("不保留并退出", "Discard & Quit", language: language))
        alert.addButton(withTitle: L10n.t("取消", "Cancel", language: language))

        do {
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                guard try saveIndependentWorkspaceAsProject?() == true else {
                    return false
                }
                AppLogger.log(.info, category: "lifecycle", "Independent workspace retained for next launch")
                return true
            case .alertSecondButtonReturn:
                try discardIndependentWorkspace?()
                AppLogger.log(.info, category: "lifecycle", "Independent workspace discarded at user request")
                return true
            default:
                return false
            }
        } catch {
            let failure = NSAlert()
            failure.alertStyle = .critical
            failure.icon = NSApp.applicationIconImage
            failure.messageText = L10n.t("无法完成退出操作", "Could Not Complete Quit", language: language)
            failure.informativeText = error.localizedDescription
            failure.addButton(withTitle: L10n.t("确定", "OK", language: language))
            failure.runModal()
            AppLogger.log(.error, category: "lifecycle", "Independent workspace quit decision failed: \(error.localizedDescription)")
            return false
        }
    }

    private func showQuitNotice() {
        let message = L10n.t("长按 ⌘Q 退出", "Hold ⌘Q to Quit", language: language)

        if let notice = quitNoticeWindow {
            updateNotice(notice, message: message)
            notice.orderFrontRegardless()
            scheduleNoticeDismissal(notice)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 210, height: 58),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]

        panel.contentView = QuitNoticeView(frame: NSRect(x: 0, y: 0, width: 210, height: 58), message: message)
        positionNotice(panel)
        quitNoticeWindow = panel
        panel.orderFrontRegardless()
        scheduleNoticeDismissal(panel)
    }

    private func updateNotice(_ notice: NSPanel, message: String) {
        if let view = notice.contentView as? QuitNoticeView {
            view.message = message
        }
        positionNotice(notice)
    }

    private func positionNotice(_ notice: NSPanel) {
        let anchor = mainWindow?.frame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = notice.frame.size
        let origin = NSPoint(
            x: anchor.midX - size.width / 2,
            y: anchor.midY - size.height / 2
        )
        notice.setFrameOrigin(origin)
    }

    private func scheduleNoticeDismissal(_ notice: NSPanel) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self, weak notice] in
            guard let notice, self?.isQuitShortcutHeld != true else { return }
            notice.orderOut(nil)
        }
    }
}

/// Keeps AppKit's default blue keyboard-focus halo out of the custom interface.
/// SwiftUI creates native controls lazily, so the suppressor also runs after each
/// window update to cover controls presented later in sheets, popovers, and panels.
final class FocusRingSuppressor {
    static let shared = FocusRingSuppressor()

    private var didInstall = false
    private var updateObserver: NSObjectProtocol?
    private var keyWindowObserver: NSObjectProtocol?

    private init() {}

    func install() {
        guard !didInstall else { return }
        didInstall = true

        let center = NotificationCenter.default
        keyWindowObserver = center.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let window = notification.object as? NSWindow {
                FocusRingSuppressor.shared.suppress(in: window)
            }
        }
        updateObserver = center.addObserver(
            forName: NSWindow.didUpdateNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let window = notification.object as? NSWindow {
                FocusRingSuppressor.shared.suppress(in: window)
            }
        }

        NSApp.windows.forEach(suppress(in:))
    }

    func suppress(in window: NSWindow) {
        guard let contentView = window.contentView else { return }
        suppress(in: contentView)
    }

    private func suppress(in view: NSView) {
        if view.focusRingType != .none {
            view.focusRingType = .none
        }
        view.subviews.forEach(suppress(in:))
    }
}

private final class QuitNoticeView: NSView {
    private let label = NSTextField(labelWithString: "")

    var message: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    init(frame frameRect: NSRect, message: String) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 0.72).cgColor
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        layer?.borderWidth = 0.7

        label.stringValue = message
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }
}

struct MainWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowRegistrationView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? WindowRegistrationView)?.registerWindow()
    }

    private final class WindowRegistrationView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            registerWindow()
        }

        func registerWindow() {
            guard let window else { return }
            AppLifecycleDelegate.current?.registerMainWindow(window)
        }
    }
}
