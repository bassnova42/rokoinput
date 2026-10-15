import Foundation

@main struct CoreTests {
    static func main() throws {
        var transcript = TranscriptBuffer()
        transcript.update("第一句。", start: 0, end: 2)
        transcript.update("第二句。", start: 4, end: 6)
        assert(transcript.text == "第一句。\n第二句。")
        transcript.update("第二句修正。", start: 4, end: 6.5)
        assert(transcript.text == "第一句。\n第二句修正。")
        transcript.update("", start: nil, end: nil)
        assert(transcript.text == "第一句。\n第二句修正。")
        transcript.update("两句合并修正。", start: 0, end: 6.5)
        assert(transcript.text == "两句合并修正。")
        transcript.update("两句合并修正。", start: 8, end: 9)
        assert(transcript.spans.count == 2) // Actually repeated speech must survive.
        var correction = TranscriptBuffer()
        correction.update("今天开会", start: 0, end: 2)
        correction.update("明天开会", start: 0, end: 2)
        assert(correction.text == "明天开会")
        print("PASS: timed utterance preservation, corrections, cumulative revisions, repeats and empty final snapshots")
        let disabled = NSError(domain: "kLSRErrorDomain", code: 201)
        assert(RecognitionFailure.message(disabled).contains("系统听写已关闭"))
        assert(!RecognitionFailure.message(NSError(domain: "OtherDomain", code: 201)).contains("系统听写已关闭"))
        var key = HoldKey()
        assert(key.update(pressed: true) && key.isHeld)
        assert(!key.update(pressed: true) && key.isHeld)
        assert(key.update(pressed: false) && !key.isHeld)
        assert(!key.update(pressed: false))
        // Permission may finish after release: the held state stays false.
        assert(!key.isHeld)
        assert(key.update(pressed: true))
        assert(key.update(pressed: false))
        var timedKey = HoldKey()
        assert(timedKey.update(pressed: true, now: 10))
        assert(!timedKey.update(pressed: true, now: 10.1))
        assert(timedKey.update(pressed: false, now: 10.3))
        assert(timedKey.wasShortPress)
        assert(timedKey.update(pressed: true, now: 20))
        assert(timedKey.update(pressed: false, now: 20.5))
        assert(!timedKey.wasShortPress)

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("roko-tests-" + UUID().uuidString)
        let suite = "im.roko.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            try? FileManager.default.removeItem(at: folder)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = HistoryStore(defaults: defaults, directory: folder)
        assert(store.enabled)
        store.enabled = false
        try store.append(text: "不应写入", final: true, reason: "final", firstMS: nil, tailMS: nil)
        assert(!FileManager.default.fileExists(atPath: folder.path))
        store.enabled = true
        let original = "第一句，中文标点。\n第二句含\"引号\"。"
        try store.append(text: original, final: true, reason: "final", firstMS: 120, tailMS: 45)
        try store.append(text: "中断保留", final: false, reason: "interrupted_or_error", firstMS: nil, tailMS: nil)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        assert(files.count == 1 && files[0].pathExtension == "jsonl")
        let lines = try String(contentsOf: files[0], encoding: .utf8).split(separator: "\n")
        assert(lines.count == 2)
        let records = try lines.map { try JSONDecoder().decode(HistoryRecord.self, from: Data($0.utf8)) }
        assert(records[0].text == original && records[0].final && !records[1].final)
        assert(records[0].id != records[1].id)
        assert(records[0].firstResultMS == 120 && records[1].firstResultMS == nil)
        let mode = try FileManager.default.attributesOfItem(atPath: files[0].path)[.posixPermissions] as! NSNumber
        assert(mode.intValue == 0o600)
        let dirMode = try FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as! NSNumber
        assert(dirMode.intValue == 0o700)
        let stats = StatisticsStore(file: folder.appendingPathComponent("stats.json"))
        assert(StatisticsStore.countCharacters("你好，Roko 123! 😊") == 9)
        let today = Date(timeIntervalSince1970: 1791936000)
        try stats.record(text: "你好。", seconds: 4, firstMS: 200, date: today)
        try stats.record(text: "abc!", seconds: 6, firstMS: nil, date: today)
        let day = try stats.load()[StatisticsStore.day(today)]!
        assert(day.characters == 5 && day.sessions == 2 && day.recordingSeconds == 10)
        assert(day.firstResultSamples == 1 && day.firstResultTotalMS == 200)
        try stats.record(text: "明天", seconds: 1, firstMS: 100, date: today.addingTimeInterval(86400))
        let allDays = try stats.load(); assert(allDays.count == 2)
        let contents = try Data(contentsOf: stats.file)
        assert(!String(decoding: contents, as: UTF8.self).contains("你好"))
        try Data("broken".utf8).write(to: stats.file)
        do { try stats.record(text: "x", seconds: 1, firstMS: nil); assertionFailure("Corrupt stats must not be overwritten") } catch { }
        let corrupted = try Data(contentsOf: stats.file); assert(corrupted == Data("broken".utf8))
        let binding = Shortcut(keyCode: 40, modifiers: 256, label: "⌘K")
        let decodedBinding = try JSONDecoder().decode(Shortcut.self, from: JSONEncoder().encode(binding)); assert(decodedBinding == binding)
        print("PASS: statistics aggregation/counting/date boundaries/corruption protection, shortcut encoding")
        print("PASS: hold/release, repeat suppression, disabled history, Chinese/newline JSONL roundtrip, interruption, metrics, file permissions")
    }
}
