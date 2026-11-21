"""Offline transaction and interruption tests; no root or system writes."""
import sys
sys.dont_write_bytecode = True
import importlib.machinery
import importlib.util
from pathlib import Path
import subprocess
import signal
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]

def load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, str(ROOT / path))
    spec = importlib.util.spec_from_loader(name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod

mu = load('mu', 'overlay/usr/bin/avalonos-make-user')
ts = load('ts', 'testing/testseed/testseed-user')

class Tests(unittest.TestCase):
    def test_transactions(self):
        for stage in ('useradd', 'finish', 'marker', 'marker_interrupt', 'success'):
            with self.subTest(stage=stage), tempfile.TemporaryDirectory() as tmp:
                flag = str(Path(tmp) / 'user-ready')
                users, calls = set(), []
                def run(cmd, **kwargs):
                    calls.append(cmd)
                    if cmd[0] == 'useradd':
                        users.add(cmd[-1])
                        if stage == 'useradd':
                            raise KeyboardInterrupt
                    if cmd[0] == 'userdel':
                        users.discard(cmd[-1])
                    return subprocess.CompletedProcess(cmd, 0)
                def finish(*args):
                    self.assertFalse(Path(flag).exists())
                    if stage == 'finish':
                        raise KeyboardInterrupt
                real_open = open
                def marker_open(*args, **kwargs):
                    fh = real_open(*args, **kwargs)
                    if stage == 'marker_interrupt':
                        fh.close()
                        raise KeyboardInterrupt
                    return fh
                with patch.object(mu, 'open', side_effect=marker_open, create=True), patch.object(mu, 'FLAG', flag), patch.object(mu, 'valid_name', return_value=None), patch.object(mu.subprocess, 'run', side_effect=run), patch.object(mu, '_finish_user', side_effect=finish), patch.object(mu.os, 'makedirs', side_effect=OSError if stage == 'marker' else None):
                    if stage == 'success':
                        mu.create_user('alice', 'secret')
                        self.assertEqual(users, {'alice'})
                        self.assertTrue(Path(flag).exists())
                    else:
                        with self.assertRaises(OSError if stage == 'marker' else KeyboardInterrupt):
                            mu.create_user('alice', 'secret')
                        self.assertFalse(users)
                        self.assertFalse(Path(flag).exists())
                        self.assertEqual(calls[-1], ['userdel', '-r', '--', 'alice'])

    def test_name_taken_is_not_removed(self):
        # useradd exit 9 (name appeared after validation): never userdel it.
        calls = []
        def run(cmd, **kwargs):
            calls.append(cmd)
            return subprocess.CompletedProcess(cmd, 9 if cmd[0] == 'useradd' else 0)
        with tempfile.TemporaryDirectory() as tmp, patch.object(mu, 'FLAG', str(Path(tmp) / 'ready')), patch.object(mu, 'valid_name', return_value=None), patch.object(mu.subprocess, 'run', side_effect=run):
            with self.assertRaises(ValueError):
                mu.create_user('alice', 'secret')
            self.assertFalse(any(c[0] == 'userdel' for c in calls))
            self.assertFalse((Path(tmp) / 'ready').exists())

    def test_bad_names_and_seed(self):
        for name in ('-rf', 'root', 'a b', 'x;id', 'Upper', '$(id)'):
            with self.assertRaises(ValueError):
                mu.create_user(name, 'pw')
        self.assertFalse(any(hasattr(mu, a) for a in ('read_seed', 'seed_requested', 'SEED_LABEL')))
        h = '$6$salt$hash'
        self.assertEqual(ts.parse_seed(f'user=qa\nhash={h}\nupgrade=0', lambda n: None), dict(user='qa', hash=h, upgrade=False))
        self.assertIsNone(ts.parse_seed('user=qa\nhash=plaintext', lambda n: None))
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'cmdline'
            path.write_text('quiet avalonos.testseed=1\n')
            self.assertTrue(ts.seed_requested(str(path)))
            path.write_text('quiet\n')
            self.assertFalse(ts.seed_requested(str(path)))

    def test_signals_ignored_in_children(self):
        saved = {sig: signal.getsignal(sig) for sig in (signal.SIGINT, signal.SIGQUIT, signal.SIGTSTP)}
        def child():
            # exec inherits SIG_IGN, including during useradd/chpasswd/dnf.
            subprocess.run([sys.executable, '-c',
                            'import os, signal; os.kill(os.getpid(), signal.SIGINT)'], check=True)
        try:
            with patch.object(mu.os, 'geteuid', return_value=0), patch.object(mu, 'already_done', return_value=False), patch.object(mu.curses, 'wrapper', side_effect=lambda fn: (child() or 0)), patch.object(mu, 'upgrade_and_reboot', side_effect=child):
                self.assertEqual(mu.main(), 0)
        finally:
            for sig, handler in saved.items():
                signal.signal(sig, handler)

    def test_committed_wrapper_and_upgrade_interruptions(self):
        with tempfile.TemporaryDirectory() as tmp:
            flag = Path(tmp) / 'ready'
            def wrapper(fn):
                flag.touch()
                raise KeyboardInterrupt
            with patch.object(mu, 'FLAG', str(flag)), patch.object(mu.os, 'geteuid', return_value=0), patch.object(mu, 'already_done', return_value=False), patch.object(mu.signal, 'signal'), patch.object(mu.curses, 'wrapper', side_effect=wrapper) as ui, patch.object(mu, 'upgrade_and_reboot', side_effect=[KeyboardInterrupt, EOFError, None]) as upgrade:
                self.assertEqual(mu.main(), 0)
                self.assertEqual(ui.call_count, 1)
                self.assertEqual(upgrade.call_count, 3)

if __name__ == '__main__':
    unittest.main()
