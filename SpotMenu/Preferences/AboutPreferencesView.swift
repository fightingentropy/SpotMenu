import SwiftUI

struct AboutPreferencesView: View {
    private let updater = UpdaterManager.shared

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    @State private var automaticallyChecksForUpdates = false
    @State private var automaticallyDownloadsUpdates = false
    @State private var lastUpdateCheckDate: Date?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // App Icon and Name
                VStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 128, height: 128)
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

                    Text("SpotMenu")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Version \(appVersion) (\(buildNumber))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                Divider()
                    .padding(.horizontal, 40)

                // Description
                VStack(spacing: 8) {
                    Text("Music Folder & Apple Music in your menu bar")
                        .font(.headline)

                    Text("Built with SwiftUI for macOS")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if updater.isConfigured {
                    Divider()
                        .padding(.horizontal, 40)

                    VStack(spacing: 12) {
                        Text("Software Updates")
                            .font(.headline)

                        Toggle(
                            "Automatically check for updates",
                            isOn: Binding(
                                get: { automaticallyChecksForUpdates },
                                set: { newValue in
                                    automaticallyChecksForUpdates = newValue
                                    updater.automaticallyChecksForUpdates = newValue
                                }
                            )
                        )
                        .toggleStyle(.switch)

                        Toggle(
                            "Automatically download updates",
                            isOn: Binding(
                                get: { automaticallyDownloadsUpdates },
                                set: { newValue in
                                    automaticallyDownloadsUpdates = newValue
                                    updater.automaticallyDownloadsUpdates = newValue
                                }
                            )
                        )
                        .toggleStyle(.switch)
                        .disabled(!automaticallyChecksForUpdates)

                        HStack {
                            Text("Last checked:")
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let lastCheck = lastUpdateCheckDate {
                                Text(lastCheck.formatted(date: .abbreviated, time: .shortened))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Never")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.subheadline)

                        Button("Check for Updates Now") {
                            updater.checkForUpdates()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                lastUpdateCheckDate = updater.lastUpdateCheckDate
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal, 20)
                    .onAppear {
                        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
                        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
                        lastUpdateCheckDate = updater.lastUpdateCheckDate
                    }

                    Divider()
                        .padding(.horizontal, 40)
                }

                // Links
                VStack(spacing: 12) {
                    Button(action: {
                        if let url = URL(string: "https://github.com/fightingentropy/SpotMenu") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                            Text("View on GitHub")
                        }
                    }
                    .buttonStyle(.link)

                    Button(action: {
                        if let url = URL(string: "https://erlin.org") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                            Text("Website")
                        }
                    }
                    .buttonStyle(.link)
                }

                Spacer()

                // Copyright
                Text("Made with love by @fightingentropy")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 20)
            }
            .frame(maxWidth: 400)
            .padding(20)
        }
    }
}

#Preview {
    AboutPreferencesView()
}
