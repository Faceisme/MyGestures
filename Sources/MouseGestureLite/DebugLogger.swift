import Foundation

enum DebugLogger {
    private static let queue = DispatchQueue(label: "com.face.mygestures.debuglog")
    private static let maxLogSize = 2_000_000

    static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MyGestures/debug.log")
    }

    static func write(_ message: String) {
        queue.async {
            let url = logURL
            let directory = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            rotateIfNeeded(at: url)

            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(timestamp)] \(message)\n"
            guard let data = line.data(using: .utf8) else {
                return
            }

            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }

            do {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } catch {
                // Logging must never affect gesture handling.
            }
        }
    }

    private static func rotateIfNeeded(at url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > maxLogSize else {
            return
        }

        let rotatedURL = url.deletingLastPathComponent().appendingPathComponent("debug.old.log")
        try? FileManager.default.removeItem(at: rotatedURL)
        try? FileManager.default.moveItem(at: url, to: rotatedURL)
    }
}
