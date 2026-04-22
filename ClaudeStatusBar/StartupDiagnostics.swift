import Foundation
import os

enum StartupDiagnostics {
    private static let logger = Logger(subsystem: "com.claude.statusbar", category: "startup")
    private static let maxFileSize: UInt64 = 64 * 1024

    static func log(_ message: String) {
        logger.log("\(message, privacy: .public)")
        appendToFile(message)
    }

    private static func appendToFile(_ message: String) {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let statusDir = home.appendingPathComponent(".claude-status")
        let logFile = statusDir.appendingPathComponent("startup.log")
        let line = "\(isoTimestamp()) \(message)\n"

        try? fm.createDirectory(at: statusDir, withIntermediateDirectories: true)

        if let attrs = try? fm.attributesOfItem(atPath: logFile.path),
           let size = attrs[.size] as? NSNumber,
           size.uint64Value > maxFileSize {
            try? fm.removeItem(at: logFile)
        }

        if !fm.fileExists(atPath: logFile.path) {
            try? line.write(to: logFile, atomically: true, encoding: .utf8)
            return
        }

        if let handle = try? FileHandle(forWritingTo: logFile),
           let data = line.data(using: .utf8) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    private static func isoTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: Date())
    }
}
