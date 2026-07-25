import AppKit

/// Finds the running Claude process behind a clone. Kept out of `Clone` so the
/// model stays a value with no view of the system.
protocol InstanceLocating {
    func runningPID(for clone: Clone) -> pid_t?
    /// The stock instance on the default profile: a Claude process that is none of ours.
    func defaultProfilePID(excluding clones: [Clone]) -> pid_t?
}

struct PidFileInstanceLocator: InstanceLocating {
    func runningPID(for clone: Clone) -> pid_t? {
        guard let text = try? String(contentsOfFile: clone.pidFile, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let app = NSRunningApplication(processIdentifier: pid),
              app.executableURL?.path == Paths.claudeBinary
        else { return nil }
        return pid
    }

    func defaultProfilePID(excluding clones: [Clone]) -> pid_t? {
        let ours = Set(clones.compactMap(runningPID))
        return NSWorkspace.shared.runningApplications
            .first { $0.executableURL?.path == Paths.claudeBinary
                     && !ours.contains($0.processIdentifier) }?
            .processIdentifier
    }
}
