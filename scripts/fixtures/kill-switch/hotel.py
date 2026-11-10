#!/usr/bin/env python3
"""The hotel network of scripts/test-vpn-kill-switch.sh, run in its own
network namespace on the far end of the laptop's wlan0.

  hotel.py serve IFACE LOG READY
      Write every frame IFACE receives to LOG, one `<hex>` line per frame,
      answer DNS on UDP and TCP port 53 with an empty NOERROR reply, accept
      and close TCP connections on ports 80 and 443, and create READY once
      all of them listen. Runs until it is signalled.

  hotel.py count LOG START
      Print one `<probe>=<frames>` line per probe kind for the frames from
      line START of LOG on, in the order of KINDS below.

  hotel.py echo ADDRESS IDENT SEQ
      Send one ICMP echo request with identifier IDENT and sequence SEQ
      to ADDRESS, and exit 0 when its reply arrives within a second, else
      1. conntrack keys an echo flow by its identifier, so a second call
      with one IDENT, within the 30 s ICMP timeout, sends that flow's
      packet in its original direction; `nft monitor trace` shows the
      second request with the first one's ct id.

tcpdump is not installed on the hosts this runs on, so the capture is an
AF_PACKET socket (packet(7)). Frames the hotel itself sends
(PACKET_OUTGOING) are not written: the capture records what left the
laptop.
"""

import ipaddress
import socket
import struct
import sys
import threading
import time

ETH_P_ALL = 0x0003
PACKET_OUTGOING = 4

# Each probe kind and the frame that carries it: (protocol, destination,
# destination port or ICMP echo type). A destination of None is any.
KINDS = [
    ("ping4", "icmp", "203.0.113.10", 8),
    ("tcp4", "tcp", "203.0.113.10", 80),
    ("tcp4-443", "tcp", "203.0.113.10", 443),
    ("ping6", "icmp6", "2001:db8:ff::10", 128),
    ("tcp6", "tcp", "2001:db8:ff::10", 80),
    ("dns-udp", "udp", None, 53),
    ("dns-tcp", "tcp", None, 53),
    ("lan-ping", "icmp", "192.168.50.1", 8),
    ("marked", "icmp", "203.0.113.20", 8),
    ("peer4", "udp", "203.0.113.51", 51820),
    ("peer6", "udp", "2001:db8:ff::51", 51820),
    ("dhcp4", "udp", None, 67),
    ("dhcp6", "udp", None, 547),
]


def frame_key(frame):
    """(protocol, destination, port or echo type) for a frame, or None."""
    if len(frame) < 14:
        return None
    ethertype = struct.unpack("!H", frame[12:14])[0]
    payload = frame[14:]
    if ethertype == 0x0800 and len(payload) >= 20:
        header = (payload[0] & 0x0F) * 4
        proto = payload[9]
        dest = str(ipaddress.IPv4Address(payload[16:20]))
        body = payload[header:]
        if proto == 1 and body:
            return ("icmp", dest, body[0])
    elif ethertype == 0x86DD and len(payload) >= 40:
        proto = payload[6]
        dest = str(ipaddress.IPv6Address(payload[24:40]))
        body = payload[40:]
        if proto == 58 and body:
            return ("icmp6", dest, body[0])
    else:
        return None
    if proto == 6 and len(body) >= 14:
        # A connection attempt: SYN set, ACK clear.
        if body[13] & 0x12 != 0x02:
            return None
        return ("tcp", dest, struct.unpack("!H", body[2:4])[0])
    if proto == 17 and len(body) >= 8:
        return ("udp", dest, struct.unpack("!H", body[2:4])[0])
    return None


def count(log, start):
    totals = {name: 0 for name, *_ in KINDS}
    with open(log) as lines:
        for number, line in enumerate(lines, 1):
            if number < start:
                continue
            key = frame_key(bytes.fromhex(line.strip()))
            if key is None:
                continue
            for name, proto, dest, port in KINDS:
                if key[0] == proto and key[2] == port and dest in (None, key[1]):
                    totals[name] += 1
    for name, *_ in KINDS:
        print(f"{name}={totals[name]}")


def capture(iface, log):
    raw = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(ETH_P_ALL))
    raw.bind((iface, 0))
    out = open(log, "a", buffering=1)

    def run():
        while True:
            frame, address = raw.recvfrom(65535)
            if address[2] != PACKET_OUTGOING:
                out.write(frame.hex() + "\n")

    return run


def dns_reply(query):
    """An empty NOERROR answer to QUERY, or None for a query too short."""
    if len(query) < 12:
        return None
    ident, flags = struct.unpack("!HH", query[:4])
    qdcount = struct.unpack("!H", query[4:6])[0]
    # QR and RA set, the query's opcode and RD kept, RCODE 0 (RFC 1035 4.1.1).
    return struct.pack("!HHHHHH", ident, 0x8080 | (flags & 0x7900), qdcount, 0, 0, 0) + query[12:]


def listener(kind, port):
    sock = socket.socket(socket.AF_INET6, kind)
    sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("::", port))
    if kind == socket.SOCK_STREAM:
        sock.listen(16)
    return sock


def serve_udp(sock):
    while True:
        query, peer = sock.recvfrom(4096)
        reply = dns_reply(query)
        if reply:
            sock.sendto(reply, peer)


def serve_tcp(sock, dns):
    while True:
        conn, _ = sock.accept()
        with conn:
            if not dns:
                continue
            conn.settimeout(2)
            try:
                size = struct.unpack("!H", conn.recv(2))[0]
                reply = dns_reply(conn.recv(size))
                if reply:
                    conn.sendall(struct.pack("!H", len(reply)) + reply)
            except (OSError, struct.error):
                pass


def serve(iface, log, ready):
    workers = [
        capture(iface, log),
        lambda sock=listener(socket.SOCK_DGRAM, 53): serve_udp(sock),
        lambda sock=listener(socket.SOCK_STREAM, 53): serve_tcp(sock, True),
        lambda sock=listener(socket.SOCK_STREAM, 80): serve_tcp(sock, False),
        lambda sock=listener(socket.SOCK_STREAM, 443): serve_tcp(sock, False),
    ]
    for work in workers:
        threading.Thread(target=work, daemon=True).start()
    open(ready, "w").close()
    threading.Event().wait()


def checksum(data):
    """The internet checksum of RFC 1071."""
    if len(data) % 2:
        data += b"\0"
    total = sum(struct.unpack(f"!{len(data) // 2}H", data))
    total = (total >> 16) + (total & 0xFFFF)
    total += total >> 16
    return ~total & 0xFFFF


def echo(address, ident, seq):
    sock = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_ICMP)
    payload = b"vgs-kill-switch"
    header = struct.pack("!BBHHH", 8, 0, 0, ident, seq)
    sock.sendto(struct.pack("!BBHHH", 8, 0, checksum(header + payload), ident, seq) + payload, (address, 0))
    deadline = time.monotonic() + 1
    while (left := deadline - time.monotonic()) > 0:
        sock.settimeout(left)
        try:
            data, peer = sock.recvfrom(2048)
        except socket.timeout:
            break
        body = data[(data[0] & 0x0F) * 4:]
        if peer[0] != address or len(body) < 8:
            continue
        kind, _, _, got_ident, got_seq = struct.unpack("!BBHHH", body[:8])
        if (kind, got_ident, got_seq) == (0, ident, seq):
            return 0
    return 1


if __name__ == "__main__":
    if sys.argv[1:2] == ["serve"] and len(sys.argv) == 5:
        serve(*sys.argv[2:])
    elif sys.argv[1:2] == ["count"] and len(sys.argv) == 4:
        count(sys.argv[2], int(sys.argv[3]))
    elif sys.argv[1:2] == ["echo"] and len(sys.argv) == 5:
        sys.exit(echo(sys.argv[2], int(sys.argv[3]), int(sys.argv[4])))
    else:
        sys.exit("usage: hotel.py serve IFACE LOG READY | hotel.py count LOG START | hotel.py echo ADDRESS IDENT SEQ")
