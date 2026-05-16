import Foundation

enum EmailPrivacy {
    static func masked(_ value: String) -> String {
        let parts = value.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return maskSegment(value, prefixCount: 4, suffixCount: 2) }

        let local = maskLocalPart(String(parts[0]))
        let domain = String(parts[1])
        return "\(local)@\(domain)"
    }

    private static func maskLocalPart(_ value: String) -> String {
        let count = value.count
        if count <= 2 { return value }
        if count <= 4 { return maskSegment(value, prefixCount: 1, suffixCount: 1) }
        if count <= 8 { return maskSegment(value, prefixCount: 3, suffixCount: 1) }
        return maskSegment(value, prefixCount: 4, suffixCount: 2)
    }

    private static func maskSegment(_ value: String, prefixCount: Int, suffixCount: Int) -> String {
        let characters = Array(value)
        guard characters.count > prefixCount + suffixCount else { return value }
        let prefix = String(characters.prefix(prefixCount))
        let suffix = String(characters.suffix(suffixCount))
        return "\(prefix)••\(suffix)"
    }
}
