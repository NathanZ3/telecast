import WebKit
import CastCore

/// Installs the bundled ad/popunder blocklist (`blocklist.json`) as a WKContentRuleList.
enum ContentBlocker {
    static var identifier: String {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "telecast-blocklist-\(build)"
    }

    @MainActor
    static func install(on controller: WKUserContentController, enabled: Bool) async {
        controller.removeAllContentRuleLists()
        guard enabled else {
            castLog("adblock", "Bloqueur de pubs désactivé")
            return
        }
        guard let store = WKContentRuleListStore.default() else { return }
        do {
            if let existing = try await store.contentRuleList(forIdentifier: identifier) {
                controller.add(existing)
                castLog("adblock", "Bloqueur de pubs actif")
                return
            }
        } catch {
            // Not compiled yet: compile below.
        }
        guard let url = Bundle.main.url(forResource: "blocklist", withExtension: "json"),
              let json = try? String(contentsOf: url, encoding: .utf8) else {
            castLog("adblock", "blocklist.json introuvable")
            return
        }
        do {
            if let compiled = try await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) {
                controller.add(compiled)
                castLog("adblock", "Bloqueur de pubs compilé et actif")
            }
        } catch {
            castLog("adblock", "Liste anti-pubs invalide : \(error.localizedDescription)")
        }
    }
}
