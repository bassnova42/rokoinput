import SwiftUI
import Cocoa
import AVFoundation
import Speech
import WebKit

enum SettingsPage: String, CaseIterable, Identifiable {
    case voice = "语音输入", shortcuts = "快捷键", statistics = "输入统计", history = "输入日志"
    var id: String { rawValue }
    var icon: String {
        switch self { case .voice: return "mic"; case .shortcuts: return "keyboard"; case .statistics: return "chart.bar.xaxis"; case .history: return "text.book.closed" }
    }
    var subtitle: String {
        switch self {
        case .voice: return "按住说话，松开落字。"
        case .shortcuts: return "让语音输入顺应你的习惯。"
        case .statistics: return "每一次开口，都看得见。"
        case .history: return "说过的文字，留在自己的电脑里。"
        }
    }
}

final class SettingsModel: ObservableObject {
    unowned let owner: VoiceApp
    @Published var page: SettingsPage = .voice
    @Published var days: [String: DailyStatistics] = [:]
    @Published var records: [HistoryRecord] = []
    @Published var dates: [String] = []
    @Published var date = StatisticsStore.day(Date())
    @Published var query = ""
    @Published var error = ""
    @Published var logError = ""
    @Published var revision = 0
    private var timer: Timer?
    init(owner: VoiceApp) {
        self.owner = owner
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.owner.window.isVisible else { return }
            self.revision += 1
        }
        refresh()
    }
    deinit { timer?.invalidate() }
    func refresh() {
        do { days = try owner.statistics.load(); error = "" }
        catch { self.error = "无法读取统计：" + error.localizedDescription }
        do {
            let folder = owner.history.directory
            dates = FileManager.default.fileExists(atPath: folder.path)
                ? try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".jsonl") }.map { String($0.dropLast(6)) }.sorted(by: >) : []
            if !dates.contains(date) { date = dates.first ?? StatisticsStore.day(Date()) }
            loadHistory()
        } catch { logError = "无法读取日志目录：" + error.localizedDescription }
        revision += 1
    }
    func loadHistory() {
        records = []; logError = ""
        let url = owner.history.directory.appendingPathComponent(date + ".jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            // Read one day only; malformed lines do not hide other recordings.
            let contents = try String(contentsOf: url, encoding: .utf8)
            var invalid = 0
            records = contents.split(separator: "\n").compactMap {
                guard let record = try? JSONDecoder().decode(HistoryRecord.self, from: Data($0.utf8)) else { invalid += 1; return nil }
                return record
            }.reversed()
            if invalid > 0 { logError = "有 \(invalid) 条记录无法读取，已显示其余记录。" }
        } catch { logError = "无法读取日志：" + error.localizedDescription }
    }
    var today: DailyStatistics { days[StatisticsStore.day(Date())] ?? DailyStatistics() }
    var week: [(String, DailyStatistics)] {
        (0..<7).reversed().map {
            let key = StatisticsStore.day(Calendar.current.date(byAdding: .day, value: -$0, to: Date())!)
            return (key, days[key] ?? DailyStatistics())
        }
    }
    var filtered: [HistoryRecord] { records.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) } }
    func copy(_ value: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string) }
    func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + pane) { NSWorkspace.shared.open(url) }
    }
}

private let accent = Color(red: 1, green: 0.57, blue: 0.18)
private let muted = Color.white.opacity(0.48)

struct SettingsRoot: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    Text("R").font(.system(size: 22, weight: .black, design: .rounded)).foregroundColor(.black)
                        .frame(width: 36, height: 36).background(accent.gradient).clipShape(RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("洛克输入法").font(.system(size: 16, weight: .semibold))
                        Text("ROKO INPUT").font(.system(size: 9, weight: .medium)).tracking(2).foregroundColor(muted)
                    }
                }.padding(.bottom, 28).padding(.top, 12)
                ForEach(SettingsPage.allCases) { page in
                    Button { model.page = page; model.refresh() } label: {
                        HStack(spacing: 12) { Image(systemName: page.icon).frame(width: 18); Text(page.rawValue); Spacer() }
                            .font(.system(size: 14, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 13)
                            .foregroundColor(model.page == page ? accent : Color.white.opacity(0.65))
                            .background(model.page == page ? accent.opacity(0.12) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Label("Apple 端侧识别", systemImage: "lock.shield").font(.system(size: 11)).foregroundColor(muted)
                Text("音频不上传 · 不回退云端").font(.system(size: 10)).foregroundColor(muted).padding(.bottom, 12)
            }.padding(20).frame(width: 190).frame(maxHeight: .infinity).background(Color(white: 0.105))
            Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.page.rawValue).font(.system(size: 28, weight: .bold))
                            Text(model.page.subtitle).font(.system(size: 13)).foregroundColor(muted)
                        }
                        Spacer()
                        Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.help("刷新页面")
                    }.padding(.bottom, 4)
                    switch model.page {
                    case .voice: voice
                    case .shortcuts: shortcuts
                    case .statistics: dashboard
                    case .history: history
                    }
                }.padding(30).frame(maxWidth: .infinity, alignment: .leading)
            }.id(model.page).background(Color(white: 0.075))
        }.foregroundColor(Color(white: 0.9)).tint(accent).preferredColorScheme(.dark)
        .onChange(of: model.date) { _ in model.loadHistory() }
    }
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16, content: content).padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.13)).clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.05)))
    }
    private func caption(_ text: String) -> some View { Text(text).font(.system(size: 12)).foregroundColor(muted).fixedSize(horizontal: false, vertical: true) }
    private var voice: some View {
        Group {
            card {
                HStack {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("把想法，说出来。").font(.system(size: 24, weight: .semibold))
                        caption("无需打开这个窗口，在输入框里直接说话。")
                        ForEach(Array(["从系统输入法菜单选择洛克", "点击需要输入文字的位置", "按住 \(model.owner.shortcut.label) 说话，松开结束"].enumerated()), id: \.offset) { i, text in
                            HStack(spacing: 10) {
                                Text("\(i + 1)").font(.system(size: 11, weight: .bold)).foregroundColor(accent).frame(width: 23, height: 23).background(accent.opacity(0.12)).clipShape(Circle())
                                Text(text).font(.system(size: 12))
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    KeyboardPreview().frame(width: 220, height: 175).allowsHitTesting(false)
                }
                Divider().overlay(Color.white.opacity(0.04))
                HStack { Label("当前说话键", systemImage: "keyboard").foregroundColor(muted); Spacer(); Text(model.owner.shortcut.label).font(.system(.body, design: .monospaced)).foregroundColor(accent) }.font(.system(size: 12))
                if model.owner.shortcut != .standard { caption("右侧键盘展示默认 F5；当前请使用上方显示的快捷键。") }
            }
            card {
                Text("权限与本地识别").font(.system(size: 15, weight: .semibold))
                permissionRow("麦克风", detail: "用于接收你说话的声音", ready: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized) { model.owner.preparePermissions() }
                permissionRow("语音识别", detail: "仅允许 Apple 端侧识别", ready: SFSpeechRecognizer.authorizationStatus() == .authorized) { model.owner.preparePermissions() }
                HStack { Label("中文端侧模型", systemImage: "cpu"); Spacer(); Text(model.owner.recognizer?.supportsOnDeviceRecognition == true ? "支持本地识别" : "资源尚未就绪").foregroundColor(muted) }.font(.system(size: 12))
                HStack { Button("麦克风系统设置") { model.openPrivacy("Privacy_Microphone") }; Button("语音识别系统设置") { model.openPrivacy("Privacy_SpeechRecognition") } }.controlSize(.small)
                caption("不需要辅助功能权限。首次授权后，重新按住快捷键即可；权限被拒绝时请到系统设置开启。")
            }
            card {
                HStack { Text("试说一句").font(.system(size: 15, weight: .semibold)); Spacer(); Text("仅在此窗口预览").font(.system(size: 11)).foregroundColor(muted) }
                Text(model.owner.text.string.isEmpty ? "识别出的文字会显示在这里…" : model.owner.text.string).font(.system(size: 15)).foregroundColor(model.owner.text.string.isEmpty ? muted : .white).textSelection(.enabled).frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                HStack {
                    Button(model.owner.active ? "结束试说" : "开始试说") { if model.owner.active { model.owner.stop() } else { model.owner.start() } }.disabled(model.owner.requestingPermission)
                    Button("复制文字") { model.owner.copyText() }.disabled(model.owner.text.string.isEmpty)
                }
                caption(model.owner.status.stringValue)
            }
        }
    }
    private func permissionRow(_ title: String, detail: String, ready: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle.dashed").foregroundColor(ready ? .green : accent)
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 13, weight: .medium)); caption(detail) }
            Spacer()
            if ready { Text("已开通").font(.system(size: 12)).foregroundColor(.green) }
            else { Button("开通", action: action).disabled(model.owner.requestingPermission) }
        }.padding(.vertical, 3)
    }
    private var shortcuts: some View {
        Group {
            card {
                Label("按住说话", systemImage: "mic").font(.system(size: 17, weight: .semibold))
                caption("按住开始收音，松手结束并将文字写入光标位置。")
                shortcutRow(model.owner.shortcut.label) { model.owner.editShortcut() }
            }
            card {
                Label("切换到洛克输入法", systemImage: "arrow.left.arrow.right").font(.system(size: 17, weight: .semibold))
                caption("在其他应用中按一次，直接选中洛克输入法。此操作不开始录音。")
                shortcutRow(model.owner.switchShortcut?.label ?? "未设置") { model.owner.editSwitchShortcut() }
            }
            caption("支持 F1–F20 或带 ⌘ / ⌥ / ⌃ 的组合键。两个快捷键需要不同；系统或其他应用已占用时会保留原设置。部分键盘需配合 fn 才能发送 F5。")
            caption(model.owner.status.stringValue)
        }
    }
    private func shortcutRow(_ value: String, action: @escaping () -> Void) -> some View {
        HStack { Text(value).font(.system(size: 20, weight: .medium, design: .monospaced)).padding(.horizontal, 20).padding(.vertical, 12).background(Color.black.opacity(0.22)).clipShape(RoundedRectangle(cornerRadius: 9)); Spacer(); Button("更改快捷键…", action: action) }
    }
    private var dashboard: some View {
        Group {
            HStack(spacing: 12) {
                metric("今日输入", value: "\(model.today.characters)", unit: "字", icon: "textformat")
                metric("使用次数", value: "\(model.today.sessions)", unit: "次", icon: "waveform")
                metric("说话时长", value: String(format: "%.1f", model.today.recordingSeconds / 60), unit: "分钟", icon: "clock")
            }
            card {
                HStack { Text("最近 7 天").font(.system(size: 16, weight: .semibold)); Spacer(); caption("识别字数") }
                HStack(alignment: .bottom, spacing: 16) {
                    ForEach(model.week, id: \.0) { key, day in
                        VStack(spacing: 10) {
                            Text("\(day.characters)").font(.system(size: 11, weight: .medium)).foregroundColor(muted)
                            RoundedRectangle(cornerRadius: 5).fill(key == StatisticsStore.day(Date()) ? accent.gradient : Color(white: 0.30).gradient)
                                .frame(height: max(3, 130 * Double(day.characters) / Double(max(1, model.week.map { $0.1.characters }.max() ?? 1))))
                            Text(String(key.suffix(5))).font(.system(size: 10)).foregroundColor(muted)
                        }.frame(maxWidth: .infinity)
                    }
                }.frame(height: 175, alignment: .bottom)
            }
            HStack(spacing: 12) {
                metric("今日平均首字", value: model.today.firstResultSamples > 0 ? String(format: "%.0f", model.today.firstResultTotalMS / Double(model.today.firstResultSamples)) : "—", unit: "ms", icon: "bolt")
                metric("累计识别", value: "\(model.days.values.reduce(0) { $0 + $1.characters })", unit: "字", icon: "sum")
            }
            if !model.error.isEmpty { Text(model.error).foregroundColor(accent) }
            caption("按最终识别结果计数，不代表已成功写入目标应用。字数不含标点、空白和表情，英文按字母计数。关闭文字历史仍保留统计汇总；不从旧日志补算。")
        }
    }
    private func metric(_ title: String, value: String, unit: String, icon: String) -> some View {
        card {
            Label(title, systemImage: icon).font(.system(size: 11)).foregroundColor(muted)
            HStack(alignment: .firstTextBaseline, spacing: 5) { Text(value).font(.system(size: 29, weight: .semibold, design: .rounded)).foregroundColor(accent).minimumScaleFactor(0.5).lineLimit(1); Text(unit).font(.system(size: 11)).foregroundColor(muted) }
        }
    }
    private var history: some View {
        Group {
            card {
                Toggle("保存文字历史", isOn: Binding(get: { model.owner.history.enabled }, set: { model.owner.history.enabled = $0; model.revision += 1 })).toggleStyle(.switch)
                caption("按天保存在本机，不保存录音。关闭后停止新增，已有记录仍可浏览。")
                HStack { Text(model.owner.history.directory.path).font(.system(size: 10, design: .monospaced)).foregroundColor(muted).textSelection(.enabled); Spacer(); Button("在 Finder 中打开") { model.owner.openHistory() } }
            }
            HStack {
                if !model.dates.isEmpty { Picker("日期", selection: $model.date) { ForEach(model.dates, id: \.self) { Text($0).tag($0) } }.frame(width: 205) }
                TextField("搜索这一天的文字", text: $model.query).textFieldStyle(.roundedBorder)
            }
            HStack { caption("\(model.filtered.count) 条记录 · 最新在前"); Spacer() }
            if !model.logError.isEmpty { Text(model.logError).font(.system(size: 12)).foregroundColor(accent) }
            if model.filtered.isEmpty {
                card { Image(systemName: "text.book.closed").font(.system(size: 28)).foregroundColor(muted); Text(model.query.isEmpty ? "这一天还没有记录" : "没有匹配的文字"); caption("保存的转写会按日期显示在这里。") }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(model.filtered, id: \.id) { record in
                        card {
                            HStack { Text(displayTime(record.timestamp)).font(.system(size: 11, design: .monospaced)).foregroundColor(muted); if !record.final { Text("未完成").font(.system(size: 10)).foregroundColor(accent) }; Spacer(); Button("复制") { model.copy(record.text) }.controlSize(.small) }
                            Text(record.text).font(.system(size: 14)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }
    private func displayTime(_ string: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: string) else { return string }
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss"; return formatter.string(from: date)
    }
}

struct KeyboardPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        if let url = Bundle.main.url(forResource: "keyboard", withExtension: "html") { view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent()) }
        return view
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
