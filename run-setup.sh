#!/bin/sh
# Shared downloader for repository and swap setup. It never runs a full install.
set -eu

setup_host=${download_virtualmin_host:-download.virtualmin.com}
mode=${1:-}
case "$mode" in
	repos) url="https://$setup_host/repository" ;;
	swap) url="https://$setup_host/virtualmin-install.sh" ;;
	*) echo '[ERROR] Expected repos or swap setup mode.' >&2; exit 1 ;;
esac
shift

# Match the installer's library channel without consuming its arguments.
slib_host=$setup_host
branch_next=0
for arg do
	if [ "$branch_next" = 1 ]; then
		case "$arg" in
			unstable|testing|development|devel|dev|nightly|bleeding-edge|cutting-edge)
				slib_host=${download_virtualmin_host_dev:-download.virtualmin.dev} ;;
			prerelease|pre-release|rc|release-candidate)
				slib_host=${download_virtualmin_host_rc:-rc.download.virtualmin.dev} ;;
			stable|production|release)
				slib_host=$setup_host ;;
		esac
		branch_next=0
	elif [ "$arg" = --branch ] || [ "$arg" = -B ]; then
		branch_next=1
	fi
done

# Remember the chosen address family for one host, for this run only.
preflight_host=
ip_family=
fetch_content() {
	download_url=$1
	download_host=${download_url#https://}
	download_host=${download_host%%/*}
	set --
	if command -v curl >/dev/null 2>&1; then
		# Reuse address selection for files from the same host.
		if [ "${preflight_host:-}" != "$download_host" ]; then
			preflight_host=$download_host
			ip_family=
			# Slow or unsupported HEAD requests leave normal address selection intact.
			if curl -4 -fsIL --max-time 0.5 -o /dev/null "$download_url" 2>/dev/null; then
				ip_family=-4
			elif curl -6 -fsIL --max-time 0.5 -o /dev/null "$download_url" 2>/dev/null; then
				ip_family=-6
			fi
		fi
		[ -z "$ip_family" ] || set -- "$ip_family"
		curl "$@" -fsSL "$download_url"
	elif command -v wget >/dev/null 2>&1; then
		if [ "${preflight_host:-}" != "$download_host" ]; then
			preflight_host=$download_host
			ip_family=
			# Wget's timeouts cover individual operations; bound each whole probe.
			if command -v timeout >/dev/null 2>&1; then
				if { timeout -s KILL 0.5 wget -4 -q --spider --tries=1 "$download_url"; } >/dev/null 2>&1; then
					ip_family=-4
				elif { timeout -s KILL 0.5 wget -6 -q --spider --tries=1 "$download_url"; } >/dev/null 2>&1; then
					ip_family=-6
				fi
			fi
		fi
		[ -z "$ip_family" ] || set -- "$ip_family"
		wget "$@" -qO- "$download_url"
	elif command -v fetch >/dev/null 2>&1; then
		fetch -qo - "$download_url"
	else
		echo '[ERROR] Neither curl, wget, nor fetch is installed.' >&2
		return 1
	fi
}

# Run downloaded code in its own directory, so it cannot pick up a local
# slib.sh, and keep the installer log outside that directory.
log_dir_path=${log_dir_path:-$PWD}
export log_dir_path
workdir=$(mktemp -d "${TMPDIR:-/tmp}/virtualmin-setup.XXXXXXXXXX") || exit 1
cleanup() {
	rm -rf "$workdir" >/dev/null 2>&1 || :
}
trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if ! fetch_content "$url" >"$workdir/install.sh"; then
	echo '[ERROR] Failed to download the Virtualmin setup script.' >&2
	exit 1
fi
if [ ! -s "$workdir/install.sh" ]; then
	echo '[ERROR] Downloaded script is empty.' >&2
	exit 1
fi
# The installer sources this local library instead of downloading it again.
if ! fetch_content "https://$slib_host/slib.sh" >"$workdir/slib.sh"; then
	echo '[ERROR] Failed to download the Virtualmin utility library.' >&2
	exit 1
fi
if [ ! -s "$workdir/slib.sh" ]; then
	echo '[ERROR] Downloaded utility library is empty.' >&2
	exit 1
fi
# Tell CLI callers the download stage is over only once both files are in place.
if [ "${VIRTUALMIN_SETUP_PROGRESS:-0}" = 1 ]; then
	printf '[SETUP] Download complete\n'
fi
cd "$workdir"
# Keep the installer's own temporary files inside the directory we clean up.
mkdir files
VIRTUALMIN_INSTALL_TEMPDIR=$workdir/files
export VIRTUALMIN_INSTALL_TEMPDIR

# Repository setup keeps its forced-mode guard; swap must clear that guard.
case "$mode" in
	repos) VIRTUALMIN_SETUP_ONLY=1 sh ./install.sh "$@" ;;
	swap) VIRTUALMIN_SETUP_ONLY=0 sh ./install.sh --swap-only "$@" ;;
esac
