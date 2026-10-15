import Cocoa
import Carbon

extension VoiceApp {
    func setupHotKey() {
        var kinds = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)), EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, data in
            guard let data, let event else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<VoiceApp>.fromOpaque(data).takeUnretainedValue()
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            var identifier = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            let isSwitch = identifier.id == 2
            DispatchQueue.main.async {
                if isSwitch { if pressed && owner.shortcutMonitor == nil { owner.selectRokoInput() } }
                else { owner.handleHotKey(pressed: pressed) }
            }
            return noErr
        }, 2, &kinds, context, &hotKeyHandler)
        _ = registerShortcut(shortcut)
        if let candidate = switchShortcut { _ = registerSwitchShortcut(candidate) }
    }

    @discardableResult func registerShortcut(_ candidate: Shortcut) -> Bool {
        if active || requestingPermission || hotkeyHeld { status.stringValue = "请先结束当前语音输入再修改快捷键。"; return false }
        if hotKeyReady && candidate == shortcut { return true }
        if let other = switchShortcut, candidate.keyCode == other.keyCode && candidate.modifiers == other.modifiers {
            status.stringValue = "两个快捷键不能相同，原设置已保留。"; return false
        }
        var replacement: EventHotKeyRef?
        let id = EventHotKeyID(signature: 0x56354635, id: 1)
        let result = RegisterEventHotKey(candidate.keyCode, candidate.modifiers, id, GetApplicationEventTarget(), 0, &replacement)
        guard result == noErr else { status.stringValue = "快捷键注册失败（\(result)），原设置已保留。"; return false }
        if let previous = hotKey { UnregisterEventHotKey(previous) }
        hotKey = replacement
        hotKeyReady = true
        shortcut = candidate
        candidate.save()
        status.stringValue = "快捷键：按住 \(candidate.label) 说话，松开结束 · 仅本地识别"
        return true
    }

    @objc func showWindow() {
        settingsModel?.refresh()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func handleHotKey(pressed: Bool) {
        if shortcutMonitor != nil {
            if pressed { cancelShortcutCapture(); status.stringValue = "当前快捷键：" + shortcut.label }
            return
        }
        guard holdKey.update(pressed: pressed) else { return }
        inputStartGeneration += 1
        if !pressed {
            if startedFromHotkey && active && holdKey.wasShortPress {
                showShortPressNotice()
            } else if active && startedFromHotkey { stop() }
            return
        }
        guard !requestingPermission, !active else { return }
        guard !IsSecureEventInputEnabled() else {
            status.stringValue = "系统处于安全输入模式，未开始录音。"
            return
        }
        guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            autoInsert = false
            start()
            return
        }
        startWhenInputReady(front: front, generation: inputStartGeneration, attempts: 8)
    }

    private func rokoIsSelected() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let value = TISGetInputSourceProperty(source, kTISPropertyBundleID) else { return false }
        return (Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String) == "im.roko.inputmethod.RokoInput"
    }

    private func startWhenInputReady(front: NSRunningApplication, generation: Int, attempts: Int) {
        guard generation == inputStartGeneration, hotkeyHeld, !active, !requestingPermission,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == front.processIdentifier,
              !IsSecureEventInputEnabled() else { return }
        guard rokoIsSelected() else {
            status.stringValue = "请先从系统输入法菜单切换到洛克输入法，再按住快捷键说话。"
            hud.notice("请先切换到洛克输入法")
            return
        }
        activeInputController?.refreshClient()
        if let controller = activeInputController,
           controller.inputClient != nil,
           controller.belongsTo(front) {
            sessionInputController = controller
            targetApp = front
            autoInsert = true
            start()
        } else if attempts > 0 {
            // App focus and IMK activation can arrive after the global hotkey.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.startWhenInputReady(front: front, generation: generation, attempts: attempts - 1)
            }
        } else {
            status.stringValue = "洛克输入法已选中，但系统尚未连接输入会话。请切换到其他输入法再切回洛克后重试。"
            hud.notice("输入会话未连接，请切换输入法后重试")
        }
    }

    func insertFinal(_ output: String) {
        guard !output.isEmpty else { return }
        guard !IsSecureEventInputEnabled(),
              let controller = sessionInputController,
              controller === activeInputController,
              let app = targetApp, !app.isTerminated,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              controller.belongsTo(app),
              controller.commit(output) else {
            status.stringValue = "输入会话已改变，文字已保留，可手动复制。"
            hud.notice("未自动写入，文字已保留")
            return
        }
        status.stringValue = "已通过输入法写入光标位置。"
    }
}
