import SwiftUI
import UniformTypeIdentifiers

// MARK: - Root Navigation

struct ContentView: View {
    @StateObject private var library = ROMLibrary.shared
    @State private var selectedROM: ROMEntry?
    @State private var showDocumentPicker = false
    @State private var showTutorial = false
    @State private var showSettings = false
    @State private var showingGame = false
    @State private var showingCoilpede = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if showingCoilpede {
                CoilpedeView { showingCoilpede = false }
                    .transition(.opacity)
            } else if showingGame, let rom = selectedROM {
                EmulatorScreenView(rom: rom) {
                    showingGame = false
                    selectedROM = nil
                }
                .transition(.opacity)
            } else {
                libraryView
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showingGame)
        .animation(.easeInOut(duration: 0.25), value: showingCoilpede)
        .sheet(isPresented: $showDocumentPicker) {
            ROMDocumentPicker { urls in
                urls.forEach { _ = library.importROM(from: $0) }
            }
        }
        .sheet(isPresented: $showTutorial) {
            TutorialView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .remuShouldLaunchROM)
        ) { note in
            // Posted by REmuApp's .onOpenURL after a successful import.
            guard let rom = note.object as? ROMEntry else { return }
            selectedROM = rom
            showingCoilpede = false
            showingGame = true
        }
    }

    // MARK: Library

    private var libraryView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("REmu")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Spacer()

                Button { showTutorial = true } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.gray)
                        .font(.title2)
                }

                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .foregroundColor(.gray)
                        .font(.title2)
                }

                Button { showDocumentPicker = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            ScrollView {
                builtInDemosSection
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                if library.roms.isEmpty {
                    emptyStateView
                        .padding(.top, 40)
                } else {
                    romGridContents
                }
            }
        }
    }

    // MARK: Built-in demos

    private var builtInDemosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundColor(.orange)
                    .font(.caption)
                Text("Built-in Demo")
                    .font(.caption).bold()
                    .foregroundColor(.orange)
            }

            Button {
                showingCoilpede = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [Color.green.opacity(0.45), Color.orange.opacity(0.35)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 62, height: 62)
                        Text("🪱")
                            .font(.system(size: 32))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Glowchase")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("Grow the chain, chase the glow")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("No ROM needed · 100% original")
                            .font(.caption2)
                            .foregroundColor(.orange.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundColor(.orange)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.3), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var romGridContents: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "gamecontroller.fill")
                    .foregroundColor(.blue)
                    .font(.caption)
                Text("Your Library")
                    .font(.caption).bold()
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)],
                spacing: 16
            ) {
                ForEach(library.roms) { rom in
                    ROMCard(rom: rom) {
                        selectedROM = rom
                        showingGame = true
                    } onDelete: {
                        library.remove(rom)
                    }
                }
            }
            .padding(20)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "gamecontroller")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            Text("No ROMs imported")
                .font(.title3)
                .foregroundColor(.gray)
            Text("Tap + to import your ROM files")
                .font(.subheadline)
                .foregroundColor(.gray.opacity(0.7))
            Spacer()
        }
    }

    // ROM import logic now lives on ROMLibrary so it can be shared
    // between the document picker and the onOpenURL handler in REmuApp.
}

// MARK: - ROM Card

struct ROMCard: View {
    let rom: ROMEntry
    let onLaunch: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onLaunch) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.05))
                        .frame(height: 100)
                    Image(systemName: rom.console.systemIcon)
                        .font(.system(size: 36))
                        .foregroundColor(.blue.opacity(0.7))
                }

                Text(rom.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(2)

                HStack {
                    Text(rom.console.displayName)
                        .font(.caption2)
                        .foregroundColor(.gray)

                    Spacer()

                    if rom.hasSaveState {
                        Image(systemName: "bookmark.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { onDelete() } label: {
                Label("Remove", systemImage: "trash")
            }
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

