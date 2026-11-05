import Combine
import Foundation

/// Finds lyrics for the current track and follows playback line by line.
@MainActor
package final class LyricsSession: ObservableObject {
    package enum Status: Equatable, Sendable {
        case off, loading, synced, unsynced, notFound
        /// Episodes, ads and local files.
        case notASong
    }

    private static let enabledKey = "lyricsInMenuBar"
    private static let tickInterval: TimeInterval = 0.2
    /// Re-read Spotify's position this often while playing, so the timing doesn't drift.
    private static let positionResyncInterval: TimeInterval = 5
    /// After seeking, give Spotify this long before re-reading the position.
    private static let seekSettleTime: TimeInterval = 1.5
    private static let unavailableNoticeDuration: UInt64 = 4_000_000_000

    @Published package var isEnabled: Bool {
        didSet {
            storage.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled {
                trackDidChange(to: nowPlaying.track)
            } else {
                reset(status: .off)
            }
        }
    }
    @Published package private(set) var status: Status = .off {
        didSet {
            if status != oldValue && hasNoLyrics { flashUnavailableNotice() }
        }
    }
    /// Where the synced lyrics came from ("LRCLIB", "NetEase").
    @Published package private(set) var source: String?
    @Published package private(set) var timeline = LyricsTimeline.empty
    /// Words without timestamps, shown when nothing synced exists.
    @Published package private(set) var plainLyrics: String?
    @Published package private(set) var currentLineIndex: Int?
    /// Lyrics on and Spotify playing. The pill hides while paused; the expanded view stays.
    @Published package private(set) var isPlaybackActive = false
    /// Briefly true when the current song turns out to have no usable lyrics.
    @Published package private(set) var isShowingUnavailableNotice = false

    private let nowPlaying: NowPlaying
    private let preferences: LyricsPreferences
    private let lookup: LyricsLookup
    private let storage: SettingsStorage
    private var loadedTrackURI: String?
    private var nextPositionResync = Date.distantPast
    private var noticeTask: Task<Void, Never>?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    package init(nowPlaying: NowPlaying, preferences: LyricsPreferences, lookup: LyricsLookup, storage: SettingsStorage) {
        self.nowPlaying = nowPlaying
        self.preferences = preferences
        self.lookup = lookup
        self.storage = storage
        isEnabled = storage.value(forKey: Self.enabledKey) ?? false

        nowPlaying.$track
            .removeDuplicates { $0?.uri == $1?.uri }
            .sink { [weak self] track in self?.trackDidChange(to: track) }
            .store(in: &cancellables)
    }

    /// Starts following playback. Separate from `init` so tests can drive `tick(at:)` themselves.
    package func startFollowingPlayback() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick(at: Date()) }
        }
    }

    /// Lyrics are on, but this song has none that can be synced.
    package var hasNoLyrics: Bool {
        isEnabled && [.notFound, .unsynced, .notASong].contains(status)
    }

    /// The current line and its neighbours, per the chosen line count.
    package var visibleLines: [VisibleLyricLine] {
        guard isPlaybackActive, let current = currentLineIndex else { return [] }
        return timeline.visibleLines(around: current, count: preferences.visibleLineCount)
    }

    /// Jumps the song to the start of a line (clicking a lyric).
    package func seek(toLine index: Int) {
        guard timeline.lines.indices.contains(index) else { return }
        nowPlaying.seek(to: timeline.lines[index].time)
        nextPositionResync = Date().addingTimeInterval(Self.seekSettleTime)
        setCurrentLine(index)
    }

    // MARK: Loading

    package func load(for track: Track?) async {
        guard let song = startLoading(track) else { return }
        await finishLoading(song)
    }

    /// Reacts to a new track right away and fetches its lyrics in the background.
    private func trackDidChange(to track: Track?) {
        guard let song = startLoading(track) else { return }
        Task { await finishLoading(song) }
    }

    /// Resets for the new track; returns it when its lyrics still need fetching.
    private func startLoading(_ track: Track?) -> Track? {
        guard isEnabled else { return nil }
        guard let track else {
            reset(status: .off)
            return nil
        }
        guard track.isSong else {
            reset(status: .notASong)
            return nil
        }
        guard track.uri != loadedTrackURI else { return nil }
        reset(status: .loading)
        loadedTrackURI = track.uri
        return track
    }

    private func finishLoading(_ track: Track) async {
        let result = await lookup.find(for: track)
        guard loadedTrackURI == track.uri else { return } // skipped to another song meanwhile
        switch result {
        case let .synced(lines, source):
            timeline = LyricsTimeline(lines: lines)
            self.source = source
            status = .synced
        case let .unsynced(text):
            plainLyrics = text
            status = .unsynced
        case .notFound:
            status = .notFound
        }
    }

    private func reset(status newStatus: Status) {
        noticeTask?.cancel()
        isShowingUnavailableNotice = false
        timeline = .empty
        plainLyrics = nil
        source = nil
        loadedTrackURI = nil
        status = newStatus
        setCurrentLine(nil)
    }

    private func flashUnavailableNotice() {
        noticeTask?.cancel()
        isShowingUnavailableNotice = true
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.unavailableNoticeDuration)
            guard !Task.isCancelled else { return }
            self?.isShowingUnavailableNotice = false
        }
    }

    // MARK: Following playback

    package func tick(at now: Date) {
        let active = isEnabled && nowPlaying.isPlaying && nowPlaying.track != nil
        if active != isPlaybackActive { isPlaybackActive = active }

        // Keep tracking the line while paused, so the expanded view stays highlighted.
        guard isEnabled, nowPlaying.track != nil, !timeline.isEmpty else {
            setCurrentLine(nil)
            return
        }
        if nowPlaying.isPlaying && now > nextPositionResync {
            nowPlaying.resyncPosition()
            nextPositionResync = now.addingTimeInterval(Self.positionResyncInterval)
        }
        let position = nowPlaying.currentPosition(at: now) + preferences.timingOffset
        setCurrentLine(timeline.lineIndex(at: position))
    }

    private func setCurrentLine(_ index: Int?) {
        guard index != currentLineIndex else { return }
        currentLineIndex = index
    }
}
