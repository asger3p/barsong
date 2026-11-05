import Foundation

/// One timed line of synced lyrics. Empty text marks an instrumental gap.
package struct LyricLine: Equatable, Sendable {
    package let time: TimeInterval
    package let text: String

    package init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
    }
}

/// A line as shown around the current position.
package struct VisibleLyricLine: Identifiable, Equatable, Sendable {
    /// Index into the song's lines, so rows animate as they scroll.
    package let id: Int
    package let text: String
    package let isCurrent: Bool

    package init(id: Int, text: String, isCurrent: Bool) {
        self.id = id
        self.text = text
        self.isCurrent = isCurrent
    }
}

/// Parses LRC, the usual synced lyrics format: "[01:23.45] text".
package enum LRCParser {
    private static let timestamp = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#)

    /// Lines sorted by time. A line may carry several timestamps (a repeated chorus);
    /// lines without a timestamp (tags, credits) are skipped.
    package static func parse(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        for raw in lrc.components(separatedBy: .newlines) {
            let text = raw as NSString
            let matches = timestamp.matches(in: raw, range: NSRange(location: 0, length: text.length))
            guard let last = matches.last else { continue }
            let words = text.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: .whitespaces)
            for match in matches {
                let minutes = Double(text.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(text.substring(with: match.range(at: 2))) ?? 0
                lines.append(LyricLine(time: minutes * 60 + seconds, text: words))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }
}
