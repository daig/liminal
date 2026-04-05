import Foundation

struct VimMarkSnapshot: Equatable {
    static let empty = VimMarkSnapshot(positions: [:])

    let positions: [Character: Int]
}

struct VimResolvedMark: Equatable {
    let name: Character
    let position: Int
}

final class VimMarkStore {
    private var positions: [Character: Int] = [:]

    func snapshot() -> VimMarkSnapshot {
        VimMarkSnapshot(positions: positions)
    }

    func restore(_ snapshot: VimMarkSnapshot) {
        positions = snapshot.positions
    }

    @discardableResult
    func setLocalMark(named name: Character, at position: Int, in text: NSString) -> Bool {
        guard Self.isSupportedLocalMarkName(name) else { return false }

        positions[name] = normalizedMarkPosition(position, in: text)
        return true
    }

    func position(of name: Character, in text: NSString) -> Int? {
        guard Self.isSupportedLocalMarkName(name) else { return nil }
        guard let storedPosition = positions[name] else { return nil }
        return normalizedMarkPosition(storedPosition, in: text)
    }

    func groupedMarksByPosition(in text: NSString) -> [Int: [Character]] {
        var grouped: [Int: [Character]] = [:]

        for (name, storedPosition) in positions {
            let normalizedPosition = normalizedMarkPosition(storedPosition, in: text)
            grouped[normalizedPosition, default: []].append(name)
        }

        for key in grouped.keys {
            grouped[key]?.sort()
        }

        return grouped
    }

    func resolvedLocalMarks(in text: NSString) -> [VimResolvedMark] {
        positions.keys.sorted().compactMap { name in
            guard let position = position(of: name, in: text) else { return nil }
            return VimResolvedMark(name: name, position: position)
        }
    }

    func apply(_ edit: VimTextEdit) {
        let removedLength = (edit.removedText as NSString).length
        let insertedLength = (edit.insertedText as NSString).length
        let start = edit.location
        let end = start + removedLength
        let delta = insertedLength - removedLength

        positions = positions.mapValues { position in
            if position < start {
                return position
            }

            if position >= end {
                return position + delta
            }

            return start
        }
    }

    private func normalizedMarkPosition(_ position: Int, in text: NSString) -> Int {
        guard text.length > 0 else { return max(position, 0) }
        return VimNavigator.normalizedPosition(position, in: text)
    }

    private static func isSupportedLocalMarkName(_ name: Character) -> Bool {
        guard name.unicodeScalars.count == 1, let scalar = name.unicodeScalars.first else {
            return false
        }

        return scalar.value >= 0x61 && scalar.value <= 0x7A
    }
}
