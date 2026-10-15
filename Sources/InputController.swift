import Cocoa
import InputMethodKit
import OSLog

@objc(RokoInputController)
final class RokoInputController: IMKInputController {
    var inputClient: IMKTextInput?
    private(set) var activatedHostPID: pid_t?

    func belongsTo(_ application: NSRunningApplication) -> Bool {
        // IMK sessions can belong to an app helper whose bundle ID differs
        // from the foreground app. Bind the active session to its focus PID.
        inputClient != nil && activatedHostPID == application.processIdentifier
    }

    private func bindActiveClient() {
        refreshClient()
        activatedHostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        (NSApp.delegate as? VoiceApp)?.activeInputController = self
    }

    override func activateServer(_ sender: Any!) {
        bindActiveClient()
    }

    override func deactivateServer(_ sender: Any!) {
        if let app = NSApp.delegate as? VoiceApp, app.activeInputController === self {
            app.activeInputController = nil
            if app.active && app.sessionInputController === self { app.stop() }
        }
        inputClient = nil
        activatedHostPID = nil
    }

    func refreshClient() {
        // The activation sender is not necessarily the text client.
        inputClient = client()
    }

    override func inputText(_ string: String!, client sender: Any!) -> Bool {
        bindActiveClient()
        return false
    }

    @discardableResult func commit(_ string: String) -> Bool {
        guard let inputClient else { return false }
        inputClient.insertText(string, replacementRange: NSRange(location: NSNotFound, length: 0))
        return true
    }

    override func menu() -> NSMenu! {
        let menu = NSMenu(title: "洛克输入法")
        // InputMethodKit dispatches menu selectors to the input controller,
        // rather than the NSMenuItem's ordinary AppKit target.
        let settings = NSMenuItem(title: "洛克输入法设置…", action: #selector(openRokoSettings(_:)), keyEquivalent: "")
        menu.addItem(settings)
        return menu
    }

    override func showPreferences(_ sender: Any!) {
        openRokoSettings(sender)
    }

    override func doCommand(by aSelector: Selector!, command infoDictionary: [AnyHashable: Any]!) {
        let name = aSelector.map { NSStringFromSelector($0) } ?? "nil"
        Logger(subsystem: "im.roko.inputmethod.RokoInput", category: "input-menu").info("Menu command: \(name, privacy: .public)")
        if ["openRokoSettings:", "showPreferences:", "showWindow"].contains(name) {
            openRokoSettings(infoDictionary)
        } else {
            super.doCommand(by: aSelector, command: infoDictionary)
        }
    }

    // macOS can retain a command selector from an earlier input-menu snapshot.
    @objc func showWindow() { openRokoSettings(nil) }

    @objc func openRokoSettings(_ sender: Any?) {
        Logger(subsystem: "im.roko.inputmethod.RokoInput", category: "input-menu").info("Opening settings from input controller")
        DispatchQueue.main.async {
            (NSApp.delegate as? VoiceApp)?.showWindow()
        }
    }
}
