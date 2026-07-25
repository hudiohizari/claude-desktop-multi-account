import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: CloneListModel
    @FocusState private var focusedField: Int?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.rows.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.rows) { row in
                            CloneRow(row: row, model: model, focusedField: $focusedField)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 320)
            }

            Divider()
            footer
        }
        .frame(width: Theme.popoverWidth)
        .background(.regularMaterial)
        .animation(Theme.transition, value: model.rows.count)
        .overlay { if let clone = model.pendingDelete { deleteSheet(clone) } }
        .alert("Something went wrong",
               isPresented: Binding(get: { model.failure != nil },
                                    set: { if !$0 { model.failure = nil } })) {
            Button("OK", role: .cancel) { model.failure = nil }
        } message: {
            Text(model.failure ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("Claude Clones")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button(action: model.create) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            .help("New profile")
            .accessibilityLabel("New profile")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No profiles yet")
                .font(.system(size: 13, weight: .medium))
            Text("Each profile is a separate Claude app with its own login, chats and VM.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("New Profile", action: model.create)
                .controlSize(.small)
                .padding(.top, 2)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 6) {
            Toggle(isOn: Binding(get: { model.routesHere },
                                 set: { model.setRouting($0) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ask where links open")
                        .font(.system(size: 12))
                    Text(model.routesHere ? "claude:// links come here first"
                                          : "claude:// links go straight to Claude")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Theme.accent)

            HStack {
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .hoverHighlight()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - Delete confirmation

    private func deleteSheet(_ clone: Clone) -> some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("Delete \(clone.displayName)?")
                    .font(.system(size: 13, weight: .semibold))
                Text("Its profile holds the login, chats and Cowork VM - \(model.profileSize(clone)).")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 6) {
                    Button("Delete launcher and profile", role: .destructive) {
                        model.confirmDelete(alsoProfile: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    Button("Delete launcher only") { model.confirmDelete(alsoProfile: false) }
                    Button("Cancel") { model.pendingDelete = nil }
                        .keyboardShortcut(.cancelAction)
                }
                .controlSize(.small)
            }
            .padding(16)
            .frame(width: 268)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.thickMaterial)
                    .shadow(radius: 18, y: 6)
            )
        }
        .transition(.opacity)
    }
}

// MARK: - Row

private struct CloneRow: View {
    let row: CloneListModel.Row
    @ObservedObject var model: CloneListModel
    var focusedField: FocusState<Int?>.Binding

    @State private var draftName = ""

    private var isEditing: Bool { model.editing == row.clone.id }

    var body: some View {
        HStack(spacing: 10) {
            badge

            if isEditing {
                TextField("Name", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .focused(focusedField, equals: row.clone.id)
                    .onSubmit { model.rename(row.clone, to: draftName) }
                    .onExitCommand { model.editing = nil }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.clone.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(row.isRunning ? "Running" : "Stopped")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                statusDot
                actions
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Theme.rowHeight)
        .hoverHighlight()
        .contentShape(Rectangle())
        .onTapGesture { if !isEditing { model.open(row) } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.clone.displayName), \(row.isRunning ? "running" : "stopped")")
        .accessibilityHint("Opens this profile")
        .onChange(of: model.editing) { editing in
            if editing == row.clone.id {
                draftName = row.clone.name
                focusedField.wrappedValue = row.clone.id
            }
        }
    }

    private var badge: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Theme.accent.opacity(row.isRunning ? 1 : 0.35))
            .frame(width: 26, height: 26)
            .overlay(
                Text("\(row.clone.id)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            )
            .animation(Theme.transition, value: row.isRunning)
    }

    /// Colour is never the only signal - the row also spells out Running/Stopped.
    private var statusDot: some View {
        Circle()
            .fill(row.isRunning ? Theme.running : Color.secondary.opacity(0.35))
            .frame(width: 7, height: 7)
    }

    private var actions: some View {
        Menu {
            Button("Rename") {
                draftName = row.clone.name
                model.editing = row.clone.id
            }
            Button("Reveal Profile") { model.reveal(row.clone) }
            Divider()
            Button("Delete…", role: .destructive) { model.pendingDelete = row.clone }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 20)
        .accessibilityLabel("Actions for \(row.clone.displayName)")
    }
}
