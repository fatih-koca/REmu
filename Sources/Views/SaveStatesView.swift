import SwiftUI

// MARK: - Save States Picker / Manager
//
// Presented as a sheet from the in-game menu (the "Load State" action).
// Lists every save the player has made for the current ROM — newest first —
// so they can keep multiple save points per game instead of a single slot.
// Tap a row to load it, tap the trash icon to delete it, or tap + to capture
// a fresh save of the current moment. The emulator is paused (by the parent)
// while this sheet is up, so loading restores cleanly on resume.

struct SaveStatesView: View {
    @Environment(\.dismiss) private var dismiss

    let romID: UUID
    /// Toast hook back to the emulator screen.
    let onMessage: (String) -> Void

    @State private var states: [SaveState] = []

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                if states.isEmpty {
                    emptyState
                } else {
                    listView
                }
            }
            .navigationTitle("Save States")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: saveNew) {
                        Label("New Save", systemImage: "plus.circle.fill")
                    }
                    .foregroundColor(.green)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.blue)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: refresh)
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 52))
                .foregroundColor(.gray.opacity(0.5))
            Text("No save states yet")
                .font(.title3)
                .foregroundColor(.gray)
            Text("Tap + to save your current progress. You can keep as many save points as you like.")
                .font(.subheadline)
                .foregroundColor(.gray.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
        }
    }

    // MARK: List

    private var listView: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(Array(states.enumerated()), id: \.element.fileName) { index, state in
                    row(for: state, number: states.count - index)
                }
            }
            .padding(20)
        }
    }

    private func row(for state: SaveState, number: Int) -> some View {
        HStack(spacing: 12) {
            Button { load(state) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "bookmark.fill")
                        .foregroundColor(.green)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Save \(number)")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.white)
                        Text(Self.dateFormatter.string(from: state.timestamp))
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(.blue)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { delete(state) } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red.opacity(0.85))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: Actions

    private func refresh() {
        states = ((try? SaveStateManager.shared.listStates(for: romID)) ?? [])
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func saveNew() {
        guard let data = CoreBridgeWrapper.shared.serializeState() else {
            onMessage(String(localized: "Save failed"))
            return
        }
        do {
            _ = try SaveStateManager.shared.saveState(romID: romID, stateData: data)
            onMessage(String(localized: "State saved"))
            refresh()
        } catch {
            onMessage(String(localized: "Save failed"))
        }
    }

    private func load(_ state: SaveState) {
        do {
            let data = try SaveStateManager.shared.loadState(state)
            CoreBridgeWrapper.shared.deserializeState(data)
            onMessage(String(localized: "State loaded"))
            dismiss()
        } catch {
            onMessage(String(localized: "Load error"))
        }
    }

    private func delete(_ state: SaveState) {
        try? SaveStateManager.shared.deleteState(state)
        refresh()
    }
}
