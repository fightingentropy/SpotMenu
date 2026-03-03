import AppKit
import SwiftUI

struct MusicPlayerPreferencesView: View {
    @ObservedObject var model: MusicPlayerPreferencesModel
    @ObservedObject var playbackModel: PlaybackModel
    @State private var folderSelectionError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Form {
                    Section {
                        Picker(
                            "Preferred Player",
                            selection: $model.preferredMusicApp
                        ) {
                            ForEach(PreferredPlayer.allCases) { player in
                                Text(player.displayName).tag(player)
                            }
                        }
                    } header: {
                        Text("Music Player")
                    } footer: {
                        Text(
                            "\"Automatic\" uses Apple Music when it is running. Otherwise it plays files from your selected music folder."
                        )
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)

                Form {
                    Section {
                        HStack {
                            Text("Current Folder")
                            Spacer()
                            Text(model.resolvedMusicFolderPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        HStack {
                            Button("Choose Folder…") {
                                chooseMusicFolder()
                            }

                            Spacer()

                            Button("Reload Library") {
                                playbackModel.fetchInfo()
                            }
                        }

                        if let folderSelectionError {
                            Text(folderSelectionError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } header: {
                        Text("Local Music Folder")
                    } footer: {
                        Text(
                            "Supported formats: mp3, m4a, aac, wav, aiff, flac, alac, and caf."
                        )
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            }
            .frame(maxWidth: 600)
            .padding(20)
        }
    }

    private func chooseMusicFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Your Music Folder"
        panel.prompt = "Select"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = model.resolveMusicFolderURL()

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }

        do {
            try model.setMusicFolderURL(selectedURL)
            folderSelectionError = nil
            playbackModel.fetchInfo()
        } catch {
            folderSelectionError =
                "Failed to save folder access: \(error.localizedDescription)"
        }
    }
}

#Preview {
    MusicPlayerPreferencesView(
        model: MusicPlayerPreferencesModel(),
        playbackModel: PlaybackModel(preferences: MusicPlayerPreferencesModel())
    )
}
