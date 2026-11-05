import AppDomain
import Foundation

/// Turns Spotify's AppleScript replies and playback notifications into domain values.
package enum SpotifyPlaybackParsing {
    /// Separates the fields of the full-state AppleScript reply (ASCII "unit separator").
    package static let fieldSeparator = "\u{1F}"

    /// Reads the reply of `SpotifyScripts.fullState`:
    /// name · artist · album · id · duration (ms) · position (s) · state · artwork url
    /// · shuffling · repeating · volume. An empty reply means nothing is playing.
    package static func playerReading(fromScriptOutput output: String) -> PlayerReading? {
        guard !output.isEmpty else { return .nothingPlaying }
        let fields = output.components(separatedBy: fieldSeparator)
        guard fields.count >= 8 else { return nil }

        var snapshot = PlaybackSnapshot(
            track: Track(title: fields[0], artist: fields[1], album: fields[2], uri: fields[3], duration: number(fields[4]) / 1000),
            isPlaying: fields[6] == "playing",
            position: number(fields[5]),
            artworkURL: URL(string: fields[7])
        )
        if fields.count >= 11 {
            snapshot.isShuffling = fields[8] == "true"
            snapshot.isRepeating = fields[9] == "true"
            snapshot.volume = number(fields[10])
        }
        return .playing(snapshot)
    }

    /// Reads a "com.spotify.client.PlaybackStateChanged" notification. Nil when stopped.
    package static func snapshot(fromNotification info: [AnyHashable: Any]) -> PlaybackSnapshot? {
        let state = info["Player State"] as? String ?? "Stopped"
        guard state != "Stopped", let uri = info["Track ID"] as? String else { return nil }
        let durationMilliseconds = (info["Duration"] as? NSNumber)?.doubleValue ?? 0
        return PlaybackSnapshot(
            track: Track(
                title: info["Name"] as? String ?? "",
                artist: info["Artist"] as? String ?? "",
                album: info["Album"] as? String ?? "",
                uri: uri,
                duration: durationMilliseconds / 1000
            ),
            isPlaying: state == "Playing",
            position: (info["Playback Position"] as? NSNumber)?.doubleValue ?? 0
        )
    }

    /// AppleScript formats reals using the system locale ("12,5").
    package static func number(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    /// Like `number`, but nil for anything that isn't a number.
    package static func optionalNumber(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }
}

/// The AppleScript sent to Spotify.
enum SpotifyScripts {
    static let fullState = """
    tell application "Spotify"
        if player state is stopped then return ""
        set t to current track
        set sep to ASCII character 31
        return (name of t) & sep & (artist of t) & sep & (album of t) & sep & (id of t) & sep & (duration of t) & sep & (player position as text) & sep & (player state as text) & sep & (artwork url of t) & sep & (shuffling as text) & sep & (repeating as text) & sep & (sound volume as text)
    end tell
    """
    static let artworkURL = #"tell application "Spotify" to return artwork url of current track"#
    static let position = #"tell application "Spotify" to return player position as text"#

    static func command(_ command: String) -> String {
        #"tell application "Spotify" to \#(command)"#
    }
}
