import SwiftUI

// MARK: - PS1 BIOS Setup Guide
//
// Reached from Settings → "PS1 BIOS Setup". PlayStation cores need a BIOS
// the user must supply themselves (REmu ships none — it's copyrighted). This
// screen walks them through dumping it and dropping it into the app's
// Files-visible System folder, which CoreBridge points the core at.

struct BIOSGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey)] = [
        (
            "externaldrive",
            "Dump your own BIOS",
            "You must legally own a PlayStation console and dump its BIOS yourself. The file is commonly named scph5501.bin (US), scph5500.bin (Japan) or scph5502.bin (Europe). Do not download BIOS files from the internet."
        ),
        (
            "folder",
            "Open Files → REmu → System",
            "In the Files app, go to On My iPhone → REmu → System. REmu creates this folder for you automatically."
        ),
        (
            "doc.badge.plus",
            "Copy the BIOS file in",
            "Place the .bin BIOS file into that System folder. You can keep more than one regional BIOS there at the same time."
        ),
        (
            "gamecontroller.fill",
            "Import a game and play",
            "Add a PlayStation disc (.bin/.cue, .pbp or .chd) from the library, then tap it to launch. PS1 is experimental — speed varies by game and device."
        ),
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        banner

                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            stepRow(number: index + 1, icon: step.icon,
                                    title: step.title, detail: step.detail)
                        }

                        Spacer(minLength: 30)
                    }
                    .padding(20)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("PS1 BIOS Setup")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.blue)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var banner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.orange)
                .font(.title2)
            Text("PlayStation games need a BIOS file dumped from your own console. REmu does not include one. Other systems (NES, SNES, Game Boy, Genesis, etc.) do not need a BIOS.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3)))
        )
    }

    private func stepRow(
        number: Int,
        icon: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .font(.body)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Step \(number)")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.blue)
                    Text("·").foregroundColor(.gray)
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)
                }
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
