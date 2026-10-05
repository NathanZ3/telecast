import Foundation

/// Approximates the registrable domain (eTLD+1) of a host — good enough to tell
/// whether two hosts belong to the same site without shipping the full public suffix list.
public enum RegistrableDomain {
    static let multiPartSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk", "net.uk",
        "com.au", "net.au", "org.au", "co.nz", "co.jp", "ne.jp", "or.jp",
        "com.br", "com.tr", "co.in", "co.za", "com.mx", "com.ar", "com.cn",
        "com.tw", "com.hk", "co.kr", "com.sg", "com.my", "co.id", "co.il",
        "gouv.fr", "asso.fr", "nom.fr", "com.fr", "tm.fr",
        "com.es", "com.pl", "com.ua", "co.ua", "com.ru",
    ]

    public static func of(_ host: String) -> String {
        var name = host.lowercased()
        if name.hasSuffix(".") { name.removeLast() }
        if isIPAddress(name) { return name }
        if name.hasPrefix("www.") { name.removeFirst(4) }
        let labels = name.split(separator: ".").map(String.init)
        guard labels.count > 2 else { return name }
        let lastTwo = labels.suffix(2).joined(separator: ".")
        if multiPartSuffixes.contains(lastTwo) {
            return labels.suffix(3).joined(separator: ".")
        }
        return lastTwo
    }

    public static func sameSite(_ a: String, _ b: String) -> Bool {
        of(a) == of(b)
    }

    static func isIPAddress(_ host: String) -> Bool {
        if host.contains(":") { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil }
    }
}
