import Foundation

public struct UPnPService: Codable, Hashable, Sendable {
    public var serviceType: String
    public var controlURL: URL
    public var eventSubURL: URL?

    public init(serviceType: String, controlURL: URL, eventSubURL: URL? = nil) {
        self.serviceType = serviceType
        self.controlURL = controlURL
        self.eventSubURL = eventSubURL
    }
}

/// A UPnP MediaRenderer (a TV) and the control endpoints we need.
public struct RendererDescription: Codable, Hashable, Sendable {
    public var udn: String
    public var friendlyName: String
    public var manufacturer: String?
    public var modelName: String?
    public var deviceType: String
    public var descriptionURL: URL
    public var avTransport: UPnPService
    public var renderingControl: UPnPService?
    public var connectionManager: UPnPService?

    public init(udn: String, friendlyName: String, manufacturer: String?, modelName: String?, deviceType: String,
                descriptionURL: URL, avTransport: UPnPService, renderingControl: UPnPService?,
                connectionManager: UPnPService?) {
        self.udn = udn
        self.friendlyName = friendlyName
        self.manufacturer = manufacturer
        self.modelName = modelName
        self.deviceType = deviceType
        self.descriptionURL = descriptionURL
        self.avTransport = avTransport
        self.renderingControl = renderingControl
        self.connectionManager = connectionManager
    }

    public var host: String { descriptionURL.host ?? "" }
}

public enum DeviceDescriptionError: Error, Equatable {
    case noRenderer
    case invalidXML
}

public enum DeviceDescriptionParser {
    /// Finds the first device (root or embedded) exposing an AVTransport service.
    public static func parseRenderer(xml: Data, descriptionURL: URL) throws -> RendererDescription {
        let root: XNode
        do {
            root = try MiniXML.parse(xml)
        } catch {
            throw DeviceDescriptionError.invalidXML
        }
        let base = root.value("URLBase").flatMap { URL(string: $0) } ?? descriptionURL
        guard let device = root.child("device") ?? root.descendant("device"),
              let renderer = findRenderer(in: device, base: base, descriptionURL: descriptionURL) else {
            throw DeviceDescriptionError.noRenderer
        }
        return renderer
    }

    static func findRenderer(in device: XNode, base: URL, descriptionURL: URL) -> RendererDescription? {
        let services = device.child("serviceList")?.children(named: "service") ?? []

        func service(_ keyword: String) -> UPnPService? {
            for node in services {
                guard let type = node.value("serviceType"), type.contains(":service:\(keyword):"),
                      let control = node.value("controlURL"), let controlURL = resolve(control, base: base) else {
                    continue
                }
                let event = node.value("eventSubURL").flatMap { resolve($0, base: base) }
                return UPnPService(serviceType: type, controlURL: controlURL, eventSubURL: event)
            }
            return nil
        }

        if let avTransport = service("AVTransport") {
            return RendererDescription(
                udn: device.value("UDN") ?? descriptionURL.absoluteString,
                friendlyName: device.value("friendlyName") ?? (descriptionURL.host ?? "TV"),
                manufacturer: device.value("manufacturer"),
                modelName: device.value("modelName"),
                deviceType: device.value("deviceType") ?? "",
                descriptionURL: descriptionURL,
                avTransport: avTransport,
                renderingControl: service("RenderingControl"),
                connectionManager: service("ConnectionManager"))
        }
        for embedded in device.child("deviceList")?.children(named: "device") ?? [] {
            if let found = findRenderer(in: embedded, base: base, descriptionURL: descriptionURL) {
                return found
            }
        }
        return nil
    }

    static func resolve(_ value: String, base: URL) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let absolute = URL(string: trimmed), absolute.scheme != nil, absolute.host != nil { return absolute }
        return URL(string: trimmed, relativeTo: base)?.absoluteURL
    }
}
