#!/usr/bin/env bash
SCRIPT_DIR=$(dirname "$0")
SCRIPT_DIR=${SCRIPT_DIR:-"."}

set -eE

KEYFILE="$SCRIPT_DIR"/lib/mp-reco-2024-05-03.txt

fail() {
	printf "%b\n" "$*" >&2
	exit 1
}

[ -f "$KEYFILE" ] || fail "Could not find required key list at $KEYFILE"

while read keyline; do
	echo "${keyline%;*}"
done <"$KEYFILE"
