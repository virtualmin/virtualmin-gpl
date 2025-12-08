#!/bin/sh
# shellcheck disable=SC2059 disable=SC2181 disable=SC2154 disable=SC2317 disable=SC2034 disable=SC2329
# virtualmin-install.sh
# Copyright 2005-2026 Virtualmin
# Simple script to install Virtualmin on a supported OS

# Different installation guides are available at:
# https://www.virtualmin.com/docs/installation/guides

# License and version
SERIAL=GPL
KEY=GPL
VER=8.0.0
vm_version=8

# Server
download_virtualmin_host="${download_virtualmin_host:-download.virtualmin.com}"
download_virtualmin_host_lib="$download_virtualmin_host"
download_virtualmin_host_dev="${download_virtualmin_host_dev:-software.virtualmin.dev}"
download_virtualmin_host_rc="${download_virtualmin_host_rc:-rc.software.virtualmin.dev}"
download_webmin_host="${download_webmin_host:-download.webmin.com}"
download_webmin_host_dev="${download_webmin_host_dev:-download.webmin.dev}"
download_webmin_host_rc="${download_webmin_host_rc:-rc.download.webmin.dev}"

# Save current working directory
pwd="$PWD"

# License file
virtualmin_license_file="/etc/virtualmin-license"

# Script name
if [ "$0" = "--" ] || [ -z "$0" ]; then
  script_name="virtualmin-install.sh"
else
  script_name=$(basename -- "$0")
fi

# Set log type
log_file_name="${install_log_file_name:-virtualmin-install}"

# Set defaults
branch='stable'
bundle='LAMP'        # Other option is LEMP
mode="${mode:-full}" # Other option is mini
skipyesno=0

usage() {
  # shellcheck disable=SC2046
  echo
  printf "Usage: %s [options]\\n" "$(basename "$0")"
  echo
  echo "  If called without arguments, installs Virtualmin with default options."
  echo
  printf "  --bundle|-b <LAMP|LEMP>          bundle to install (default: LAMP)\\n"
  printf "  --type|-t <full|mini>            install type (default: full)\\n"
  echo
  printf "  --branch|-B <stable|prerelease|unstable>\\n"
  printf "                                   install branch (default: stable)\\n"
  printf "  --os-grade|-g <A|B>              operating system support grade (default: A)\\n"
  echo
  printf "  --module|-o                      load custom module in post-install phase\\n"
  echo
  printf "  --hostname|-n                    force hostname during install\\n"
  printf "  --no-package-updates|-x          skip package updates during install\\n"
  echo
  printf "  --setup|-s                       reconfigure repos without installing\\n"
  printf "  --connect|-C <ipv4|ipv6>         test connectivity without installing\\n"
  echo
  printf "  --insecure-downloads|-i          skip SSL certificate check for downloads\\n"
  echo
  printf "  --uninstall|-u                   remove all packages and dependencies\\n"
  echo
  printf "  --force|-f|--yes|-y              assume \"yes\" to all prompts\\n"
  printf "  --force-reinstall|-fr            force complete reinstall (not recommended)\\n"
  printf "  --no-banner|-nb                  suppress installation messages and warnings\\n"
  printf "  --verbose|-v                     enable verbose mode\\n"
  printf "  --version|-V                     show installer version\\n"
  printf "  --help|-h                        show this help\\n"
  echo
}

# Bind hooks
bind_hook() {
    hook="$1"
    shift
    pre_hook="pre_hook__$hook"
    post_hook="post_hook__$hook"
    # Do we want to completely override the original function?
    if command -v "hook__$hook" > /dev/null 2>&1; then
        "hook__$hook" "$@"
    # Or do we want to run the original function wrapped by third-party functions?
    else
        if command -v "$pre_hook" > /dev/null 2>&1; then
            "$pre_hook" "$@"
        fi
        if command -v "$hook" > /dev/null 2>&1; then
            "$hook" "$@"
        fi
        if command -v "$post_hook" > /dev/null 2>&1; then
            "$post_hook" "$@"
        fi
    fi
}

test_connection() {
  input="$1"
  ip_version="$2"
  ip_version_nice=$(echo "$ip_version" | sed 's/ip/IP/')
  timeout=5
  http_protocol="http"
  http_protocol_nice=$(echo "$http_protocol" | tr '[:lower:]' '[:upper:]')

  # Setup colors for messages
  GREEN="" BLACK="" RED="" RESET="" BOLD="" GRBG="" REDBG=""
  if command -pv 'tput' > /dev/null; then
    GREEN=$(tput setaf 2)
    BLACK=$(tput setaf 0)
    RED=$(tput setaf 1)
    RESET=$(tput sgr0)
    BOLD=$(tput bold)
    GRBG=$(tput setab 22; tput setaf 10)
    REDBG=$(tput setab 52; tput setaf 9)
  fi

  # Extract the domain from the input
  domain=$(echo "$input" | awk -F[/:] '{print $4}')
  [ -z "$domain" ] && domain="$input"

  # Validate parameters
  if [ -z "$domain" ] || [ -z "$ip_version" ]; then
    echo "${RED}[ERROR]  ${RESET} Domain and IP version are required" >&2
    return 1
  fi

  # Setup protocol-specific flags
  case "$ip_version" in
    ipv4)
      if ! getent ahostsv4 "$domain" >/dev/null 2>&1; then
        echo "${RED}[ERROR]  ${RESET} ${BOLD}$domain${RESET} — cannot find IPv4 address" >&2
        return 1
      fi
      ping_cmd="ping -c 1 -W $timeout $domain"
      http_cmd="curl -sS --ipv4 --max-time $timeout --head $http_protocol://$domain \
        || wget --spider -4 -T $timeout $http_protocol://$domain"
      ;;
    ipv6)
      if ! getent ahostsv6 "$domain" >/dev/null 2>&1; then
        echo "${RED}[ERROR]  ${RESET} ${BOLD}$domain${RESET} — cannot find IPv6 address" >&2
        return 1
      fi
      ping_cmd="ping6 -c 1 -W $timeout $domain"
      http_cmd="curl -sS --ipv6 --max-time $timeout --head $http_protocol://$domain \
        || wget --spider -6 -T $timeout $http_protocol://$domain"
      ;;
  esac

  # Try ping first
  if eval "$ping_cmd" >/dev/null 2>&1; then
    echo "${GREEN}[SUCCESS]${RESET} ${GRBG}[$ip_version_nice]${RESET} ${GRBG}[ICMP]${RESET} ${BOLD}$domain${RESET}"
  else
    echo "${RED}[ERROR]  ${RESET} ${REDBG}[$ip_version_nice]${RESET} ${REDBG}[ICMP]${RESET} ${BOLD}$domain${RESET}"
  fi

  # HTTP test as well
  if command -v 'curl' > /dev/null || command -v 'wget' > /dev/null; then
    if eval "$http_cmd" >/dev/null 2>&1; then
      echo "${GREEN}[SUCCESS]${RESET} ${GRBG}[$ip_version_nice]${RESET} ${GRBG}[$http_protocol_nice]${RESET} ${BOLD}$domain${RESET}"
      return 0
    else
      echo "${RED}[ERROR]  ${RESET} ${REDBG}[$ip_version_nice]${RESET} ${REDBG}[$http_protocol_nice]${RESET} ${BOLD}$domain${RESET}"
      return 1
    fi
  fi
}

# Default function to parse arguments
parse_args() {
  while [ "$1" != "" ]; do
    case $1 in
    --help | -h)
      bind_hook "usage"
      exit 0
      ;;
    --bundle | -b)
      shift
      case "$1" in
      LAMP)
        shift
        bundle='LAMP'
        ;;
      LEMP)
        shift
        bundle='LEMP'
        ;;
      *)
        printf "Unknown bundle: $1\\n"
        bind_hook "usage"
        exit 1
        ;;
      esac
      ;;
    --minimal | -m)
      shift
      mode='mini'
      ;;
    --type | -t)
      shift
      case "$1" in
      full)
        shift
        mode='full'
        ;;
      mini)
        shift
        mode='mini'
        ;;
      *)
        printf "Unknown type: $1\\n"
        bind_hook "usage"
        exit 1
        ;;
      esac
      ;;
    --branch | -B)
      shift
      case "$1" in
      unstable|testing|development|devel|dev|nightly|bleeding-edge|cutting-edge)
        shift
        branch='unstable'
        ;;
      prerelease|pre-release|rc|release-candidate)
        shift
        branch='prerelease'
        ;;
      stable|production|release)
        shift
        branch='stable'
        ;;
      *)
        printf "Unknown branch: $1\\n"
        bind_hook "usage"
        exit 1
        ;;
      esac
      ;;
    --insecure-downloads | -i)
      shift
      insecure_download_wget_flag=' --no-check-certificate'
      insecure_download_curl_flag=' -k'
      ;;
    --no-package-updates | -x)
      shift
      noupdates=1
      ;;
    --setup | -s)
      shift
      setup_only=1
      mode='setup'
      unstable='unstable'
      log_file_name="${setup_log_file_name:-virtualmin-repos-setup}"
      ;;
    --connect | -C)
      shift
      if [ -z "$1" ] || [ "${1#-}" != "$1" ]; then
        test_connection_type="ipv4 ipv6"
      else
        if [ "$1" != "ipv4" ] && [ "$1" != "ipv6" ]; then
          printf "Invalid protocol: $1\\n"
          bind_hook "usage"
          exit 1
        fi
        test_connection_type="$1"
        shift
      fi
      ;;
    --os-grade | -g)
      shift
      case "$1" in
      A|a)
        shift
        ;;
      B|b)
        shift
        unstable='unstable'
        virtualmin_config_system_excludes=""
        virtualmin_stack_custom_packages=""
        ;;
      *)
        printf "Unknown OS grade: $1\\n"
        bind_hook "usage"
        exit 1
        ;;
      esac
      ;;
    --unstable | -e)
      shift
      unstable='unstable'
      virtualmin_config_system_excludes=""
      virtualmin_stack_custom_packages=""
      ;;
    --module | -o)
      shift
      module_name=$1
      shift
      ;;
    --hostname | -n)
      shift
      forcehostname=$1
      shift
      ;;
    --force | -f | --yes | -y)
      shift
      skipyesno=1
      ;;
    --force-reinstall | -fr)
      shift
      forcereinstall=1
      ;;
    --no-banner | -nb)
      shift
      skipbanner=1
      ;;
    --verbose | -v)
      shift
      VERBOSE=1
      ;;
    --version | -V)
      shift
      showversion=1
      ;;
    --uninstall | -u)
      shift
      mode="uninstall"
      log_file_name="${uninstall_log_file_name:-virtualmin-uninstall}"
      ;;
    *)
      printf "Unrecognized option: $1\\n"
      bind_hook "usage"
      exit 1
      ;;
    esac
  done
}

# Hook arguments
bind_hook "parse_args" "$@"

# Default function to show installer version
show_version() {
  echo "$VER"
  exit 0
}

# Hook version
if [ -n "$showversion" ]; then
  bind_hook "show_version"
fi

# Update variables based on branch
if [ "$branch" = 'unstable' ]; then
  download_virtualmin_host_lib="$download_virtualmin_host_dev"
elif [ "$branch" = 'prerelease' ]; then
  download_virtualmin_host_lib="$download_virtualmin_host_rc"
fi

# If connectivity test is requested
if [ -n "$test_connection_type" ]; then
  for test_type in $test_connection_type; do
    if [ "$branch" = "unstable" ]; then
      test_connection "$download_webmin_host_dev" "$test_type"
      test_connection "$download_virtualmin_host_dev" "$test_type"
    elif [ "$branch" = "prerelease" ]; then
      test_connection "$download_webmin_host_rc" "$test_type"
      test_connection "$download_virtualmin_host_rc" "$test_type"
    else
      test_connection "$download_webmin_host" "$test_type"
      test_connection "$download_virtualmin_host" "$test_type"
    fi
  done
  exit 0
fi

# Force setup mode, if script name is `setup-repos.sh` as it
# is used by Virtualmin API, to make sure users won't run an
# actual install script under any circumstances
if [ "$script_name" = "setup-repos.sh" ]; then
  setup_only=1
  mode='setup'
  unstable='unstable'
fi

# Store new log each time
logpath=${log_dir_path:-"$pwd"}
log="$logpath/$log_file_name.log"
if [ -e "$log" ]; then
  while true; do
    logcnt=$((logcnt+1))
    logold="$log.$logcnt"
    if [ ! -e "$logold" ]; then
      mv "$log" "$logold"
      break
    fi
  done
fi

# If Pro user downloads GPL version of `install.sh` script
# to fix repos check if there is an active license exists
if [ -n "$setup_only" ]; then
  if [ "$SERIAL" = "GPL" ] && [ "$KEY" = "GPL" ] && [ -f "$virtualmin_license_file" ]; then
    virtualmin_license_existing_serial="$(grep 'SerialNumber=' "$virtualmin_license_file" | sed 's/SerialNumber=//')"
    virtualmin_license_existing_key="$(grep 'LicenseKey=' "$virtualmin_license_file" | sed 's/LicenseKey=//')"
    if [ -n "$virtualmin_license_existing_serial" ] && [ -n "$virtualmin_license_existing_key" ]; then
      SERIAL="$virtualmin_license_existing_serial"
      KEY="$virtualmin_license_existing_key"
    fi    
  fi
fi

arch="$(uname -m)"
if [ "$arch" = "i686" ]; then
  arch="i386"
fi
if [ "$SERIAL" = "GPL" ]; then
  PRODUCT="GPL"
else
  PRODUCT="Professional"
fi

# Virtualmin-provided packages
vmgroup="'Virtualmin Core'"
vmgroupid="virtualmincore"
vmgrouptext="Virtualmin $vm_version provided packages"
debvmpackages="virtualmin-core"
deps=

if [ "$mode" = 'full' ]; then
  if [ "$bundle" = 'LAMP' ]; then
    rhgroup="'Virtualmin LAMP Stack'"
    rhgroupid="virtualmin-lamp"
    rhgrouptext="Virtualmin $vm_version LAMP stack"
    debdeps="virtualmin-lamp-stack"
    ubudeps="virtualmin-lamp-stack"
  elif [ "$bundle" = 'LEMP' ]; then
    rhgroup="'Virtualmin LEMP Stack'"
    rhgroupid="virtualmin-lemp"
    rhgrouptext="Virtualmin $vm_version LEMP stack"
    debdeps="virtualmin-lemp-stack"
    ubudeps="virtualmin-lemp-stack"
  fi
elif [ "$mode" = 'mini' ]; then
  if [ "$bundle" = 'LAMP' ]; then
    rhgroup="'Virtualmin LAMP Stack Minimal'"
    rhgroupid="virtualmin-lamp-minimal"
    rhgrouptext="Virtualmin $vm_version LAMP stack mini"
    debdeps="virtualmin-lamp-stack-minimal"
    ubudeps="virtualmin-lamp-stack-minimal"
  elif [ "$bundle" = 'LEMP' ]; then
    rhgroup="'Virtualmin LEMP Stack Minimal'"
    rhgroupid="virtualmin-lemp-minimal"
    rhgrouptext="Virtualmin $vm_version LEMP stack mini'"
    debdeps="virtualmin-lemp-stack-minimal"
    ubudeps="virtualmin-lemp-stack-minimal"
  fi
fi

# Find temp directory
if [ -z "$TMPDIR" ]; then
  TMPDIR=/tmp
fi

# Check whether $TMPDIR is mounted noexec (everything will fail, if so)
# XXX: This check is imperfect. If $TMPDIR is a full path, but the parent dir
# is mounted noexec, this won't catch it.
TMPNOEXEC="$(grep "$TMPDIR" /etc/mtab | grep noexec)"
if [ -n "$TMPNOEXEC" ]; then
  echo "Error: $TMPDIR directory is mounted noexec. Cannot continue."
  exit 1
fi

if [ -z "$VIRTUALMIN_INSTALL_TEMPDIR" ]; then
  VIRTUALMIN_INSTALL_TEMPDIR="$TMPDIR/.virtualmin-$$"
  if [ -e "$VIRTUALMIN_INSTALL_TEMPDIR" ]; then
    rm -rf "$VIRTUALMIN_INSTALL_TEMPDIR"
  fi
  mkdir "$VIRTUALMIN_INSTALL_TEMPDIR"
fi

# Export temp directory for Virtualmin Config
export VIRTUALMIN_INSTALL_TEMPDIR

# "files" subdir for libs
mkdir "$VIRTUALMIN_INSTALL_TEMPDIR/files"
srcdir="$VIRTUALMIN_INSTALL_TEMPDIR/files"

# Switch to temp directory or exit with error
goto_tmpdir() {
  if ! cd "$srcdir" >>"$log" 2>&1; then
    echo "Error: Failed to enter $srcdir temporary directory"
    exit 1
  fi
}
goto_tmpdir

pre_check_http_client() {
  # Check for wget or curl or fetch
  printf "Checking for HTTP client .." >>"$log"
  while true; do
    if [ -x "/usr/bin/wget" ]; then
      download="/usr/bin/wget -nv$insecure_download_wget_flag"
      break
    elif [ -x "/usr/bin/curl" ]; then
      download="/usr/bin/curl -f$insecure_download_curl_flag -s -L -O"
      break
    elif [ -x "/usr/bin/fetch" ]; then
      download="/usr/bin/fetch"
      break
    elif [ "$wget_attempted" = 1 ]; then
      printf " error: No HTTP client available. The installation of a download command has failed. Cannot continue.\\n" >>"$log"
      return 1
    fi

    # Made it here without finding a downloader, so try to install one
    wget_attempted=1
    if [ -x /usr/bin/dnf ]; then
      dnf -y install wget >>"$log"
    elif [ -x /usr/bin/yum ]; then
      yum -y install wget >>"$log"
    elif [ -x /usr/bin/apt-get ]; then
      apt-get update >>/dev/null
      apt-get -y -q install wget >>"$log"
    fi
  done
  if [ -z "$download" ]; then
    printf " not found\\n" >>"$log"
    return 1
  else
    printf " found %s\\n" "$download" >>"$log"
    return 0;
  fi
}

download_slib() {
  # If slib.sh is available locally in the same directory use it
  if [ -f "$pwd/slib.sh" ]; then
    chmod +x "$pwd/slib.sh"
    # shellcheck disable=SC1091
    . "$pwd/slib.sh"
  # Download the slib (source: http://github.com/virtualmin/slib)
  else
    # We need HTTP client first
    pre_check_http_client
    $download "https://$download_virtualmin_host_lib/slib.sh" >>"$log" 2>&1
    if [ $? -ne 0 ]; then
      echo "Error: Failed to download utility function library. Cannot continue. Check your network connection and DNS settings, and verify that your system's time is accurately synchronized."
      exit 1
    fi
    chmod +x slib.sh
    # shellcheck disable=SC1091
    . ./slib.sh
  fi
}

# Check if already installed successfully
already_installed_block() {
  log_error "Your system already has a successful Virtualmin installation deployed."
  log_error "Re-installation is neither possible nor necessary. This script must be"
  log_error "run on a freshly installed supported operating system. It is not meant"
  log_error "for package updates or license changes. For further assistance, please"
  log_error "visit the Virtualmin Community forum."
  exit 100
}

# Utility function library
##########################################
download_slib # for production this block
              # can be replaces with the
              # content of slib.sh file,
              # minus its header
##########################################

# Get OS type
get_distro

# Check the serial number and key
serial_ok "$SERIAL" "$KEY"
# Setup slog
LOG_PATH="$log"
# Setup run_ok
RUN_LOG="$log"
# Exit on any failure during shell stage
RUN_ERRORS_FATAL=1

# Console output level; ignore debug level messages.
if [ "$VERBOSE" = "1" ]; then
  LOG_LEVEL_STDOUT="DEBUG"
else
  LOG_LEVEL_STDOUT="INFO"
fi
# Log file output level; catch literally everything.
LOG_LEVEL_LOG="DEBUG"

# If already installed successfully, do not allow running again
if [ -f "/etc/webmin/virtual-server/installed-auto" ] && 
   [ -z "$setup_only" ] && [ -z "$forcereinstall" ] &&
   [ "$mode" != "uninstall" ]; then
  bind_hook "already_installed_block"
fi
if [ -n "$setup_only" ]; then
  log_info "Setup log is written to $LOG_PATH"
elif [ "$mode" = "uninstall" ]; then
  log_info "Uninstallation log is written to $LOG_PATH"
else
  log_info "Installation log is written to $LOG_PATH"
fi
log_debug "LOG_ERRORS_FATAL=$RUN_ERRORS_FATAL"
log_debug "LOG_LEVEL_STDOUT=$LOG_LEVEL_STDOUT"
log_debug "LOG_LEVEL_LOG=$LOG_LEVEL_LOG"

# log_fatal calls log_error
log_fatal() {
  log_error "$1"
}

# Write chosen branch to file for future reference
write_virtualmin_branch() {
  branch_dir=/etc/webmin/virtual-server
  branch_file="$branch_dir/branch"

  # If directory doesn't exist, do nothing
  [ -d "$branch_dir" ] || return 0

  # Write current $branch value
  printf '%s\n' "$branch" >"$branch_file" 2>/dev/null || :
  # Write major version
  printf '%s\n' "$vm_version" >>"$branch_file" 2>/dev/null || :
}

# Configure Virtualmin repositories (stable, prerelease, or unstable) and keep
# matching Webmin repositories in sync.
manage_virtualmin_branch_repos() {
  del_cmd="" found_type="" reinstalling=0
  found_both=0 found_unstable=0 found_prerelease=0

  # Set paths based on package type
  case "$package_type" in
    deb)
      repo_dir="/etc/apt/sources.list.d"
      auth_dir="/etc/apt/auth.conf.d"
      repo_ext="list"
      ;;
    rpm)
      repo_dir="/etc/yum.repos.d"
      repo_ext="repo"
      ;;
    *)
      return 1
      ;;
  esac

  # Remove existing unstable, prerelease or stable repos if found
  for repo in virtualmin-unstable virtualmin-prerelease virtualmin-stable virtualmin \
              webmin-unstable webmin-prerelease webmin-stable webmin; do
    repo_file="${repo_dir}/${repo}.${repo_ext}"
    if [ -f "$repo_file" ]; then
      del_cmd="${del_cmd:+$del_cmd && }rm -f $repo_file"
      case "$repo" in
        *unstable*)
          found_unstable=1
          found_type="unstable"
          ;;
        *prerelease*)
          found_prerelease=1
          found_type="prerelease"
          ;;
        *)
          found_stable=1
          found_type="stable"
          ;;
      esac
    fi

    # Auth file check for deb
    if [ "$package_type" = "deb" ]; then
      case "$repo" in
        virtualmin*) 
          auth_file="${auth_dir}/${repo}.conf"
          [ -f "$auth_file" ] && del_cmd="${del_cmd:+$del_cmd && }rm -f $auth_file"
          ;;
      esac
    fi
  done

  # Execute removal if exists
  if [ -n "$del_cmd" ]; then
    if [ "$found_unstable" -eq 1 ] && [ "$found_prerelease" -eq 1 ]; then
      msg="Uninstalling Virtualmin $vm_version unstable and prerelease repositories"
      found_both=1
    elif [ "$found_unstable" -eq 1 ]; then
      msg="Uninstalling Virtualmin $vm_version unstable repository"
    elif [ "$found_prerelease" -eq 1 ]; then
      msg="Uninstalling Virtualmin $vm_version prerelease repository"
    elif [ "$found_stable" -eq 1 ]; then
      msg="Uninstalling Virtualmin $vm_version stable repository"
    fi

    # If removing only, update metadata
    if [ -z "$branch" ]; then
      del_cmd="$del_cmd && $update"
    fi

    # Remove any existing repo configs and keys first
    remove_virtualmin_release

    # Remove silently if reinstalling
    if [ -n "$branch" ] && [ "$found_both" -eq 0 ] && [ "$found_type" = "$branch" ]; then
      eval "$del_cmd"
      reinstalling=1
    else
      run_ok "$del_cmd" "$msg"
    fi
  fi

  # Save branch name
  write_virtualmin_branch
  
  # Configure repo based on requested branch
  if [ "$reinstalling" -eq 1 ]; then
    install_pre_msg="Reinstalling Virtualmin $vm_version"
  else
    install_pre_msg="Installing Virtualmin $vm_version"
  fi
  case "$branch" in
    unstable)
      down_cmd="$download https://$download_virtualmin_host_dev/install"
      cmd="$down_cmd && sh install webmin unstable && \
            sh install virtualmin unstable"
      msg="$install_pre_msg unstable repository"
      ;;
    prerelease)
      down_cmd="$download https://$download_virtualmin_host_rc/install"
      cmd="$down_cmd && sh install webmin prerelease && \
            sh install virtualmin prerelease"
      msg="$install_pre_msg prerelease repository"
      ;;
    stable)
      down_cmd="$download https://$download_virtualmin_host/install"
      cmd="$down_cmd && sh install virtualmin stable"
      msg="$install_pre_msg stable repository"
      ;;
    *)
      return 1
      ;;
  esac
  run_ok "$cmd" "$msg"
}

# Test if grade B system
grade_b_system() {
  case "$os_type" in
    rhel | centos | rocky | almalinux | debian)
      return 1
      ;;
    ubuntu)
      case "$os_version" in
        *\.10|*[13579].04) # non-LTS versions are unstable
          return 0
          ;;
        *)
          return 1
          ;;
      esac
      ;;
    *)
      return 0
      ;;
  esac
}

if grade_b_system && [ "$unstable" != 'unstable' ]; then
  log_error "Unsupported operating system detected. You may be able to install with"
  log_error "${BOLD}--unstable${NORMAL} flag, but this is not recommended. Consult the installation"
  log_error "documentation."
  exit 1
fi

remove_virtualmin_release() {
  # Directories where Virtualmin and Webmin config or keys may live
  for d in \
    /etc/apt/sources.list.d \
    /etc/apt/auth.conf.d \
    /usr/share/keyrings \
    /etc/apt/keyrings \
    /etc/pki/rpm-gpg \
    /etc/yum.repos.d
  do
    [ -d "$d" ] || continue

    case "$d" in
      /etc/yum.repos.d)
        # Repo files
        patterns="virtualmin* webmin*"
        ;;
      /etc/pki/rpm-gpg)
        # RPM GPG keys and/or any style keys
        patterns="RPM-GPG-KEY-virtualmin* RPM-GPG-KEY-webmin* *-virtualmin* *-webmin*"
        ;;
      *)
        # APT dirs / keyring dirs, etc.
        patterns="virtualmin* webmin* *-virtualmin* *-webmin*"
        ;;
    esac

    for p in $patterns; do
      # shellcheck disable=SC2086
      rm -f "$d"/$p 2>/dev/null || :
    done
  done

  # Clean APT main sources file if it exists
  if [ -f /etc/apt/sources.list ]; then
    tmp="${VIRTUALMIN_INSTALL_TEMPDIR:-/tmp}/sources.list.$$"
    grep -vi "virtualmin\|webmin" /etc/apt/sources.list >"$tmp" || :
    mv "$tmp" /etc/apt/sources.list
  fi
}

fatal() {
  echo
  log_fatal "Fatal Error Occurred: $1"
  printf "${RED}Cannot continue installation.${NORMAL}\\n"
  remove_virtualmin_release
  if [ -x "$VIRTUALMIN_INSTALL_TEMPDIR" ]; then
    log_warning "Removing temporary directory and files."
    rm -rf "$VIRTUALMIN_INSTALL_TEMPDIR"
  fi
  log_fatal "If you are unsure of what went wrong, you may wish to review the log"
  log_fatal "in $log"
  exit 1
}

success() {
  log_success "$1 Succeeded."
}

# Function to find out if some services were pre-installed
is_preconfigured() {
  preconfigured=""
  if named -v 1>/dev/null 2>&1; then
    preconfigured="${preconfigured}${YELLOW}${BOLD}BIND${NORMAL} "
  fi
  if apachectl -v 1>/dev/null 2>&1; then
    preconfigured="${preconfigured}${YELLOW}${BOLD}Apache${NORMAL} "
  fi
  if nginx -v 1>/dev/null 2>&1; then
    preconfigured="${preconfigured}${YELLOW}${BOLD}Nginx${NORMAL} "
  fi
  if command -pv mariadb 1>/dev/null 2>&1; then
    preconfigured="${preconfigured}${YELLOW}${BOLD}MariaDB${NORMAL} "
  fi
  if postconf mail_version 1>/dev/null 2>&1; then
    preconfigured="${preconfigured}${YELLOW}${BOLD}Postfix${NORMAL} "
  fi
  if php -v 1>/dev/null 2>&1; then
    preconfigured="${preconfigured}${YELLOW}${BOLD}PHP${NORMAL} "
  fi
  preconfigured=$(echo "$preconfigured" | sed 's/ /, /g' | sed 's/, $/ /')
  echo "$preconfigured"
}

# Function to find out if Virtualmin is already installed, so we can get
# rid of some of the warning message. Nobody reads it, and frequently
# folks run the install script on a production system; either to attempt
# to upgrade, or to "fix" something. That's never the right thing.
is_installed() {
  if [ -f "$virtualmin_license_file" ]; then
    # looks like it's been installed before
    return 0
  fi
  # XXX Probably not installed? Maybe we should remove license on uninstall, too.
  return 1
}

# This function performs a rough uninstallation of Virtualmin
# all related packages and configurations
uninstall() {
  log_debug "Initiating Virtualmin uninstallation procedure"
  log_debug "Operating system name:    $os_real"
  log_debug "Operating system version: $os_version"
  log_debug "Operating system type:    $os_type"
  log_debug "Operating system major:   $os_major_version"

  if [ "$skipyesno" -ne 1 ]; then
    echo
    printf "  ${REDBG}${BLACK}${BOLD} WARNING ${NORMAL}\\n"
    echo
    echo "  This operation is highly disruptive and cannot be undone. It removes all of"
    echo "  the packages and configuration files installed by the Virtualmin installer!"
    echo
    echo "  It must never be executed on a live production system!"
    echo
    printf " ${RED}Uninstall?${NORMAL} (y/N) "
    if ! yesno; then
      exit
    fi
  fi

  # Always sleep just a bit in case the user changes their mind
  sleep 3

  # Go to the temp directory
  goto_tmpdir

  # Uninstall packages
  uninstall_packages()
  {
    # Detect the package manager
    case "$os_type" in
    rhel | fedora | centos | centos_stream | rocky | almalinux | openEuler | ol | cloudlinux | amzn )
      package_type=rpm
      if command -pv dnf 1>/dev/null 2>&1; then
        uninstall_cmd="dnf remove -y"
        uninstall_cmd_group="dnf groupremove -y"
        update="dnf clean all ; dnf makecache"
      else
        uninstall_cmd="yum remove -y"
        uninstall_cmd_group="yum groupremove -y"
        update="yum clean all ; yum makecache"
      fi
      ;;
    debian | ubuntu | kali)
      package_type=deb
      uninstall_cmd="apt-get remove --assume-yes --purge"
      update="apt-get clean ; apt-get update"
      ;;
    esac
    
    case "$package_type" in
    rpm)
      $uninstall_cmd_group "Virtualmin Core" "Virtualmin LAMP Stack" "Virtualmin LEMP Stack" "Virtualmin LAMP Stack Minimal" "Virtualmin LEMP Stack Minimal"
      $uninstall_cmd wbm-* wbt-* webmin* usermin* virtualmin*
      os_type="rhel"
      return 0
      ;;
    deb)
      $uninstall_cmd "virtualmin*" "webmin*" "usermin*"
      uninstall_cmd_auto="apt-get autoremove --assume-yes"
      $uninstall_cmd_auto
      os_type="debian"
      return 0
      ;;
    *)
      log_error "Unknown package manager, cannot uninstall"
      return 1
      ;;
    esac
  }

  # Uninstall repos and helper command
  uninstall_repos()
  {
    if [ -f "$virtualmin_license_file" ]; then
      log_debug "Removing Virtualmin license"
      rm -f "$virtualmin_license_file" 2>/dev/null || :
    fi
  
    log_debug "Removing Virtualmin helper command"
    rm -f "/usr/sbin/virtualmin" 2>/dev/null || :
  
    remove_virtualmin_release
  
    log_debug "Virtualmin uninstallation complete"
  }
  
  phase_number=${phase_number:-1}
  phases_total=${phases_total:-1}
  uninstall_phase_description=${uninstall_phase_description:-"Uninstall"}
  echo
  phase "$uninstall_phase_description" "$phase_number"
  run_ok "uninstall_packages" "Uninstalling Virtualmin $vm_version and all stack packages"
  run_ok "uninstall_repos" "Uninstalling Virtualmin $vm_version configuration and license"
  manage_virtualmin_branch_repos
}

# Phase control
phase() {
    phases_total="${phases_total:-4}"
    phase_description="$1"
    phase_number="$2"
    # Print completed phases (green)
    printf "${GREEN}"
    for i in $(seq 1 $(( phase_number - 1 ))); do
        printf "▣"
    done
    # Print current phase (yellow)
    printf "${YELLOW}▣"
    # Print remaining phases (cyan)
    for i in $(seq $(( phase_number + 1 )) "$phases_total"); do
        printf "${CYAN}◻"
    done
    log_debug "Phase ${phase_number} of ${phases_total}: ${phase_description}"
    printf "${NORMAL} Phase ${YELLOW}${phase_number}${NORMAL} of ${GREEN}${phases_total}${NORMAL}: ${phase_description}\\n"
}

if [ "$mode" = "uninstall" ]; then
  bind_hook "uninstall"
  exit 0
fi

# Calculate disk space requirements (this is a guess, for now)
if [ "$mode" != 'full' ]; then
  disk_space_required=1
else
  disk_space_required=2
fi

# Message to display in interactive mode
install_msg() {
  supported="    ${CYANBG}${BLACK}${BOLD}Red Hat Enterprise Linux and derivatives${NORMAL}${CYAN}
      - Alma and Rocky 8, 9 and 10 on x86_64 and aarch64
      - RHEL 8, 9 and 10 on x86_64 and aarch64
      UNSTABLERHEL${NORMAL}
    ${CYANBG}${BLACK}${BOLD}Debian Linux and derivatives${NORMAL}${CYAN}
      - Debian 11, 12 and 13 on i386, amd64 and arm64
      - Ubuntu 20.04, 22.04 and 24.04 on i386, amd64 and arm64${NORMAL}
      UNSTABLEDEB${NORMAL}"

  cat <<EOF

  Welcome to the ${GREEN}${BOLD}Virtualmin $PRODUCT${NORMAL} installer, version ${GREEN}${BOLD}$VER${NORMAL}

  This script must be run on a freshly installed supported OS. It does not
  perform updates or upgrades (use your system package manager) or license
  changes (use the "virtualmin change-license" command).

EOF
  screen_height=$(tput lines 2>/dev/null || echo 0)
  # Check if screen height can fit the message entirely
  if { [ "$screen_height" -gt 0 ] &&
       [ "$screen_height" -lt 33 ]; } ||
     [ "$screen_height" -eq 0 ]; then
      printf " Continue? (y/n) "
      if ! yesno; then
          exit
      fi
      echo
  fi
  cat <<EOF
  The systems currently supported by the install script are:

EOF
  supported_all=$supported
  if [ -n "$unstable" ]; then
    unstable_rhel="${YELLOW}- Fedora Server 42 and above on x86_64 and aarch64\\n \
     - CentOS Stream 8, 9 and 10 on x86_64 and aarch64\\n \
     - Oracle Linux 8, 9 and 10 on x86_64 and aarch64\\n \
     - Amazon Linux 2023 and above on x86_64 and aarch64\\n \
     - CloudLinux 8 and 9 on x86_64\\n \
     - openEuler 24.03 and above on x86_64 and aarch64\\n \
          ${NORMAL}"
    unstable_deb="${YELLOW}- Kali Linux Rolling 2025 and above on amd64 and arm64\\n \
     - Ubuntu interim (non-LTS) on i386, amd64 and arm64\\n \
          ${NORMAL}"
    supported_all=$(echo "$supported_all" | sed "s/UNSTABLERHEL/$unstable_rhel/")
    supported_all=$(echo "$supported_all" | sed "s/UNSTABLEDEB/$unstable_deb/")
  else
    supported_all=$(echo "$supported_all" | sed 's/UNSTABLERHEL//')
    supported_all=$(echo "$supported_all" | sed 's/UNSTABLEDEB//')
  fi
  echo "$supported_all"
  cat <<EOF
  If your OS/version/arch is not listed, installation ${BOLD}${RED}will fail${NORMAL}. More
  details about the systems supported by the script can be found here:

    ${UNDERLINE}https://www.virtualmin.com/os-support${NORMAL}

  The installation will require up to ${CYAN}${disk_space_required} GB${NORMAL} of disk space. The selected
  package bundle is ${CYAN}${bundle}${NORMAL} and the type of install is ${CYAN}${mode}${NORMAL}. More details
  about the package bundles and types can be found here:

    ${UNDERLINE}https://www.virtualmin.com/installation-variations${NORMAL}

EOF

  if [ "$skipyesno" -ne 1 ]; then
  cat <<EOF
  Exit and re-run this script with ${CYAN}--help${NORMAL} flag to see available options.

EOF
  fi
  if [ "$skipyesno" -ne 1 ]; then
    printf " Continue? (y/n) "
    if ! yesno; then
      exit
    fi
  fi
}

if [ -z "$setup_only" ] && [ -z "$skipbanner" ]; then
    bind_hook "install_msg"
fi

os_unstable_pre_check() {
  if [ -n "$unstable" ]; then
    cat <<EOF

  ${YELLOWBG}${BLACK}${BOLD} INSTALLATION WARNING ${NORMAL}

  You are about to install Virtualmin $PRODUCT on a ${BOLD}Grade B${NORMAL} operating
  system. Be advised that this OS version is not recommended for servers,
  and may have bugs that could affect the performance and stability of
  the system.

  Certain features may not work as intended or might be unavailable on
  this OS.

EOF
    if [ "$skipyesno" -ne 1 ]; then
      printf " Continue? (y/n) "
      if ! yesno; then
        exit
      fi
    fi
  fi
}

unstable_repos_system_msg() {
  if [ -n "$branch" ]; then
    if [ "$branch" = "unstable" ]; then
      cat <<EOF

  ${REDBG}${WHITE}${BOLD} DANGER ${NORMAL}

  You have enabled the unstable development branch, where packages are built
  automatically with every commit to the repositories of each product we
  offer. This branch is strictly for testing and development purposes
  and must not be used in a production environment!

EOF
    elif [ "$branch" = "prerelease" ]; then
      cat <<EOF

  ${YELLOWBG}${BLACK}${BOLD} NOTICE ${NORMAL}

  You have enabled the prerelease branch, where packages are automatically
  built for tagged releases of each product we offer. This branch provides
  early access to features and updates before they are included in the
  stable branch.

EOF
    fi
    
    if [ "$skipyesno" -ne 1 ]; then
      printf " Continue with $branch branch? (y/n) "
      if ! yesno; then
        exit
      fi
    fi
  fi
}

preconfigured_system_msg() {
  # Double check if installed, just in case above error ignored.
  is_preconfigured_rs=$(is_preconfigured)
  if [ -n "$is_preconfigured_rs" ]; then
    cat <<EOF

  ${WHITEBG}${RED}${BOLD} ATTENTION ${NORMAL}

  Pre-installed software detected: $is_preconfigured_rs

  It is highly advised ${BOLD}${RED}not to pre-install${NORMAL} any additional packages on your
  OS. The installer expects a freshly installed OS, and anything you do
  differently might cause conflicts or configuration errors. If you need
  to enable third-party package repositories, do so after installation
  of Virtualmin, and only with extreme caution.

EOF
    if [ "$skipyesno" -ne 1 ]; then
      printf " Continue? (y/n) "
      if ! yesno; then
        exit
      fi
    fi
  fi
}

already_installed_msg() {
  # Double check if installed, just in case above error ignored.
  if is_installed; then
    cat <<EOF

  ${WHITEBG}${RED}${BOLD} WARNING ${NORMAL}

  Virtualmin may already be installed. This can happen if an installation
  failed, and can be ignored in that case.

  However, if Virtualmin has already been successfully installed you
  ${BOLD}${RED}must not${NORMAL} run this script again! It will cause breakage to your
  existing configuration.

  Virtualmin repositories can be fixed using ${WHITEBG}${BLACK}${BOLD}$script_name --setup${NORMAL}
  command.

  License can be changed using ${WHITEBG}${BLACK}${BOLD}virtualmin change-license${NORMAL} command.
  Changing the license never requires re-installation.

  Updates and upgrades must be performed from within either Virtualmin or
  using system package manager on the command line.

EOF
    if [ "$skipyesno" -ne 1 ]; then
      printf " Continue? (y/n) "
      if ! yesno; then
        exit
      fi
    fi
  fi
}

post_install_message() {
  # Login at message
  login_at1="https://${hostname}:10000."
  if [ -z "$ssl_host_success" ]; then
    login_at_combined="https://${hostname}:10000 (or https://${address}:10000)."
    login_at_len=${#login_at_combined}
    if [ "$login_at_len" -gt 64 ]; then
        # Split into two lines
        login_at1="https://${hostname}:10000 (or"
        login_at2="https://${address}:10000)."
    else
        # Single line
        login_at1=$login_at_combined
        login_at2=
    fi
    
  fi
  log_success "Installation Complete!"
  log_success "If there were no errors above, Virtualmin is ready to be configured"
  log_success "at $login_at1"
  if [ -n "$login_at2" ]; then
    log_success "$login_at2"
  fi
  if [ -z "$ssl_host_success" ]; then
    log_success "You will see a security warning in the browser on your first visit."
  fi
}

if [ -z "$setup_only" ] && [ -z "$skipbanner" ]; then
  if grade_b_system; then
    bind_hook "os_unstable_pre_check"
  fi
  bind_hook "unstable_repos_system_msg"
  bind_hook "preconfigured_system_msg"
  bind_hook "already_installed_msg"
fi

# Check memory
if [ "$mode" = "full" ]; then
  minimum_memory=1610613
else
  # minimal mode probably needs less memory to succeed
  minimum_memory=1048576
fi
if ! memory_ok "$minimum_memory" "$disk_space_required"; then
  log_fatal "Too little memory, and unable to create a swap file. Consider adding swap"
  log_fatal "or more RAM to your system."
  exit 1
fi

# Check for localhost in /etc/hosts
if [ -z "$setup_only" ]; then
  grep localhost /etc/hosts >/dev/null
  if [ "$?" != 0 ]; then
    log_warning "There is no localhost entry in /etc/hosts. This is required, so one will be added."
    run_ok "echo 127.0.0.1 localhost >> /etc/hosts" "Editing /etc/hosts"
    if [ "$?" -ne 0 ]; then
      log_error "Failed to configure a localhost entry in /etc/hosts."
      log_error "This may cause problems, but we'll try to continue."
    fi
  fi
fi

pre_check_system_time() {
  # Check if current time
  # is not older than
  # Wed Dec 01 2022
  printf "Syncing system time ..\\n" >>"$log"
  TIMEBASE=1669888800
  TIME=$(date +%s)
  if [ "$TIME" -lt "$TIMEBASE" ]; then

    # Try to sync time automatically first
    if systemctl restart chronyd 1>/dev/null 2>&1; then
      sleep 30
    elif systemctl restart systemd-timesyncd 1>/dev/null 2>&1; then
      sleep 30
    fi

    # Check again after all
    TIME=$(date +%s)
    if [ "$TIME" -lt "$TIMEBASE" ]; then
      printf ".. failed to automatically sync system time; it should be corrected manually to continue\\n" >>"$log"
      return 1;
    fi
  # Graceful sync
  else
    if systemctl restart chronyd 1>/dev/null 2>&1; then
      sleep 10
    elif systemctl restart systemd-timesyncd 1>/dev/null 2>&1; then
      sleep 10
    fi
  fi
  printf ".. done\\n" >>"$log"
  return 0
}

pre_check_ca_certificates() {
  printf "Checking for an update for a set of CA certificates ..\\n" >>"$log"
  if [ -x /usr/bin/dnf ]; then
    dnf -y update ca-certificates >>"$log" 2>&1
  elif [ -x /usr/bin/yum ]; then
    yum -y update ca-certificates >>"$log" 2>&1
  elif [ -x /usr/bin/apt-get ]; then
    apt-get -y install ca-certificates >>"$log" 2>&1
  fi
  res=$?
  printf ".. done\\n" >>"$log"
  return "$res"
}

pre_check_perl() {
  printf "Checking for Perl .." >>"$log"
  # loop until we've got a Perl or until we can't try any more
  while true; do
    perl="$(command -pv perl 2>/dev/null)"
    if [ -z "$perl" ]; then
      if [ -x /usr/bin/perl ]; then
        perl=/usr/bin/perl
        break
      elif [ -x /usr/local/bin/perl ]; then
        perl=/usr/local/bin/perl
        break
      elif [ -x /opt/csw/bin/perl ]; then
        perl=/opt/csw/bin/perl
        break
      elif [ "$perl_attempted" = 1 ]; then
        printf ".. Perl could not be installed. Cannot continue\\n" >>"$log"
        return 1
      fi
      # couldn't find Perl, so we need to try to install it
      if [ -x /usr/bin/dnf ]; then
        dnf -y install perl >>"$log" 2>&1
      elif [ -x /usr/bin/yum ]; then
        yum -y install perl >>"$log" 2>&1
      elif [ -x /usr/bin/apt-get ]; then
        apt-get update >>"$log" 2>&1
        apt-get -q -y install perl >>"$log" 2>&1
      fi
      perl_attempted=1
      # Loop. Next loop should either break or exit.
    else
      break
    fi
  done
  printf ".. found Perl at $perl\\n" >>"$log"
  return 0
}

pre_check_gpg() {
  if [ -x /usr/bin/apt-get ]; then
    printf "Checking for GPG .." >>"$log"
    if [ ! -x /usr/bin/gpg ]; then
      printf " not found, attempting to install .." >>"$log"
      apt-get update >>/dev/null
      apt-get -y -q install gnupg >>"$log"
      printf " finished : $?\\n" >>"$log"
    else
      printf " found GPG command\\n" >>"$log"
    fi
  fi
}

pre_check_all() {
  
  if [ -z "$setup_only" ]; then
    # Check system time
    run_ok pre_check_system_time "Checking system time"
    
    # Make sure Perl is installed
    run_ok pre_check_perl "Checking Perl installation"

    # Update CA certificates package
    run_ok pre_check_ca_certificates "Checking CA certificates package"
  else
    # Make sure Perl is installed
    run_ok pre_check_perl "Checking Perl installation"
  fi

  # Checking for HTTP client
  run_ok pre_check_http_client "Checking HTTP client"

  # Check for gpg, debian 10 doesn't install by default!?
  run_ok pre_check_gpg "Checking GPG package"
}

# download()
# Use $download to download the provided filename or exit with an error.
download() {
  # XXX Check this to make sure run_ok is doing the right thing.
  # Especially make sure failure gets logged right.
  # awk magic prints the filename, rather than whole URL
  export download_file
  download_file=$(echo "$1" | awk -F/ '{print $NF}')
  run_ok "$download $1" "$2"
  if [ $? -ne 0 ]; then
    fatal "Failed to download Virtualmin release package. Cannot continue. Check your network connection and DNS settings, and verify that your system's time is accurately synchronized."
  else
    return 0
  fi
}

# Only root can run this
if [ "$(id -u)" -ne 0 ]; then
  uname -a | grep -i CYGWIN >/dev/null
  if [ "$?" != "0" ]; then
    fatal "${RED}Fatal:${NORMAL} The Virtualmin install script must be run as root"
  fi
fi

bind_hook "phases_all_pre"

if [ -n "$setup_only" ]; then
  pre_check_perl
  pre_check_http_client
  pre_check_gpg
  log_info "Started Virtualmin $vm_version $PRODUCT software repositories setup"
else
  echo
  phase "Check" 1
  bind_hook "phase1_pre"
  pre_check_all
  bind_hook "phase1_post"
  echo

  phase "Setup" 2
  bind_hook "phase2_pre"
fi

# Print out some details that we gather before logging existed
log_debug "Install mode: $mode"
log_debug "Product: Virtualmin $PRODUCT"
log_debug "virtualmin-install.sh version: $VER"

# Check for a fully qualified hostname
if [ -z "$setup_only" ]; then
  log_debug "Checking for fully qualified hostname .."
  name="$(hostname -f)"
  if [ $? -ne 0 ]; then
    name=$(hostnamectl --static)
  fi
  if [ -n "$forcehostname" ]; then
    set_hostname "$forcehostname"
  elif ! is_fully_qualified "$name"; then
    set_hostname
  else
    # Hostname is already FQDN, yet still set it 
    # again to make sure to have it updated everywhere
    set_hostname "$name"
  fi
fi

# Insert the serial number and password into license file
log_debug "Installing serial number and license key into '$virtualmin_license_file'"
echo "SerialNumber=$SERIAL" > "$virtualmin_license_file"
echo "LicenseKey=$KEY" >> "$virtualmin_license_file"
chmod 700 "$virtualmin_license_file"
cd ..

# Populate some distro version globals
log_debug "Operating system name:    $os_real"
log_debug "Operating system version: $os_version"
log_debug "Operating system type:    $os_type"
log_debug "Operating system major:   $os_major_version"

preconfigure_virtualmin_release() {
  # Grab virtualmin-release from the server
  log_debug "Configuring package manager for ${os_real} ${os_version} .."

  # EL-based systems handling
  case "$os_type" in
  rhel | fedora | centos | centos_stream | rocky | almalinux | openEuler | ol | cloudlinux | amzn )
    case "$os_type" in
    rhel | centos | centos_stream)
      if [ "$os_type" = "centos_stream" ]; then
        if [ "$os_major_version" -lt 8 ]; then
          printf "${RED}${os_real} ${os_version}${NORMAL} is not supported by this installer.\\n"
          exit 1
        fi
      else
        if [ "$os_major_version" -lt 7 ]; then
          printf "${RED}${os_real} ${os_version}${NORMAL} is not supported by this installer.\\n"
          exit 1
        fi
      fi
      ;;
    rocky | almalinux | openEuler | ol)
      if [ "$os_major_version" -lt 8 ]; then
        printf "${RED}${os_real} ${os_version}${NORMAL} is not supported by this installer.\\n"
        exit 1
      fi
      ;;
    cloudlinux)
      if [ "$os_major_version" -lt 8 ] && [ "$os_type" = "cloudlinux" ]; then
        printf "${RED}${os_real} ${os_version}${NORMAL} is not supported by this installer.\\n"
        exit 1
      fi
      ;;
    fedora)
      if [ "$os_major_version" -lt 35 ] && [ "$os_type" = "fedora" ]  ; then
        printf "${RED}${os_real} ${os_version}${NORMAL} is not supported by this installer.\\n"
        exit 1
      fi
      ;;
    amzn)
      if [ "$os_major_version" -lt 2023 ] && [ "$os_type" = "amzn" ]  ; then
        printf "${RED}${os_real} ${os_version}${NORMAL} is not supported by this installer.\\n"
        exit 1
      fi
      ;;
    *)
      printf "${RED}This OS/version is not recognized! Cannot continue!${NORMAL}\\n"
      exit 1
      ;;
    esac
    if [ -x /usr/sbin/setenforce ]; then
      log_debug "Disabling SELinux during installation .."
      if /usr/sbin/setenforce 0 1>/dev/null 2>&1; then
        log_debug " setenforce 0 succeeded"
      else
        log_debug "  setenforce 0 failed: $?"
      fi
    fi
    package_type="rpm"
    allow_skip_broken=" --skip-broken"
    if [ "$unstable" != 'unstable' ]; then
      allow_skip_broken=""
    fi
    if command -pv dnf 1>/dev/null 2>&1; then
      install_cmd="dnf"
      install="$install_cmd -y install"
      upgrade="$install_cmd -y update"
      update="$install_cmd clean all ; $install_cmd makecache"
      install_group_opts="-y --quiet group install --setopt=group_package_types=mandatory,default$allow_skip_broken"
      install_group="$install_cmd $install_group_opts"
      install_config_manager="$install_cmd config-manager"
      # Do not use package manager when fixing repos
      if [ -z "$setup_only" ]; then
        run_ok "$install dnf-plugins-core" "Installing core plugins for package manager"
      fi
    else
      install_cmd="yum"
      install="$install_cmd -y install"
      upgrade="$install_cmd -y update"
      update="$install_cmd clean all ; $install_cmd makecache"
      if [ "$os_major_version" -ge 7 ]; then
        # Do not use package manager when fixing repos
        if [ -z "$setup_only" ]; then
          run_ok "$install_cmd --quiet groups mark convert" "Updating groups metadata"
        fi
      fi
      install_group_opts="-y --quiet$allow_skip_broken groupinstall --setopt=group_package_types=mandatory,default"
      install_group="$install_cmd $install_group_opts"
      install_config_manager="yum-config-manager"
    fi

    # Remove any existing obsolete package release
    if [ -x "/usr/bin/rpm" ]; then
      rpm_release_files="$(rpm -qal virtualmin*release)"
      rpm_release_files=$(echo "$rpm_release_files" | tr '\n' ' ')
      if [ -n "$rpm_release_files" ]; then
        for rpm_release_file in $rpm_release_files; do
          rm -f "$rpm_release_file"
        done
      fi
    fi
    rpm -e --nodeps --quiet "$(rpm -qa virtualmin*release 2>/dev/null)" >> "$RUN_LOG" 2>&1
    
    # Repo setup is done by "manage_virtualmin_branch_repos" using a unified
    # logic
    ;;
  
  # Debian-based systems handling
  debian | ubuntu | kali)
    case "$os_type" in
    ubuntu)
      case "$os_version:$unstable" in
        18.04:*|20.04:*|22.04:*|24.04:*|*\.10:unstable|*[13579].04:unstable)
          : ;; # Do nothing for supported or allowed unstable versions
        *)
          printf "${RED}${os_real} ${os_version} is not supported by this installer.${NORMAL}\\n"
          exit 1
          ;;
      esac
      ;;
    debian)
      if [ "$os_major_version" -lt 10 ]; then
        printf "${RED}${os_real} ${os_version} is not supported by this installer.${NORMAL}\\n"
        exit 1
      fi
      ;;
    kali)
      if [ "$os_major_version" -lt 2023 ] && [ "$os_type" = "kali" ]  ; then
        printf "${RED}${os_real} ${os_version}${NORMAL} is not supported by this installer.\\n"
        exit 1
      fi
      ;;
    esac
    package_type="deb"
    if [ "$os_type" = "ubuntu" ]; then
      deps="$ubudeps"
      repos="virtualmin"
    else
      deps="$debdeps"
      repos="virtualmin"
    fi
    
    # Make sure universe repos are available
    if [ "$os_type" = "ubuntu" ]; then
      if [ -x "/bin/add-apt-repository" ] || [ -x "/usr/bin/add-apt-repository" ]; then
        run_ok "add-apt-repository -y universe" \
          "Enabling universe repositories, if not already available"
      elif [ -f /etc/apt/sources.list ]; then
        run_ok "sed -ie '/backports/b; s/#*[ ]*deb \\(.*\\) universe$/deb \\1 universe/' /etc/apt/sources.list" \
          "Enabling universe repositories, if not already available"
      fi
    fi

    # Is this still enabled by default on Debian/Ubuntu systems?
    if [ -f /etc/apt/sources.list ]; then
      run_ok "sed -ie 's/^deb cdrom:/#deb cdrom:/' /etc/apt/sources.list" "Disabling cdrom: repositories"
    fi
    install="DEBIAN_FRONTEND='noninteractive' /usr/bin/apt-get --quiet --assume-yes --install-recommends -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' -o Dpkg::Pre-Install-Pkgs::='/usr/sbin/dpkg-preconfigure --apt' install"
    upgrade="DEBIAN_FRONTEND='noninteractive' /usr/bin/apt-get --quiet --assume-yes --install-recommends -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' -o Dpkg::Pre-Install-Pkgs::='/usr/sbin/dpkg-preconfigure --apt' upgrade"
    update="/usr/bin/apt-get clean ; /usr/bin/apt-get update"
    run_ok "apt-get clean" "Cleaning up software repo metadata"
    if [ -f /etc/apt/sources.list ]; then
      sed -i "s/\\(deb[[:space:]]file.*\\)/#\\1/" /etc/apt/sources.list
    fi
    
    # Repo setup is done by "manage_virtualmin_branch_repos" using a unified
    # logic
    ;;
  *)
    log_error " Your OS is not currently supported by this installer. Nevertheless, you"
    log_error " should still be able to run Virtualmin on your system by following the"
    log_error " manual installation process."
    exit 1
    ;;
  esac

  return 0
}

# Setup repos only
if [ -n "$setup_only" ]; then
  if preconfigure_virtualmin_release; then
    manage_virtualmin_branch_repos
    log_success "Virtualmin repository is configured successfully."
  else
    log_error "Errors occurred during setup of Virtualmin software repositories. You may find more"
    log_error "information in ${RUN_LOG}."
  fi
  exit $?
fi

# Install Functions
install_with_apt() {
  # Install system package upgrades, if any
  if [ -z "$noupdates" ]; then
    run_ok "$upgrade" "Checking and installing system package updates"
  fi

  # Silently purge packages that may cause issues upon installation
  /usr/bin/apt-get --quiet --assume-yes purge ufw >> "$RUN_LOG" 2>&1

  # Install Webmin/Usermin first, because it needs to be already done
  # for the deps. Then install Virtualmin Core and then Stack packages
  # Do it all in one go for the nicer UI
  run_ok "$install webmin && $install $debvmpackages && $install $deps" "Installing Virtualmin $vm_version and all related packages"
  if [ $? -ne 0 ]; then
    log_warning "apt-get seems to have failed. Are you sure your OS and version is supported?"
    log_warning "https://www.virtualmin.com/os-support"
    fatal "Installation failed: $?"
  fi

  # Make sure the time is set properly
  /usr/sbin/ntpdate-debian >> "$RUN_LOG" 2>&1

  return 0
}

install_with_yum() {
  # Enable CodeReady and EPEL on RHEL 8+
  if [ "$os_major_version" -ge 8 ] && [ "$os_type" = "rhel" ]; then
    # Important Perl packages are now hidden in CodeReady repo
    run_ok "$install_config_manager --set-enabled codeready-builder-for-rhel-$os_major_version-$arch-rpms" "Enabling Red Hat CodeReady package repository"
    # Install EPEL
    download "https://dl.fedoraproject.org/pub/epel/epel-release-latest-$os_major_version.noarch.rpm" >>"$log" 2>&1
    run_ok "rpm -U --replacepkgs --quiet epel-release-latest-$os_major_version.noarch.rpm" "Installing EPEL $os_major_version release package"
  # Install EPEL on RHEL 7
  elif [ "$os_major_version" -eq 7 ] && [ "$os_type" = "rhel" ]; then
    download "https://dl.fedoraproject.org/pub/epel/epel-release-latest-$os_major_version.noarch.rpm" >>"$log" 2>&1
    run_ok "rpm -U --replacepkgs --quiet epel-release-latest-$os_major_version.noarch.rpm" "Installing EPEL $os_major_version release package"
  # Install EPEL on CentOS/Alma/Rocky
  elif [ "$os_type" = "centos" ] || [ "$os_type" = "centos_stream" ] || [ "$os_type" = "rocky" ] || [ "$os_type" = "almalinux" ]; then  
    run_ok "$install epel-release" "Installing EPEL $os_major_version release package"
  # CloudLinux EPEL 
  elif [ "$os_type" = "cloudlinux" ]; then
    # Install EPEL on CloudLinux
    download "https://dl.fedoraproject.org/pub/epel/epel-release-latest-$os_major_version.noarch.rpm" >>"$log" 2>&1
    run_ok "rpm -U --replacepkgs --quiet epel-release-latest-$os_major_version.noarch.rpm" "Installing EPEL $os_major_version release package"
  # Install EPEL on Oracle 7+
  elif [ "$os_type" = "ol" ]; then
    run_ok "$install oracle-epel-release-el$os_major_version" "Installing EPEL release package"
  # Installation on Amazon Linux
  elif [ "$os_type" = "amzn" ]; then
    # Set for installation packages whichever available on Amazon Linux as they
    # go with different name, e.g. mariadb105-server instead of mariadb-server
    virtualmin_stack_custom_packages="mariadb*-server"
    # Exclude from config what's not available on Amazon Linux
    virtualmin_config_system_excludes=" --exclude AWStats --exclude Etckeeper --exclude Fail2banFirewalld --exclude ProFTPd"
  fi

  # Important Perl packages are now hidden in PowerTools repo
  if [ "$os_major_version" -ge 8 ] && [ "$os_type" = "centos" ] || [ "$os_type" = "centos_stream" ] || [ "$os_type" = "rocky" ] || [ "$os_type" = "almalinux" ] || [ "$os_type" = "cloudlinux" ]; then
    # Detect CRB/PowerTools repo name
    if [ "$os_major_version" -ge 9 ]; then
      extra_packages=$(dnf repolist all | grep "^crb")
      if [ -n "$extra_packages" ]; then
        extra_packages="crb"
        extra_packages_name="CRB"
      fi
    else
      extra_packages=$(dnf repolist all | grep "^powertools")
      extra_packages_name="PowerTools"
      if [ -n "$extra_packages" ]; then
        extra_packages="powertools"
      else
        extra_packages="PowerTools"
      fi
    fi

    run_ok "$install_config_manager --set-enabled $extra_packages" "Enabling $extra_packages_name package repository"
  fi


  # Important Perl packages are hidden in ol8_codeready_builder repo in Oracle
  if [ "$os_major_version" -ge 8 ] && [ "$os_type" = "ol" ]; then
    run_ok "$install_config_manager --set-enabled ol${os_major_version}_codeready_builder" "Enabling Oracle Linux $os_major_version CodeReady Builder"
  fi

  # XXX This is so stupid. Why does yum insists on extra commands?
  if [ "$os_major_version" -eq 7 ]; then
    run_ok "yum --quiet groups mark install $rhgroup" "Marking $rhgrouptext for install"
    run_ok "yum --quiet groups mark install $vmgroup" "Marking $vmgrouptext for install"
  fi
  
  # Clear cache
  run_ok "$install_cmd clean all" "Cleaning up software repo metadata"

  # Upgrade system packages first
  if [ -z "$noupdates" ]; then
    run_ok "$upgrade" "Checking and installing system package updates"
  fi

  # Install custom stack packages
  if [ -n "$virtualmin_stack_custom_packages" ]; then
    run_ok "$install $virtualmin_stack_custom_packages" "Installing missing stack packages"
  fi

  # Install core and stack
  run_ok "$install_group $rhgroupid" "Installing dependencies and system packages"
  run_ok "$install_group $vmgroupid" "Installing Virtualmin $vm_version and all related packages"
  rs=$?
  if [ $? -ne 0 ]; then
    fatal "Installation failed: $rs"
  fi

  return 0
}

install_virtualmin() {
  case "$package_type" in
  rpm)
    install_with_yum
    ;;
  deb)
    install_with_apt
    ;;
  *)
    install_with_tar
    ;;
  esac
  rs=$?
  if [ $? -eq 0 ]; then
    return 0
  else
    return "$rs"
  fi
}

yum_check_skipped() {
  loginstalled=0
  logskipped=0
  skippedpackages=""
  skippedpackagesnum=0
  while IFS= read -r line
  do
    if [ "$line" = "Installed:" ]; then
      loginstalled=1
    elif [ "$line" = "" ]; then
      loginstalled=0
      logskipped=0
    elif [ "$line" = "Skipped:" ] && [ "$loginstalled" = 1 ]; then
      logskipped=1
    elif [ "$logskipped" = 1 ]; then
      skippedpackages="$skippedpackages$line"
      skippedpackagesnum=$((skippedpackagesnum+1))
    fi
  done < "$log"
  if [ -z "$noskippedpackagesforce" ] && [ "$skippedpackages" != "" ]; then
    if [ "$skippedpackagesnum" != 1 ]; then
      ts="s"
    fi
    skippedpackages=$(echo "$skippedpackages" | tr -s ' ')
    log_warning "Skipped package${ts}:${skippedpackages}"
  fi
}

# virtualmin-release only exists for one platform...but it's as good a function
# name as any, I guess.  Should just be "setup_repositories" or something.
errors=$((0))
preconfigure_virtualmin_release
manage_virtualmin_branch_repos
bind_hook "phase2_post"
echo
phase "Installation" 3
bind_hook "phase3_pre"
install_virtualmin
if [ "$?" != "0" ]; then
  errorlist="${errorlist}  ${YELLOW}◉${NORMAL} Package installation returned an error.\\n"
  errors=$((errors + 1))
fi

bind_hook "phase3_post"

# Initialize embedded module if any
if [ -n "$module_name" ]; then
  bind_hook "modules_pre"
  # If module is available locally in the same directory use it
  if [ -f "$pwd/${module_name}.sh" ]; then
    chmod +x "$pwd/${module_name}.sh"
    # shellcheck disable=SC1090
    . "$pwd/${module_name}.sh"
  else
    log_warning "Requested module with the filename $pwd/${module_name}.sh does not exist."
  fi
  bind_hook "modules_post"
fi

# Reap any clingy processes (like spinner forks)
# get the parent pids (as those are the problem)
allpids="$(ps -o pid= --ppid $$) $allpids"
for pid in $allpids; do
  kill "$pid" 1>/dev/null 2>&1
done

# Final step is configuration. Wait here for a moment, hopefully letting any
# apt processes disappear before we start, as they're huge and memory is a
# problem. XXX This is hacky. I'm not sure what's really causing random fails.
sleep 1
echo
phase "Configuration" 4
bind_hook "phase4_pre"
if [ "$mode" = "mini" ]; then
  bundle="Mini${bundle}"
fi
# shellcheck disable=SC2086
virtualmin-config-system --bundle "$bundle" $virtualmin_config_system_excludes --log "$log"
if [ "$?" != "0" ]; then
  errorlist="${errorlist}  ${YELLOW}◉${NORMAL} Postinstall configuration returned an error.\\n"
  errors=$((errors + 1))
fi
sleep 1
# Do we still need to kill stuck spinners?
kill $! 1>/dev/null 2>&1

# Log SSL request status, if available
if [ -f "$VIRTUALMIN_INSTALL_TEMPDIR/virtualmin_ssl_host_status" ]; then
  virtualmin_ssl_host_status=$(cat "$VIRTUALMIN_INSTALL_TEMPDIR/virtualmin_ssl_host_status")
  log_debug "$virtualmin_ssl_host_status"
fi

# Functions that are used in the OS specific modifications section
disable_selinux() {
  seconfigfiles="/etc/selinux/config /etc/sysconfig/selinux"
  for i in $seconfigfiles; do
    if [ -e "$i" ]; then
      perl -pi -e 's/^SELINUX=.*/SELINUX=disabled/' "$i"
    fi
  done
}

# Changes that are specific to OS
case "$os_type" in
rhel | fedora | centos | centos_stream | rocky | almalinux | openEuler | ol | cloudlinux | amzn)
  disable_selinux
  ;;
esac

bind_hook "phase4_post"

# Process additional phases if set in third-party functions
if [ -n "$hooks__phases" ]; then
    # Trim leading and trailing whitespace
    trim() {
        echo "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
    }
    bind_hook "phases_pre"
    unset current_phase
    phases_error_occurred=0
    printf '%s\n' "$hooks__phases" | sed '/^$/d' > hooks__phases_tmp
    while IFS= read -r line; do
        # Split the line into components
        phase_number=$(trim "${line%%	*}")
        rest="${line#*	}"
        phase_name=$(trim "${rest%%	*}")
        rest="${rest#*	}"
        command=$(trim "${rest%%	*}")
        description=$(trim "${rest#*	}")
        # If it's a new phase, display phase progress
        if [ "$phase_number" != "$current_phase" ]; then
            echo
            phase "$phase_name" "$phase_number"
            current_phase="$phase_number"
        fi
        # Run the command
        if ! run_ok "$command" "$description"; then
            phases_error_occurred=1
            break
        fi
    done < hooks__phases_tmp
    # Exit if an error occurred
    if [ "$phases_error_occurred" -eq 1 ]; then
        exit 1
    fi
    bind_hook "phases_post"
fi

bind_hook "phases_all_post"

# Was LE SSL for hostname request successful?
if [ -d "$VIRTUALMIN_INSTALL_TEMPDIR/virtualmin_ssl_host_success" ]; then
  ssl_host_success=1
fi

# Cleanup the tmp files
bind_hook "clean_pre"
printf "${GREEN}▣▣▣${NORMAL} Cleaning up\\n"
if [ "$VIRTUALMIN_INSTALL_TEMPDIR" != "" ] && [ "$VIRTUALMIN_INSTALL_TEMPDIR" != "/" ]; then
  log_debug "Cleaning up temporary files in $VIRTUALMIN_INSTALL_TEMPDIR."
  find "$VIRTUALMIN_INSTALL_TEMPDIR" -delete
else
  log_error "Could not safely clean up temporary files because TMPDIR set to $VIRTUALMIN_INSTALL_TEMPDIR."
fi

if [ -n "$QUOTA_FAILED" ]; then
  log_warning "Quotas were not configurable. A reboot may be required. Or, if this is"
  log_warning "a VM, configuration may be required at the host level."
fi
bind_hook "clean_post"
echo
if [ $errors -eq "0" ]; then
  hostname=$(hostname -f)
  detect_ip
  if [ "$package_type" = "rpm" ]; then
    yum_check_skipped
  fi
  bind_hook "post_install_message"
  TIME=$(date +%s)
  echo "$VER=$TIME" > "/etc/webmin/virtual-server/installed"
  echo "$VER=$TIME" > "/etc/webmin/virtual-server/installed-auto"
  write_virtualmin_branch
else
  log_warning "The following errors occurred during installation:"
  echo
  printf "${errorlist}"
fi

exit 0
