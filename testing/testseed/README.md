# Test seed (QA test builds only)

Built only when `AVALONOS_TEST_BUILD=1` (decision 2026-11-14 11:31 CT: "Strip
the test-seed from release ISOs, keep it for test builds only"). Release
builds never contain this directory's code: `scripts/build-rpms.sh` leaves it
out of Source0, `avalonos.spec` has no `avalonos-testseed` subpackage without
`--with testseed`, `scripts/render-kickstart.sh` adds no seed lines to the
kickstart, and `scripts/verify-iso.sh` fails a release ISO that contains any
seed artifact. See `docs/iso.md` ("Test builds (QA only)").

- `testseed-user`: ExecStartPre of `avalonos-firstboot-user.service`; creates
  the user from an `AVTESTSEED` disk when booted with `avalonos.testseed=1`.
- `50-avalonos-testseed.conf`: the drop-in that runs it.
