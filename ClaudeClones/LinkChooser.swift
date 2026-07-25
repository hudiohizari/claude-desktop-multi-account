import SwiftUI

/// The window that opens when a claude:// link arrives and this app owns the scheme.
@MainActor
final class LinkChooser {
    private var window: NSWindow?

    struct Choice {
        let clone: Clone?   // nil = the default profile
    }

    func ask(link: String,
             clones: [Clone],
             running: Set<Int>,
             suggested: Clone?,
             completion: @escaping (Choice?) -> Void) {
        let view = LinkChooserView(link: link,
                                   clones: clones,
                                   running: running,
                                   selected: suggested?.id) { [weak self] choice in
            self?.close()
            completion(choice)
        }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 100),
                              styleMask: [.titled, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.level = .floating

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func close() {
        window?.orderOut(nil)
        window = nil
    }
}

struct LinkChooserView: View {
    let link: String
    let clones: [Clone]
    let running: Set<Int>
    @State var selected: Int?      // clone id, nil = default profile
    let done: (LinkChooser.Choice?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Open this link in")
                    .font(.system(size: 13, weight: .semibold))
                Text(link)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(spacing: 2) {
                    option(id: nil, badge: "C", title: "Claude",
                           subtitle: "Default profile", isRunning: true)
                    ForEach(clones, id: \.id) { clone in
                        option(id: clone.id,
                               badge: clone.badgeText,
                               title: clone.displayName,
                               subtitle: running.contains(clone.id) ? "Running" : "Will be launched",
                               isRunning: running.contains(clone.id))
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 240)

            Divider()

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { done(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Open") {
                    done(.init(clone: clones.first { $0.id == selected }))
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 360)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func option(id: Int?, badge: String, title: String,
                        subtitle: String, isRunning: Bool) -> some View {
        let isSelected = selected == id
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(id == nil ? Color.secondary.opacity(0.35)
                                : Theme.accent.opacity(isRunning ? 1 : 0.35))
                .frame(width: 24, height: 24)
                .overlay(
                    Text(badge)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .opacity(isSelected ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(isSelected ? Theme.accent.opacity(0.14) : .clear)
        )
        .hoverHighlight()
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(Theme.transition) { selected = id } }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(title), \(subtitle)")
    }
}
