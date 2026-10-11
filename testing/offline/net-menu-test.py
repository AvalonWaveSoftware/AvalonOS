#!/usr/bin/env python3
"""Offline regression tests. Usage: python3 net-menu-test.py [path/to/net-menu]."""

import __future__
import ast
import re
import io
import uuid
import os
from pathlib import Path
import shutil
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

# Synthetic public test data, never a real credential.
TEST_PSK = "public-test-psk: with spaces!"
TEST_SSID = "public-test-ssid"
TEST_UUID = "12345678-1234-1234-1234-123456789abc"
HEX_PSK = "ab" * 32
TEST_VPN_PSK = "public-test-vpn-psk!"
TEST_EAP_PW = "public-test-eap-password!"
TEST_VPN_USER = "public-test-user"
TEST_VPN_NAME = "public-test-vpn"
TEST_VPN_GW = "203.0.113.10"
TEST_CERT = "public-test-nss-nick"


def gui_stubs():
    gi = types.ModuleType("gi")
    gi.require_version = Mock()
    repository = types.ModuleType("gi.repository")
    repository.Gtk = types.SimpleNamespace(Window=object, Label=object, Button=object)
    repository.Gdk = types.SimpleNamespace()
    repository.GLib = types.SimpleNamespace()
    repository.Pango = types.SimpleNamespace()
    gi.repository = repository
    return {"gi": gi, "gi.repository": repository}


def assert_no_psk_on_argv(test, argv, password=TEST_PSK):
    test.assertTrue(argv, "empty argv")
    test.assertIn(argv[0], ("nmcli", "iwctl", "systemctl"))
    if argv[0] == "systemctl":
        test.assertEqual(argv, ["systemctl", "is-active", "iwd"])
    test.assertTrue(all(password not in str(arg) for arg in argv))
    test.assertNotIn("password", argv)
    test.assertNotIn("--passphrase", argv)
    test.assertNotIn("--password", argv)
    if argv[0] == "nmcli" and "passwd-file" in argv:
        test.assertIn("connection", argv)
        test.assertIn("up", argv)
        test.assertIn("uuid", argv)
        test.assertNotIn("device", argv)
        test.assertNotIn("connect", argv)
        test.assertNotIn("id", argv)


class NetMenuTests(unittest.TestCase):
    def setUp(self):
        self.gui_patch = patch.dict(sys.modules, gui_stubs())
        self.gui_patch.start()
        self.addCleanup(self.gui_patch.stop)
        self.real_run = subprocess.run
        self.run_patch = patch("subprocess.run", side_effect=AssertionError("unexpected subprocess"))
        self.run_mock = self.run_patch.start()
        self.addCleanup(self.run_patch.stop)
        self.uuid_patch = patch("uuid.uuid4", return_value=uuid.UUID(TEST_UUID))
        self.uuid_patch.start()
        self.addCleanup(self.uuid_patch.stop)
        self._iwd_forget_error = None
        self._iwd_probe_failure = False
        self._iwd_inactive = False
        self._iwd_list_text = ""
        self._iwd_list_rc = 0

    def load(self):
        namespace = {"__name__": "net_menu_under_test", "__file__": str(TARGET)}
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
                    self.load()["main"]()
                self.assertNotEqual(raised.exception.code, 0)
                self.assertIn("XDG_RUNTIME_DIR", str(raised.exception.code))
        self.run_mock.assert_not_called()

    def test_stale_cleanup_follows_instance_check(self):
        for running in (False, True):
            with self.subTest(running=running), tempfile.TemporaryDirectory() as runtime:
                stale = Path(runtime) / "avalonos-nm-stale"
                keep = Path(runtime) / "unrelated-file"
                stale.write_text("stale")
                keep.write_text("keep")
                with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime):
                    menu = self.load()
                    self.assertTrue(stale.exists(), "load must not clean tempfiles")
                    def check_instance():
                        self.assertTrue(stale.exists())
                        return running
                    menu["already_running"] = check_instance
                    # Stop immediately after cleanup for the new instance.
                    menu["GLib"].set_prgname = Mock(side_effect=RuntimeError("stop"))
                    with self.assertRaises(SystemExit if running else RuntimeError):
                        menu["main"]()
                self.assertEqual(stale.exists(), running)
                self.assertTrue(keep.exists())

    def test_psk_validation(self):
        with tempfile.TemporaryDirectory() as runtime:
            with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime):
                menu = self.load()
                accept = menu["psk_acceptable"]
                self.assertTrue(accept(TEST_PSK))
                self.assertTrue(accept(HEX_PSK))
                self.assertTrue(accept("12345678"))
                self.assertFalse(accept("1234567"))
                self.assertFalse(accept("x" * 64))
                self.assertFalse(accept("a" * 65))
                self.assertFalse(accept("pass\nword!!"))
                self.assertFalse(accept("pass\rword!!"))
                self.assertFalse(accept("password" + chr(0) + "xx"))
                self.run_mock.side_effect = AssertionError("nmcli must not run for invalid PSK")
                for bad in ("short", "pass\nword!!", "a" * 65):
                    ok, err = menu["connect_wifi"](TEST_SSID, bad)
                    self.assertFalse(ok)
                    self.assertEqual(err, "invalid password")

    def _password_fake_run(self, runtime, outcome, observed, deleted, add_rc=0, add_uuid=TEST_UUID):
        def fake_run(argv, **kwargs):
            assert_no_psk_on_argv(self, argv)
            if "show" in argv and "connection" in argv:
                # QA-L2: list mode may only ask for UUID,TYPE. A setting
                # field in list mode is the 1.56.1 failure mode (rc=2).
                if "-f" in argv:
                    fields = argv[argv.index("-f") + 1]
                    if "802-11-wireless.ssid" in fields:
                        return subprocess.CompletedProcess(
                            argv, 2, "",
                            "Error: invalid field '802-11-wireless.ssid'; "
                            "allowed fields: NAME,UUID,TYPE,TIMESTAMP,"
                            "TIMESTAMP-REAL,AUTOCONNECT,AUTOCONNECT-PRIORITY,"
                            "READONLY,DBUS-PATH,ACTIVE,DEVICE,STATE,"
                            "ACTIVE-PATH,SLAVE,FILENAME.\n",
                        )
                    if fields == "UUID,TYPE":
                        return subprocess.CompletedProcess(
                            argv, 0,
                            f"{TEST_UUID[:-1]}0:802-11-wireless\n"
                            f"{TEST_UUID}:802-11-wireless\n"
                            f"{TEST_UUID[:-1]}1:802-11-wireless\n"
                            f"{TEST_UUID[:-1]}2:802-11-wireless\n",
                            "",
                        )
                if "-g" in argv and argv[argv.index("-g") + 1] == "802-11-wireless.ssid":
                    uid = argv[argv.index("uuid") + 1]
                    ssid = {
                        TEST_UUID[:-1] + "0": TEST_SSID,
                        TEST_UUID: TEST_SSID,
                        TEST_UUID[:-1] + "1": TEST_SSID,
                        TEST_UUID[:-1] + "2": "other",
                    }.get(uid, "")
                    return subprocess.CompletedProcess(argv, 0, ssid + "\n", "")
                raise AssertionError(f"unexpected connection show argv: {argv}")
            if argv[:3] == ["systemctl", "is-active", "iwd"]:
                if getattr(self, "_iwd_inactive", False):
                    return subprocess.CompletedProcess(argv, 3, "inactive\n", "")
                return subprocess.CompletedProcess(argv, 0, "active\n", "")
            if argv[0] == "iwctl":
                if argv == ["iwctl", "--", "known-networks", "list"]:
                    rc = getattr(self, "_iwd_list_rc", 0)
                    if getattr(self, "_iwd_probe_failure", False):
                        rc = 1
                    return subprocess.CompletedProcess(
                        argv, rc, getattr(self, "_iwd_list_text", "") or "", ""
                    )
                self.assertEqual(argv[:3], ["iwctl", "--", "known-networks"])
                self.assertNotEqual(argv[3], "--", "P-M30: no second -- after known-networks")
                self.assertEqual(argv[4], "forget")
                name = argv[3]
                self.assertTrue(name.startswith(TEST_SSID + ".") or name == TEST_SSID)
                repeated = ("iwctl-forget", name) in observed
                observed.append(("iwctl-forget", name))
                rc = 1 if repeated else 0
                err = "No network with specified parameters was found" if repeated else ""
                if getattr(self, "_iwd_forget_error", None) and name.endswith(self._iwd_forget_error[0]):
                    rc, err = 1, self._iwd_forget_error[1]
                return subprocess.CompletedProcess(argv, rc, "", err)
            if argv[1:3] == ["connection", "add"]:
                self.assertNotIn("passwd-file", argv)
                self.assertIn("wifi-sec.key-mgmt", argv)
                self.assertIn("wpa-psk", argv)
                self.assertIn(TEST_SSID, argv)
                self.assertEqual(argv[argv.index("connection.uuid") + 1], TEST_UUID)
                self.assertIn("con-name", argv)
                name = argv[argv.index("con-name") + 1]
                self.assertTrue(name.startswith("avalonos-"))
                self.assertNotEqual(name, TEST_SSID)
                if outcome == "add_timeout":
                    raise subprocess.TimeoutExpired(argv, 30)
                if add_rc != 0:
                    return subprocess.CompletedProcess(argv, add_rc, "", "test add failure")
                return subprocess.CompletedProcess(
                    argv, 0, f"Connection '{name}' ({add_uuid}) successfully added.\n", ""
                )
            if "up" in argv and "connection" in argv and "passwd-file" in argv:
                self.assertEqual(argv[:7], ["nmcli", "-w", "25", "connection", "up", "uuid", add_uuid])
                self.assertEqual(argv[7], "passwd-file")
                path = Path(argv[8])
                observed.append(path)
                self.assertEqual(path.resolve().parent, Path(runtime).resolve())
                self.assertTrue(path.name.startswith("avalonos-nm-"))
                self.assertTrue(path.is_file())
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
                self.assertEqual(
                    path.read_bytes(),
                    f"802-11-wireless-security.psk:{TEST_PSK}\n".encode(),
                )
                if outcome == "timeout":
                    raise subprocess.TimeoutExpired(argv, 30)
                return subprocess.CompletedProcess(
                    argv, int(outcome == "failure"), "", "test connection failure"
                )
            if "delete" in argv and "connection" in argv:
                if "uuid" in argv:
                    deleted.append(argv[argv.index("uuid") + 1])
                elif "id" in argv:
                    deleted.append(argv[argv.index("id") + 1])
                return subprocess.CompletedProcess(argv, 0, "", "")
            raise AssertionError(f"unexpected nmcli argv: {argv}")
        return fake_run

    def test_password_file_is_private_and_removed(self):
        for outcome in ("success", "failure", "timeout"):
            with self.subTest(outcome=outcome), tempfile.TemporaryDirectory() as runtime, tempfile.TemporaryDirectory() as state:
                with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime, XDG_STATE_HOME=state, HOME=state):
                    menu = self.load()
                    observed, deleted = [], []
                    self.run_mock.side_effect = self._password_fake_run(
                        runtime, outcome, observed, deleted
                    )
                    # P-I24: only a registered menu UUID is eligible for cleanup.
                    if outcome == "success":
                        menu["remember_menu_profile"](TEST_UUID[:-1] + "0")
                    if outcome == "timeout":
                        with self.assertRaises(subprocess.TimeoutExpired):
                            menu["connect_wifi"](TEST_SSID, TEST_PSK)
                    else:
                        result = menu["connect_wifi"](TEST_SSID, TEST_PSK)
                        self.assertEqual(result[0], outcome == "success")
                    passwd_paths = [x for x in observed if not (isinstance(x, tuple) and x and x[0] == "iwctl-forget")]
                    self.assertEqual(len(passwd_paths), 1)
                    self.assertFalse(passwd_paths[0].exists(), "password file survived nmcli")
                    leftovers = [p for p in Path(runtime).iterdir() if p.name.startswith("avalonos-nm-")]
                    self.assertEqual(leftovers, [])
                    if outcome == "success":
                        self.assertEqual(deleted, [TEST_UUID[:-1] + "0"])
                        self.assertTrue(any(x[1].startswith(TEST_SSID + ".") for x in observed if isinstance(x, tuple) and x[0]=="iwctl-forget"))
                    else:
                        self.assertIn(TEST_UUID, deleted)

    def test_add_failure_does_not_activate(self):
        with tempfile.TemporaryDirectory() as runtime:
            with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime):
                menu = self.load()
                observed, deleted = [], []
                self.run_mock.side_effect = self._password_fake_run(
                    runtime, "success", observed, deleted, add_rc=1
                )
                ok, err = menu["connect_wifi"](TEST_SSID, TEST_PSK)
                self.assertFalse(ok)
                self.assertIn("test add failure", err)
                self.assertEqual(observed, [])
                self.assertEqual(list(Path(runtime).iterdir()), [])

    def test_add_timeout_deletes_generated_uuid(self):
        with tempfile.TemporaryDirectory() as runtime, patch.dict(os.environ, XDG_RUNTIME_DIR=runtime):
            menu = self.load()
            observed, deleted = [], []
            self.run_mock.side_effect = self._password_fake_run(runtime, "add_timeout", observed, deleted)
            with self.assertRaises(subprocess.TimeoutExpired):
                menu["connect_wifi"](TEST_SSID, TEST_PSK)
            self.assertEqual(deleted, [TEST_UUID])
            self.assertEqual(list(Path(runtime).iterdir()), [])

    def test_failed_delete_is_reported(self):
        with tempfile.TemporaryDirectory() as runtime, patch.dict(os.environ, XDG_RUNTIME_DIR=runtime):
            menu = self.load()
            fake = self._password_fake_run(runtime, "failure", [], [])
            def fail_delete(argv, **kwargs):
                if argv[1:3] == ["connection", "delete"]:
                    return subprocess.CompletedProcess(argv, 1, "", "failure")
                return fake(argv, **kwargs)
            self.run_mock.side_effect = fail_delete
            with patch("sys.stderr", new_callable=io.StringIO) as stderr:
                self.assertFalse(menu["connect_wifi"](TEST_SSID, TEST_PSK)[0])
                self.assertIn("delete failed", stderr.getvalue())
                self.assertNotIn(TEST_PSK, stderr.getvalue())

    def test_password_path_does_not_up_existing_profile(self):
        # Fold-in of QA 5d: wrong passwd-file must not ride a stored PSK.
        with tempfile.TemporaryDirectory() as runtime:
            with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime):
                menu = self.load()
                observed, deleted = [], []
                self.run_mock.side_effect = self._password_fake_run(
                    runtime, "success", observed, deleted
                )
                ok, err = menu["connect_wifi"](TEST_SSID, TEST_PSK)
                self.assertTrue(ok)
                self.assertEqual(err, "")
                # up must use the newly added UUID, not the pre-existing one
                passwd_paths = [x for x in observed if not (isinstance(x, tuple) and x and x[0] == "iwctl-forget")]
                self.assertEqual(len(passwd_paths), 1)
                self.assertTrue(any(x[1].startswith(TEST_SSID + ".") for x in observed if isinstance(x, tuple) and x[0]=="iwctl-forget"))

    def test_open_network_activates_by_uuid(self):
        with tempfile.TemporaryDirectory() as runtime:
            with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime):
                menu = self.load()
                ups = []

                def fake_run(argv, **kwargs):
                    assert_no_psk_on_argv(self, argv)
                    if "show" in argv and "connection" in argv:
                        if "-f" in argv:
                            self.assertEqual(argv[argv.index("-f") + 1], "UUID,TYPE")
                            return subprocess.CompletedProcess(
                                argv, 0, f"{TEST_UUID}:802-11-wireless\n", ""
                            )
                        if "-g" in argv:
                            self.assertEqual(argv[argv.index("-g") + 1], "802-11-wireless.ssid")
                            self.assertEqual(argv[argv.index("uuid") + 1], TEST_UUID)
                            return subprocess.CompletedProcess(argv, 0, TEST_SSID + "\n", "")
                        raise AssertionError(f"unexpected show argv: {argv}")
                    if "up" in argv:
                        self.assertEqual(
                            argv, ["nmcli", "-w", "25", "connection", "up", "uuid", TEST_UUID]
                        )
                        ups.append(argv)
                        return subprocess.CompletedProcess(argv, 0, "", "")
                    raise AssertionError(f"unexpected nmcli argv: {argv}")

                self.run_mock.side_effect = fake_run
                ok, err = menu["connect_wifi"](TEST_SSID, None)
                self.assertTrue(ok)
                self.assertEqual(err, "")
                self.assertEqual(len(ups), 1)

    def test_cleanup_on_write_or_chmod_error(self):
        for which in ("write", "chmod"):
            with self.subTest(fail=which), tempfile.TemporaryDirectory() as runtime:
                with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime):
                    menu = self.load()
                    observed, deleted = [], []
                    self.run_mock.side_effect = self._password_fake_run(
                        runtime, "success", observed, deleted
                    )
                    boom = OSError("synthetic %s failure" % which)
                    target = "os.write" if which == "write" else "os.chmod"
                    with patch(target, side_effect=boom):
                        with self.assertRaises(OSError):
                            menu["connect_wifi"](TEST_SSID, TEST_PSK)
                    leftovers = [p for p in Path(runtime).iterdir() if p.name.startswith("avalonos-nm-")]
                    self.assertEqual(leftovers, [])
                    self.assertEqual(observed, [])

    @unittest.skipUnless(shutil.which("nmcli"), "nmcli is not on PATH")
    def test_nmcli_accepts_connection_up_passwd_file_syntax(self):
        real_run = self.real_run
        with tempfile.TemporaryDirectory() as runtime:
            with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime):
                menu = self.load()
                results = []

                def run_real(argv, **kwargs):
                    result = real_run(argv, **kwargs)
                    results.append(argv)
                    return result

                self.run_mock.side_effect = run_real
                try:
                    menu["connect_wifi"]("avalonos-offline-test-" + Path(runtime).name, TEST_PSK)
                finally:
                    leftovers = [p for p in Path(runtime).glob("avalonos-nm-*")]
                    self.assertEqual(leftovers, [])
                # At least one real nmcli call should have been a connection up
                # with passwd-file, and none should have been rejected solely
                # for that argument (checked via returning from connect_wifi).
                ups = [a for a in results if "passwd-file" in a]
                self.assertTrue(ups)
                # Best-effort cleanup of any profile the test created.
                for argv in results:
                    if argv[1:3] == ["connection", "add"]:
                        name = argv[argv.index("con-name") + 1]
                        real_run(["nmcli", "connection", "delete", "id", name],
                                 capture_output=True, text=True, timeout=15)


    def test_list_mode_setting_field_is_the_156_failure(self):
        # Fixtures captured on Fedora 44 nmcli 1.56.1-2.fc44 (QA-L2).
        fix = ROOT / "testing/offline/fixtures/nmcli-1.56.1"
        err = (fix / "list-mode-ssid.err").read_text()
        self.assertIn("invalid field '802-11-wireless.ssid'", err)
        self.assertEqual((fix / "list-mode-ssid.rc").read_text().strip(), "2")
        self.assertEqual((fix / "list-mode-ssid.out").read_text(), "")
        self.assertIn("1.56.1", (fix / "version.txt").read_text())

        with tempfile.TemporaryDirectory() as runtime:
            with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime):
                menu = self.load()
                seen = []

                def fake_run(argv, **kwargs):
                    assert_no_psk_on_argv(self, argv, password="unused-psk-xx")
                    if "show" in argv and "connection" in argv and "-f" in argv:
                        fields = argv[argv.index("-f") + 1]
                        seen.append(fields)
                        if "802-11-wireless.ssid" in fields:
                            return subprocess.CompletedProcess(
                                argv, 2, "", err
                            )
                        if fields == "UUID,TYPE":
                            return subprocess.CompletedProcess(
                                argv, 0, f"{TEST_UUID}:802-11-wireless\n", ""
                            )
                    if "show" in argv and "-g" in argv:
                        self.assertIn("-e", argv)
                        self.assertEqual(argv[argv.index("-e") + 1], "no")
                        self.assertEqual(argv[argv.index("-g") + 1], "802-11-wireless.ssid")
                        return subprocess.CompletedProcess(argv, 0, TEST_SSID + "\n", "")
                    raise AssertionError(f"unexpected argv: {argv}")

                self.run_mock.side_effect = fake_run
                got = menu["wifi_uuids_for_ssid"](TEST_SSID)
                self.assertEqual(got, [TEST_UUID])
                self.assertEqual(seen, ["UUID,TYPE"])
                self.assertNotIn("802-11-wireless.ssid", ",".join(seen))

    def test_iwd_forget_on_password_path_only_for_that_ssid(self):
        with tempfile.TemporaryDirectory() as runtime, tempfile.TemporaryDirectory() as state:
            with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime, XDG_STATE_HOME=state, HOME=state):
                menu = self.load()
                observed, deleted = [], []
                self.run_mock.side_effect = self._password_fake_run(
                    runtime, "success", observed, deleted
                )
                self.assertTrue(menu["connect_wifi"](TEST_SSID, TEST_PSK)[0])
                forgets = [x for x in observed if isinstance(x, tuple) and x[0] == "iwctl-forget"]
                self.assertEqual(sorted(forgets), sorted(("iwctl-forget", f"{TEST_SSID}.{typ}") for typ in ("psk", "open", "8021x") for _ in range(2)))

    def test_prefix_only_name_is_not_enough_to_delete(self):
        # P-I24: a user-created profile named avalonos-* must be kept.
        with tempfile.TemporaryDirectory() as runtime, tempfile.TemporaryDirectory() as state:
            with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime, XDG_STATE_HOME=state, HOME=state):
                menu = self.load()
                observed, deleted = [], []
                self.run_mock.side_effect = self._password_fake_run(
                    runtime, "success", observed, deleted
                )
                # Do not pre-register the existing avalonos-named UUID.
                self.assertTrue(menu["connect_wifi"](TEST_SSID, TEST_PSK)[0])
                self.assertNotIn(TEST_UUID[:-1] + "0", deleted)
                self.assertNotIn(TEST_UUID[:-1] + "1", deleted)

    def test_iwd_ssid_filename_encoding(self):
        with tempfile.TemporaryDirectory() as runtime:
            with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime):
                menu = self.load()
                stem = menu["iwd_ssid_config_stem"]
                self.assertEqual(stem("AvalonQA-WPA2"), "AvalonQA-WPA2")
                self.assertEqual(stem("nice_ssid"), "nice_ssid")
                self.assertEqual(stem("Cafe Name"), "Cafe Name")
                self.assertEqual(stem("a/b"), "=" + b"a/b".hex())
                self.assertEqual(stem("ssid.with.dots"), "=" + b"ssid.with.dots".hex())


    def _vpn_fake_run(self, runtime, mode, observed, deleted, profiles=None, active=None):
        # profiles: list of dicts {uuid,name,data,service}
        profiles = list(profiles or [])
        active = set(active or [])
        file_modes = {}

        def fake_run(argv, **kwargs):
            argv = list(argv)
            observed.append(argv)
            assert_no_psk_on_argv(self, argv, password="unused-placeholder-xx")
            for secret in (TEST_VPN_PSK, TEST_EAP_PW, TEST_PSK):
                self.assertTrue(all(secret not in str(arg) for arg in argv))
            self.assertNotIn("password", argv)
            stdout = ""
            rc = 0
            if argv[0] == "nmcli" and argv[1:4] == ["-t", "-f", "UUID,TYPE,NAME"]:
                lines = []
                for row in profiles:
                    lines.append(f"{row['uuid']}:vpn:{row['name']}")
                stdout = "\n".join(lines)
            elif argv[0] == "nmcli" and argv[1:4] == ["-t", "-f", "UUID,TYPE"]:
                lines = []
                for u in active:
                    lines.append(f"{u}:vpn")
                stdout = "\n".join(lines)
            elif argv[0] == "nmcli" and "-g" in argv and argv[argv.index("-g") + 1] == "vpn.service-type":
                self.assertEqual(argv[argv.index("-e") + 1] if "-e" in argv else None, "no")
                uuid_value = argv[argv.index("uuid") + 1]
                match = next((r for r in profiles if r["uuid"] == uuid_value), None)
                stdout = (match or {}).get("service", "org.freedesktop.NetworkManager.libreswan")
            elif argv[0] == "nmcli" and "-g" in argv and argv[argv.index("-g") + 1] == "vpn.data":
                self.assertEqual(argv[argv.index("-e") + 1] if "-e" in argv else None, "no")
                uuid_value = argv[argv.index("uuid") + 1]
                match = next((r for r in profiles if r["uuid"] == uuid_value), None)
                stdout = (match or {}).get("data", "")
            elif argv[:3] == ["nmcli", "connection", "add"]:
                self.assertIn("vpn-type", argv)
                self.assertEqual(argv[argv.index("vpn-type") + 1], "libreswan")
                self.assertNotIn(TEST_VPN_PSK, " ".join(argv))
                self.assertNotIn(TEST_EAP_PW, " ".join(argv))
                if mode == "add-fail":
                    rc = 1
                    stdout = "add failed"
                else:
                    stdout = "Connection added"
            elif argv[0] == "nmcli" and "up" in argv and "passwd-file" in argv:
                path = argv[argv.index("passwd-file") + 1]
                self.assertTrue(str(path).startswith(runtime))
                self.assertTrue(Path(path).is_file())
                file_modes["mode"] = Path(path).stat().st_mode & 0o777
                text = Path(path).read_text()
                observed.append(("passwd-file", text, file_modes["mode"]))
                if mode == "up-fail":
                    rc = 1
                    stdout = "activation failed"
                else:
                    stdout = "Connection successfully activated"
            elif argv[0] == "nmcli" and "up" in argv:
                if mode == "up-fail":
                    rc = 1
                    stdout = "activation failed"
                else:
                    stdout = "Connection successfully activated"
            elif argv[:3] == ["nmcli", "connection", "down"]:
                stdout = "Connection deactivated"
            elif argv[:3] == ["nmcli", "connection", "delete"]:
                deleted.append(argv[argv.index("uuid") + 1] if "uuid" in argv else argv[-1])
            else:
                raise AssertionError(f"unexpected argv {argv}")
            return types.SimpleNamespace(returncode=rc, stdout=stdout, stderr="")

        return fake_run

    def test_vpn_psk_uses_passwd_file_and_never_argv(self):
        with tempfile.TemporaryDirectory() as runtime, tempfile.TemporaryDirectory() as state:
            with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime, XDG_STATE_HOME=state, HOME=state):
                menu = self.load()
                observed, deleted = [], []
                self.run_mock.side_effect = self._vpn_fake_run(runtime, "success", observed, deleted)
                ok, msg = menu["configure_and_connect_libreswan"](
                    TEST_VPN_NAME, TEST_VPN_GW, "psk", psk=TEST_VPN_PSK
                )
                self.assertTrue(ok, msg)
                self.assertEqual(deleted, [])
                ups = [x for x in observed if isinstance(x, tuple) and x[0] == "passwd-file"]
                self.assertEqual(len(ups), 1)
                body, mode = ups[0][1], ups[0][2]
                self.assertEqual(body, f"vpn.secrets.pskvalue:{TEST_VPN_PSK}\n")
                self.assertEqual(mode, 0o600)
                self.assertFalse(any(Path(runtime).glob("avalonos-nm-*")))
                add = next(a for a in observed if isinstance(a, list) and "add" in a)
                data = add[add.index("vpn.data") + 1]
                self.assertIn("right=203.0.113.10", data)
                self.assertIn("ikev2=insist", data)
                self.assertIn("authby=secret", data)
                self.assertIn("pskvalue-flags=2", data)
                self.assertIn("leftmodecfgclient=yes", data)
                self.assertIn("narrowing=yes", data)
                self.assertIn("leftsubnet=0.0.0.0/0", data)
                self.assertNotIn("rightca=", data)
                self.assertNotIn("leftid=", data)
                self.assertNotIn(TEST_VPN_PSK, data)
                registry = Path(state) / "avalonos" / "net-menu.uuids"
                self.assertTrue(registry.is_file())
                self.assertEqual(registry.stat().st_mode & 0o777, 0o600)
                self.assertIn(TEST_UUID, registry.read_text())

    def test_vpn_eap_username_password_is_unsupported(self):
        # QA H-1: Fedora libreswan has no EAP-MSCHAPv2. The option stays
        # selectable but is labeled and refused; no conn is written and
        # no secret is placed on argv, in a passwd-file, or in logs.
        label = "EAP username/password (unsupported)"
        src = TARGET.read_text()
        self.assertIn('vpn_auth.append("eap", EAP_USERNAME_PASSWORD_UNSUPPORTED)', src)
        self.assertEqual(
            self.load()["EAP_USERNAME_PASSWORD_UNSUPPORTED"],
            label,
        )
        with tempfile.TemporaryDirectory() as runtime, tempfile.TemporaryDirectory() as state:
            with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime, XDG_STATE_HOME=state, HOME=state):
                menu = self.load()
                observed, deleted = [], []
                self.run_mock.side_effect = self._vpn_fake_run(runtime, "success", observed, deleted)
                ok, msg = menu["configure_and_connect_libreswan"](
                    TEST_VPN_NAME, TEST_VPN_GW, "eap",
                    username=TEST_VPN_USER, password=TEST_EAP_PW,
                )
                self.assertFalse(ok)
                self.assertEqual(msg, label)
                created, err = menu["add_libreswan_connection"](
                    TEST_VPN_NAME, TEST_VPN_GW, "eap", username=TEST_VPN_USER,
                )
                self.assertIsNone(created)
                self.assertEqual(err, label)
                ok, msg = menu["connect_libreswan"](TEST_UUID, password=TEST_EAP_PW)
                self.assertFalse(ok)
                self.assertEqual(msg, label)
                self.assertEqual(observed, [])
                self.assertEqual(deleted, [])
                self.assertFalse(any(Path(runtime).glob("avalonos-nm-*")))
                joined = " ".join(" ".join(map(str, a)) if isinstance(a, (list, tuple)) else str(a) for a in observed)
                self.assertNotIn(TEST_EAP_PW, joined)
                self.assertNotIn(TEST_VPN_USER, joined)
                self.run_mock.assert_not_called()

    def test_vpn_psk_cert_and_eap_tls_unchanged(self):
        # Certificate auth is the EAP-TLS path (NSS nickname, no password
        # EAP). PSK, cert, and that path must keep the r7 keys and
        # no-secret-on-argv behavior.
        with tempfile.TemporaryDirectory() as runtime, tempfile.TemporaryDirectory() as state:
            with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime, XDG_STATE_HOME=state, HOME=state):
                menu = self.load()
                observed, deleted = [], []
                self.run_mock.side_effect = self._vpn_fake_run(runtime, "success", observed, deleted)
                ok, msg = menu["configure_and_connect_libreswan"](
                    TEST_VPN_NAME, TEST_VPN_GW, "psk", psk=TEST_VPN_PSK
                )
                self.assertTrue(ok, msg)
                psk_add = next(a for a in observed if isinstance(a, list) and "add" in a)
                psk_data = psk_add[psk_add.index("vpn.data") + 1]
                self.assertIn("authby=secret", psk_data)
                self.assertIn("pskvalue-flags=2", psk_data)
                self.assertIn("leftsubnet=0.0.0.0/0", psk_data)
                self.assertIn("leftmodecfgclient=yes", psk_data)
                self.assertIn("narrowing=yes", psk_data)
                self.assertNotIn("leftusername=", psk_data)
                self.assertNotIn(TEST_VPN_PSK, psk_data)
                psk_ups = [x for x in observed if isinstance(x, tuple) and x[0] == "passwd-file"]
                self.assertEqual(psk_ups[0][1], f"vpn.secrets.pskvalue:{TEST_VPN_PSK}\n")
                observed.clear()
                deleted.clear()
                ok, msg = menu["configure_and_connect_libreswan"](
                    TEST_VPN_NAME + "-cert", TEST_VPN_GW, "certificate", cert=TEST_CERT,
                )
                self.assertTrue(ok, msg)
                cert_add = next(a for a in observed if isinstance(a, list) and "add" in a)
                cert_data = cert_add[cert_add.index("vpn.data") + 1]
                self.assertIn(f"leftcert={TEST_CERT}", cert_data)
                self.assertIn("leftid=%fromcert", cert_data)
                self.assertIn("rightca=%same", cert_data)
                self.assertIn("leftsubnet=0.0.0.0/0", cert_data)
                self.assertIn("ikev2=insist", cert_data)
                self.assertNotIn("leftusername=", cert_data)
                self.assertFalse(any(isinstance(x, tuple) and x[0] == "passwd-file" for x in observed))
                joined = " ".join(" ".join(a) for a in observed if isinstance(a, list))
                self.assertNotIn("private-key", joined)
                self.assertNotIn(TEST_VPN_PSK, joined)
                self.assertNotIn(TEST_EAP_PW, joined)
                self.assertEqual(deleted, [])

    def test_vpn_certificate_has_no_secret_or_private_key_on_argv(self):
        with tempfile.TemporaryDirectory() as runtime, tempfile.TemporaryDirectory() as state:
            with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime, XDG_STATE_HOME=state, HOME=state):
                menu = self.load()
                observed, deleted = [], []
                self.run_mock.side_effect = self._vpn_fake_run(runtime, "success", observed, deleted)
                ok, msg = menu["configure_and_connect_libreswan"](
                    TEST_VPN_NAME, TEST_VPN_GW, "certificate", cert=TEST_CERT,
                )
                self.assertTrue(ok, msg)
                self.assertFalse(any(isinstance(x, tuple) and x[0] == "passwd-file" for x in observed))
                add = next(a for a in observed if isinstance(a, list) and "add" in a)
                data = add[add.index("vpn.data") + 1]
                self.assertIn(f"leftcert={TEST_CERT}", data)
                self.assertIn("leftid=%fromcert", data)
                self.assertIn("rightca=%same", data)
                self.assertIn("leftsubnet=0.0.0.0/0", data)
                self.assertIn("ikev2=insist", data)
                joined = " ".join(" ".join(a) for a in observed if isinstance(a, list))
                self.assertNotIn("private-key", joined)
                self.assertNotIn("--password", joined)
                ups = [a for a in observed if isinstance(a, list) and "up" in a]
                self.assertTrue(ups)
                self.assertNotIn("passwd-file", ups[0])

    def test_vpn_failed_activation_deletes_created_profile(self):
        with tempfile.TemporaryDirectory() as runtime, tempfile.TemporaryDirectory() as state:
            with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime, XDG_STATE_HOME=state, HOME=state):
                menu = self.load()
                observed, deleted = [], []
                self.run_mock.side_effect = self._vpn_fake_run(runtime, "up-fail", observed, deleted)
                ok, msg = menu["configure_and_connect_libreswan"](
                    TEST_VPN_NAME, TEST_VPN_GW, "psk", psk=TEST_VPN_PSK
                )
                self.assertFalse(ok)
                self.assertEqual(deleted, [TEST_UUID])

    def test_vpn_rejects_injected_vpn_data_without_calling_nmcli(self):
        with tempfile.TemporaryDirectory() as runtime, tempfile.TemporaryDirectory() as state:
            with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime, XDG_STATE_HOME=state, HOME=state):
                menu = self.load()
                observed, deleted = [], []
                self.run_mock.side_effect = self._vpn_fake_run(runtime, "success", observed, deleted)
                ok, msg = menu["add_libreswan_connection"]("bad,name", TEST_VPN_GW, "psk")
                self.assertIsNone(ok)
                self.assertEqual(observed, [])
                ok, msg = menu["add_libreswan_connection"](TEST_VPN_NAME, "1.2.3.4\nleftupdown=/bin/true", "psk")
                self.assertIsNone(ok)
                self.assertEqual(observed, [])

    def test_vpn_list_does_not_use_list_mode_setting_fields(self):
        with tempfile.TemporaryDirectory() as runtime, tempfile.TemporaryDirectory() as state:
            with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime, XDG_STATE_HOME=state, HOME=state):
                menu = self.load()
                observed, deleted = [], []
                profiles = [{
                    "uuid": TEST_UUID,
                    "name": TEST_VPN_NAME,
                    "data": "right = 203.0.113.10, ikev2 = insist, authby = secret",
                    "service": "org.freedesktop.NetworkManager.libreswan",
                }]
                self.run_mock.side_effect = self._vpn_fake_run(
                    runtime, "success", observed, deleted, profiles=profiles, active={TEST_UUID}
                )
                rows = menu["list_libreswan_profiles"]()
                self.assertEqual(len(rows), 1)
                self.assertEqual(rows[0]["kind"], "psk")
                self.assertEqual(menu["active_vpn_uuids"](), {TEST_UUID})
                for argv in observed:
                    if not isinstance(argv, list) or argv[0] != "nmcli":
                        continue
                    if "-f" in argv:
                        fields = argv[argv.index("-f") + 1]
                        self.assertNotIn("vpn.data", fields)
                        self.assertNotIn("802-11-wireless.ssid", fields)
                    if "-t" in argv and "-g" in argv:
                        self.fail("list-mode get together")

    def test_vpn_connect_existing_psk_and_disconnect(self):
        with tempfile.TemporaryDirectory() as runtime, tempfile.TemporaryDirectory() as state:
            with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime, XDG_STATE_HOME=state, HOME=state):
                menu = self.load()
                observed, deleted = [], []
                self.run_mock.side_effect = self._vpn_fake_run(runtime, "success", observed, deleted)
                ok, msg = menu["connect_libreswan"](TEST_UUID, psk=TEST_VPN_PSK)
                self.assertTrue(ok, msg)
                ok, msg = menu["disconnect_libreswan"](TEST_UUID)
                self.assertTrue(ok, msg)
                downs = [a for a in observed if isinstance(a, list) and "down" in a]
                self.assertEqual(downs[0][downs[0].index("uuid") + 1], TEST_UUID)

    def test_list_mode_vpn_setting_field_is_rejected_by_fixture(self):
        # Same 1.56.1 class of failure as Wi-Fi: do not query vpn.data in list mode.
        fixture = ROOT / "testing/offline/fixtures/nmcli-1.56.1"
        err = (fixture / "list-mode-ssid.err").read_text()
        self.assertIn("invalid field", err)




    def test_ssid_with_colon_and_backslash_unescaped(self):
        # M-1: -e no must be used so "QA:Colon:Net" and backslash SSIDs match.
        colon = "QA:Colon:Net"
        slash = "QA\\Net"
        with tempfile.TemporaryDirectory() as runtime:
            with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime):
                menu = self.load()
                seen = []

                def fake_run(argv, **kwargs):
                    if "-f" in argv and argv[argv.index("-f") + 1] == "UUID,TYPE":
                        return subprocess.CompletedProcess(argv, 0, f"{TEST_UUID}:802-11-wireless\n", "")
                    if "-g" in argv:
                        self.assertEqual(argv[argv.index("-e") + 1] if "-e" in argv else None, "no")
                        seen.append(argv)
                        uid = argv[argv.index("uuid") + 1]
                        return subprocess.CompletedProcess(argv, 0, colon + "\n", "")
                    raise AssertionError(argv)

                self.run_mock.side_effect = fake_run
                self.assertEqual(menu["wifi_uuids_for_ssid"](colon), [TEST_UUID])
                # escaped form must not match
                self.assertEqual(menu["wifi_uuids_for_ssid"]("QA\\:Colon\\:Net"), [])

                def fake_run_slash(argv, **kwargs):
                    if "-f" in argv and argv[argv.index("-f") + 1] == "UUID,TYPE":
                        return subprocess.CompletedProcess(argv, 0, f"{TEST_UUID}:802-11-wireless\n", "")
                    if "-g" in argv:
                        self.assertEqual(argv[argv.index("-e") + 1], "no")
                        return subprocess.CompletedProcess(argv, 0, slash + "\n", "")
                    raise AssertionError(argv)

                self.run_mock.side_effect = fake_run_slash
                self.assertEqual(menu["wifi_uuids_for_ssid"](slash), [TEST_UUID])

    def test_forget_qualifies_types_and_fails_closed(self):
        # M-2: qualify .psk/.open/.8021x; do not connect if forget fails.
        with tempfile.TemporaryDirectory() as runtime, tempfile.TemporaryDirectory() as state:
            with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime, XDG_STATE_HOME=state, HOME=state):
                menu = self.load()
                observed, deleted = [], []
                self._iwd_forget_error = (".psk", "Ambiguous name or not permitted")
                self.run_mock.side_effect = self._password_fake_run(
                    runtime, "success", observed, deleted
                )
                ok, msg = menu["connect_wifi"](TEST_SSID, TEST_PSK)
                self.assertFalse(ok)
                self.assertIn("could not clear saved Wi-Fi credentials", msg)
                self.assertEqual(deleted, [TEST_UUID])
                forgets = [x[1] for x in observed if isinstance(x, tuple) and x[0] == "iwctl-forget"]
                self.assertIn(f"{TEST_SSID}.psk", forgets)
                self.assertIn(f"{TEST_SSID}.open", forgets)
                self.assertIn(f"{TEST_SSID}.8021x", forgets)
                self.assertFalse(any(isinstance(a, Path) for a in observed))

    def test_iwd_not_found_requires_live_service_before_connect(self):
        # P-L31: not-found is clean only when iwd is active AND the
        # parsed list lacks the network. A list rc of 0 is not enough.
        cases = (
            ("inactive", True, False, "", 0, False),
            ("active-absent", False, False, "OtherNet                     psk        no        never\n", 0, True),
            ("active-listed", False, False, f"{TEST_SSID}                     psk        no        never\n", 0, False),
            ("active-list-rc", False, False, "", 1, False),
            ("list-rc0-but-inactive", True, False, "", 0, False),
        )
        for label, inactive, probe_failure, list_text, list_rc, expect_ok in cases:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as runtime, tempfile.TemporaryDirectory() as state:
                with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime, XDG_STATE_HOME=state, HOME=state):
                    menu = self.load()
                    observed, deleted = [], []
                    self._iwd_inactive = inactive
                    self._iwd_probe_failure = probe_failure
                    self._iwd_list_text = list_text
                    self._iwd_list_rc = list_rc
                    self._iwd_forget_error = (".psk", "No network with specified parameters was found")
                    self.run_mock.side_effect = self._password_fake_run(runtime, "success", observed, deleted)
                    ok, _ = menu["connect_wifi"](TEST_SSID, TEST_PSK)
                    self.assertEqual(ok, expect_ok)
                    if expect_ok:
                        self.assertTrue(any(isinstance(a, Path) for a in observed))
                    else:
                        self.assertEqual(deleted, [TEST_UUID])
                        self.assertFalse(any(isinstance(a, Path) for a in observed))

    def test_known_network_list_parser(self):
        menu = self.load()
        listed = menu["known_network_in_iwctl_list"]
        sample = (
            "Known Networks\n"
            "Name                              Security   Hidden    Last connected\n"
            "--------------------------------------------------------------------------------\n"
            "HomeNet                           psk        no        yesterday\n"
            "\\ColonSSID                        open       no        never\n"
        )
        self.assertTrue(listed(sample, "HomeNet.psk"))
        self.assertFalse(listed(sample, "HomeNet.open"))
        self.assertFalse(listed(sample, "Home.psk"))  # substring must not match
        self.assertFalse(listed(sample, "HomeNetX.psk"))
        self.assertTrue(listed(sample, "\\ColonSSID.open"))
        self.assertFalse(listed(sample, "missing.psk"))
        ansi = "\x1b[1mHomeNet\x1b[0m                           psk        no        yesterday\n"
        self.assertTrue(listed(ansi, "HomeNet.psk"))

    def test_iwctl_getopt_semantics(self):
        # Real GNU getopt_long, same short/long options as iwctl (not a
        # mock that accepts any argv). P-L27: without a leading --, a
        # -hSSID is help. P-M30: a single leading -- leaves the name as
        # a positional; a second -- after known-networks becomes the entity.
        root = Path(__file__).resolve().parent
        src = root / "iwctl-getopt-probe.c"
        with tempfile.TemporaryDirectory() as tmp:
            exe = Path(tmp) / "iwctl-getopt-probe"
            compiled = self.real_run(
                ["gcc", "-o", str(exe), str(src)],
                env={k: v for k, v in os.environ.items() if k != "POSIXLY_CORRECT"},
                capture_output=True, text=True,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            def probe(args):
                env = os.environ.copy()
                env.pop("POSIXLY_CORRECT", None)
                ran = self.real_run(
                    [str(exe), *args], env=env, capture_output=True, text=True,
                )
                return ran.returncode, ran.stdout.strip()
            no_rc, no_dash = probe(["known-networks", "-hSSID.psk", "forget"])
            self.assertIn("help=1", no_dash)
            with_rc, with_dash = probe(["--", "known-networks", "-hSSID.psk", "forget"])
            self.assertEqual(with_rc, 0, with_dash)
            self.assertIn("help=0", with_dash)
            self.assertIn("err=0", with_dash)
            self.assertIn("rest=known-networks\t-hSSID.psk\tforget", with_dash)
            double_rc, double = probe(["--", "known-networks", "--", "-hSSID.psk", "forget"])
            self.assertEqual(double_rc, 0, double)
            self.assertIn("help=0", double)
            self.assertIn("err=0", double)
            self.assertIn("rest=known-networks\t--\t-hSSID.psk\tforget", double)

    def test_iwd_option_names_and_confirmation(self):
        menu = self.load()
        for ssid in ("-hSSID", "--other"):
            for behavior in ("real", "help", "absent"):
                with self.subTest(ssid=ssid, behavior=behavior):
                    calls = {}
                    def fake(argv, **kwargs):
                        if argv[:3] == ["systemctl", "is-active", "iwd"]:
                            return subprocess.CompletedProcess(argv, 0, "active\n", "")
                        if argv[-1] == "list":
                            return subprocess.CompletedProcess(argv, 0, "", "")
                        self.assertEqual(argv[:3], ["iwctl", "--", "known-networks"])
                        self.assertNotEqual(argv[3], "--")
                        self.assertTrue(argv[3].startswith(ssid + "."))
                        self.assertEqual(argv[4], "forget")
                        calls[argv[3]] = calls.get(argv[3], 0) + 1
                        absent = behavior == "absent" or (behavior == "real" and calls[argv[3]] == 2)
                        return subprocess.CompletedProcess(argv, 1 if absent else 0, "help" if behavior == "help" else "", "No network with specified parameters was found" if absent else "")
                    self.run_mock.side_effect = fake
                    self.assertEqual(menu["forget_iwd_known_network"](ssid), behavior != "help")
                    self.assertEqual(set(calls.values()), {1 if behavior == "absent" else 2})

    def test_cert_vpn_sets_leftid_fromcert_and_modecfg(self):
        with tempfile.TemporaryDirectory() as runtime, tempfile.TemporaryDirectory() as state:
            with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime, XDG_STATE_HOME=state, HOME=state):
                menu = self.load()
                observed, deleted = [], []
                self.run_mock.side_effect = self._vpn_fake_run(runtime, "success", observed, deleted)
                ok, msg = menu["configure_and_connect_libreswan"](
                    TEST_VPN_NAME, TEST_VPN_GW, "certificate", cert=TEST_CERT,
                )
                self.assertTrue(ok, msg)
                add = next(a for a in observed if isinstance(a, list) and "add" in a)
                data = add[add.index("vpn.data") + 1]
                self.assertIn("leftid=%fromcert", data)
                self.assertIn("leftmodecfgclient=yes", data)
                self.assertIn("narrowing=yes", data)
                self.assertIn("leftsubnet=0.0.0.0/0", data)
                self.assertIn("rightca=%same", data)
                self.assertIn("ikev2=insist", data)

    def test_vpn_data_rejects_controls_and_quotes(self):
        menu = self.load()
        self.assertTrue(menu["_vpn_data_ok"]("ok-name"))
        self.assertFalse(menu["_vpn_data_ok"]("bad,name"))
        self.assertFalse(menu["_vpn_data_ok"]("a=b"))
        self.assertFalse(menu["_vpn_data_ok"]("a\\b"))
        self.assertFalse(menu["_vpn_data_ok"]('a"b'))
        self.assertFalse(menu["_vpn_data_ok"]("a\tb"))
        self.assertFalse(menu["_vpn_gateway_ok"]("bad host"))
        self.assertTrue(menu["_vpn_gateway_ok"]("203.0.113.10"))
        self.assertTrue(menu["_vpn_gateway_ok"]("vpn.example.com"))
        self.assertEqual(menu["vpn_psk_strength_warning"]("shortpsk"), "pre-shared key is under 20 characters")
        self.assertEqual(menu["vpn_psk_strength_warning"]("x" * 20), "")

    def test_registry_rejects_symlink_destination(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, XDG_RUNTIME_DIR=directory):
            menu = self.load()
            root = Path(directory)
            target = root / "target"
            target.write_text("untouched\n")
            registry = root / "registry"
            registry.symlink_to(target)
            menu["_write_registry"](registry, {TEST_UUID})
            self.assertTrue(registry.is_symlink())
            self.assertEqual(target.read_text(), "untouched\n")

    def test_registry_filters_invalid_lines_and_round_trips_uuid(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, XDG_RUNTIME_DIR=directory):
            menu = self.load()
            registry = Path(directory) / "registry"
            registry.write_bytes((TEST_UUID + "\ninvalid\n" + TEST_UUID + "extra\n").encode() + b"\xff\n")
            self.assertEqual(menu["_read_registry_lines"](registry), {TEST_UUID})
            registry.unlink()
            menu["_write_registry"](registry, {TEST_UUID, "invalid"})
            self.assertEqual(menu["_read_registry_lines"](registry), {TEST_UUID})
            self.assertEqual(registry.read_text(), TEST_UUID + "\n")

    def test_nmcli_get_queries_disable_escaping(self):
        tree = ast.parse(TARGET.read_text())
        queries = []
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call) or not node.args:
                continue
            args = node.args[0].elts if isinstance(node.args[0], (ast.List, ast.Tuple)) else node.args
            values = [arg.value if isinstance(arg, ast.Constant) else None for arg in args]
            if values and values[0] == "nmcli" and "-g" in values:
                queries.append(node.lineno)
                self.assertTrue(any(values[i:i + 2] == ["-e", "no"]
                                    for i in range(len(values) - 1)),
                                f"nmcli -g missing -e no at line {node.lineno}")
        self.assertTrue(queries, "no nmcli -g invocations found")

    def test_niri_net_window_default_size(self):
        text = (ROOT / "overlay/etc/niri/config.kdl").read_text()
        # Window rules contain nested size blocks, so locate the matching brace.
        rules = []
        for match in re.finditer(r"\bwindow-rule\s*\{", text):
            depth, end = 1, match.end()
            while depth and end < len(text):
                depth += (text[end] == "{") - (text[end] == "}")
                end += 1
            self.assertEqual(depth, 0, "unclosed niri window rule")
            rule = text[match.end():end - 1]
            if re.search(r'match\s+[^\n]*app-id="\^AvalonOS-net\$"', rule):
                rules.append(rule)
        self.assertEqual(len(rules), 1, "expected exactly one AvalonOS-net rule")
        rule = rules[0]
        for key, expected in (("default-column-width", 420), ("default-window-height", 520)):
            size = re.search(r"\b" + key + r"\s*\{\s*fixed\s+(\d+)\s*;?\s*\}", rule)
            self.assertIsNotNone(size, f"missing {key}")
            self.assertEqual(int(size.group(1)), expected)
        self.assertNotRegex(rule, r"\b(?:min|max)-(?:width|height)\b")

    def test_vpn_pages_are_scrollable_and_resizable(self):
        src = Path(__file__).resolve().parents[2] / "overlay/usr/share/AvalonOS/net-menu"
        text = src.read_text()
        self.assertIn("set_resizable(True)", text)
        self.assertIn("PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC", text)
        self.assertIn("VPN_SIZE = (420, 520)", text)


if __name__ == "__main__":
    unittest.main()
