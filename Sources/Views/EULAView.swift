import SwiftUI

// MARK: - First-Launch EULA Gate
//
// Presented as a full-screen overlay above ContentView the first time the
// app is opened. Acceptance is persisted via @AppStorage under
// "remu.eula.accepted.v1" — bumping the version suffix forces existing users
// to re-accept if the terms are ever revised in a meaningful way.
//
// Why this matters: Apple's Guideline 4.7 permits emulator apps but holds
// the publisher responsible for the software offered. Surfacing a clear
// acceptance gate up front is the standard defensive pattern (Delta,
// Provenance, RetroArch ports all do this in some form) and shifts liability
// for imported content onto the user.

struct EULAView: View {
    /// First-launch presents the toggle + Continue gate; review hides
    /// the toggle and shows a Close button so users can re-read the
    /// terms from Settings without being asked to agree again.
    enum DisplayMode {
        case firstLaunch
        case review
    }

    let displayMode: DisplayMode
    let onDismiss: () -> Void

    @State private var hasAgreed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Divider().background(Color.white.opacity(0.08))

                ScrollView {
                    termsContent
                        .padding(.horizontal, 28)
                        .padding(.vertical, 18)
                        .frame(maxWidth: 720, alignment: .leading)
                        .frame(maxWidth: .infinity)
                }

                Divider().background(Color.white.opacity(0.08))

                footer
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 28))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(displayMode == .firstLaunch ? "Welcome to REmu" : "Terms of Use"))
                    .font(.title3).bold()
                    .foregroundColor(.white)
                Text(LocalizedStringKey(displayMode == .firstLaunch
                     ? "Please review and accept the terms before continuing."
                     : "Below are the terms you accepted when first launching REmu."))
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: Terms

    private var termsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            section(
                icon: "books.vertical",
                title: "1. No Bundled Games or BIOS",
                body: "REmu does not provide, distribute, or include any commercial game ROMs, BIOS files, or other copyrighted content. The only software bundled with this application is the original Glowchase demo and the emulation framework itself."
            )

            section(
                icon: "person.fill.checkmark",
                title: "2. Your Responsibility",
                body: "You are solely responsible for the legality of any file you import into this application. By importing a ROM or BIOS, you confirm that (a) you legally own the original game cartridge, disc, or console, and you produced the file by dumping hardware you own, OR (b) the file is free homebrew, public domain, or otherwise covered by a license that permits your use."
            )

            section(
                icon: "xmark.shield",
                title: "3. No ROM Sharing",
                body: "REmu does not include, link to, or facilitate access to any ROM download service. Downloading or distributing ROMs of games you do not own is illegal in most jurisdictions and constitutes a violation of these terms and your local copyright law."
            )

            section(
                icon: "lock.shield",
                title: "4. Privacy",
                body: "REmu stores all save states and imported files locally on your device. No game data, save states, or imported ROMs are uploaded to any server, and the developer has no access to them."
            )

            section(
                icon: "exclamationmark.triangle",
                title: "5. No Warranty",
                body: "REmu is provided \"as-is\" without warranty of any kind, express or implied. The developer is not liable for any damages, data loss, or legal consequences arising from your use of this software or any content you choose to load into it."
            )

            section(
                icon: "rosette",
                title: "6. Trademarks & Affiliation",
                body: "REmu is an independent project and is not affiliated with, endorsed by, or sponsored by Nintendo Co., Ltd., Sony Interactive Entertainment Inc., Microsoft Corporation, or any other console manufacturer. All trademarks, product names, console designs, and logos are the property of their respective owners. References to console identifiers within the application are made for technical interoperability only."
            )
        }
    }

    private func section(icon: String, title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.orange)
                .frame(width: 22)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline).bold()
                    .foregroundColor(.white)
                Text(body)
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        switch displayMode {
        case .firstLaunch: firstLaunchFooter
        case .review:      reviewFooter
        }
    }

    private var firstLaunchFooter: some View {
        HStack(spacing: 16) {
            Toggle(isOn: $hasAgreed) {
                Text("I have read and agree to the terms above")
                    .font(.footnote)
                    .foregroundColor(.white)
            }
            .toggleStyle(SwitchToggleStyle(tint: .orange))
            .fixedSize()

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Text("Continue")
                    .font(.headline)
                    .foregroundColor(hasAgreed ? .black : .white.opacity(0.4))
                    .padding(.horizontal, 26)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(hasAgreed ? Color.orange : Color.white.opacity(0.10))
                    )
            }
            .disabled(!hasAgreed)
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.15), value: hasAgreed)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private var reviewFooter: some View {
        HStack {
            Spacer()

            Button(action: onDismiss) {
                Text("Close")
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.orange))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}
