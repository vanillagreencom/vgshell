"""The D-Bus wire protocol over AF_UNIX in the Python standard library: the
bus address, EXTERNAL authentication, little-endian marshalling of the
types VGS sends and reads, header fields and message reads and writes
bounded by a deadline. bin/vgshell-scan probes bus names with it and
bin/vgshell-idle-inhibit answers org.freedesktop.ScreenSaver with it, so
VGS depends on no D-Bus binding. Every layout here follows
https://dbus.freedesktop.org/doc/dbus-specification.html.

Every read and write takes a monotonic DEADLINE; a peer that stops reading
or writing past it raises socket.timeout, an OSError. A malformed or
big-endian message raises OSError too.
"""
import os
import socket
import struct
import sys
import time

# Message types and the header field codes this module reads and writes.
METHOD_CALL, METHOD_RETURN, ERROR, SIGNAL = 1, 2, 3, 4
NO_REPLY_EXPECTED = 0x1
PATH, INTERFACE, MEMBER, ERROR_NAME, REPLY_SERIAL, DESTINATION, SENDER, SIGNATURE = 1, 2, 3, 4, 5, 6, 7, 8
BUS_NAME = "org.freedesktop.DBus"
BUS_PATH = "/org/freedesktop/DBus"


def percent_unescape(value):
    out = bytearray()
    i = 0
    data = value.encode("ascii", "surrogateescape")
    while i < len(data):
        if data[i:i + 1] == b"%" and i + 2 < len(data):
            try:
                out.append(int(data[i + 1:i + 3], 16))
                i += 3
                continue
            except ValueError:
                pass
        out.append(data[i])
        i += 1
    return bytes(out)


def bus_address(bus):
    if bus == "system":
        address = os.environ.get("DBUS_SYSTEM_BUS_ADDRESS") or "unix:path=/run/dbus/system_bus_socket"
    else:
        runtime = os.environ.get("XDG_RUNTIME_DIR", "")
        address = os.environ.get("DBUS_SESSION_BUS_ADDRESS") or ("unix:path=" + os.path.join(runtime, "bus"))
    for entry in address.split(";"):
        if not entry.startswith("unix:"):
            continue
        fields = {}
        for part in entry[5:].split(","):
            if "=" not in part:
                continue
            key, value = part.split("=", 1)
            fields[key] = value
        if "path" in fields:
            return percent_unescape(fields["path"]).decode(sys.getfilesystemencoding(), sys.getfilesystemencodeerrors())
        if "abstract" in fields:
            return "\0" + percent_unescape(fields["abstract"]).decode("latin1")
    raise OSError("no supported unix address")


def remaining(deadline):
    return max(0.05, deadline - time.monotonic())


def send(sock, data, deadline):
    sock.settimeout(remaining(deadline))
    sock.sendall(data)


def read_exact(sock, count, deadline):
    data = bytearray()
    while len(data) < count:
        sock.settimeout(remaining(deadline))
        chunk = sock.recv(count - len(data))
        if not chunk:
            raise OSError("connection closed")
        data.extend(chunk)
    return bytes(data)


def read_auth_line(sock, deadline):
    data = bytearray()
    while not data.endswith(b"\r\n"):
        sock.settimeout(remaining(deadline))
        chunk = sock.recv(1)
        if not chunk:
            raise OSError("auth closed")
        data.extend(chunk)
        if len(data) > 4096:
            raise OSError("auth line too long")
    return bytes(data[:-2])


def connect(bus, deadline):
    """A socket on BUS ("session" or "system"), authenticated and past
    Hello, which took serial 1. The caller closes it."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        sock.settimeout(remaining(deadline))
        sock.connect(bus_address(bus))
        # EXTERNAL with no identity: the bus takes the uid it reads from the
        # socket itself, which stays right across user namespaces.
        send(sock, b"\0AUTH EXTERNAL\r\n", deadline)
        line = read_auth_line(sock, deadline)
        if line == b"DATA":
            send(sock, b"DATA\r\n", deadline)
            line = read_auth_line(sock, deadline)
        if not line.startswith(b"OK "):
            raise OSError("auth " + line.decode("ascii", "replace"))
        send(sock, b"BEGIN\r\n", deadline)
        call(sock, 1, "Hello", deadline)
        return sock
    except BaseException:
        sock.close()
        raise


def align(offset, boundary):
    return (boundary - offset % boundary) % boundary


def pack_string(value):
    data = value.encode("utf-8")
    return struct.pack("<I", len(data)) + data + b"\0"


def pack_signature(value):
    data = value.encode("ascii")
    return bytes([len(data)]) + data + b"\0"


def pack_body(signature, values):
    """The body of SIGNATURE, a run of `s`, `u` and `b`, holding VALUES."""
    out = bytearray()
    for code, value in zip(signature, values, strict=True):
        if code == "s":
            out.extend(b"\0" * align(len(out), 4))
            out.extend(pack_string(value))
        elif code in ("u", "b"):
            out.extend(b"\0" * align(len(out), 4))
            out.extend(struct.pack("<I", int(value)))
        else:
            raise ValueError("unsupported body signature " + signature)
    return bytes(out)


def append_field(out, code, signature, value):
    out.extend(b"\0" * align(len(out), 8))
    out.append(code)
    out.extend(pack_signature(signature))
    out.extend(b"\0" * align(len(out), 4))
    if signature in ("s", "o"):
        out.extend(pack_string(value))
    elif signature == "g":
        out.extend(pack_signature(value))
    elif signature == "u":
        out.extend(struct.pack("<I", value))
    else:
        raise ValueError("unsupported header field signature " + signature)


def message(msg_type, serial, fields, signature="", body=b""):
    """One message of MSG_TYPE: FIELDS is a list of (code, signature,
    value) header fields in order; SIGNATURE, when not empty, is added
    last."""
    out = bytearray()
    for code, field_signature, value in fields:
        append_field(out, code, field_signature, value)
    if signature != "":
        append_field(out, SIGNATURE, "g", signature)
    header = bytearray(b"l" + bytes([msg_type]) + b"\x00\x01")
    header.extend(struct.pack("<I", len(body)))
    header.extend(struct.pack("<I", serial))
    header.extend(struct.pack("<I", len(out)))
    header.extend(out)
    header.extend(b"\0" * align(len(header), 8))
    header.extend(body)
    return bytes(header)


def method_call(serial, member, signature="", body=b"", destination=BUS_NAME, path=BUS_PATH, interface=BUS_NAME):
    return message(METHOD_CALL, serial, [(PATH, "o", path), (INTERFACE, "s", interface), (MEMBER, "s", member), (DESTINATION, "s", destination)], signature, body)


def method_return(serial, reply_to, destination, signature="", body=b""):
    return message(METHOD_RETURN, serial, [(REPLY_SERIAL, "u", reply_to), (DESTINATION, "s", destination)], signature, body)


def error(serial, reply_to, destination, name, text):
    return message(ERROR, serial, [(ERROR_NAME, "s", name), (REPLY_SERIAL, "u", reply_to), (DESTINATION, "s", destination)], "s", pack_string(text))


def parse_header_fields(data):
    fields = {}
    offset = 0
    while offset < len(data):
        offset += align(offset, 8)
        if offset >= len(data):
            break
        code = data[offset]
        offset += 1
        sig_len = data[offset]
        offset += 1
        signature = data[offset:offset + sig_len].decode("ascii")
        offset += sig_len + 1
        if signature in ("s", "o"):
            offset += align(offset, 4)
            size = struct.unpack_from("<I", data, offset)[0]
            offset += 4
            fields[code] = data[offset:offset + size].decode("utf-8")
            offset += size + 1
        elif signature == "u":
            offset += align(offset, 4)
            fields[code] = struct.unpack_from("<I", data, offset)[0]
            offset += 4
        elif signature == "g":
            sig_len = data[offset]
            offset += 1
            fields[code] = data[offset:offset + sig_len].decode("ascii")
            offset += sig_len + 1
        else:
            break
    return fields


def read_message(sock, deadline):
    """(type, flags, serial, header fields, body) of the next message."""
    fixed = read_exact(sock, 16, deadline)
    if fixed[0:1] != b"l":
        raise OSError("big-endian reply unsupported")
    msg_type = fixed[1]
    flags = fixed[2]
    body_len, serial, fields_len = struct.unpack_from("<III", fixed, 4)
    rest_len = fields_len + align(16 + fields_len, 8)
    rest = read_exact(sock, rest_len + body_len, deadline)
    fields = parse_header_fields(rest[:fields_len])
    body = rest[rest_len:]
    return msg_type, flags, serial, fields, body


def parse_strings(body, count):
    """The first COUNT strings of a body whose signature opens with that
    many `s`."""
    out = []
    offset = 0
    for _ in range(count):
        offset += align(offset, 4)
        if offset + 4 > len(body):
            raise OSError("short string length")
        length = struct.unpack_from("<I", body, offset)[0]
        offset += 4
        if offset + length + 1 > len(body):
            raise OSError("short string")
        out.append(body[offset:offset + length].decode("utf-8"))
        offset += length + 1
    return out


def parse_uint(body):
    if len(body) < 4:
        raise OSError("short uint32")
    return struct.unpack_from("<I", body, 0)[0]


def parse_string_array(body):
    if len(body) < 4:
        raise OSError("short array reply")
    size = struct.unpack_from("<I", body, 0)[0]
    offset = 4 + align(4, 4)
    end = offset + size
    names = []
    while offset < end:
        if offset + 4 > len(body):
            raise OSError("short string length")
        length = struct.unpack_from("<I", body, offset)[0]
        offset += 4
        if offset + length + 1 > len(body):
            raise OSError("short string")
        names.append(body[offset:offset + length].decode("utf-8"))
        offset += length + 1
        offset += align(offset, 4)
    return names


def call(sock, serial, member, deadline, signature="", body=b"", destination=BUS_NAME, path=BUS_PATH, interface=BUS_NAME):
    """The reply body of one method call; an error reply raises OSError
    naming it. Messages that are not its reply are dropped."""
    send(sock, method_call(serial, member, signature, body, destination, path, interface), deadline)
    while True:
        msg_type, _flags, _serial, fields, body = read_message(sock, deadline)
        if fields.get(REPLY_SERIAL) != serial:
            continue
        if msg_type == ERROR:
            raise OSError("method error " + fields.get(ERROR_NAME, "unknown"))
        if msg_type != METHOD_RETURN:
            raise OSError("unexpected reply type " + str(msg_type))
        return body
