import Foundation

/// Process-independent hashing for persisted IDs and seeded game content.
enum StableHash {
    private static let fnvOffsetBasis: UInt64 = 14_695_981_039_346_656_037
    private static let fnvPrime: UInt64 = 1_099_511_628_211

    static func fnv1a64(_ value: String) -> UInt64 {
        value.utf8.reduce(fnvOffsetBasis) { hash, byte in
            (hash ^ UInt64(byte)) &* fnvPrime
        }
    }
}
