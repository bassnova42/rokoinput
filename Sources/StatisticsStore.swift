import Foundation

struct DailyStatistics: Codable {
    var characters = 0
    var sessions = 0
    var recordingSeconds = 0.0
    var firstResultTotalMS = 0.0
    var firstResultSamples = 0
}

final class StatisticsStore {
    let file: URL
    init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Roko Input/statistics.json")
    }
    static func countCharacters(_ text: String) -> Int {
        text.filter { character in character.unicodeScalars.contains { CharacterSet.letters.union(.decimalDigits).contains($0) } }.count
    }
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    func load() throws -> [String: DailyStatistics] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        return try JSONDecoder().decode([String: DailyStatistics].self, from: Data(contentsOf: file))
    }
    func record(text: String, seconds: Double, firstMS: Double?, date: Date = Date()) throws {
        var days = try load()
        let key = Self.day(date)
        var day = days[key] ?? DailyStatistics()
        day.characters += Self.countCharacters(text)
        day.sessions += 1
        day.recordingSeconds += max(0, seconds)
        if let firstMS { day.firstResultTotalMS += max(0, firstMS); day.firstResultSamples += 1 }
        days[key] = day
        let folder = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(days).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
