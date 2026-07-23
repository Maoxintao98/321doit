import CryptoKit
import Foundation

protocol ChecksumSink: AnyObject {
    func update(_ data: Data)
    func finalize() -> String
}

enum Checksum {
    static func makeSink(
        for algorithm: ChecksumAlgorithm,
        xxHash64Implementation: XXHash64Implementation = .automatic
    ) -> ChecksumSink {
        switch algorithm {
        case .xxhash64:
            return xxHash64Implementation.usesCShim
                ? CShimXXHash64ChecksumSink()
                : SwiftXXHash64ChecksumSink()
        case .md5:
            return CryptoChecksumSink<Insecure.MD5>()
        case .sha1:
            return CryptoChecksumSink<Insecure.SHA1>()
        case .sha256:
            return CryptoChecksumSink<SHA256>()
        }
    }

    static func hash(
        data: Data,
        algorithm: ChecksumAlgorithm,
        xxHash64Implementation: XXHash64Implementation = .automatic
    ) -> String {
        let sink = makeSink(for: algorithm, xxHash64Implementation: xxHash64Implementation)
        sink.update(data)
        return sink.finalize()
    }

    static func hashFile(
        at url: URL,
        algorithm: ChecksumAlgorithm,
        xxHash64Implementation: XXHash64Implementation = .automatic,
        chunkSize: Int = 1024 * 1024,
        bypassCache: Bool = false
    ) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        if bypassCache {
            // Read straight from the storage device rather than the unified
            // buffer cache, so verifying a just-written file checks what
            // actually landed on disk instead of the in-memory copy we wrote.
            _ = fcntl(handle.fileDescriptor, F_NOCACHE, 1)
        }

        let sink = makeSink(for: algorithm, xxHash64Implementation: xxHash64Implementation)
        while true {
            try Task.checkCancellation()
            let data = try handle.read(upToCount: chunkSize) ?? Data()
            if data.isEmpty { break }
            sink.update(data)
        }
        return sink.finalize()
    }
}

private final class CShimXXHash64ChecksumSink: ChecksumSink {
    private let state: OpaquePointer?
    private let fallback: XXHash64?

    init() {
        let created = doit_xxh64_create()
        state = created
        fallback = created == nil ? XXHash64() : nil
    }

    deinit {
        if let state {
            doit_xxh64_free(state)
        }
    }

    func update(_ data: Data) {
        guard !data.isEmpty else { return }
        if let state {
            data.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return }
                doit_xxh64_update(state, base, rawBuffer.count)
            }
        } else {
            fallback?.update(data)
        }
    }

    func finalize() -> String {
        if let state {
            return formatHash(doit_xxh64_digest(state))
        }
        return formatHash(fallback?.digest() ?? XXHash64.hash(data: Data()))
    }
}

private final class SwiftXXHash64ChecksumSink: ChecksumSink {
    private let hasher = XXHash64()

    func update(_ data: Data) {
        hasher.update(data)
    }

    func finalize() -> String {
        formatHash(hasher.digest())
    }
}

private final class CryptoChecksumSink<H: HashFunction>: ChecksumSink {
    private var hasher = H()

    func update(_ data: Data) {
        hasher.update(data: data)
    }

    func finalize() -> String {
        hexString(hasher.finalize())
    }
}

private func hexString<D: ContiguousBytes>(_ digest: D) -> String {
    var output = ""
    digest.withUnsafeBytes { rawBuffer in
        output = rawBuffer.map { String(format: "%02x", $0) }.joined()
    }
    return output
}
