# shellcheck shell=bash
# shellcheck disable=SC2034  # variables are used by the scripts that source this file
# AvalonOS RPM signing keys, one per build kind (Code Security P-L11; Master
# Chief 2026-11-14 16:15 CT: "Yes, use a separate signing key for test builds.").
#   release (AVALONOS_TEST_BUILD=0): production key; trusts ONLY that key
#   QA test (AVALONOS_TEST_BUILD=1):  TEST key;      trusts ONLY that key
# A release must never contain or trust the test key (and vice versa).
# Sourced by build-rpms.sh, render-kickstart.sh, build-iso.sh, verify-iso.sh
# and check-signatures.sh after they set ROOT.
AV_PROD_NAME=RPM-GPG-KEY-avalonos
AV_PROD_PIN=f0aa82e5feb779364658a18d96508b1357fdab48
AV_TEST_NAME=RPM-GPG-KEY-avalonos-test
AV_TEST_PIN=f2bc6934fb6501b6114177a7e221dd18ae8eaae9
# Key-file names as whole words (the test name extends the production one).
AV_PROD_NAME_RE='RPM-GPG-KEY-avalonos([^-A-Za-z0-9]|$)'
AV_TEST_NAME_RE='RPM-GPG-KEY-avalonos-test'
case "${AVALONOS_TEST_BUILD:-0}" in
    0) AV_KEY_NAME=$AV_PROD_NAME AV_KEY_PIN=$AV_PROD_PIN
       AV_OTHER_NAME_RE=$AV_TEST_NAME_RE AV_OTHER_PIN=$AV_TEST_PIN ;;
    1) AV_KEY_NAME=$AV_TEST_NAME AV_KEY_PIN=$AV_TEST_PIN
       AV_OTHER_NAME_RE=$AV_PROD_NAME_RE AV_OTHER_PIN=$AV_PROD_PIN ;;
    *) echo "AVALONOS_TEST_BUILD must be 0 or 1" >&2; exit 2 ;;
esac
AV_KEY_FILE="$ROOT/keys/$AV_KEY_NAME"
# Short key IDs as rpm prints them in signature headers ("Key ID ...").
AV_KEY_ID="${AV_KEY_PIN: -16}"
AV_OTHER_ID="${AV_OTHER_PIN: -16}"
