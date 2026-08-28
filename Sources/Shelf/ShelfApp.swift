import AppKit
import ServiceManagement
import SwiftUI

@main
enum ShelfApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Menu bar only: no Dock tile, no main window.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

/// Sits over the status item button and does all of its interaction.
///
/// A plain subview would swallow clicks, and returning nil from `hitTest` to let
/// them through would also stop drags reaching us — so this view takes both and
/// forwards the clicks on.
final class DropTargetView: NSView {
    var onDrop: (([URL]) -> Void)?
    var onDragHover: ((Bool) -> Void)?
    var onClick: (() -> Void)?
    var onRightClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragHover?(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragHover?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDragHover?(false)
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                              options: options) as? [URL],
              !urls.isEmpty
        else { return false }
        onDrop?(urls)
        return true
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { onRightClick?() }
}

/// Launch-at-login, backed by the system login item registry so the switch always
/// agrees with System Settings > General > Login Items.
final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled = false

    init() { refresh() }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Fails when running the bare binary rather than the .app bundle.
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't \(enabled ? "enable" : "disable") launch at login"
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        refresh()

        if enabled, SMAppService.mainApp.status == .requiresApproval {
            let alert = NSAlert()
            alert.messageText = "Approve Shelf in Login Items"
            alert.informativeText = "macOS needs you to switch Shelf on under "
                + "System Settings > General > Login Items."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = ShelfStore()
    private let loginItem = LoginItem()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var hostingController: NSHostingController<PopoverView>!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        updateIcon()

        let target = DropTargetView(frame: button.bounds)
        target.autoresizingMask = [.width, .height]
        target.onClick = { [weak self] in self?.togglePopover() }
        target.onRightClick = { [weak self] in self?.showContextMenu() }
        target.onDragHover = { [weak self] hovering in
            // The only feedback that the icon is a valid target mid-drag.
            self?.statusItem.button?.highlight(hovering)
        }
        target.onDrop = { [weak self] urls in
            self?.store.add(urls)
            self?.updateIcon()
        }
        button.addSubview(target)

        hostingController = NSHostingController(
            rootView: PopoverView(store: store,
                                  loginItem: loginItem,
                                  dismiss: { [weak self] in self?.popover.performClose(nil) }))
        // Without this the controller reports a zero preferredContentSize, so the
        // popover sizes itself from a default and leaves dead space below.
        hostingController.sizingOptions = [.preferredContentSize]

        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = hostingController

        // Files get moved and deleted behind our back; do not show stale rows.
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.store.pruneMissing()
            self?.updateIcon()
        }
    }

    /// A filled tray means the shelf is holding something.
    private func updateIcon() {
        let name = store.items.isEmpty ? "tray" : "tray.full.fill"
        statusItem.button?.image = NSImage(systemSymbolName: name,
                                          accessibilityDescription: "Shelf")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = store.items.isEmpty
            ? "Shelf — drag files here"
            : "Shelf — \(store.items.count) item\(store.items.count == 1 ? "" : "s")"
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            loginItem.refresh()
            store.pruneMissing()
            // Resolve the SwiftUI content size before the popover reads it.
            hostingController.view.layoutSubtreeIfNeeded()
            popover.contentSize = hostingController.view.fittingSize
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Shelf", action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
}
