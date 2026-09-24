//
//  ZipArchive.swift
//  HyperPad
//

import Foundation

/// Minimal store-only zip support for the stack container (D4).
///
/// Writing is deterministic — fixed timestamps, entries sorted by name —
/// so stack files diff cleanly, and any zip tool can open one. Entries are
/// stored uncompressed: the manifest is small and media assets are already
/// compressed. Reading treats input as hostile (D7): bounds-checked,
/// store-only, CRC-verified, path-sanitized, and size-capped.
nonisolated enum ZipArchive {
    enum ZipError: LocalizedError {
        case notAnArchive
        case malformed
        case unsupported(String)

        var errorDescription: String? {
            switch self {
            case .notAnArchive: "This file is not a stack archive."
            case .malformed: "This stack archive is damaged."
            case .unsupported(let reason): "This stack archive can't be opened: \(reason)."
            }
        }
    }

    static let maxEntryCount = 4096
    static let maxEntryBytes = 128 << 20
    static let maxTotalBytes = 256 << 20

    // MARK: - Writing

    static func archive(_ entries: [String: Data]) -> Data {
        var output = Data()
        var centralDirectory = Data()
        var entryCount: UInt16 = 0

        for name in entries.keys.sorted() {
            let contents = entries[name]!
            let nameBytes = Data(name.utf8)
            let crc = crc32(of: contents)
            let localOffset = UInt32(output.count)

            // Local file header. Flags bit 11 marks UTF-8 names; the fixed
            // date is 1980-01-01, zip's epoch, for deterministic output.
            output.appendUInt32(0x04034b50)
            output.appendUInt16(20)             // version needed
            output.appendUInt16(0x0800)         // flags: UTF-8 names
            output.appendUInt16(0)              // method: store
            output.appendUInt16(0)              // mod time
            output.appendUInt16(0x21)           // mod date
            output.appendUInt32(crc)
            output.appendUInt32(UInt32(contents.count))
            output.appendUInt32(UInt32(contents.count))
            output.appendUInt16(UInt16(nameBytes.count))
            output.appendUInt16(0)              // extra length
            output.append(nameBytes)
            output.append(contents)

            centralDirectory.appendUInt32(0x02014b50)
            centralDirectory.appendUInt16(20)   // version made by
            centralDirectory.appendUInt16(20)   // version needed
            centralDirectory.appendUInt16(0x0800)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0x21)
            centralDirectory.appendUInt32(crc)
            centralDirectory.appendUInt32(UInt32(contents.count))
            centralDirectory.appendUInt32(UInt32(contents.count))
            centralDirectory.appendUInt16(UInt16(nameBytes.count))
            centralDirectory.appendUInt16(0)    // extra
            centralDirectory.appendUInt16(0)    // comment
            centralDirectory.appendUInt16(0)    // disk number
            centralDirectory.appendUInt16(0)    // internal attributes
            centralDirectory.appendUInt32(0)    // external attributes
            centralDirectory.appendUInt32(localOffset)
            centralDirectory.append(nameBytes)

            entryCount += 1
        }

        let directoryOffset = UInt32(output.count)
        output.append(centralDirectory)

        // End of central directory.
        output.appendUInt32(0x06054b50)
        output.appendUInt16(0)                  // disk number
        output.appendUInt16(0)                  // directory start disk
        output.appendUInt16(entryCount)
        output.appendUInt16(entryCount)
        output.appendUInt32(UInt32(centralDirectory.count))
        output.appendUInt32(directoryOffset)
        output.appendUInt16(0)                  // comment length
        return output
    }

    // MARK: - Reading

    static func extract(_ data: Data) throws -> [String: Data] {
        guard data.count >= 22 else { throw ZipError.notAnArchive }

        // Find the end-of-central-directory record from the back.
        var eocd = -1
        let searchFloor = max(0, data.count - 22 - 65_535)
        var position = data.count - 22
        while position >= searchFloor {
            if data.readUInt32(at: position) == 0x06054b50 {
                eocd = position
                break
            }
            position -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAnArchive }

        let entryCount = Int(data.readUInt16(at: eocd + 10))
        let directorySize = Int(data.readUInt32(at: eocd + 12))
        let directoryOffset = Int(data.readUInt32(at: eocd + 16))
        guard entryCount <= maxEntryCount else { throw ZipError.unsupported("too many entries") }
        guard entryCount != 0xFFFF, directoryOffset != 0xFFFF_FFFF else { throw ZipError.unsupported("zip64 archives are not supported") }
        guard directoryOffset >= 0, directorySize >= 0, directoryOffset + directorySize <= eocd else { throw ZipError.malformed }

        var entries: [String: Data] = [:]
        var totalBytes = 0
        var cursor = directoryOffset

        for _ in 0..<entryCount {
            guard cursor + 46 <= directoryOffset + directorySize,
                  data.readUInt32(at: cursor) == 0x02014b50 else { throw ZipError.malformed }
            let method = data.readUInt16(at: cursor + 10)
            let crc = data.readUInt32(at: cursor + 16)
            let compressedSize = Int(data.readUInt32(at: cursor + 20))
            let size = Int(data.readUInt32(at: cursor + 24))
            let nameLength = Int(data.readUInt16(at: cursor + 28))
            let extraLength = Int(data.readUInt16(at: cursor + 30))
            let commentLength = Int(data.readUInt16(at: cursor + 32))
            let localOffset = Int(data.readUInt32(at: cursor + 42))

            guard method == 0, compressedSize == size else {
                throw ZipError.unsupported("compressed entries are not supported")
            }
            guard size <= maxEntryBytes else { throw ZipError.unsupported("an entry is too large") }
            totalBytes += size
            guard totalBytes <= maxTotalBytes else { throw ZipError.unsupported("the archive is too large") }

            guard cursor + 46 + nameLength <= directoryOffset + directorySize,
                  let name = String(data: data.subdata(in: (cursor + 46)..<(cursor + 46 + nameLength)), encoding: .utf8) else {
                throw ZipError.malformed
            }
            // Path hygiene: no escapes, no absolute paths, no duplicates.
            guard !name.hasPrefix("/"), !name.contains("\\"),
                  !name.components(separatedBy: "/").contains(".."),
                  entries[name] == nil else {
                throw ZipError.malformed
            }

            // The entry's bytes live after its local header.
            guard localOffset + 30 <= data.count,
                  data.readUInt32(at: localOffset) == 0x04034b50 else { throw ZipError.malformed }
            let localNameLength = Int(data.readUInt16(at: localOffset + 26))
            let localExtraLength = Int(data.readUInt16(at: localOffset + 28))
            let start = localOffset + 30 + localNameLength + localExtraLength
            guard start >= 0, start + size <= data.count else { throw ZipError.malformed }

            let contents = data.subdata(in: start..<(start + size))
            guard crc32(of: contents) == crc else { throw ZipError.malformed }

            entries[name] = contents
            cursor += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    // MARK: - CRC32

    private static let crcTable: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) == 1 ? (value >> 1) ^ 0xEDB8_8320 : value >> 1
        }
        return value
    }

    static func crc32(of data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt32(byte)) & 0xFF)]
        }
        return crc ^ 0xFFFF_FFFF
    }
}

// MARK: - Byte helpers

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }

    /// Little-endian reads, safe for any `at` (returns 0 out of bounds —
    /// callers bound-check separately; this only prevents traps).
    func readUInt16(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        let base = startIndex + offset
        return UInt16(self[base]) | (UInt16(self[base + 1]) << 8)
    }

    func readUInt32(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        let base = startIndex + offset
        return UInt32(self[base])
            | (UInt32(self[base + 1]) << 8)
            | (UInt32(self[base + 2]) << 16)
            | (UInt32(self[base + 3]) << 24)
    }
}
