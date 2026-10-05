#!/usr/bin/env python3
"""greetd's stand-in for the greeter host in the smoke sandbox.

Usage: greetd.py SOCKET PASSWORD LOG

scripts/smoke/rows/greeter.sh starts this before a greeter host whose
GREETD_SOCK names SOCKET, since Quickshell's Greetd connects once, when
it is first built, and never retries. It binds an AF_UNIX stream socket
at SOCKET, serves one connection after another until it is killed, and
answers greetd's IPC as Quickshell's client speaks it: each message both
ways is a 4-byte length in host byte order, then that many bytes of
UTF-8 JSON. It starts no session and reaches no PAM: the one password is
PASSWORD, and its state is whether a session is being configured, and
whether that session has authenticated.

- create_session asks for the password with a `secret` auth_message.
- post_auth_message_response equal to PASSWORD authenticates the session
  and answers success; any other ends the session and answers an
  `auth_error`.
- start_session on an authenticated session answers success and ends it.
- cancel_session ends the session and answers success.
- A response with no session, a start with no authenticated session and
  any other type answer an `error`.

Each request appends one line to LOG, flushed at once, which the row
reads: `create_session username=U`, `response=right` or `response=wrong`
(never the text), `start_session cmd=JSON env=JSON` (compact JSON),
`cancel_session`, or `refused type=T` for each request it refused.
"""

import json
import socket
import struct
import sys

LENGTH = struct.Struct("=I")


def read_exact(conn, n):
    data = b""
    while len(data) < n:
        chunk = conn.recv(n - len(data))
        if not chunk:
            return None
        data += chunk
    return data


def send(conn, message):
    body = json.dumps(message, separators=(",", ":")).encode()
    conn.sendall(LENGTH.pack(len(body)) + body)


def compact(value):
    return json.dumps(value, separators=(",", ":"))


def serve(conn, password, log):
    session = None  # None, "authenticating" or "authenticated"

    def note(line):
        log.write(line + "\n")
        log.flush()

    def refuse(kind):
        note("refused type=" + kind)
        send(conn, {"type": "error", "error_type": "error", "description": "refused " + kind})

    while True:
        head = read_exact(conn, LENGTH.size)
        if head is None:
            return
        body = read_exact(conn, LENGTH.unpack(head)[0])
        if body is None:
            return
        request = json.loads(body)
        kind = request.get("type")
        if kind == "create_session":
            note("create_session username=" + request["username"])
            session = "authenticating"
            send(conn, {"type": "auth_message", "auth_message_type": "secret", "auth_message": "Password: "})
        elif kind == "post_auth_message_response":
            if session != "authenticating":
                refuse(kind)
            elif request.get("response") == password:
                note("response=right")
                session = "authenticated"
                send(conn, {"type": "success"})
            else:
                note("response=wrong")
                session = None
                send(conn, {"type": "error", "error_type": "auth_error", "description": "pam_authenticate: AUTH_ERR"})
        elif kind == "start_session":
            if session != "authenticated":
                refuse(kind)
            else:
                note("start_session cmd=" + compact(request["cmd"]) + " env=" + compact(request["env"]))
                session = None
                send(conn, {"type": "success"})
        elif kind == "cancel_session":
            note("cancel_session")
            session = None
            send(conn, {"type": "success"})
        else:
            refuse(str(kind))


def main():
    if len(sys.argv) != 4:
        sys.exit("usage: greetd.py SOCKET PASSWORD LOG")
    path, password, log_path = sys.argv[1:]
    with open(log_path, "a", encoding="utf-8") as log:
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(path)
        server.listen(1)
        while True:
            conn, _ = server.accept()
            with conn:
                serve(conn, password, log)


if __name__ == "__main__":
    main()
