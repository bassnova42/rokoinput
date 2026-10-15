import Cocoa
import SwiftUI
import AVFoundation
import Speech
import Carbon
import InputMethodKit
import OSLog

// Serialize the end-of-input marker with in-flight audio callbacks.
final class AudioFeed {
    let request: SFSpeechAudioBufferRecognitionRequest
    let lock = NSLock()
    var ended = false
    init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        if !ended { request.append(buffer) }
    }
    func end() {
        lock.lock()
        defer { lock.unlock() }
        if !ended { ended = true; request.endAudio() }
    }
}

final class VoiceApp: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let status = NSTextField(labelWithString: "就绪 · 苹果语音识别")
    let metrics = NSTextField(labelWithString: "首字与收尾耗时将在识别后显示")
    let text = NSTextView()
    let startButton = NSButton(title: "开始说话", target: nil, action: nil)
    let stopButton = NSButton(title: "结束说话", target: nil, action: nil)
    let copyButton = NSButton(title: "复制文字", target: nil, action: nil)
    var engine = AVAudioEngine()
    var recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    var request: SFSpeechAudioBufferRecognitionRequest?
    var audioFeed: AudioFeed?
    var task: SFSpeechRecognitionTask?
    var generation = UUID()
    var started: TimeInterval = 0
    var stopped: TimeInterval?
    var first: TimeInterval?
    var timer: Timer?
    var tapInstalled = false
    var active = false
    var requestingPermission = false
    var switchHotKey: EventHotKeyRef?
    var switchShortcut = Shortcut.loadSwitch()
    var capturingSwitchShortcut = false
    var settingsModel: SettingsModel!
    var hotKey: EventHotKeyRef?
    var hotKeyHandler: EventHandlerRef?
    var targetApp: NSRunningApplication?
    var autoInsert = false
    var inputStartGeneration = 0
    var holdKey = HoldKey()
    var hotkeyHeld: Bool { holdKey.isHeld }
    var startedFromHotkey = false
    var reachedRecordingLimit = false
    var transcriptBuffer = TranscriptBuffer()
    weak var activeInputController: RokoInputController?
    weak var sessionInputController: RokoInputController?
    let history = HistoryStore()
    let loggingCheckbox = NSButton(checkboxWithTitle: "保存每次转写的文字历史（本机明文）", target: nil, action: nil)
    var historyEnabledForSession = true
    var hotKeyReady = false
    var shortcut = Shortcut.load()
    var shortcutMonitor: Any?
    var shortcutSheet: NSWindow?
    var statsWindow: NSWindow?
    let statistics = StatisticsStore()
    let hud = RecordingHUD()
    let clock = { ProcessInfo.processInfo.systemUptime }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let menu = NSMenu()
        let item = NSMenuItem()
        menu.addItem(item)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出洛克输入法", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 610), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "洛克输入法 · Roko Input"
        window.center()
        window.setContentSize(NSSize(width: 1000, height: 740))
        window.minSize = NSSize(width: 920, height: 680)
        window.appearance = NSAppearance(named: .darkAqua)
        settingsModel = SettingsModel(owner: self)
        window.contentView = NSHostingView(rootView: SettingsRoot(model: settingsModel))
        for button in [startButton, stopButton, copyButton] { button.target = self }
        startButton.action = #selector(start)
        stopButton.action = #selector(stop)
        copyButton.action = #selector(copyText)
        setupHotKey()
        if CommandLine.arguments.contains("--settings") { showWindow() }
    }

    @objc func start() {
        guard !active && !requestingPermission else { return }
        if !hotkeyHeld {
            autoInsert = false
            sessionInputController = nil
            targetApp = nil
        }
        startedFromHotkey = hotkeyHeld
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized && SFSpeechRecognizer.authorizationStatus() == .authorized {
            beginCapture()
            return
        }
        preparePermissions()
    }

    func preparePermissions() {
        let microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        guard microphone != .denied && microphone != .restricted else {
            permissionFailed("麦克风未获授权，请在系统设置 → 隐私与安全性 → 麦克风中允许洛克输入法。")
            return
        }
        let speech = SFSpeechRecognizer.authorizationStatus()
        guard speech != .denied && speech != .restricted else {
            permissionFailed("语音识别未获授权，请在系统设置 → 隐私与安全性 → 语音识别中允许洛克输入法。")
            return
        }
        requestingPermission = true
        startButton.isEnabled = false
        status.stringValue = "首次使用需要麦克风与语音识别权限，请完成系统提示。"
        // Permission setup is separate from recording. A released key during a
        // system dialog is expected and must not become a failed dictation.
        if microphone == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { allowed in
                DispatchQueue.main.async {
                    guard allowed else { self.finishPermissionSetup(); return }
                    self.requestSpeechPermissionIfNeeded()
                }
            }
        } else { requestSpeechPermissionIfNeeded() }
    }

    func requestSpeechPermissionIfNeeded() {
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { _ in
                DispatchQueue.main.async { self.finishPermissionSetup() }
            }
        } else { finishPermissionSetup() }
    }

    func finishPermissionSetup() {
        requestingPermission = false
        startButton.isEnabled = true
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized && SFSpeechRecognizer.authorizationStatus() == .authorized {
            let message = "权限已就绪，请重新按住快捷键说话。"
            status.stringValue = message
            hud.notice(message, seconds: 4)
        } else {
            permissionFailed("权限尚未开启，可在系统设置 → 隐私与安全性中允许洛克输入法后再试。")
        }
    }

    func permissionFailed(_ message: String) {
        requestingPermission = false
        autoInsert = false
        startButton.isEnabled = true
        status.stringValue = message
        hud.notice(message, seconds: 6)
    }

    func showShortPressNotice() {
        // Cancel this request without logging partial text or adding statistics.
        let hadActiveRequest = active
        cleanup()
        if hadActiveRequest { text.string = "" }
        autoInsert = false
        startButton.isEnabled = !requestingPermission
        stopButton.isEnabled = false
        text.isEditable = true
        let message = "按住时间太短，请按住快捷键说完后再松开。"
        status.stringValue = message
        hud.notice(message, seconds: 3)
    }

    func beginCapture() {
        cleanup()
        // Device changes can invalidate a previously configured engine/tap format.
        engine = AVAudioEngine()
        guard let recognizer = recognizer, recognizer.supportsOnDeviceRecognition else {
            permissionFailed("本机暂不支持中文端侧识别，请先在系统中准备中文语音资源。不会使用云端。")
            return
        }
        generation = UUID()
        let id = generation
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        req.taskHint = .dictation
        request = req
        let feed = AudioFeed(req)
        audioFeed = feed
        started = clock()
        reachedRecordingLimit = false
        historyEnabledForSession = history.enabled
        stopped = nil
        first = nil
        text.string = ""
        transcriptBuffer = TranscriptBuffer()
        text.isEditable = false
        metrics.stringValue = "首字：等待中 · 收尾：—"
        active = true
        task = recognizer.recognitionTask(with: req) { result, error in
            DispatchQueue.main.async {
                guard self.generation == id, self.active else { return }
                if let result = result {
                    let transcript = result.bestTranscription.formattedString
                    let segments = result.bestTranscription.segments
                    let validTimes = !segments.isEmpty && segments.allSatisfy { $0.timestamp.isFinite && $0.duration.isFinite && $0.duration > 0 }
                    let firstTime = validTimes ? segments.first?.timestamp : nil
                    let lastTime = validTimes ? segments.last.map { $0.timestamp + $0.duration } : nil
                    self.transcriptBuffer.update(transcript, start: firstTime, end: lastTime)
                    if !self.transcriptBuffer.text.isEmpty { self.text.string = self.transcriptBuffer.text }
                    Logger(subsystem: "im.roko.inputmethod.RokoInput", category: "recognition").info("ASR snapshot chars=\(transcript.count) timed=\(validTimes) spans=\(self.transcriptBuffer.spans.count) final=\(result.isFinal)")
                    if self.first == nil && !self.text.string.isEmpty { self.first = self.clock() }
                    self.updateMetrics(final: result.isFinal)
                    if result.isFinal {
                        let output = self.text.string
                        let shouldInsert = self.autoInsert
                        self.finish("识别完成，可以复制。", final: true)
                        if shouldInsert { self.insertFinal(output) }
                    }
                }
                if let error = error, self.active {
                    let native = error as NSError
                    Logger(subsystem: "im.roko.inputmethod.RokoInput", category: "recognition").error("Recognition failure domain=\(native.domain, privacy: .public) code=\(native.code)")
                    self.finish(RecognitionFailure.message(native))
                }
            }
        }
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            finish("没有可用麦克风。")
            return
        }
        let meter = hud.level
        input.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            meter.capture(buffer)
            feed.append(buffer)
        }
        tapInstalled = true
        do {
            engine.prepare()
            try engine.start()
            hud.recording()
            status.stringValue = "正在录音 · 临时文字可能继续修正"
            stopButton.isEnabled = true
            timer = Timer.scheduledTimer(withTimeInterval: 55, repeats: false) { _ in
                self.reachedRecordingLimit = true
                self.stop()
            }
        } catch { finish("录音启动失败：\(error.localizedDescription)") }
    }

    @objc func stop() {
        guard active && stopped == nil else { return }
        stopped = clock()
        hud.waiting()
        if reachedRecordingLimit {
            hud.notice("已录满55秒，请松开后重新按住", seconds: 10)
        }
        stopCapture()
        audioFeed?.end()
        stopButton.isEnabled = false
        status.stringValue = "录音已停止，等待最终修正…"
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { _ in
            self.finish("本地识别等待最终结果超时。")
        }
    }

    func updateMetrics(final: Bool) {
        let firstText = first.map { String(format: "%.0f ms", ($0 - started) * 1000) } ?? "等待中"
        let tail = final ? stopped.map { String(format: "%.0f ms", (clock() - $0) * 1000) } ?? "自动结束" : "—"
        metrics.stringValue = "开始到首字：\(firstText) · 停止到最终结果：\(tail)"
    }

    func stopCapture() {
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        engine.stop()
    }

    func cleanup() {
        active = false
        generation = UUID()
        timer?.invalidate()
        timer = nil
        stopCapture()
        audioFeed?.end()
        task?.cancel()
        task = nil
        request = nil
        audioFeed = nil
    }

    func finish(_ message: String, final: Bool = false) {
        var historyError: String?
        if active && !text.string.isEmpty && historyEnabledForSession && history.enabled {
            do {
                try history.append(text: text.string, final: final, reason: final ? "final" : "interrupted_or_error", firstMS: first.map { ($0 - started) * 1000 }, tailMS: final ? stopped.map { (clock() - $0) * 1000 } : nil)
            } catch { historyError = error.localizedDescription }
        }
        if active && final && !text.string.isEmpty {
            do {
                try statistics.record(text: text.string, seconds: max(0, (stopped ?? clock()) - started), firstMS: first.map { ($0 - started) * 1000 })
            } catch { historyError = "统计保存失败：" + error.localizedDescription }
        }
        cleanup()
        refreshStatistics()
        status.stringValue = historyError.map { message + " 日志保存失败：" + $0 } ?? message
        startButton.isEnabled = true
        stopButton.isEnabled = false
        text.isEditable = true
        if final {
            if reachedRecordingLimit {
                hud.notice("已录满55秒，请松开后重新按住", seconds: 8)
            } else if startedFromHotkey && hotkeyHeld {
                hud.notice("本次识别已结束，请松开后重新按住", seconds: 8)
            } else { hud.hide() }
        } else {
            let retained = !text.string.isEmpty
            let detail = message + (retained ? " 文字已保留，可从 Roko 设置复制。" : " 未获得文字。")
            status.stringValue = detail
            hud.notice(detail, seconds: 7)
        }
        autoInsert = false
    }

    @objc func copyText() {
        guard !text.string.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text.string, forType: .string)
        status.stringValue = active ? "已复制当前临时文字 · 仍在识别" : "文字已复制"
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { false }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        if active { finish("应用退出，已保留本次文字。") } else { cleanup() }
        hud.hide()
        if let monitor = shortcutMonitor { NSEvent.removeMonitor(monitor) }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let switchHotKey { UnregisterEventHotKey(switchHotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    }
}

if CommandLine.arguments.contains("--register-input-source") {
    let result = TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
    if result != noErr { fputs("Input source registration failed: \(result)\n", stderr); exit(1) }
    let filter = [kTISPropertyBundleID as String: Bundle.main.bundleIdentifier ?? ""] as CFDictionary
    let sources = TISCreateInputSourceList(filter, true).takeRetainedValue() as! [TISInputSource]
    for source in sources { _ = TISEnableInputSource(source) }
    print("Registered Roko Input. If absent in the input menu, log out and sign in, then add it in Keyboard settings.")
    exit(0)
}

let app = NSApplication.shared
let delegate = VoiceApp()
app.delegate = delegate
let inputServer = IMKServer(name: "RokoInput_Connection", bundleIdentifier: Bundle.main.bundleIdentifier)
guard inputServer != nil else {
    fputs("Roko Input: failed to create InputMethodKit server.\n", stderr)
    exit(1)
}
app.run()
