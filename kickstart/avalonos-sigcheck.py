#!/usr/bin/python3
# AvalonOS installed-package signature verification (Code Security P-M1).
#
#   avalonos-sigcheck.py [--root DIR] KEYFILE...
#
# Cryptographically verifies the header signature of EVERY package in the
# rpmdb of DIR (default /) against a keyring built ONLY from KEYFILE(s) (the
# pinned keys), not from the rpmdb's own gpg-pubkey entries. A package fails
# if it has no OpenPGP header signature, if the signing key is not one of the
# pinned keys, or if the signature/digests do not verify. Headers are read
# with verification off (so rpm cannot silently skip a bad one) and the count
# is cross-checked against the raw rpmdb rows. Exit 0 = all good, 1 = failure.
import os
import sqlite3
import sys

import rpm


def die(msg):
    print("avalonos-sigcheck: " + msg, file=sys.stderr)
    sys.exit(1)


args = sys.argv[1:]
root = "/"
if args[:1] == ["--root"]:
    root, args = args[1], args[2:]
if not args:
    die("usage: avalonos-sigcheck.py [--root DIR] KEYFILE...")

# Keyring from the pinned key files only.
keyring = rpm.keyring()
nkeys = 0
for f in args:
    with open(f, "rb") as fh:
        armor = fh.read()
    try:
        keyring.addKey(rpm.pubkey(armor))
    except Exception as e:  # noqa: BLE001 - any parse error is fatal
        die("cannot load key %s: %s" % (f, e))
    nkeys += 1

# Reader: no verification, so every header in the db is returned.
reader = rpm.TransactionSet(root, rpm._RPMVSF_NOSIGNATURES | rpm._RPMVSF_NODIGESTS)
checker = rpm.TransactionSet(root, 0)
checker.setKeyring(keyring)
checker.setVSFlags(0)

total = 0
pubkeys = 0
bad = []
for h in reader.dbMatch():
    total += 1
    if h["name"] == "gpg-pubkey":
        pubkeys += 1
        continue
    nevra = h["nevra"]
    if not (h[rpm.RPMTAG_RSAHEADER] or h[rpm.RPMTAG_DSAHEADER]
            or (hasattr(rpm, "RPMTAG_OPENPGP") and h[rpm.RPMTAG_OPENPGP])):
        bad.append("%s: UNSIGNED (no OpenPGP header signature)" % nevra)
        continue
    try:
        checker.hdrCheck(h.unload())
    except Exception as e:  # noqa: BLE001 - rpm.error carries the reason
        reason = " ".join(str(e).split())
        bad.append("%s: %s" % (nevra, reason or "signature check failed"))

# Cross-check: every row of the raw rpmdb must have been seen.
dbpath = rpm.expandMacro("%{_dbpath}")
db = os.path.join(root, dbpath.lstrip("/"), "rpmdb.sqlite")
if os.path.exists(db):
    con = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
    rows = con.execute("SELECT COUNT(*) FROM Packages").fetchone()[0]
    con.close()
    if rows != total:
        bad.append("rpmdb has %d package rows but %d headers were read" % (rows, total))
else:
    bad.append("rpmdb %s not found" % db)

checked = total - pubkeys
if bad:
    print("avalonos-sigcheck: FAIL: %d of %d packages not verified by the %d pinned key(s):"
          % (len(bad), checked, nkeys), file=sys.stderr)
    for b in bad:
        print("  " + b, file=sys.stderr)
    sys.exit(1)
print("avalonos-sigcheck: OK: %d packages, every header signature verified against %d pinned key(s)"
      % (checked, nkeys))
