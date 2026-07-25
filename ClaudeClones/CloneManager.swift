import Foundation

/// The operations the popover and the CLI both need. Owns the list; delegates
/// persistence to a `CloneStoring` and bundle work to a `CloneProvisioning`.
final class CloneManager {
    private let store: CloneStoring
    private let builder: CloneProvisioning
    private let layout: Layout

    init(store: CloneStoring, builder: CloneProvisioning, layout: Layout = .standard) {
        self.store = store
        self.builder = builder
        self.layout = layout
    }

    /// Clones whose wrapper still exists, so a launcher deleted in Finder drops out.
    func clones() -> [Clone] {
        let stored = store.load()
        let live = stored.filter { FileManager.default.fileExists(atPath: $0.appPath) }
        if live.count != stored.count { store.save(live) }
        return live
    }

    @discardableResult
    func create(name: String) throws -> Clone {
        var all = clones()
        let id = nextID(after: all)
        let clone = Clone(id: id,
                          name: name,
                          profileDir: layout.profile(id: id),
                          appPath: layout.app(named: name))
        try builder.provision(clone)
        all.append(clone)
        store.save(all)
        return clone
    }

    func rename(_ clone: Clone, to newName: String) throws {
        var updated = clone
        let newPath = layout.app(named: newName)
        if newPath != clone.appPath { try builder.move(clone, to: newPath) }
        updated.name = newName
        updated.appPath = newPath
        try builder.provision(updated)

        // Write through the raw list, never `clones()`: its pruning would drop this
        // entry, whose old bundle path stopped existing the moment we moved it.
        var all = store.load()
        if let index = all.firstIndex(where: { $0.id == clone.id }) {
            all[index] = updated
        } else {
            all.append(updated)
        }
        store.save(all)
    }

    func delete(_ clone: Clone, includingProfile: Bool) {
        builder.remove(clone, includingProfile: includingProfile)
        store.save(store.load().filter { $0.id != clone.id })
    }

    /// Highest id in the store *or* on disk, plus one. Profile directories outlive
    /// their store entry whenever one is lost or pruned, and handing the same id out
    /// twice would point a new clone at someone else's data.
    private func nextID(after known: [Clone]) -> Int {
        (known.map(\.id) + layout.profileIDsOnDisk()).max().map { $0 + 1 } ?? 1
    }
}
