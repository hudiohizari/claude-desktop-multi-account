import Foundation

/// The same operations without the menu - for scripting, and the runnable check
/// that the wrapper plumbing works. Second consumer of `CloneManager`, which is
/// what makes the protocol seams pay for themselves.
struct CLI {
    let manager: CloneManager
    let locator: InstanceLocating

    func run(_ arguments: [String]) -> Int32 {
        switch arguments.first {
        case "--list":
            for clone in manager.clones() {
                let state = locator.runningPID(for: clone).map { "running pid \($0)" } ?? "stopped"
                print("\(clone.id)\t\(clone.displayName)\t\(state)\t\(clone.profileDir)")
            }
            return 0

        case "--create":
            guard let name = arguments.dropFirst().first else { return usage() }
            do {
                let clone = try manager.create(name: name)
                print("created \(clone.appPath)")
                return 0
            } catch {
                print("failed: \(error.localizedDescription)")
                return 1
            }

        case "--rename":
            let names = Array(arguments.dropFirst())
            guard names.count == 2,
                  let clone = manager.clones().first(where: { $0.name == names[0] })
            else { return usage() }
            do {
                try manager.rename(clone, to: names[1])
                print("renamed \(names[0]) to \(names[1])")
                return 0
            } catch {
                print("failed: \(error.localizedDescription)")
                return 1
            }

        case "--delete":
            guard let name = arguments.dropFirst().first,
                  let clone = manager.clones().first(where: { $0.name == name })
            else { return usage() }
            manager.delete(clone, includingProfile: arguments.contains("--with-profile"))
            print("deleted \(name)")
            return 0

        default:
            return usage()
        }
    }

    private func usage() -> Int32 {
        print("usage: ClaudeClones [--list | --create <name> | --rename <old> <new> "
              + "| --delete <name> [--with-profile]]")
        return 2
    }
}
