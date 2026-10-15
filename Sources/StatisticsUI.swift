import Cocoa
extension VoiceApp {
    @objc func showStatistics() {
        settingsModel.page = .statistics
        showWindow()
    }
    func refreshStatistics() { settingsModel.refresh() }
}
