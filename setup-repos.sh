#!/bin/sh
# setup-repos.sh — runs the upstream Virtualmin repository setup logic
# (downloaded at runtime), passing through args

set -eu

URL_BASE="download.virtualmin.com"
URL_PATH="/repository"
URL="https://${URL_BASE}${URL_PATH}"

fetch_content() {
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$URL"
	elif command -v wget >/dev/null 2>&1; then
		wget -qO- "$URL"
	elif command -v fetch >/dev/null 2>&1; then
		fetch -qo - "$URL"
	else
		echo "Error: Neither curl, wget, nor fetch is installed." >&2
		return 1
	fi
}

tmp="$(mktemp)" || exit 1
cleanup() {
	rm -f "$tmp" >/dev/null 2>&1 || :
}
trap cleanup EXIT HUP INT TERM

fetch_content >"$tmp" || exit 1
[ -s "$tmp" ] || { echo "Error: Downloaded script is empty." >&2; exit 1; }

VIRTUALMIN_SETUP_ONLY=1 sh "$tmp" "$@"
