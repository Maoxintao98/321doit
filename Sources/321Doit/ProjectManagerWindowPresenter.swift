import AppKit
import SwiftUI

@MainActor
final class ProjectManagerWindowPresenter {
    static let shared = ProjectManagerWindowPresenter()
    private var window: NSWindow?
    private let defaultContentSize = NSSize(width: 1_040, height: 720)
    private let minimumContentSize = NSSize(width: 900, height: 620)

    private init() {}

    func show(
        settings: SettingsStore,
        store: ScriptLogStore,
        recentProjects: RecentProjectStore,
        openNewProjectSheet: Bool = false,
        enterWorkspace: @escaping (Workspace) -> Void,
        showSupport: @escaping () -> Void
    ) {
        let root = ProjectQuickPickerView(
            store: store,
            recentProjects: recentProjects,
            openNewProjectOnAppear: openNewProjectSheet,
            enterWorkspace: { [weak self] workspace in
                enterWorkspace(workspace)
                self?.close()
            }
        )
        .environmentObject(settings)
        .environment(\.appTheme, settings.settings.general.theme)
        .tint(settings.settings.general.theme.colors(isDark: isDarkAppearance).accent)
        .accentColor(settings.settings.general.theme.colors(isDark: isDarkAppearance).accent)
        .preferredColorScheme(colorScheme(for: settings.settings.general.appearance))

        if let window {
            window.contentViewController = NSHostingController(rootView: root)
            configure(window)
            restoreVisibleFrameIfNeeded(window)
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultContentSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = NSHostingController(rootView: root)
        configure(window)
        window.setContentSize(defaultContentSize)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }

    private var isDarkAppearance: Bool {
        isSystemDarkAppearance()
    }

    private func configure(_ window: NSWindow) {
        window.title = "321Doit"
        window.minSize = minimumContentSize
        window.contentMinSize = minimumContentSize
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        if window.contentLayoutRect.width < minimumContentSize.width
            || window.contentLayoutRect.height < minimumContentSize.height {
            window.setContentSize(defaultContentSize)
        }
        window.isMovableByWindowBackground = true
    }

    /// Repairs the invalid near-zero window frame that previously appeared as
    /// a long horizontal line.  Normal user-resized frames are preserved.
    private func restoreVisibleFrameIfNeeded(_ window: NSWindow) {
        let contentSize = window.contentLayoutRect.size
        let frame = window.frame
        let hasCollapsedFrame = contentSize.width < minimumContentSize.width
            || contentSize.height < minimumContentSize.height
            || frame.width < minimumContentSize.width
            || frame.height < minimumContentSize.height

        guard hasCollapsedFrame else { return }
        window.setContentSize(defaultContentSize)
        window.center()
        window.displayIfNeeded()
    }

    private func colorScheme(for mode: AppearanceMode) -> ColorScheme? {
        switch mode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
