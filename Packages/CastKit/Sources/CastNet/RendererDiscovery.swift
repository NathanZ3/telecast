import Foundation
import CastCore

public struct DiscoveredRenderer: Identifiable, Sendable {
    public var id: String { description.udn }
    public var description: RendererDescription
    public var capabilities: RendererCapabilities

    public init(description: RendererDescription, capabilities: RendererCapabilities) {
        self.description = description
        self.capabilities = capabilities
    }
}

/// Finds DLNA renderers on the Wi-Fi network and reads what they can play.
public final class RendererDiscovery: @unchecked Sendable {
    let transport: HTTPTransport
    let scanner: SSDPScanner

    public init(transport: HTTPTransport = URLSessionTransport(), scanner: SSDPScanner = SSDPScanner()) {
        self.transport = transport
        self.scanner = scanner
    }

    /// Sweeps the Wi-Fi subnet and also re-reads the descriptions of already known TVs.
    public func discover(known: [URL]) async -> [DiscoveredRenderer] {
        var locations = Set(known)
        if let wifi = NetworkInterfaces.wifi() {
            let hosts = SubnetMath.hosts(address: wifi.address, netmask: wifi.netmask)
            castLog("discovery", "Recherche sur \(wifi.name) \(wifi.address)/\(wifi.netmask)")
            let responses = await scanner.scan(hosts: hosts, localAddress: wifi.address, includeMulticast: true)
            for response in responses {
                locations.insert(response.location)
            }
        } else {
            castLog("discovery", "Aucune interface Wi-Fi active")
        }
        return await load(locations: Array(locations))
    }

    /// Manual add: unicast search on one IP, then common description URLs.
    public func probe(ip: String) async -> DiscoveredRenderer? {
        let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SubnetMath.parse(trimmed) != nil else { return nil }
        let responses = await scanner.scan(hosts: [trimmed], localAddress: NetworkInterfaces.wifi()?.address,
                                           includeMulticast: false, listen: 2)
        var candidates = responses.map(\.location)
        for suffix in ["49152/description.xml", "49153/description.xml", "49154/description.xml",
                       "49155/description.xml", "9197/dmr", "52323/dmr.xml"] {
            if let url = URL(string: "http://\(trimmed):\(suffix)") { candidates.append(url) }
        }
        return await withTaskGroup(of: DiscoveredRenderer?.self) { group in
            for url in candidates {
                group.addTask { try? await self.load(descriptionURL: url) }
            }
            for await found in group {
                if let found {
                    group.cancelAll()
                    return found
                }
            }
            return nil
        }
    }

    public func load(descriptionURL: URL) async throws -> DiscoveredRenderer {
        let response = try await transport.send(HTTPRequestSpec(url: descriptionURL, timeout: 4))
        guard (200..<300).contains(response.status) else { throw DLNAError.httpStatus(response.status) }
        let description = try DeviceDescriptionParser.parseRenderer(xml: response.body, descriptionURL: descriptionURL)
        let client = DLNAClient(renderer: description, transport: transport)
        var sink: [ProtocolInfo] = []
        do {
            sink = try await client.protocolInfoSink()
        } catch {
            castLog("discovery", "\(description.friendlyName) : GetProtocolInfo indisponible (\(error))")
        }
        castLog("discovery", "TV trouvée : \(description.friendlyName) (\(description.manufacturer ?? "?") \(description.modelName ?? "")) \(sink.count) formats")
        return DiscoveredRenderer(description: description, capabilities: RendererCapabilities(sink: sink))
    }

    func load(locations: [URL]) async -> [DiscoveredRenderer] {
        await withTaskGroup(of: DiscoveredRenderer?.self) { group in
            for location in locations {
                group.addTask { try? await self.load(descriptionURL: location) }
            }
            var found: [String: DiscoveredRenderer] = [:]
            for await renderer in group {
                if let renderer { found[renderer.id] = renderer }
            }
            return found.values.sorted {
                $0.description.friendlyName.localizedCaseInsensitiveCompare($1.description.friendlyName) == .orderedAscending
            }
        }
    }
}
