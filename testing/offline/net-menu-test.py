#!/usr/bin/env python3
"""Offline regression tests. Usage: python3 net-menu-test.py [path/to/net-menu]."""

import __future__
import os
import shutil
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import Mock, patch


ROOT = Path(__file__).resolve().parents[2]
if len(sys.argv) > 1 and not sys.argv[1].startswith("-"):
    TARGET = Path(sys.argv.pop(1)).resolve()
else:
    TARGET = ROOT / "overlay/usr/share/AvalonOS/net-menu"


def gui_stubs():
    # Always stub GI: even an installed Gtk must never open a display here.
    gi = types.ModuleType("gi")
    gi.require_version = Mock()
    repository = types.ModuleType("gi.repository")
    repository.Gtk = types.SimpleNamespace(Window=object, Label=object, Button=object)
    repository.Gdk = types.SimpleNamespace()
    repository.GLib = types.SimpleNamespace()
    repository.Pango = types.SimpleNamespace()
    gi.repository = repository
    return {"gi": gi, "gi.repository": repository}


class NetMenuTests(unittest.TestCase):
    def setUp(self):
        self.gui_patch = patch.dict(sys.modules, gui_stubs())
        self.gui_patch.start()
        self.addCleanup(self.gui_patch.stop)
        # This guard also prevents accidental external commands during loading.
        self.real_run = subprocess.run
        self.run_patch = patch("subprocess.run", side_effect=AssertionError("unexpected subprocess"))
        self.run_mock = self.run_patch.start()
        self.addCleanup(self.run_patch.stop)

    def load(self):
        # A non-main run name skips the application's GUI entry point.
        namespace = {"__name__": "net_menu_under_test", "__file__": str(TARGET)}
        # Defer annotations so the test also runs on Python 3.9 hosts.
        code = compile(TARGET.read_bytes(), str(TARGET), "exec",
                       flags=__future__.annotations.compiler_flag, dont_inherit=True)
        exec(code, namespace)
        return namespace

    def test_missing_runtime_exits_without_tmp_fallback(self):
        for value in (None, ""):
            with self.subTest(runtime=value), patch.dict(os.environ):
                if value is None:
                    os.environ.pop("XDG_RUNTIME_DIR", None)
                else:
                    os.environ["XDG_RUNTIME_DIR"] = value
                with self.assertRaises(SystemExit) as raised:
                    self.load()
                self.assertNotEqual(raised.exception.code, 0)
                self.assertIn("XDG_RUNTIME_DIR", str(raised.exception.code))
        self.run_mock.assert_not_called()

    def test_password_file_is_private_and_removed(self):
        # Synthetic public test data, never a real credential.
        password = "public-test-psk: with spaces!"
        for outcome in ("success", "failure", "timeout"):
            for saved in (False, True):
                with self.subTest(outcome=outcome, saved=saved), tempfile.TemporaryDirectory() as runtime:
                    with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime):
                        menu = self.load()
                        self.assertEqual(menu["PIDFILE"], Path(runtime) / "avalonos-net.pid")
                        observed = []

                        menu["saved_wifi"] = lambda: {"public-test-ssid"} if saved else set()
                        calls = []

                        def fake_run(argv, **kwargs):
                            calls.append(argv)
                            self.assertEqual(argv[0], "nmcli")
                            self.assertTrue(all(password not in arg for arg in argv))
                            self.assertNotIn("password", argv)
                            if argv[1:3] == ["connection", "add"]:
                                self.assertFalse(saved)
                                self.assertEqual(argv, ["nmcli", "connection", "add", "type", "wifi",
                                    "ifname", "*", "con-name", "public-test-ssid", "ssid",
                                    "public-test-ssid", "wifi-sec.key-mgmt", "wpa-psk"])
                                return subprocess.CompletedProcess(argv, 0, "", "")
                            self.assertEqual(argv[:7], ["nmcli", "-w", "25", "connection", "up",
                                                        "id", "public-test-ssid"])
                            self.assertEqual(len(argv), 9)
                            self.assertEqual(argv[7], "passwd-file")
                            path = Path(argv[8])
                            observed.append(path)
                            self.assertEqual(path.resolve().parent, Path(runtime).resolve())
                            self.assertTrue(path.name.startswith("avalonos-nm-"))
                            self.assertTrue(path.is_file())
                            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
                            self.assertEqual(path.read_bytes(),
                                f"802-11-wireless-security.psk:{password}\n".encode())
                            if outcome == "timeout":
                                raise subprocess.TimeoutExpired(argv, 30)
                            return subprocess.CompletedProcess(
                                argv, int(outcome == "failure"), "", "test connection failure"
                            )

                        self.run_mock.side_effect = fake_run
                        if outcome == "timeout":
                            with self.assertRaises(subprocess.TimeoutExpired):
                                menu["connect_wifi"]("public-test-ssid", password)
                        else:
                            result = menu["connect_wifi"]("public-test-ssid", password)
                            self.assertEqual(result[0], outcome == "success")
                        self.assertEqual(len(calls), 1 if saved else 2)
                        self.assertEqual(len(observed), 1)
                        self.assertFalse(observed[0].exists(), "password file survived nmcli")
                        self.assertEqual(list(Path(runtime).iterdir()), [])

    def test_password_file_removed_when_write_or_chmod_fails(self):
        password = "public-test-psk: with spaces!"
        for operation in ("write", "chmod"):
            with self.subTest(operation=operation), tempfile.TemporaryDirectory() as runtime:
                with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime):
                    menu = self.load()
                    menu["saved_wifi"] = lambda: set()
                    with patch.object(menu["os"], operation, side_effect=OSError("test failure")):
                        with self.assertRaises(OSError):
                            menu["connect_wifi"]("public-test-ssid", password)
                    self.assertEqual(list(Path(runtime).glob("avalonos-nm-*")), [])
                    self.run_mock.assert_not_called()

    @unittest.skipUnless(shutil.which("nmcli"), "nmcli is not on PATH")
    def test_nmcli_accepts_connection_up_passwd_file_syntax(self):
        password = "public-test-psk: with spaces!"
        # setUp has patched subprocess.run; use the original saved before the patch.
        real_run = self.real_run
        with tempfile.TemporaryDirectory() as runtime:
            with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime):
                menu = self.load()
                # Avoid creating or activating a real saved connection.
                ssid = "avalonos-offline-test-" + Path(runtime).name
                menu["saved_wifi"] = lambda: {ssid}
                results = []

                def run_real(argv, **kwargs):
                    result = real_run(argv, **kwargs)
                    results.append(result)
                    return result

                self.run_mock.side_effect = run_real
                try:
                    menu["connect_wifi"](ssid, password)
                finally:
                    self.assertEqual(list(Path(runtime).glob("avalonos-nm-*")), [])
                self.assertEqual(len(results), 1)
                output = (results[0].stdout + results[0].stderr).lower()
                self.assertNotIn("invalid extra argument 'passwd-file'", output)


if __name__ == "__main__":
    unittest.main()
