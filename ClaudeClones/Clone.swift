import Foundation

/// One Claude profile: identity and the paths derived from it. No behaviour.
struct Clone: Codable, Equatable {
    var id: Int
    var name: String
    var profileDir: String
    var appPath: String

    var displayName: String { "Claude \(name)" }
    var bundleID: String { "com.local.claude.clone\(id)" }

    /// What the row and launcher icon show. The initial carries meaning; the id is
    /// a directory number that skips whenever a profile is left on disk.
    var badgeText: String {
        name.trimmingCharacters(in: .whitespaces).first
            .map { String($0).uppercased() } ?? "\(id)"
    }

    /// The wrapper writes its own pid here before exec'ing Claude, and exec keeps
    /// the pid, so this file identifies the Claude process itself.
    var pidFile: String { profileDir + "/.instance.pid" }
}

enum Paths {
    static let claudeApp = "/Applications/Claude.app"
    static let claudeBinary = claudeApp + "/Contents/MacOS/Claude"
    static let instancesRoot = NSHomeDirectory() + "/.claude-instances"
    static let applications = NSHomeDirectory() + "/Applications"
    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Versions/A/"
        + "Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

    static func app(named name: String) -> String { applications + "/Claude \(name).app" }
    static func profile(id: Int) -> String { instancesRoot + "/clone-\(id)" }
}
