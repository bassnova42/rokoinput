import Foundation
import Cocoa

struct HistoryRecord: Codable {
    let schemaVersion: Int
    let id: UUID
    let timestamp: String
    let text: String
    let final: Bool
    let reason: String
    let backend: String
    let processingLocation: String
    let firstResultMS: Double?
    let stopToFinalMS: Double?
}

final class HistoryStore {
    let defaults: UserDefaults
    let customDirectory: URL?
    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        self.customDirectory = directory
    }
    var enabled: Bool {
        get { defaults.object(forKey: "saveTranscripts") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "saveTranscripts") }
    }
    var directory: URL {
        customDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Roko Input/History", isDirectory: true)
    }
    func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
    func append(text: String, final: Bool, reason: String, firstMS: Double?, tailMS: Double?) throws {
        guard enabled else { return }
        try prepareDirectory()
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let file = directory.appendingPathComponent(formatter.string(from: now) + ".jsonl")
        let record = HistoryRecord(schemaVersion: 1, id: UUID(), timestamp: ISO8601DateFormatter().string(from: now), text: text, final: final, reason: reason, backend: "Apple Speech on-device / zh-CN", processingLocation: "on_device_required", firstResultMS: firstMS, stopToFinalMS: tailMS)
        var bytes = try JSONEncoder().encode(record)
        bytes.append(0x0a)
        if !FileManager.default.fileExists(atPath: file.path) {
            guard FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: bytes)
        try handle.synchronize()
    }
}
