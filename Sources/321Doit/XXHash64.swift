import Foundation

final class XXHash64 {
    private static let prime1: UInt64 = 11_400_714_785_074_694_791
    private static let prime2: UInt64 = 14_029_467_366_897_019_727
    private static let prime3: UInt64 = 1_609_587_929_392_839_161
    private static let prime4: UInt64 = 9_650_029_242_287_828_579
    private static let prime5: UInt64 = 2_870_177_450_012_600_261

    private let seed: UInt64
    private var totalLength: UInt64 = 0
    private var v1: UInt64
    private var v2: UInt64
    private var v3: UInt64
    private var v4: UInt64
    private var memory: [UInt8] = []

    init(seed: UInt64 = 0) {
        self.seed = seed
        self.v1 = seed &+ Self.prime1 &+ Self.prime2
        self.v2 = seed &+ Self.prime2
        self.v3 = seed
        self.v4 = seed &- Self.prime1
    }

    func update(_ data: Data) {
        guard !data.isEmpty else { return }
        totalLength &+= UInt64(data.count)

        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            var remaining = rawBuffer.count

            if !memory.isEmpty {
                let needed = 32 - memory.count
                if remaining < needed {
                    memory.append(contentsOf: UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self), count: remaining))
                    return
                }

                memory.append(contentsOf: UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self), count: needed))
                memory.withUnsafeBytes { block in
                    processStripe(block, offset: 0)
                }
                memory.removeAll(keepingCapacity: true)
                offset += needed
                remaining -= needed
            }

            while remaining >= 32 {
                processStripe(rawBuffer, offset: offset)
                offset += 32
                remaining -= 32
            }

            if remaining > 0 {
                let pointer = base.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
                memory.append(contentsOf: UnsafeBufferPointer(start: pointer, count: remaining))
            }
        }
    }

    func digest() -> UInt64 {
        var hash: UInt64
        if totalLength >= 32 {
            hash = rotateLeft(v1, by: 1)
                &+ rotateLeft(v2, by: 7)
                &+ rotateLeft(v3, by: 12)
                &+ rotateLeft(v4, by: 18)
            hash = mergeRound(hash, v1)
            hash = mergeRound(hash, v2)
            hash = mergeRound(hash, v3)
            hash = mergeRound(hash, v4)
        } else {
            hash = seed &+ Self.prime5
        }

        hash &+= totalLength

        memory.withUnsafeBytes { rawBuffer in
            var offset = 0
            var remaining = rawBuffer.count

            while remaining >= 8 {
                let k1 = round(0, readUInt64LE(rawBuffer, at: offset))
                hash ^= k1
                hash = rotateLeft(hash, by: 27) &* Self.prime1 &+ Self.prime4
                offset += 8
                remaining -= 8
            }

            if remaining >= 4 {
                hash ^= UInt64(readUInt32LE(rawBuffer, at: offset)) &* Self.prime1
                hash = rotateLeft(hash, by: 23) &* Self.prime2 &+ Self.prime3
                offset += 4
                remaining -= 4
            }

            while remaining > 0 {
                hash ^= UInt64(rawBuffer[offset]) &* Self.prime5
                hash = rotateLeft(hash, by: 11) &* Self.prime1
                offset += 1
                remaining -= 1
            }
        }

        hash ^= hash >> 33
        hash &*= Self.prime2
        hash ^= hash >> 29
        hash &*= Self.prime3
        hash ^= hash >> 32
        return hash
    }

    static func hash(data: Data, seed: UInt64 = 0) -> UInt64 {
        let hasher = XXHash64(seed: seed)
        hasher.update(data)
        return hasher.digest()
    }

    static func hashFile(at url: URL, chunkSize: Int = 1024 * 1024) throws -> UInt64 {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let hasher = XXHash64()
        while true {
            let data = try handle.read(upToCount: chunkSize) ?? Data()
            if data.isEmpty { break }
            hasher.update(data)
        }
        return hasher.digest()
    }

    private func processStripe(_ rawBuffer: UnsafeRawBufferPointer, offset: Int) {
        v1 = round(v1, readUInt64LE(rawBuffer, at: offset))
        v2 = round(v2, readUInt64LE(rawBuffer, at: offset + 8))
        v3 = round(v3, readUInt64LE(rawBuffer, at: offset + 16))
        v4 = round(v4, readUInt64LE(rawBuffer, at: offset + 24))
    }
}

@inline(__always)
private func round(_ accumulator: UInt64, _ input: UInt64) -> UInt64 {
    var acc = accumulator &+ input &* 14_029_467_366_897_019_727
    acc = rotateLeft(acc, by: 31)
    acc &*= 11_400_714_785_074_694_791
    return acc
}

@inline(__always)
private func mergeRound(_ accumulator: UInt64, _ value: UInt64) -> UInt64 {
    var acc = accumulator ^ round(0, value)
    acc = acc &* 11_400_714_785_074_694_791 &+ 9_650_029_242_287_828_579
    return acc
}

@inline(__always)
private func rotateLeft(_ value: UInt64, by amount: UInt64) -> UInt64 {
    (value << amount) | (value >> (64 - amount))
}

@inline(__always)
private func readUInt64LE(_ rawBuffer: UnsafeRawBufferPointer, at offset: Int) -> UInt64 {
    let b0 = UInt64(rawBuffer[offset])
    let b1 = UInt64(rawBuffer[offset + 1]) << 8
    let b2 = UInt64(rawBuffer[offset + 2]) << 16
    let b3 = UInt64(rawBuffer[offset + 3]) << 24
    let b4 = UInt64(rawBuffer[offset + 4]) << 32
    let b5 = UInt64(rawBuffer[offset + 5]) << 40
    let b6 = UInt64(rawBuffer[offset + 6]) << 48
    let b7 = UInt64(rawBuffer[offset + 7]) << 56
    return b0 | b1 | b2 | b3 | b4 | b5 | b6 | b7
}

@inline(__always)
private func readUInt32LE(_ rawBuffer: UnsafeRawBufferPointer, at offset: Int) -> UInt32 {
    let b0 = UInt32(rawBuffer[offset])
    let b1 = UInt32(rawBuffer[offset + 1]) << 8
    let b2 = UInt32(rawBuffer[offset + 2]) << 16
    let b3 = UInt32(rawBuffer[offset + 3]) << 24
    return b0 | b1 | b2 | b3
}
