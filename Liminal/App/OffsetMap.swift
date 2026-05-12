import Foundation

/// O(1) lookup from UTF-8 byte offset to UTF-16 code-unit offset,
/// built in a single linear pass over the source. Replaces the
/// O(position) `String.UTF8View.index(_:offsetBy:)` + `utf16.distance`
/// walks that previously dominated the highlight pass on large docs
/// (each conversion was O(position-in-doc); applying N spans was
/// O(N²/2)).
struct OffsetMap {
    /// `table[i]` is the UTF-16 offset corresponding to UTF-8 byte
    /// offset `i`. Continuation bytes inside a multi-byte scalar share
    /// the scalar's UTF-16 offset. Size is `byteCount + 1` so that
    /// `endByte == byteCount` is a valid lookup.
    private let table: [Int]

    init(source: String) {
        let utf8 = source.utf8
        var table: [Int] = []
        table.reserveCapacity(utf8.count + 1)
        var utf16Position = 0
        for scalar in source.unicodeScalars {
            let utf8Len = scalar.utf8.count
            for _ in 0..<utf8Len {
                table.append(utf16Position)
            }
            utf16Position += scalar.utf16.count
        }
        table.append(utf16Position)
        self.table = table
    }

    var byteCount: Int { table.count - 1 }

    /// Convert a UTF-8 byte range `[start, start + length)` to an
    /// `NSRange` in UTF-16 coordinates. Returns nil for out-of-bounds
    /// inputs.
    func nsRange(forByteStart start: UInt32, length: UInt32) -> NSRange? {
        let startByte = Int(start)
        let endByte = startByte + Int(length)
        guard startByte >= 0, endByte >= startByte, endByte < table.count else {
            return nil
        }
        let startUTF16 = table[startByte]
        let endUTF16 = table[endByte]
        return NSRange(location: startUTF16, length: endUTF16 - startUTF16)
    }
}
