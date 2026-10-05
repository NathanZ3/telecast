import Foundation

/// A UPnP control error (`<UPnPError>` inside a SOAP fault).
public struct SOAPFault: Error, Equatable, Sendable {
    public var code: Int?
    public var detail: String?

    public init(code: Int?, detail: String?) {
        self.code = code
        self.detail = detail
    }
}

/// SOAP 1.1 helpers for UPnP control.
public enum SOAP {
    public static func xmlEscape(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.utf8.count)
        for character in string {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default: result.append(character)
            }
        }
        return result
    }

    public static func envelope(action: String, serviceType: String, arguments: [(String, String)]) -> String {
        var body = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        body += "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" "
        body += "s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">"
        body += "<s:Body><u:\(action) xmlns:u=\"\(serviceType)\">"
        for (name, value) in arguments {
            body += "<\(name)>\(xmlEscape(value))</\(name)>"
        }
        body += "</u:\(action)></s:Body></s:Envelope>"
        return body
    }

    public static func actionHeader(serviceType: String, action: String) -> String {
        "\"\(serviceType)#\(action)\""
    }

    /// Output arguments of `<ActionResponse>`; throws `SOAPFault` when the body is a fault.
    public static func parseResponse(_ data: Data, action: String) throws -> [String: String] {
        let root = try MiniXML.parse(data)
        guard let response = root.descendant("\(action)Response") else {
            if let fault = parseFault(data) { throw fault }
            throw MiniXMLError.invalid("missing \(action)Response")
        }
        var result: [String: String] = [:]
        for child in response.children {
            result[child.name] = child.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    public static func parseFault(_ data: Data) -> SOAPFault? {
        guard let root = try? MiniXML.parse(data), let fault = root.descendant("Fault") else { return nil }
        let upnpError = fault.descendant("UPnPError")
        let code = upnpError?.value("errorCode").flatMap { Int($0) }
        let detail = upnpError?.value("errorDescription") ?? fault.value("faultstring")
        return SOAPFault(code: code, detail: detail)
    }
}
