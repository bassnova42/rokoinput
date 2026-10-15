import Cocoa
import AVFoundation

// Audio thread writes only a scalar. AppKit drawing stays on the main thread.
final class AudioLevel {
    private let lock = NSLock()
    private var value: CGFloat = 0
    func capture(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        let stride = max(1, Int(buffer.frameLength) / 512)
        var sum: Float = 0
        var count: Float = 0
        for index in Swift.stride(from: 0, to: Int(buffer.frameLength), by: stride) {
            sum += samples[index] * samples[index]; count += 1
        }
        let rms = sqrt(sum / max(1, count))
        lock.lock(); value = CGFloat(min(1, rms * 9)); lock.unlock()
    }
    func read() -> CGFloat { lock.lock(); defer { lock.unlock() }; return value }
    func reset() { lock.lock(); value = 0; lock.unlock() }
}

final class WaveformView: NSView {
    var levels = [CGFloat](repeating: 0, count: 29)
    var message: String?
    override func draw(_ dirtyRect: NSRect) {
        let capsule = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 29, yRadius: 29)
        NSColor(calibratedWhite: 0.035, alpha: 0.91).setFill(); capsule.fill()
        NSColor.white.withAlphaComponent(0.14).setStroke(); capsule.lineWidth = 1; capsule.stroke()
        if let message {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.9)]
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingTail
            var textAttributes = attributes
            textAttributes[.paragraphStyle] = paragraph
            let string = NSAttributedString(string: message, attributes: textAttributes)
            let area = bounds.insetBy(dx: 14, dy: 12)
            string.draw(with: area, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            return
        }
        let gap: CGFloat = 3.5, width: CGFloat = 4
        let total = CGFloat(levels.count) * (width + gap) - gap
        for (index, level) in levels.enumerated() {
            let height = 5 + 33 * min(1, max(0, level))
            let x = (bounds.width - total) / 2 + CGFloat(index) * (width + gap)
            let rect = NSRect(x: x, y: (bounds.height - height) / 2, width: width, height: height)
            let fraction = CGFloat(index) / CGFloat(levels.count - 1)
            NSColor(calibratedRed: 1, green: 0.68 - fraction * 0.28, blue: 0.16 - fraction * 0.08, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        }
    }
}

final class RecordingHUD {
    let level = AudioLevel()
    private let panel: NSPanel
    private let waveform = WaveformView(frame: NSRect(x: 0, y: 0, width: 276, height: 58))
    private var timer: Timer?
    private var dismissal: DispatchWorkItem?
    init() {
        panel = NSPanel(contentRect: waveform.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Roko · 语音状态"
        panel.level = .floating
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.hidesOnDeactivate = false; panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = waveform
        panel.isReleasedWhenClosed = false
    }
    private func present() {
        dismissal?.cancel(); dismissal = nil
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 24))
        }
        panel.orderFrontRegardless() // Nonactivating: keep the editor's cursor and focus.
    }
    func recording() {
        hide(); level.reset(); waveform.message = nil
        waveform.levels = .init(repeating: 0, count: 29)
        present()
        timer = Timer.scheduledTimer(withTimeInterval: 0.045, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.waveform.levels.removeFirst(); self.waveform.levels.append(self.level.read())
            self.waveform.needsDisplay = true
        }
    }
    func waiting() { timer?.invalidate(); timer = nil; waveform.message = "正在识别…"; waveform.needsDisplay = true; present() }
    func notice(_ message: String, seconds: Double = 2.5) {
        timer?.invalidate(); timer = nil
        waveform.message = message; waveform.needsDisplay = true; present()
        let job = DispatchWorkItem { [weak self] in self?.hide() }
        dismissal = job; DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: job)
    }
    func hide() {
        timer?.invalidate(); timer = nil; dismissal?.cancel(); dismissal = nil
        panel.orderOut(nil)
    }
}
