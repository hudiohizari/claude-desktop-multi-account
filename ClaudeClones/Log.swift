import Foundation

/// Appends to ~/Library/Logs/ClaudeClones.log. NSLog only reaches stderr, which is
/// discarded when LaunchServices starts the app, and the unified log does not
/// surface it either, so link routing was undiagnosable without this.
enum Log {
    private static let file = NSHomeDirectory() + "/Library/Logs/ClaudeClones.log"
    private static let queue = DispatchQueue(label: "claudeclones.log")

    static func write(_ message: String) {
        queue.async {
            let stamp = ISO8601DateFormatter().string(from: Date())
            let line = "\(stamp) \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if let handle = FileHandle(forWritingAtPath: file) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: file))
                // Owner only: the log names profiles and link shapes.
                try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                      ofItemAtPath: file)
            }
        }
    }
}
