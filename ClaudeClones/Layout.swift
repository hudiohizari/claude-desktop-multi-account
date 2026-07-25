import Foundation

/// Where clones and profiles live. Injected rather than read from `Paths` directly
/// so tests can point everything at a temp directory instead of the real home.
struct Layout {
    var applications: String
    var instancesRoot: String

    static let standard = Layout(applications: Paths.applications,
                                 instancesRoot: Paths.instancesRoot)

    func app(named name: String) -> String { applications + "/Claude \(name).app" }
    func profile(id: Int) -> String { instancesRoot + "/clone-\(id)" }

    /// Profile directory numbers that already exist on disk, whether or not the
    /// store still knows about them.
    func profileIDsOnDisk() -> [Int] {
        (try? FileManager.default.contentsOfDirectory(atPath: instancesRoot))?
            .compactMap { name in
                name.hasPrefix("clone-") ? Int(name.dropFirst("clone-".count)) : nil
            } ?? []
    }
}
