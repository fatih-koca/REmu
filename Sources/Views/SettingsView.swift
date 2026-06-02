import SwiftUI

// MARK: - Settings
//
// Reachable from the gear icon on the library screen. Hosts the legal
// documents (Terms / Privacy) and small "About" details. Apple App Review
// reviewers expect both Terms and Privacy to be reachable from inside the
// app — surfacing them here keeps the EULA from being a one-shot wall and
// lets us point Apple at a stable in-app location.

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var showingTerms = false
    @State private var showingPrivacy = false
    @State private var showBIOSGuide = false

    /// Default OFF on a fresh install. The lookup hits a public GitHub
    /// repo (libretro-thumbnails) and fetches a public-domain image keyed
    /// on the ROM filename; nothing about the user is transmitted, but
    /// the most defensive App Store posture is to make it opt-in.
    @AppStorage("remu.library.autoDownloadCovers")
    private var autoDownloadCovers: Bool = false

    // On-screen control customization. Read by the emulator screen
    // (EmulatorScreenView) to scale, shift and fade the touch controls.
    @AppStorage("remu.controls.scale")   private var controlScale: Double = 1.0
    @AppStorage("remu.controls.voffset") private var controlVOffset: Double = 0
    @AppStorage("remu.controls.opacity") private var controlOpacity: Double = 1.0

    // Screen rendering options, read by the Metal renderer.
    @AppStorage("remu.screen.aspect") private var screenAspect: Int = 0
    @AppStorage("remu.screen.smooth") private var screenSmooth: Bool = true

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        librarySection
                        controlsSection
                        screenSection
                        emulationSection
                        legalSection
                        aboutSection
                        Spacer(minLength: 20)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.blue)
                }
            }
            .fullScreenCover(isPresented: $showingTerms) {
                EULAView(displayMode: .review) {
                    showingTerms = false
                }
            }
            .sheet(isPresented: $showingPrivacy) {
                PrivacyPolicyView()
            }
            .sheet(isPresented: $showBIOSGuide) {
                BIOSGuideView()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Sections

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "photo.on.rectangle", label: "LIBRARY", tint: .blue)

            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    iconCell(systemName: "icloud.and.arrow.down", tint: .blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-download cover art")
                            .font(.subheadline)
                            .foregroundColor(.white)
                        Text("Fetches public box art from GitHub when a ROM has no embedded cover. Off by default.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $autoDownloadCovers)
                        .labelsHidden()
                        .tint(.orange)
                }
                .padding(14)
            }
            .background(rowGroupBackground)
        }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "gamecontroller", label: "CONTROLS", tint: .green)

            VStack(spacing: 16) {
                sliderRow(title: "Button Size", value: $controlScale, range: 0.7...1.3)
                Divider().background(Color.white.opacity(0.08))
                sliderRow(title: "Vertical Position", value: $controlVOffset, range: -60...60)
                Divider().background(Color.white.opacity(0.08))
                sliderRow(title: "Opacity", value: $controlOpacity, range: 0.3...1.0)
                Divider().background(Color.white.opacity(0.08))
                Button(action: resetControls) {
                    Text("Reset to Default")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(rowGroupBackground)
        }
    }

    private func sliderRow(
        title: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.white)
            Slider(value: value, in: range)
                .tint(.green)
        }
    }

    private func resetControls() {
        controlScale = 1.0
        controlVOffset = 0
        controlOpacity = 1.0
    }

    private var screenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "rectangle.on.rectangle", label: "SCREEN", tint: .purple)

            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Aspect Ratio")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Picker("Aspect Ratio", selection: $screenAspect) {
                        Text("Fit").tag(0)
                        Text("Fill").tag(1)
                        Text("Integer").tag(2)
                    }
                    .pickerStyle(.segmented)
                }

                Divider().background(Color.white.opacity(0.08))

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smooth Pixels")
                            .font(.subheadline)
                            .foregroundColor(.white)
                        Text("Turn off for a sharp, pixel-perfect retro look.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $screenSmooth)
                        .labelsHidden()
                        .tint(.purple)
                }
            }
            .padding(14)
            .background(rowGroupBackground)
        }
    }

    private var emulationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "cpu", label: "EMULATION", tint: .purple)

            VStack(spacing: 0) {
                settingRow(
                    icon: "memorychip",
                    title: "PS1 BIOS Setup",
                    subtitle: "How to add a PlayStation BIOS"
                ) { showBIOSGuide = true }
            }
            .background(rowGroupBackground)
        }
    }

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "doc.text", label: "LEGAL", tint: .orange)

            VStack(spacing: 0) {
                settingRow(
                    icon: "doc.text",
                    title: "Terms of Use",
                    subtitle: "Review the agreement you accepted"
                ) { showingTerms = true }

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.leading, 56)

                settingRow(
                    icon: "lock.shield",
                    title: "Privacy Policy",
                    subtitle: "What data REmu does and doesn't collect"
                ) { showingPrivacy = true }
            }
            .background(rowGroupBackground)
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "info.circle", label: "ABOUT", tint: .blue)

            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    iconCell(systemName: "app.badge", tint: .blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Version")
                            .font(.subheadline)
                            .foregroundColor(.white)
                        Text(appVersion)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                }
                .padding(14)
            }
            .background(rowGroupBackground)
        }
    }

    // MARK: Row helpers

    private func sectionHeader(icon: String, label: LocalizedStringKey, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(tint)
            Text(label)
                .font(.caption).bold()
                .foregroundColor(tint)
                .tracking(0.5)
        }
        .padding(.leading, 4)
    }

    private func settingRow(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                iconCell(systemName: icon, tint: .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.gray.opacity(0.6))
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func iconCell(systemName: String, tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.opacity(0.18))
                .frame(width: 32, height: 32)
            Image(systemName: systemName)
                .font(.body)
                .foregroundColor(tint)
        }
    }

    private var rowGroupBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

// MARK: - Privacy Policy
//
// Plain-text in-app version of the policy. Mirror the same wording at a
// public URL (GitHub Pages, your domain, etc.) and paste that URL into
// App Store Connect's "Privacy Policy URL" field at submission time —
// Apple requires both an in-app surface and a publicly reachable copy.

private struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    /// Public mirror of this policy. Submit the same URL to App Store Connect
    /// in the "Privacy Policy URL" field at app submission.
    private let publicURL = URL(string: "https://fatih-koca.github.io/REmu/privacy.html")!

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text("Last updated: April 26, 2026")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Spacer()
                            Link(destination: publicURL) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.right.square")
                                    Text("View Online")
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                        }

                        intro

                        section(
                            title: "No Personal Data Collected",
                            body: "REmu does not collect, store, or transmit any personally identifiable information. We do not require an account, and we do not log your activity."
                        )

                        section(
                            title: "Local-Only Storage",
                            body: "All ROM files, save states, and screenshots remain on your device, inside the app's protected sandbox. They are never uploaded to any server, shared with us, or made available to third parties."
                        )

                        section(
                            title: "No Analytics or Tracking",
                            body: "This version of REmu does not include any analytics SDK, tracking pixel, or third-party telemetry. Crash reports, if shared, are handled by Apple's standard system tooling and require your explicit opt-in via iOS Settings."
                        )

                        section(
                            title: "Advertising",
                            body: "The current version of REmu does not display advertisements. If a future release introduces ad-supported features, this policy will be updated and consent will be requested where required (e.g., via App Tracking Transparency)."
                        )

                        section(
                            title: "External Links",
                            body: "The app's tutorial may reference public websites such as itch.io for legal homebrew games. Following an external link takes you to the third party's own privacy environment, which is governed by their policies, not this one."
                        )

                        section(
                            title: "Children's Privacy",
                            body: "REmu is not directed at children under 13 and does not knowingly collect data from anyone. If you believe a child has provided personal data through this app, please contact us so we can confirm there is nothing on our end to remove."
                        )

                        section(
                            title: "Contact",
                            body: "For privacy questions, please contact: fatihkcf@gmail.com"
                        )

                        section(
                            title: "Changes",
                            body: "We may revise this policy. The \"Last updated\" date above reflects the most recent revision."
                        )

                        Spacer(minLength: 20)
                    }
                    .padding(20)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Privacy Policy")
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

    private var intro: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .foregroundColor(.green)
                .font(.title2)
            Text("REmu is built to respect your privacy. This document describes what data the app handles and what it does not.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.25)))
        )
    }

    private func section(title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            Text(body)
                .font(.subheadline)
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
