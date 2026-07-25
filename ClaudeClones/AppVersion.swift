import Foundation

/// Single source of truth at runtime, read from the bundle that build.sh stamps
/// from the VERSION file. "dev" when running outside a bundle, as the CLI and the
/// tests do.
enum AppVersion {
    static var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev"
    }

    static var display: String { "v\(current)" }
}
