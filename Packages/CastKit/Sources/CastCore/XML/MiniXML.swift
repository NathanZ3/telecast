import Foundation

/// Minimal DOM node built from `XMLParser` events. Namespace prefixes are stripped
/// from element and attribute names (`s:Envelope` → `Envelope`).
public final class XNode {
    public let name: String
    public internal(set) var attributes: [String: String]
    public internal(set) var text: String = ""
    public internal(set) var children: [XNode] = []

    public init(name: String, attributes: [String: String] = [:]) {
        self.name = name
        self.attributes = attributes
    }

    public func child(_ name: String) -> XNode? {
        children.first { $0.name == name }
    }

    public func children(named name: String) -> [XNode] {
        children.filter { $0.name == name }
    }

    /// Depth-first search for the first descendant with this local name.
    public func descendant(_ name: String) -> XNode? {
        for child in children {
            if child.name == name { return child }
            if let found = child.descendant(name) { return found }
        }
        return nil
    }

    /// Trimmed text of the first child with this name.
    public func value(_ name: String) -> String? {
        child(name).map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

public enum MiniXMLError: Error, Equatable {
    case invalid(String)
}

public enum MiniXML {
    public static func parse(_ data: Data) throws -> XNode {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = builder
        let ok = parser.parse()
        guard ok, let root = builder.root else {
            throw MiniXMLError.invalid(parser.parserError?.localizedDescription ?? "empty document")
        }
        return root
    }

    static func localName(_ qualified: String) -> String {
        guard let colon = qualified.lastIndex(of: ":") else { return qualified }
        return String(qualified[qualified.index(after: colon)...])
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: XNode?
        private var stack: [XNode] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            var attributes: [String: String] = [:]
            for (key, value) in attributeDict {
                attributes[MiniXML.localName(key)] = value
            }
            let node = XNode(name: MiniXML.localName(elementName), attributes: attributes)
            if let parent = stack.last {
                parent.children.append(node)
            } else if root == nil {
                root = node
            }
            stack.append(node)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            _ = stack.popLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if let string = String(data: CDATABlock, encoding: .utf8) {
                stack.last?.text += string
            }
        }
    }
}
