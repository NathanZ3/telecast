"""Fake DLNA TV (UPnP MediaRenderer) to test TéléCast without a real TV.

Run it on a PC connected to the same Wi-Fi/box as the iPhone:
    python tools/fake-renderer/fake_renderer.py              # answers discovery, logs every command
    python tools/fake-renderer/fake_renderer.py --play       # also plays what it receives with ffplay
    python tools/fake-renderer/fake_renderer.py --no-hls     # behaves like a TV without HLS support
    python tools/fake-renderer/fake_renderer.py --stop-after 30   # "cuts" playback after 30 s (tests auto-resume)
Then in TéléCast: Ma TV -> Rechercher, or "Ajouter par adresse IP" with this PC's IP.
"""
import argparse
import html
import re
import socket
import struct
import subprocess
import sys
import threading
import time
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UDN = "uuid:" + str(uuid.uuid5(uuid.NAMESPACE_DNS, socket.gethostname() + "-telecast-fake"))
SSDP_GROUP = ("239.255.255.250", 1900)


def log(message):
    print(time.strftime("%H:%M:%S"), message, flush=True)


def lan_ip():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))
        return sock.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        sock.close()


class Renderer:
    def __init__(self, args):
        self.args = args
        self.lock = threading.Lock()
        self.uri = ""
        self.state = "NO_MEDIA_PRESENT"
        self.started_at = None
        self.offset = 0.0
        self.volume = 30
        self.player = None

    def position(self):
        with self.lock:
            if self.state == "PLAYING" and self.started_at is not None:
                elapsed = self.offset + time.time() - self.started_at
                if self.args.stop_after and elapsed - self.offset > self.args.stop_after:
                    self.state = "STOPPED"
                    log("Coupure simulée (--stop-after)")
                return elapsed
            return self.offset

    def set_uri(self, uri):
        with self.lock:
            self.uri = uri
            self.state = "STOPPED"
            self.offset = 0.0
            self.started_at = None
        threading.Thread(target=probe, args=(uri,), daemon=True).start()

    def play(self):
        with self.lock:
            if not self.uri:
                return False
            self.state = "PLAYING"
            self.started_at = time.time()
            uri = self.uri
        if self.args.play:
            self.stop_player()
            try:
                self.player = subprocess.Popen(["ffplay", "-autoexit", "-loglevel", "warning", "-i", uri])
            except OSError as error:
                log(f"ffplay introuvable : {error}")
        return True

    def pause(self):
        with self.lock:
            self.offset = self.position_unlocked()
            self.state = "PAUSED_PLAYBACK"
            self.started_at = None

    def position_unlocked(self):
        if self.state == "PLAYING" and self.started_at is not None:
            return self.offset + time.time() - self.started_at
        return self.offset

    def stop(self):
        with self.lock:
            self.state = "STOPPED"
            self.started_at = None
        self.stop_player()

    def seek(self, seconds):
        with self.lock:
            self.offset = seconds
            if self.state == "PLAYING":
                self.started_at = time.time()

    def stop_player(self):
        if self.player and self.player.poll() is None:
            self.player.terminate()
        self.player = None


def probe(uri):
    """Fetch the first bytes like a TV would and say what they look like."""
    try:
        request = urllib.request.Request(uri, headers={"Range": "bytes=0-4095", "User-Agent": "FakeTV/1.0 DLNADOC/1.50"})
        with urllib.request.urlopen(request, timeout=10) as response:
            data = response.read(4096)
            kind = "inconnu"
            if data.startswith(b"#EXTM3U"):
                kind = "playlist HLS"
            elif data[:1] == b"\x47":
                kind = "flux MPEG-TS"
            elif b"ftyp" in data[:16]:
                kind = "MP4"
            log(f"  -> média joignable : HTTP {response.status}, {response.headers.get('Content-Type')}, {kind}")
    except Exception as error:  # noqa: BLE001
        log(f"  -> média INJOIGNABLE : {error}")


def time_text(seconds):
    seconds = max(0, int(seconds))
    return f"{seconds // 3600}:{seconds % 3600 // 60:02d}:{seconds % 60:02d}"


def parse_time(text):
    parts = text.strip().split(":")
    try:
        if len(parts) == 3:
            return int(parts[0]) * 3600 + int(parts[1]) * 60 + float(parts[2])
        return float(text)
    except ValueError:
        return 0.0


def arg(body, name):
    match = re.search(rf"<{name}>(.*?)</{name}>", body, re.S)
    return html.unescape(match.group(1)) if match else ""


def description_xml(args, base):
    services = [
        ("AVTransport", "urn:schemas-upnp-org:service:AVTransport:1"),
        ("RenderingControl", "urn:schemas-upnp-org:service:RenderingControl:1"),
        ("ConnectionManager", "urn:schemas-upnp-org:service:ConnectionManager:1"),
    ]
    service_xml = "".join(
        f"<service><serviceType>{stype}</serviceType><serviceId>urn:upnp-org:serviceId:{name}</serviceId>"
        f"<SCPDURL>/{name}/scpd.xml</SCPDURL><controlURL>/{name}/control</controlURL>"
        f"<eventSubURL>/{name}/event</eventSubURL></service>"
        for name, stype in services
    )
    return (
        '<?xml version="1.0"?><root xmlns="urn:schemas-upnp-org:device-1-0">'
        "<specVersion><major>1</major><minor>0</minor></specVersion><device>"
        "<deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>"
        f"<friendlyName>{html.escape(args.name)}</friendlyName><manufacturer>TeleCast</manufacturer>"
        f"<modelName>Faux téléviseur</modelName><UDN>{UDN}</UDN><serviceList>{service_xml}</serviceList>"
        "</device></root>"
    )


def make_handler(args, renderer, base):
    class Handler(BaseHTTPRequestHandler):
        server_version = "FakeTV/1.0 UPnP/1.0"

        def log_message(self, *_):
            pass

        def send_xml(self, status, body):
            data = body.encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", 'text/xml; charset="utf-8"')
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if self.path.startswith("/description.xml"):
                self.send_xml(200, description_xml(args, base))
            else:
                self.send_xml(404, "<error/>")

        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length).decode("utf-8", "replace")
            action_header = self.headers.get("SOAPAction", "").strip('"')
            service, _, action = action_header.partition("#")
            outputs = {}
            fault = None
            if action == "SetAVTransportURI":
                uri = arg(body, "CurrentURI")
                log(f"SetAVTransportURI {uri}")
                if args.no_hls and ".m3u8" in uri:
                    fault = (714, "Illegal MIME-type")
                else:
                    renderer.set_uri(uri)
            elif action == "Play":
                log("Play")
                if not renderer.play():
                    fault = (701, "Transition not available")
            elif action == "Pause":
                log("Pause")
                renderer.pause()
            elif action == "Stop":
                log("Stop")
                renderer.stop()
            elif action == "Seek":
                target = arg(body, "Target")
                log(f"Seek {target}")
                renderer.seek(parse_time(target))
            elif action == "GetTransportInfo":
                renderer.position()
                outputs = {"CurrentTransportState": renderer.state, "CurrentTransportStatus": "OK", "CurrentSpeed": "1"}
            elif action == "GetPositionInfo":
                position = renderer.position()
                outputs = {"Track": "1", "TrackDuration": "0:00:00", "TrackMetaData": "", "TrackURI": html.escape(renderer.uri),
                           "RelTime": time_text(position), "AbsTime": time_text(position), "RelCount": "0", "AbsCount": "0"}
            elif action == "GetMediaInfo":
                outputs = {"NrTracks": "1", "CurrentURI": html.escape(renderer.uri)}
            elif action == "GetProtocolInfo":
                sink = args.sink
                if args.no_hls:
                    sink = ",".join(item for item in sink.split(",") if "mpegurl" not in item.lower())
                outputs = {"Source": "", "Sink": sink}
            elif action == "GetVolume":
                outputs = {"CurrentVolume": str(renderer.volume)}
            elif action == "SetVolume":
                renderer.volume = int(arg(body, "DesiredVolume") or renderer.volume)
                log(f"Volume {renderer.volume}")
            elif action in ("GetMute", "SetMute"):
                outputs = {"CurrentMute": "0"} if action == "GetMute" else {}
            else:
                fault = (401, "Invalid Action")
            if fault:
                log(f"  -> refus {fault[0]} {fault[1]}")
                self.send_xml(500, (
                    '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault>'
                    "<faultcode>s:Client</faultcode><faultstring>UPnPError</faultstring><detail>"
                    f'<UPnPError xmlns="urn:schemas-upnp-org:control-1-0"><errorCode>{fault[0]}</errorCode>'
                    f"<errorDescription>{fault[1]}</errorDescription></UPnPError></detail></s:Fault></s:Body></s:Envelope>"))
                return
            inner = "".join(f"<{key}>{value}</{key}>" for key, value in outputs.items())
            self.send_xml(200, (
                '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
                's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>'
                f'<u:{action}Response xmlns:u="{service}">{inner}</u:{action}Response></s:Body></s:Envelope>'))

    return Handler


def ssdp_responder(location, stop):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(("", 1900))
    except OSError as error:
        log(f"Port SSDP 1900 indisponible ({error}) : utilise « Ajouter par adresse IP » dans l'appli.")
        return
    try:
        membership = struct.pack("4s4s", socket.inet_aton(SSDP_GROUP[0]), socket.inet_aton(lan_ip()))
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, membership)
    except OSError as error:
        log(f"Multicast SSDP indisponible ({error}), réponses unicast seulement")
    sock.settimeout(1)
    wanted = ("ssdp:all", "upnp:rootdevice", "urn:schemas-upnp-org:device:MediaRenderer:1", UDN)
    while not stop.is_set():
        try:
            data, sender = sock.recvfrom(4096)
        except socket.timeout:
            continue
        text = data.decode("utf-8", "replace")
        if not text.startswith("M-SEARCH"):
            continue
        target = re.search(r"(?im)^ST:\s*(.+)$", text)
        st = target.group(1).strip() if target else ""
        if st not in wanted:
            continue
        reply = (
            "HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nEXT:\r\n"
            f"LOCATION: {location}\r\nSERVER: FakeTV/1.0 UPnP/1.0\r\nST: {st}\r\nUSN: {UDN}::{st}\r\n\r\n"
        )
        sock.sendto(reply.encode(), sender)
        log(f"Découverte : réponse envoyée à {sender[0]} ({st})")


def main():
    parser = argparse.ArgumentParser(description="Faux téléviseur DLNA pour tester TéléCast")
    parser.add_argument("--port", type=int, default=49152)
    parser.add_argument("--name", default="Faux téléviseur (PC)")
    parser.add_argument("--play", action="store_true", help="lire le flux reçu avec ffplay")
    parser.add_argument("--no-hls", action="store_true", help="refuser le HLS comme certaines TV")
    parser.add_argument("--stop-after", type=float, default=0, help="simuler une coupure après N secondes")
    parser.add_argument("--sink", default="http-get:*:video/mp4:*,http-get:*:video/mpeg:*,http-get:*:video/mp2t:*,"
                                          "http-get:*:application/vnd.apple.mpegurl:*")
    args = parser.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    ip = lan_ip()
    base = f"http://{ip}:{args.port}"
    location = f"{base}/description.xml"
    renderer = Renderer(args)
    server = ThreadingHTTPServer(("0.0.0.0", args.port), make_handler(args, renderer, base))
    stop = threading.Event()
    threading.Thread(target=ssdp_responder, args=(location, stop), daemon=True).start()
    log(f"Faux téléviseur « {args.name} » prêt : {location}")
    log(f"Dans TéléCast : Rechercher les TV, ou Ajouter par adresse IP = {ip}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        renderer.stop_player()
        server.server_close()


if __name__ == "__main__":
    main()
