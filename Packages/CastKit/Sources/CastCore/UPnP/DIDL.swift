import Foundation

/// DIDL-Lite metadata sent with `SetAVTransportURI` (many TVs refuse an empty one).
public enum DIDL {
    public static func metadata(title: String, url: String, protocolInfo: String, duration: Double? = nil) -> String {
        var resource = "<res protocolInfo=\"\(SOAP.xmlEscape(protocolInfo))\""
        if let duration, duration.isFinite, duration > 0 {
            resource += " duration=\"\(UPnPTime.format(duration)).000\""
        }
        resource += ">\(SOAP.xmlEscape(url))</res>"

        return "<DIDL-Lite xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\" "
            + "xmlns:dc=\"http://purl.org/dc/elements/1.1/\" "
            + "xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\" "
            + "xmlns:dlna=\"urn:schemas-dlna-org:metadata-1-0/\">"
            + "<item id=\"telecast-0\" parentID=\"-1\" restricted=\"1\">"
            + "<dc:title>\(SOAP.xmlEscape(title))</dc:title>"
            + "<upnp:class>object.item.videoItem</upnp:class>"
            + resource
            + "</item></DIDL-Lite>"
    }
}
