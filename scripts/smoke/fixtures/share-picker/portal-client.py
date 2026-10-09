#!/usr/bin/env python3
"""Fixture app: public ScreenCast API and the returned PipeWire descriptor.

https://github.com/flatpak/xdg-desktop-portal/blob/main/data/org.freedesktop.portal.ScreenCast.xml
The parent supplies an isolated bus and bounds the process with timeout.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid
import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib


class PortalClient:
    def __init__(self, root):
        self.root = Path(root)
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.interface = "org.freedesktop.portal.ScreenCast"
        self.session = None

    def phase(self, value):
        target = self.root.with_suffix(".phase")
        temporary = target.with_suffix(".next")
        temporary.write_text(value)
        temporary.replace(target)

    def request(self, method, arguments, signature):
        responses = {}
        loop = GLib.MainLoop()
        def response(_bus, _sender, path, _iface, _signal, parameters):
            responses[path] = parameters.unpack()
            loop.quit()
        listener = self.bus.signal_subscribe(
            "org.freedesktop.portal.Desktop", "org.freedesktop.portal.Request",
            "Response", None, None, Gio.DBusSignalFlags.NONE, response)
        try:
            self.phase(method)
            reply = self.bus.call_sync(
                "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
                self.interface, method, GLib.Variant(signature, arguments),
                GLib.VariantType.new("(o)"), Gio.DBusCallFlags.NONE, 30000, None)
            path = reply.unpack()[0]
            while path not in responses:
                loop.run()
            return responses[path]
        finally:
            self.bus.signal_unsubscribe(listener)

    def run(self, consumer, restore_file=None, hold=False):
        nonce = "vgs" + uuid.uuid4().hex
        code, data = self.request("CreateSession", ({
            "handle_token": GLib.Variant("s", nonce + "create"),
            "session_handle_token": GLib.Variant("s", nonce)},), "(a{sv})")
        if code != 0:
            raise RuntimeError("create-session=" + str(code))
        self.session = data["session_handle"]
        options = {"handle_token": GLib.Variant("s", nonce + "select"),
                   "types": GLib.Variant("u", 3), "multiple": GLib.Variant("b", False),
                   "cursor_mode": GLib.Variant("u", 1), "persist_mode": GLib.Variant("u", 2)}
        if restore_file:
            options["restore_token"] = GLib.Variant("s", json.loads(Path(restore_file).read_text())["restore_token"])
        code, _ = self.request("SelectSources", (self.session, options), "(oa{sv})")
        if code != 0:
            self.root.with_suffix(".json").write_text(json.dumps({"response": code, "streams": []}))
            self.phase("cancelled")
            return
        code, data = self.request("Start", (self.session, "", {
            "handle_token": GLib.Variant("s", nonce + "start")}), "(osa{sv})")
        if code != 0:
            raise RuntimeError("start=" + str(code))
        self.root.with_suffix(".json").write_text(json.dumps({"response": code, **data}))
        node, _ = data["streams"][0]
        reply, descriptors = self.bus.call_with_unix_fd_list_sync(
            "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
            self.interface, "OpenPipeWireRemote", GLib.Variant("(oa{sv})", (self.session, {})),
            GLib.VariantType.new("(h)"), Gio.DBusCallFlags.NONE, 30000, None, None)
        descriptor = descriptors.get(reply.unpack()[0])
        try:
            child_env = {key: os.environ[key] for key in ("PATH", "HOME", "XDG_RUNTIME_DIR", "PIPEWIRE_RUNTIME_DIR", "PIPEWIRE_CONFIG_DIR", "DBUS_SESSION_BUS_ADDRESS", "DBUS_SYSTEM_BUS_ADDRESS", "LD_PRELOAD", "VGS_TEST_RUN") if key in os.environ}
            subprocess.run([consumer, str(descriptor), str(node), str(self.root.with_suffix(".ppm"))],
                           env=child_env, stdin=subprocess.DEVNULL, pass_fds=(descriptor,),
                           check=True, timeout=30)
        finally:
            os.close(descriptor)
        if hold:
            self.phase("sharing")
            while not self.root.with_suffix(".stop").exists():
                while GLib.MainContext.default().iteration(False):
                    pass
                time.sleep(0.05)
        self.phase("complete")

    def close(self):
        if self.session:
            self.bus.call_sync("org.freedesktop.portal.Desktop", self.session,
                               "org.freedesktop.portal.Session", "Close", None, None,
                               Gio.DBusCallFlags.NONE, 5000, None)


if __name__ == "__main__":
    client = PortalClient(sys.argv[1])
    try:
        arguments = sys.argv[3:]
        hold = "--hold" in arguments
        arguments = [argument for argument in arguments if argument != "--hold"]
        if len(arguments) > 1:
            raise ValueError("unexpected arguments")
        client.run(sys.argv[2], arguments[0] if arguments else None, hold)
    except Exception as error:
        client.phase("failed")
        print("portal-client: " + str(error), file=sys.stderr)
        raise SystemExit(1)
    finally:
        client.close()
