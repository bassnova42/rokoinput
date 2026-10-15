import Cocoa
import Carbon

extension VoiceApp {
    @objc func editShortcut() { captureShortcut(forSwitch: false) }
    @objc func editSwitchShortcut() { captureShortcut(forSwitch: true) }

    func captureShortcut(forSwitch: Bool) {
        guard !active, !requestingPermission, !hotkeyHeld else { status.stringValue = "请先结束当前语音输入。"; return }
        showWindow()
        cancelShortcutCapture()
        capturingSwitchShortcut = forSwitch
        let alert = NSAlert()
        alert.messageText = forSwitch ? "设置切换到洛克的快捷键" : "设置按住说话快捷键"
        let current = forSwitch ? (switchShortcut?.label ?? "未设置") : shortcut.label
        alert.informativeText = "当前：\(current)\n直接按下新组合键：功能键，或含 ⌘/⌥/⌃ 的组合键。\nEsc 取消；冲突时保留原设置。"
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: forSwitch ? "清除快捷键" : "恢复 F5")
        shortcutSheet = alert.window
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.cancelShortcutCapture(); return nil }
            var modifiers: UInt32 = 0
            let flags = event.modifierFlags
            if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
            if flags.contains(.option) { modifiers |= UInt32(optionKey) }
            if flags.contains(.control) { modifiers |= UInt32(controlKey) }
            if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
            let functions: [UInt16: String] = [122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12",105:"F13",107:"F14",113:"F15",106:"F16",64:"F17",79:"F18",80:"F19",90:"F20"]
            guard functions[event.keyCode] != nil || modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 else { NSSound.beep(); return nil }
            guard !event.isARepeat else { return nil }
            let name = functions[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
            let prefix = (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
            let candidate = Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, label: prefix + name)
            self.cancelShortcutCapture()
            if forSwitch { _ = self.registerSwitchShortcut(candidate) }
            else { _ = self.registerShortcut(candidate) }
            self.settingsModel.refresh()
            return nil
        }
        alert.beginSheetModal(for: window) { [weak self] response in
            self?.cancelShortcutCapture()
            if response == .alertSecondButtonReturn {
                if forSwitch { self?.clearSwitchShortcut() }
                else { _ = self?.registerShortcut(.standard) }
            }
            self?.settingsModel.refresh()
        }
    }

    func cancelShortcutCapture() {
        if let monitor = shortcutMonitor { NSEvent.removeMonitor(monitor) }
        shortcutMonitor = nil
        if let sheet = shortcutSheet { window.endSheet(sheet); sheet.orderOut(nil) }
        shortcutSheet = nil
    }
}

extension VoiceApp {
    @discardableResult func registerSwitchShortcut(_ candidate: Shortcut) -> Bool {
        guard !active, !requestingPermission, !hotkeyHeld else { return false }
        if candidate.keyCode == shortcut.keyCode && candidate.modifiers == shortcut.modifiers {
            status.stringValue = "两个快捷键不能相同，原设置已保留。"; return false
        }
        if candidate == switchShortcut && switchHotKey != nil { return true }
        var replacement: EventHotKeyRef?
        let result = RegisterEventHotKey(candidate.keyCode, candidate.modifiers,
            EventHotKeyID(signature: 0x56354635, id: 2), GetApplicationEventTarget(), 0, &replacement)
        guard result == noErr else { status.stringValue = "快捷键被占用，原设置已保留。"; return false }
        if let old = switchHotKey { UnregisterEventHotKey(old) }
        switchHotKey = replacement; switchShortcut = candidate; candidate.saveSwitch()
        status.stringValue = "切换输入法快捷键已保存：" + candidate.label
        return true
    }
    func clearSwitchShortcut() {
        if let old = switchHotKey { UnregisterEventHotKey(old) }
        switchHotKey = nil; switchShortcut = nil
        UserDefaults.standard.removeObject(forKey: "switchShortcut")
    }
    func selectRokoInput() {
        guard !active, !requestingPermission else { return }
        let filter = [kTISPropertyInputSourceID as String: "im.roko.inputmethod.RokoInput.voice"] as CFDictionary
        let sources = TISCreateInputSourceList(filter, false).takeRetainedValue() as! [TISInputSource]
        guard let source = sources.first, TISSelectInputSource(source) == noErr else {
            hud.notice("请先在系统键盘设置中添加洛克输入法"); return
        }
        hud.notice("已切换到洛克输入法", seconds: 1.5)
    }
}
