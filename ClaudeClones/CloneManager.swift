import Foundation

/// The operations the menu and the CLI both need. Owns the list; delegates
/// persistence to a `CloneStoring` and bundle work to a `CloneProvisioning`.
final class CloneManager {
    private let store: CloneStoring
    private let builder: CloneProvisioning

    init(store: CloneStoring, builder: CloneProvisioning) {
        self.store = store
        self.builder = builder
    }

    /// Clones whose wrapper still exists - a launcher deleted in Finder drops out.
    func clones() -> [Clone] {
        let live = store.load().filter { FileManager.default.fileExists(atPath: $0.appPath) }
        if live.count != store.load().count { store.save(live) }
        return live
    }

    @discardableResult
    func create(name: String) throws -> Clone {
        var all = clones()
        let id = (all.map(\.id).max() ?? 0) + 1
        let clone = Clone(id: id,
                          name: name,
                          profileDir: Paths.profile(id: id),
                          appPath: Paths.app(named: name))
        try builder.provision(clone)
        all.append(clone)
        store.save(all)
        return clone
    }

    func rename(_ clone: Clone, to newName: String) throws {
        var updated = clone
        let newPath = Paths.app(named: newName)
        if newPath != clone.appPath { try builder.move(clone, to: newPath) }
        updated.name = newName
        updated.appPath = newPath
        try builder.provision(updated)

        var all = clones()
        if let index = all.firstIndex(where: { $0.id == clone.id }) { all[index] = updated }
        store.save(all)
    }

    func delete(_ clone: Clone, includingProfile: Bool) {
        builder.remove(clone, includingProfile: includingProfile)
        store.save(clones().filter { $0.id != clone.id })
    }
}
