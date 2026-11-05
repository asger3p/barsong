import Foundation

/// A song's synced lyrics laid out in time: which line is current, and which lines
/// surround it.
package struct LyricsTimeline: Equatable, Sendable {
    /// How many lines can be shown at once.
    package static let lineCountOptions = [1, 2, 3, 5]

    package let lines: [LyricLine]
    /// Indices of lines with words (LRC uses empty lines to mark instrumental gaps).
    private let wordLineIndices: [Int]

    package init(lines: [LyricLine]) {
        self.lines = lines
        wordLineIndices = lines.indices.filter { !lines[$0].text.isEmpty }
    }

    package static let empty = LyricsTimeline(lines: [])

    package var isEmpty: Bool { lines.isEmpty }

    /// The last line that has started by `position`; nil before the first one.
    package func lineIndex(at position: TimeInterval) -> Int? {
        lines.lastIndex { $0.time <= position }
    }

    /// The current line and its neighbours for 1 (current), 2 (current, next),
    /// 3 (previous, current, next) or 5 lines (two either side). Neighbours skip
    /// instrumental gaps; a gap as the current line shows as "♪" when there's context.
    package func visibleLines(around current: Int, count: Int) -> [VisibleLyricLine] {
        guard lines.indices.contains(current) else { return [] }
        let currentText = lines[current].text
        let (before, after): (Int, Int) = switch count {
        case 2: (0, 1)
        case 3: (1, 1)
        case 5: (2, 2)
        default: (0, 0)
        }
        if before == 0 && after == 0 {
            return currentText.isEmpty ? [] : [VisibleLyricLine(id: current, text: currentText, isCurrent: true)]
        }
        let previous = wordLineIndices.filter { $0 < current }.suffix(before)
        let next = wordLineIndices.filter { $0 > current }.prefix(after)
        let neighbour = { (index: Int) in VisibleLyricLine(id: index, text: lines[index].text, isCurrent: false) }
        return previous.map(neighbour)
            + [VisibleLyricLine(id: current, text: currentText.isEmpty ? "♪" : currentText, isCurrent: true)]
            + next.map(neighbour)
    }
}
