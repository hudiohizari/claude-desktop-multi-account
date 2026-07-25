import Foundation

/// Human-readable size of a profile directory, for the delete confirmation.
enum DiskSize {
    static func of(_ path: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sh", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        return output?.split(separator: "\t").first.map(String.init) ?? "unknown size"
    }
}
