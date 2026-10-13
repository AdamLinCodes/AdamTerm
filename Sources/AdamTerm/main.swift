// AdamTerm: a minimal macOS terminal shaped like Ghostty's native shell.
//
// Ghostty.app (as inspected with REA) is a Swift/AppKit shell around a C core
// (libghostty, exported as ghostty_* symbols). The shell's shape:
//   AppDelegate            -> menus, newWindow:/newTab:, app lifecycle
//   TerminalController     -> NSWindowController, one per window, tabs
//   TerminalWindow         -> NSWindow subclass, native titlebar tabs
//   Ghostty.SurfaceView    -> NSView, keyboard/mouse/IME, hands bytes to the core
// AdamTerm keeps that shape and swaps the Zig core for SwiftTerm.
import AppKit
import SwiftTerm

final class SurfaceView: LocalProcessTerminalView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        font = SurfaceView.font(size: 13)
        nativeBackgroundColor = NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 1)
        nativeForegroundColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.append("TERM_PROGRAM=AdamTerm")
        startProcess(executable: shell, args: ["-l"], environment: env, execName: "-" + (shell as NSString).lastPathComponent)
    }
    required init?(coder: NSCoder) { fatalError() }

    static func font(size: CGFloat) -> NSFont {
        NSFont(name: "MesloLGM Nerd Font Mono", size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
    func zoom(by delta: CGFloat) { font = SurfaceView.font(size: max(6, delta == 0 ? 13 : font.pointSize + delta)) }
}

final class TerminalWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class TerminalController: NSWindowController, NSWindowDelegate, LocalProcessTerminalViewDelegate {
    static var all: [TerminalController] = []
    let surface = SurfaceView(frame: NSRect(x: 0, y: 0, width: 900, height: 560))

    init() {
        let window = TerminalWindow(contentRect: surface.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "AdamTerm"
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "AdamTerm"
        window.contentView = surface
        window.delegate = self
        window.center()
        surface.processDelegate = self
        TerminalController.all.append(self)
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(asTabOf parent: NSWindow? = nil) {
        if let parent, let window { parent.addTabbedWindow(window, ordered: .above) }
        showWindow(nil)
        window?.makeFirstResponder(surface)
    }

    // LocalProcessTerminalViewDelegate
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) { window?.title = title.isEmpty ? "AdamTerm" : title }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) { window?.close() }

    func windowWillClose(_ notification: Notification) { TerminalController.all.removeAll { $0 === self } }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMenu()
        newWindow(nil)
        // Self-check: ADAMTERM_SCREENSHOT=<png path> types a command, opens a tab, snapshots the window, quits.
        if let path = ProcessInfo.processInfo.environment["ADAMTERM_SCREENSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
                keySurface?.send(txt: "echo hello from $TERM_PROGRAM on $(uname -m)\n")
                newTab(nil)
                keySurface?.send(txt: "ls /Applications | head -5\n")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    // Own-window capture needs no screen-recording permission; cacheDisplay would miss the Metal layer.
                    guard let w = NSApp.keyWindow,
                          let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber), [.boundsIgnoreFraming, .bestResolution]),
                          let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { exit(2) }
                    try? png.write(to: URL(fileURLWithPath: path))
                    exit(0)
                }
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { newWindow(nil) }
        return true
    }

    @objc func newWindow(_ sender: Any?) { TerminalController().show() }
    @objc func newTab(_ sender: Any?) {
        guard let key = NSApp.keyWindow else { return newWindow(sender) }
        TerminalController().show(asTabOf: key)
    }
    @objc func increaseFontSize(_ sender: Any?) { keySurface?.zoom(by: 1) }
    @objc func decreaseFontSize(_ sender: Any?) { keySurface?.zoom(by: -1) }
    @objc func resetFontSize(_ sender: Any?) { keySurface?.zoom(by: 0) }
    private var keySurface: SurfaceView? { NSApp.keyWindow?.contentView as? SurfaceView }

    private func buildMenu() -> NSMenu {
        func menu(_ title: String, _ items: [(String, Selector?, String)]) -> NSMenuItem {
            let m = NSMenu(title: title)
            for (t, sel, key) in items {
                if t == "-" { m.addItem(.separator()); continue }
                m.addItem(withTitle: t, action: sel, keyEquivalent: key)
            }
            let item = NSMenuItem(); item.submenu = m; return item
        }
        let main = NSMenu()
        main.addItem(menu("AdamTerm", [
            ("About AdamTerm", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
            ("-", nil, ""),
            ("Hide AdamTerm", #selector(NSApplication.hide(_:)), "h"),
            ("Quit AdamTerm", #selector(NSApplication.terminate(_:)), "q"),
        ]))
        main.addItem(menu("File", [
            ("New Window", #selector(newWindow(_:)), "n"),
            ("New Tab", #selector(newTab(_:)), "t"),
            ("-", nil, ""),
            ("Close", #selector(NSWindow.performClose(_:)), "w"),
        ]))
        main.addItem(menu("Edit", [
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a"),
        ]))
        main.addItem(menu("View", [
            ("Increase Font Size", #selector(increaseFontSize(_:)), "+"),
            ("Decrease Font Size", #selector(decreaseFontSize(_:)), "-"),
            ("Reset Font Size", #selector(resetFontSize(_:)), "0"),
            ("-", nil, ""),
            ("Toggle Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f"),
        ]))
        let window = menu("Window", [
            ("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            ("Show Previous Tab", #selector(NSWindow.selectPreviousTab(_:)), "{"),
            ("Show Next Tab", #selector(NSWindow.selectNextTab(_:)), "}"),
        ])
        main.addItem(window)
        NSApp.windowsMenu = window.submenu
        return main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
