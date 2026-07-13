import SwiftUI
import UniformTypeIdentifiers

// MARK: - Root Navigation

// Which full-screen layout editor to present after the Settings sheet closes.
private enum LayoutEditor: String, Identifiable {
    case controls, screen
    var id: String { rawValue }
}

// Built-in demo games (ids match XMBHomeView's demo HomeGame ids).
private enum ActiveDemo: String, Identifiable {
    case glowchase, glowbreak, lumo
    var id: String { rawValue }
}

struct ContentView: View {
    @StateObject private var library = ROMLibrary.shared
    @State private var selectedROM: ROMEntry?
    @State private var showDocumentPicker = false
    @State private var showTutorial = false
    @State private var showSettings = false
    @State private var showingGame = false
    @State private var activeDemo: ActiveDemo?
    // Layout editors: SettingsView requests one, the sheet dismisses, then the
    // requested editor is presented full-screen via `.fullScreenCover` below.
    @State private var pendingEditor: LayoutEditor?
    @State private var activeEditor: LayoutEditor?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let demo = activeDemo {
                Group {
                    switch demo {
                    case .glowchase: CoilpedeView { activeDemo = nil }
                    case .glowbreak: GlowbreakView { activeDemo = nil }
                    case .lumo:      LumoView { activeDemo = nil }
                    }
                }
                .transition(.opacity)
            } else if showingGame, let rom = selectedROM {
                EmulatorScreenView(rom: rom) {
                    showingGame = false
                    selectedROM = nil
                    // Natural break point: back at the library, session over.
                    AdManager.shared.showInterstitialIfEligible()
                }
                .transition(.opacity)
            } else {
                XMBHomeView(
                    library: library,
                    onPlayROM:      { rom in
                        library.markPlayed(rom)
                        selectedROM = rom; showingGame = true
                    },
                    onPlayDemo:     { id in activeDemo = ActiveDemo(rawValue: id) ?? .glowchase },
                    onOpenTutorial: { showTutorial = true },
                    onOpenSettings: { showSettings = true },
                    onImport:       { showDocumentPicker = true }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showingGame)
        .animation(.easeInOut(duration: 0.25), value: activeDemo)
        .sheet(isPresented: $showDocumentPicker) {
            ROMDocumentPicker { urls in
                urls.forEach { _ = library.importROM(from: $0) }
            }
        }
        .sheet(isPresented: $showTutorial) {
            TutorialView()
        }
        .sheet(isPresented: $showSettings, onDismiss: {
            if let pending = pendingEditor {
                pendingEditor = nil
                activeEditor = pending
            }
        }) {
            SettingsView(
                onEditScreen:   { pendingEditor = .screen;   showSettings = false },
                onEditControls: { pendingEditor = .controls; showSettings = false }
            )
        }
        .fullScreenCover(item: $activeEditor) { editor in
            switch editor {
            case .controls:
                ControlLayoutEditorView { activeEditor = nil }
            case .screen:
                ScreenLayoutEditorView { activeEditor = nil }
            }
        }
        .onAppear { library.backfillMissingCovers() }
        .onReceive(
            NotificationCenter.default.publisher(for: .remuShouldLaunchROM)
        ) { note in
            // Posted by REmuApp's .onOpenURL after a successful import.
            guard let rom = note.object as? ROMEntry else { return }
            library.markPlayed(rom)
            selectedROM = rom
            activeDemo = nil
            showingGame = true
        }
    }
}

// MARK: - Document Picker

struct ROMDocumentPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.data, .item]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}
