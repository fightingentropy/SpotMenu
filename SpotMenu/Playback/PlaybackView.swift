import AppKit
import Foundation
import SwiftUI

struct PlaybackView: View {
    private enum LibraryCategory {
        case library
        case streams
    }

    private struct StreamItem: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let artist: String
        let url: URL
        let iconAssetName: String?
    }

    @ObservedObject var model: PlaybackModel
    @ObservedObject var preferences: PlaybackAppearancePreferencesModel
    @ObservedObject var musicPlayerPreferencesModel: MusicPlayerPreferencesModel
    @State private var isHovering = false
    @State private var librarySearchText = ""
    @State private var selectedCategory: LibraryCategory = .library
    @Environment(\.colorScheme) private var systemColorScheme

    private var compactDimension: CGFloat { 300 }
    private var expandedWidth: CGFloat { preferences.popoverSize.width }
    private var expandedHeight: CGFloat { preferences.popoverSize.height }
    private var metadataTextHeight: CGFloat { 46 }
    private var streams: [StreamItem] {
        [
            StreamItem(
                title: "Dromos.gr",
                subtitle: "n39a-eu.rcs.revma.com",
                artist: "Live Stream",
                url: URL(
                    string:
                        "https://n39a-eu.rcs.revma.com/10q3enqxbfhvv?rj-ttl=5&rj-tok=AAABnLZzfw8ASa_yyCYLNy3gcg"
                )!,
                iconAssetName: "DromosIcon"
            )
        ]
    }

    private var filteredLibraryTracks: [LibraryTrack] {
        let trimmedQuery = librarySearchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedQuery.isEmpty else {
            return model.libraryTracks
        }

        let lowered = trimmedQuery.lowercased()
        return model.libraryTracks.filter { track in
            track.title.lowercased().contains(lowered)
                || track.artist.lowercased().contains(lowered)
                || (track.album?.lowercased().contains(lowered) ?? false)
        }
    }

    var body: some View {
        Group {
            if preferences.showExpandedLibraryView {
                expandedBody
            } else {
                compactBody
            }
        }
        .onHover { hovering in
            guard !preferences.showExpandedLibraryView else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .onAppear {
            model.refreshLibrary()
        }
    }

    private var compactBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .frame(width: compactDimension, height: compactDimension)

            compactContent
                .clipShape(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        }
        .frame(width: compactDimension, height: compactDimension)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var expandedBody: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)

                expandedHeroContent
            }
            .frame(width: expandedWidth - 20, height: compactDimension)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            libraryContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(10)
        .frame(width: expandedWidth, height: expandedHeight)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var compactContent: some View {
        let blurRadius = isHovering ? preferences.blurIntensity * 10 : 0
        let overlayColor =
            isHovering
            ? adaptiveHoverTintColor.opacity(preferences.hoverTintOpacity)
            : nil

        artworkBackground(
            width: compactDimension,
            height: compactDimension,
            blurRadius: blurRadius,
            overlayColor: overlayColor
        )

        if isHovering {
            controlsOverlay
        }
    }

    private var expandedHeroContent: some View {
        let blurRadius = preferences.blurIntensity * 10
        let overlayColor = adaptiveHoverTintColor.opacity(
            max(preferences.hoverTintOpacity, 0.28)
        )

        return ZStack {
            artworkBackground(
                width: expandedWidth - 20,
                height: compactDimension,
                blurRadius: blurRadius,
                overlayColor: overlayColor
            )

            controlsOverlay
        }
    }

    private var libraryContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    categoryButton(title: "Library", category: .library)
                    categoryButton(title: "Streams", category: .streams)
                }

                Spacer()

                if selectedCategory == .library {
                    Text("\(filteredLibraryTracks.count) tracks")
                        .font(.caption)
                        .foregroundColor(
                            preferences.foregroundColor.color.opacity(0.75)
                        )
                }

                Button("Play All") {
                    model.playAllFromLibrary()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(trackRowBackgroundColor.opacity(0.9))
                )
                .foregroundColor(preferences.foregroundColor.color)
                .disabled(selectedCategory != .library || filteredLibraryTracks.isEmpty)
            }

            if selectedCategory == .library {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(preferences.foregroundColor.color.opacity(0.7))
                    TextField("Search songs", text: $librarySearchText)
                        .textFieldStyle(.plain)
                        .foregroundColor(preferences.foregroundColor.color)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(trackRowBackgroundColor.opacity(0.85))
                )
            }

            if selectedCategory == .streams {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(streams) { stream in
                            streamRow(stream)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else if !model.supportsLibraryBrowser {
                Spacer()
                Text("Library browser is available in Music Folder mode.")
                    .font(.subheadline)
                    .foregroundColor(preferences.foregroundColor.color.opacity(0.8))
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if filteredLibraryTracks.isEmpty {
                Spacer()
                Text(model.libraryTracks.isEmpty ? "No tracks found in folder." : "No tracks match your search.")
                    .font(.subheadline)
                    .foregroundColor(preferences.foregroundColor.color.opacity(0.8))
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredLibraryTracks) { track in
                            trackRow(track)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private func categoryButton(title: String, category: LibraryCategory) -> some View {
        let isSelected = selectedCategory == category

        return Button(title) {
            selectedCategory = category
        }
        .buttonStyle(.plain)
        .font(.headline)
        .foregroundColor(
            preferences.foregroundColor.color.opacity(isSelected ? 1 : 0.7)
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(isSelected ? trackRowBackgroundColor.opacity(0.9) : Color.clear)
        )
    }

    private func streamRow(_ stream: StreamItem) -> some View {
        let isCurrentStream = model.currentTrackID == stream.url

        return Button(action: {
            if isCurrentStream {
                model.togglePlayPause()
            } else {
                model.playStream(
                    url: stream.url,
                    title: stream.title,
                    artist: stream.artist,
                    imageAssetName: stream.iconAssetName
                )
            }
        }) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(trackRowBackgroundColor.opacity(0.9))

                    if let iconAssetName = stream.iconAssetName,
                        NSImage(named: iconAssetName) != nil
                    {
                        Image(iconAssetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 5,
                                    style: .continuous
                                )
                            )
                    } else {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(
                                preferences.foregroundColor.color.opacity(0.8)
                            )
                    }
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(stream.title)
                        .font(.headline)
                        .foregroundColor(preferences.foregroundColor.color)
                        .lineLimit(1)

                    Text(stream.subtitle)
                        .font(.subheadline)
                        .foregroundColor(preferences.foregroundColor.color.opacity(0.8))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: indicatorSymbol(isCurrentTrack: isCurrentStream))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(preferences.foregroundColor.color)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(
                                isCurrentStream
                                    ? Color.accentColor.opacity(0.55)
                                    : trackRowBackgroundColor.opacity(0.95)
                            )
                    )
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        isCurrentStream
                            ? Color.accentColor.opacity(0.22)
                            : trackRowBackgroundColor
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func trackRow(_ track: LibraryTrack) -> some View {
        let isCurrentTrack = model.currentTrackID == track.id

        return Button(action: {
            model.playLibraryTrack(track)
        }) {
            HStack(spacing: 10) {
                trackArtwork(for: track)

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.headline)
                        .foregroundColor(preferences.foregroundColor.color)
                        .lineLimit(1)

                    Text(trackSubtitle(for: track))
                        .font(.subheadline)
                        .foregroundColor(
                            preferences.foregroundColor.color.opacity(0.8)
                        )
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(
                    formatTime(track.duration, styleMatching: max(track.duration, 1))
                )
                .font(.body.monospacedDigit())
                .foregroundColor(preferences.foregroundColor.color.opacity(0.85))
                .fixedSize(horizontal: true, vertical: false)

                Image(systemName: indicatorSymbol(isCurrentTrack: isCurrentTrack))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(preferences.foregroundColor.color)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(
                                isCurrentTrack
                                    ? Color.accentColor.opacity(0.55)
                                    : trackRowBackgroundColor.opacity(0.95)
                            )
                    )
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        isCurrentTrack
                            ? Color.accentColor.opacity(0.22)
                            : trackRowBackgroundColor
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func indicatorSymbol(isCurrentTrack: Bool) -> String {
        if isCurrentTrack {
            return model.isPlaying ? "pause.fill" : "play.fill"
        }

        return "play.fill"
    }

    @ViewBuilder
    private func trackArtwork(for track: LibraryTrack) -> some View {
        if let image = track.image {
            image
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(trackRowBackgroundColor.opacity(0.9))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(preferences.foregroundColor.color.opacity(0.8))
                }
        }
    }

    private func trackSubtitle(for track: LibraryTrack) -> String {
        if let album = track.album,
            !album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return "\(track.artist) - \(album)"
        }

        return track.artist
    }

    private var trackRowBackgroundColor: Color {
        if systemColorScheme == .dark {
            return Color.white.opacity(0.12)
        }
        return Color.black.opacity(0.08)
    }

    @ViewBuilder
    private func artworkBackground(
        width: CGFloat,
        height: CGFloat,
        blurRadius: Double,
        overlayColor: Color?
    ) -> some View {
        if let url = model.imageURL {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: height)
                        .clipped()
                        .blur(radius: blurRadius)
                        .overlay {
                            artworkOverlay(customColor: overlayColor)
                        }
                }
            }
        } else if let fallbackImage = model.image {
            fallbackImage
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipped()
                .blur(radius: blurRadius)
                .overlay {
                    artworkOverlay(customColor: overlayColor)
                }
        } else {
            ZStack {
                Color.clear
                Image(systemName: "music.note")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(preferences.foregroundColor.color.opacity(0.2))
                    .frame(width: 100, height: 100)
            }
            .frame(width: width, height: height)
            .blur(radius: blurRadius)
            .overlay {
                artworkOverlay(customColor: overlayColor)
            }
        }
    }

    @ViewBuilder
    private func artworkOverlay(customColor: Color?) -> some View {
        Color.black.opacity(0.34)
        if let customColor {
            customColor
        }
    }

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: model.openMusicApp) {
                    if let systemName = iconSystemName(from: model.playerIconName)
                    {
                        Image(systemName: systemName)
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(preferences.foregroundColor.color)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(model.playerIconName)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(preferences.foregroundColor.color)
                            .frame(width: 20, height: 20)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    model.toggleShuffle()
                }) {
                    Image(
                        systemName: model.isShuffleEnabled
                            ? "shuffle.circle.fill"
                            : "shuffle.circle"
                    )
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(preferences.foregroundColor.color)
                    .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    NSApp.sendAction(
                        #selector(AppDelegate.preferencesAction),
                        to: nil,
                        from: nil
                    )
                }) {
                    Image(systemName: "gearshape.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(preferences.foregroundColor.color)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 20)
            .padding(.leading, 30)
            .padding(.trailing, 30)
            .padding(.bottom, 24)

            VStack(spacing: 12) {
                Text(model.artist)
                    .font(.title3)
                    .foregroundColor(preferences.foregroundColor.color)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: metadataTextHeight,
                        maxHeight: metadataTextHeight,
                        alignment: .center
                    )
                    .padding(.horizontal)

                HStack(spacing: 10) {
                    tappableIconButton(
                        imageName: "backward.fill",
                        imageSize: 30
                    ) {
                        model.skipBack()
                    }

                    tappableIconButton(
                        imageName: model.isPlaying ? "pause.fill" : "play.fill",
                        imageSize: 40
                    ) {
                        model.togglePlayPause()
                    }

                    tappableIconButton(imageName: "forward.fill", imageSize: 30)
                    {
                        model.skipForward()
                    }
                }
                .foregroundColor(preferences.foregroundColor.color)

                Text(model.title)
                    .font(.title3)
                    .foregroundColor(preferences.foregroundColor.color)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: metadataTextHeight,
                        maxHeight: metadataTextHeight,
                        alignment: .center
                    )
                    .padding(.horizontal)
            }

            Spacer(minLength: 0)

            HStack(alignment: .center) {
                Text(
                    formatTime(
                        model.currentTime,
                        styleMatching: model.totalTime
                    )
                )
                .font(.body.monospacedDigit())
                .foregroundColor(preferences.foregroundColor.color)
                .frame(alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)

                CustomSlider(
                    value: Binding(
                        get: { model.currentTime },
                        set: { model.updatePlaybackPosition(to: $0) }
                    ),
                    range: 0...model.totalTime,
                    foregroundColor: preferences.foregroundColor.color,
                    trackColor: preferences.foregroundColor.color
                )
                .frame(maxWidth: .infinity)

                Text(
                    formatTime(model.totalTime, styleMatching: model.totalTime)
                )
                .font(.body.monospacedDigit())
                .foregroundColor(preferences.foregroundColor.color)
                .frame(alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)

                if model.isLikingImplemented
                    && musicPlayerPreferencesModel.likingEnabled
                {
                    Group {
                        if let isLiked = model.isLiked {
                            Button(action: {
                                model.toggleLiked()
                            }) {
                                Image(
                                    systemName: isLiked ? "heart.fill" : "heart"
                                )
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(
                                    preferences.foregroundColor.color
                                )
                                .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)
                            .help("Toggle like status")
                        } else {
                            Button(action: {
                                model.toggleLiked()
                            }) {
                                Image(systemName: "heart")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundColor(
                                        preferences.foregroundColor.color
                                            .opacity(0.3)
                                    )
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)
                            .help("Login to enable liking tracks")
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .padding(.horizontal)
        .transition(.opacity)
    }

    func formatTime(_ seconds: Double, styleMatching total: Double) -> String {
        let safeSeconds = max(0, seconds)
        let safeTotal = max(1, total)

        let s = Int(safeSeconds)
        let t = Int(safeTotal)
        let (h, m, sec) = (s / 3600, (s % 3600) / 60, s % 60)
        let (th, tm) = (t / 3600, (t % 3600) / 60)

        if th > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        } else if tm >= 10 {
            return String(format: "%02d:%02d", m, sec)
        } else {
            return String(format: "%d:%02d", m, sec)
        }
    }

    private var adaptiveHoverTintColor: Color {
        return Color(preferences.hoverTintColor)
    }

    private func iconSystemName(from iconName: String) -> String? {
        let prefix = "system:"
        guard iconName.hasPrefix(prefix) else { return nil }
        return String(iconName.dropFirst(prefix.count))
    }
}

#Preview {
    let model = PlaybackModel(preferences: MusicPlayerPreferencesModel())
    model.imageURL = URL(
        string:
            "https://i.scdn.co/image/ab67616d0000b27377054612c5275c1515b18a50"
    )
    model.artist = "The Weeknd"
    return PlaybackView(
        model: model,
        preferences: PlaybackAppearancePreferencesModel(),
        musicPlayerPreferencesModel: MusicPlayerPreferencesModel()
    )
}

@ViewBuilder
func tappableIconButton(
    imageName: String,
    imageSize: CGFloat,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        Image(systemName: imageName)
            .resizable()
            .scaledToFit()
            .frame(width: imageSize, height: imageSize)
            .frame(width: 44, height: 44)
            .padding(16)
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
}
