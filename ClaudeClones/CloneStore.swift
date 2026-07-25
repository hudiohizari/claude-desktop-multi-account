import Foundation

/// Persistence of the clone list.
protocol CloneStoring {
    func load() -> [Clone]
    func save(_ clones: [Clone])
}

struct JSONCloneStore: CloneStoring {
    let file: String

    init(file: String = Paths.instancesRoot + "/clones.json") {
        self.file = file
    }

    func load() -> [Clone] {
        guard let data = FileManager.default.contents(atPath: file),
              let clones = try? JSONDecoder().decode([Clone].self, from: data)
        else { return [] }
        return clones
    }

    func save(_ clones: [Clone]) {
        try? FileManager.default.createDirectory(atPath: (file as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(clones).write(to: URL(fileURLWithPath: file))
    }
}
