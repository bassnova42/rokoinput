import Cocoa

extension VoiceApp {
    @objc func toggleHistory() { history.enabled = loggingCheckbox.state == .on }
    @objc func openHistory() {
        do { try history.prepareDirectory(); NSWorkspace.shared.open(history.directory) }
        catch { status.stringValue = "无法打开日志目录：\(error.localizedDescription)" }
    }
}
