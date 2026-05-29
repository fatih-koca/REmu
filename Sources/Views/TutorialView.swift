import SwiftUI

struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey)] = [
        (
            "doc.badge.plus",
            "Obtain ROMs Legally",
            "Dump your own physical cartridges or discs using a dedicated dumper device. You must own the original media. Do not download ROMs from the internet — sharing or distributing copyrighted game files is illegal."
        ),
        (
            "gift",
            "Free Legal Alternatives",
            "If you don't have a dumper, many systems have free homebrew and public-domain games you can use legally — for example, GB Studio releases on itch.io, NES homebrew (Nebs 'n Debs, Witch n Wiz), or Genesis SGDK demos. Always read the license before importing a file."
        ),
        (
            "folder.badge.plus",
            "Import Your ROM",
            "Tap the + button on the Library screen. Select your ROM file from the Files app. Supported formats: .nes (NES), .smc/.sfc (SNES), .gb/.gbc/.gba (Game Boy family), .md/.gen/.smd (Genesis), .sms (Master System), .gg (Game Gear), .bin/.cue (PS1)."
        ),
        (
            "folder.fill",
            "Place BIOS Files",
            "Some systems require a BIOS dump from your own console. Place BIOS files in the /System folder inside the app's Documents directory (Files → REmu → System). You must dump the BIOS yourself from hardware you own."
        ),
        (
            "gamecontroller.fill",
            "Launch & Play",
            "Tap any ROM card to start. Use the on-screen controller, or connect a MFi/Bluetooth gamepad. Use the menu (⋮) to save/load states or return to the library."
        ),
        (
            "bookmark.fill",
            "Save States",
            "Tap the Save button during gameplay to create a snapshot. Load it anytime via Quick Load. States are stored locally in /SaveStates and are never uploaded anywhere."
        ),
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        disclaimerBanner

                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            StepRow(number: index + 1, icon: step.icon, title: step.title, detail: step.detail)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("How to Use")
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

    private var disclaimerBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundColor(.orange)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Legal Notice")
                    .font(.headline)
                    .foregroundColor(.orange)
                Text("REmu is an emulation platform. It does not include any game software or BIOS files. You are solely responsible for ensuring you have the legal right to use any files you load into this app.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3)))
        )
    }
}

private struct StepRow: View {
    let number: Int
    let icon: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
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
                        .font(.caption)
                        .foregroundColor(.blue)
                        .fontWeight(.semibold)
                    Text("·")
                        .foregroundColor(.gray)
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
