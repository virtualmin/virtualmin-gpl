#!/bin/sh
# shellcheck disable=SC2059 disable=SC2181 disable=SC2154
# virtualmin-install.sh
# Copyright 2005-2022 Virtualmin, Inc.
# Simple script to grab the virtualmin-release and virtualmin-base packages.
# The packages do most of the hard work, so this script can be small-ish and
# lazy-ish.

# WARNING: Anything not listed in the currently supported systems list is not
# going to work, despite the fact that you might see code that detects your
# OS and acts on it.  If it isn't in the list, the code is not complete and
# will not work.  More importantly, the repos that this script uses do not
# exist, if the OS isn't listed.  Don't even bother trying it.
#
# A manual install might work for you though.
# See here: https://www.virtualmin.com/documentation/installation/manual/

# License and version
SERIAL=GPL
KEY=GPL
VER=7.0.1
vm_version=7
upgrade_virtualmin_host=software.virtualmin.com

# Determines if we have a terminal
if ! tty -s; then
  INTERACTIVE_MODE="off"
else
  INTERACTIVE_MODE="on"
fi

# Set a trap to catch any exit, whether
# normal or forced (e.g. Ctrl-C)
enable_stty () {
  if [ "${INTERACTIVE_MODE}" != "off" ];then
    stty echo
  fi
}
trap enable_stty INT QUIT TERM EXIT

# Print usage info, if --help, set mode, etc.
# Temporary colors
if [ "${INTERACTIVE_MODE}" != "off" ];then
  RED="$(tput setaf 1)"
  YELLOW="$(tput setaf 3)"
  CYAN="$(tput setaf 6)"
  BLACK="$(tput setaf 16)"
  NORMAL="$(tput sgr0)"
  GREEN=$(tput setaf 2)
  CYANBG=$(tput setab 6)
  BRIGHTWHITEBG=$(tput setab 15)
  BOLD=$(tput bold)
else
  RED=''
  YELLOW=''
  CYAN=''
  BLACK=''
  NORMAL=''
  GREEN=''
  CYANBG=''
  BRIGHTWHITEBG=''
  BOLD=''
fi

# Currently supported systems:
supported="    ${CYANBG}${BLACK}${BOLD}Red Hat Enterprise Linux and derivatives${NORMAL}${CYAN}
      - RHEL 8 and 9 on x86_64
      - Alma and Rocky 8 and 9 on x86_64
      - CentOS 7 on x86_64${NORMAL}
      UNSTABLERHEL
    ${CYANBG}${BLACK}${BOLD}Debian Linux and derivatives${NORMAL}${CYAN}
      - Debian 10 and 11 on i386 and amd64
      - Ubuntu 20.04 LTS and 22.04 LTS on i386 and amd64${NORMAL}"

# Store new log each time
log=/root/virtualmin-install.log
if [ -e "$log" ]; then
  while true; do
    logcnt=$((logcnt+1))
    logold="$log.$logcnt"
    if [ ! -e "$logold" ]; then
      mv $log $logold
      break
    fi
  done
fi

skipyesno=0

# Set defaults
bundle='LAMP' # Other option is LEMP
mode='full'   # Other option is minimal

usage() {
  # shellcheck disable=SC2046
  printf "Usage: %s %s [options]\\n" "${CYAN}" $(basename "$0")
  echo
  echo "  If called without arguments, installs Virtualmin."
  echo
  printf "  ${YELLOW}--help|-h${NORMAL}               display this help and exit\\n"
  printf "  ${YELLOW}--bundle|-b <LAMP|LEMP>${NORMAL} choose bundle to install (defaults to LAMP)\\n"
  printf "  ${YELLOW}--minimal|-m${NORMAL}            install a smaller subset of packages for low-memory/low-resource systems\\n"
  printf "  ${YELLOW}--unstable|-e${NORMAL}           enable support for Grade B systems (Fedora, CentOS Stream, Oracle)\\n"
  printf "  ${YELLOW}--no-package-updates|-x${NORMAL} skip installing system package updates\\n"
  printf "  ${YELLOW}--setup|-s${NORMAL}              setup Virtualmin software repositories and exit\\n"
  printf "  ${YELLOW}--hostname|-n${NORMAL}           set fully qualified hostname\\n"
  printf "  ${YELLOW}--force|-f${NORMAL}              assume \"yes\" as answer to all prompts\\n"
  printf "  ${YELLOW}--verbose|-v${NORMAL}            increase verbosity\\n"
  printf "  ${YELLOW}--uninstall|-u${NORMAL}          removes all Virtualmin packages (do not use on a production system)\\n"
  echo
}

while [ "$1" != "" ]; do
  case $1 in
  --help | -h)
    usage
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
      printf "Unknown bundle ${YELLOW}$1${NORMAL}: exiting\\n"
      exit 1
      ;;
    esac
    ;;
  --minimal | -m)
    shift
    mode='minimal'
    ;;
  --unstable | -e)
    shift
    unstable='unstable'
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
    break
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
  --verbose | -v)
    shift
    VERBOSE=1
    ;;
  --uninstall | -u)
    shift
    mode="uninstall"
    ;;
  *)
    printf "Unrecognized option: $1\\n\\n"
    usage
    exit 1
    ;;
  esac
done

if [ "${INTERACTIVE_MODE}" != "off" ];then
  stty -echo
fi

if [ -z "$setup_only" ]; then
  echo "Running ${GREEN}Virtualmin ${vm_version}${NORMAL} pre-installation setup:"

  # Check if current time
  # is not older than
  # May 16, 2022
  TIMEBASE=1652691600
  TIME=$(date +%s)
  if [ "$TIME" -lt "$TIMEBASE" ]; then
    echo "  Force-syncing system time .."

    # Try to sync time automatically first
    if systemctl restart chronyd 1>/dev/null 2>&1; then
      sleep 15
    elif systemctl restart systemd-timesyncd 1>/dev/null 2>&1; then
      sleep 15
    fi

    # Check again after all
    TIME=$(date +%s)
    if [ "$TIME" -lt "$TIMEBASE" ]; then
      echo "  .. failed to automatically sync system time; it must be corrected manually to continue"
      exit
    fi
    echo "  .. done"
  # Graceful sync
  else
    echo "  Syncing system time .."
    if systemctl restart chronyd 1>/dev/null 2>&1; then
      sleep 2
      echo "  .. done"
    elif systemctl restart systemd-timesyncd 1>/dev/null 2>&1; then
      echo "  .. done"
      sleep 2
    fi
  fi

  # Update all system packages first
  printf "Checking for an update for a set of CA certificates ..\\n" >>$log
  echo "  Updating CA certificates .."
  if [ -x /usr/bin/dnf ]; then
    dnf -y update ca-certificates >>$log 2>&1
  elif [ -x /usr/bin/yum ]; then
    yum -y update ca-certificates >>$log 2>&1
  elif [ -x /usr/bin/apt-get ]; then
    apt-get -y install ca-certificates >>$log 2>&1
  fi
  echo "  .. done"

  # Make sure Perl is installed
  printf "Checking for Perl ..\\n" >>$log
fi
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
      printf "Perl ${RED}could not${NORMAL} be installed. Cannot continue.\\n"
      exit 2
    fi
    # couldn't find Perl, so we need to try to install it
    if [ -z "$setup_only" ]; then
      echo "  Attempting to install Perl .."
    fi
    if [ -x /usr/bin/dnf ]; then
      dnf -y install perl >>$log
    elif [ -x /usr/bin/yum ]; then
      yum -y install perl >>$log
    elif [ -x /usr/bin/apt-get ]; then
      apt-get update >>$log
      apt-get -q -y install perl >>$log
    fi
    perl_attempted=1
    # Loop. Next loop should either break or exit.
  else
    break
  fi
done
if [ -z "$setup_only" ]; then
  if [ "$perl_attempted" = 1 ]; then
    echo "  .. done"
  fi
fi
printf ".. found Perl at $perl\\n" >>$log

# Check for wget or curl or fetch
printf "Checking for HTTP client .." >>$log
while true; do
  if [ -x "/usr/bin/wget" ]; then
    download="/usr/bin/wget -nv"
    break
  elif [ -x "/usr/bin/curl" ]; then
    download="/usr/bin/curl -f -s -L -O"
    break
  elif [ -x "/usr/bin/fetch" ]; then
    download="/usr/bin/fetch"
    break
  elif [ "$wget_attempted" = 1 ]; then
    printf ".. ${RED}no HTTP client available. Could not install wget. Cannot continue.${NORMAL}\\n"
    exit 1
  fi

  # Made it here without finding a downloader, so try to install one
  wget_attempted=1
  if [ -x /usr/bin/dnf ]; then
    dnf -y install wget >>$log
  elif [ -x /usr/bin/yum ]; then
    yum -y install wget >>$log
  elif [ -x /usr/bin/apt-get ]; then
    apt-get update >>/dev/null
    apt-get -y -q install wget >>$log
  fi
done
if [ -z "$download" ]; then
  echo "Tried to install downloader, but failed. Do you have working network and DNS?"
fi
printf " found %s\\n" "$download" >>$log

# Check for gpg, debian 10 doesn't install by default!?
if [ -x /usr/bin/apt-get ]; then
  if [ ! -x /usr/bin/gpg ]; then
    printf "GPG not found, attempting to install .." >>$log
    apt-get update >>/dev/null
    apt-get -y -q install gnupg >>$log
  fi
fi

# If Pro user downloads GPL version of `install.sh` script
# to fix repos check if there is an active license exists
if [ -n "$setup_only" ]; then
  if [ "$SERIAL" = "GPL" ] && [ "$KEY" = "GPL" ] && [ -f /etc/virtualmin-license ]; then
    virtualmin_license_existing_serial="$(grep 'SerialNumber=' /etc/virtualmin-license | sed 's/SerialNumber=//')"
    virtualmin_license_existing_key="$(grep 'LicenseKey=' /etc/virtualmin-license | sed 's/LicenseKey=//')"
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
  LOGIN=""
  PRODUCT="GPL"
  repopath="gpl/"
  packagetype="gpl"
else
  LOGIN="$SERIAL:$KEY@"
  PRODUCT="Professional"
  packagetype="pro"
  repopath="pro/"
fi

# Virtualmin-provided packages
vmgroup="'Virtualmin Core'"
vmgrouptext="Virtualmin $vm_version provided packages"
debvmpackages="virtualmin-core"
deps=

if [ "$mode" = 'full' ]; then
  if [ "$bundle" = 'LAMP' ]; then
    rhgroup="'Virtualmin LAMP Stack'"
    rhgrouptext="Virtualmin $vm_version LAMP stack"
    debdeps="virtualmin-lamp-stack"
    ubudeps="virtualmin-lamp-stack"
  elif [ "$bundle" = 'LEMP' ]; then
    rhgroup="'Virtualmin LEMP Stack'"
    rhgrouptext="Virtualmin $vm_version LEMP stack"
    debdeps="virtualmin-lemp-stack"
    ubudeps="virtualmin-lemp-stack"
  fi
elif [ "$mode" = 'minimal' ]; then
  if [ "$bundle" = 'LAMP' ]; then
    rhgroup="'Virtualmin LAMP Stack Minimal'"
    rhgrouptext="Virtualmin $vm_version LAMP stack minimal"
    debdeps="virtualmin-lamp-stack-minimal"
    ubudeps="virtualmin-lamp-stack-minimal"
  elif [ "$bundle" = 'LEMP' ]; then
    rhgroup="'Virtualmin LEMP Stack Minimal'"
    rhgrouptext="Virtualmin $vm_version LEMP stack minimal'"
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
TMPNOEXEC="$(grep $TMPDIR /etc/mtab | grep noexec)"
if [ -n "$TMPNOEXEC" ]; then
  echo "${RED}Fatal:${NORMAL} $TMPDIR directory is mounted noexec. Cannot continue."
  exit 1
fi

if [ -z "$tempdir" ]; then
  tempdir="$TMPDIR/.virtualmin-$$"
  if [ -e "$tempdir" ]; then
    rm -rf "$tempdir"
  fi
  mkdir "$tempdir"
fi

# "files" subdir for libs
mkdir "$tempdir/files"
srcdir="$tempdir/files"
if ! cd "$srcdir"; then
  echo "Failed to cd to $srcdir"
  exit 1
fi

# Download the slib (source: http://github.com/virtualmin/slib)
# Lots of little utility functions.
$download "https://$upgrade_virtualmin_host/lib/slib.sh" >>$log 2>&1
if [ $? -ne 0 ]; then
  echo "${RED}Error:${NORMAL} Failed to download utility function library. Cannot continue. Check your network connection and DNS settings."
  exit 1
fi
chmod +x slib.sh
# shellcheck disable=SC1091
. ./slib.sh

# Check the serial number and key
serial_ok "$SERIAL" "$KEY"
# Setup slog
# shellcheck disable=SC2034
LOG_PATH="$log"
# Setup run_ok
# shellcheck disable=SC2034
RUN_LOG="$log"
# Exit on any failure during shell stage
# shellcheck disable=SC2034
RUN_ERRORS_FATAL=1

# Console output level; ignore debug level messages.
if [ "$VERBOSE" = "1" ]; then
  # shellcheck disable=SC2034
  LOG_LEVEL_STDOUT="DEBUG"
else
  # shellcheck disable=SC2034
  LOG_LEVEL_STDOUT="INFO"
fi
# Log file output level; catch literally everything.
# shellcheck disable=SC2034
LOG_LEVEL_LOG="DEBUG"

# log_fatal calls log_error
log_fatal() {
  log_error "$1"
}

remove_virtualmin_release() {
  # shellcheck disable=SC2154
  case "$os_type" in
  "fedora" | "centos" | "centos_stream" | "rhel" | "rocky" | "almalinux" | "ol")
    rm -f /etc/yum.repos.d/virtualmin.repo
    rm -f /etc/pki/rpm-gpg/RPM-GPG-KEY-virtualmin-*
    rm -f /etc/pki/rpm-gpg/RPM-GPG-KEY-webmin
    ;;
  "debian" | "ubuntu")
    grep -v "virtualmin" /etc/apt/sources.list >"$tempdir"/sources.list
    mv "$tempdir"/sources.list /etc/apt/sources.list
    rm -f /etc/apt/sources.list.d/virtualmin.list
    rm -f /etc/apt/auth.conf.d/virtualmin.conf
    rm -f /usr/share/keyrings/debian-virtualmin-*
    rm -f /usr/share/keyrings/debian-webmin.gpg
    ;;
  esac
}

fatal() {
  echo
  log_fatal "Fatal Error Occurred: $1"
  printf "${RED}Cannot continue installation.${NORMAL}\\n"
  remove_virtualmin_release
  if [ -x "$tempdir" ]; then
    log_warning "Removing temporary directory and files."
    rm -rf "$tempdir"
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
  if command -pv named -v 1>/dev/null 2>&1; then
    preconfigured="${preconfigured}${YELLOW}${BOLD}BIND${NORMAL} "
  fi
  if command -pv apachectl -v 1>/dev/null 2>&1; then
    preconfigured="${preconfigured}${YELLOW}${BOLD}Apache${NORMAL} "
  fi
  if command -pv nginx -v 1>/dev/null 2>&1; then
    preconfigured="${preconfigured}${YELLOW}${BOLD}Nginx${NORMAL} "
  fi
  if command -pv mariadb 1>/dev/null 2>&1; then
    preconfigured="${preconfigured}${YELLOW}${BOLD}MariaDB${NORMAL} "
  fi
  if command -pv mysql 1>/dev/null 2>&1; then
    preconfigured="${preconfigured}${YELLOW}${BOLD}MySQL${NORMAL} "
  fi
  if command -pv php -v 1>/dev/null 2>&1; then
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
  if [ -f /etc/virtualmin-license ]; then
    # looks like it's been installed before
    return 0
  fi
  # XXX Probably not installed? Maybe we should remove license on uninstall, too.
  return 1
}

# This function performs a rough uninstallation of Virtualmin
# It is neither complete, nor correct, but it almost certainly won't break
# anything.  It is primarily useful for cleaning up a botched install, so you
# can run the installer again.
uninstall() {
  # Very destructive, ask first.
  echo
  printf "  ${REDBG}WARNING${NORMAL}\\n"
  echo
  echo "  This operation is very destructive. It removes nearly all of the packages"
  echo "  installed by the Virtualmin installer. Never run this on a production system."
  echo
  printf " Continue? (y/n) "
  if ! yesno; then
    exit
  fi

  # This is a crummy way to detect package manager...but going through
  # half the installer just to get here is even crummier.
  if command -pv rpm 1>/dev/null 2>&1; then
    package_type=rpm
  elif command -pv dpkg 1>/dev/null 2>&1; then
    package_type=deb
  fi

  case "$package_type" in
  rpm)
    yum groupremove -y --setopt="groupremove_leaf_only=true" "Virtualmin Core"
    yum groupremove -y --setopt="groupremove_leaf_only=true" "Virtualmin LAMP Stack"
    yum groupremove -y --setopt="groupremove_leaf_only=true" "Virtualmin LEMP Stack"
    yum groupremove -y --setopt="groupremove_leaf_only=true" "Virtualmin LAMP Stack Minimal"
    yum groupremove -y --setopt="groupremove_leaf_only=true" "Virtualmin LEMP Stack Minimal"
    yum remove -y virtualmin-base
    yum remove -y wbm-virtual-server wbm-virtualmin-htpasswd wbm-virtualmin-dav wbm-virtualmin-mailman wbm-virtualmin-awstats wbm-php-pear wbm-ruby-gems wbm-virtualmin-registrar wbm-virtualmin-init wbm-jailkit wbm-virtualmin-git wbm-virtualmin-slavedns wbm-virtual-server wbm-virtualmin-sqlite wbm-virtualmin-svn
    yum remove -y wbt-virtual-server-mobile
    yum remove -y virtualmin-config perl-Term-Spinner-Color
    yum remove -y webmin usermin awstats
    yum remove -y nginx
    yum remove -y fail2ban
    yum clean all
    os_type="centos"
    ;;
  deb)
    rm -rf /etc/fail2ban/jail.d/00-firewalld.conf
    rm -f /etc/fail2ban/jail.local
    apt-get remove --assume-yes --purge virtualmin-base virtualmin-core virtualmin-lamp-stack virtualmin-lemp-stack
    apt-get remove --assume-yes --purge virtualmin-lamp-stack-minimal virtualmin-lemp-stack-minimal
    apt-get remove --assume-yes --purge virtualmin-config libterm-spinner-color-perl
    apt-get remove --assume-yes --purge webmin-virtual-server webmin-virtualmin-htpasswd webmin-virtualmin-git webmin-virtualmin-slavedns webmin-virtualmin-dav webmin-virtualmin-mailman webmin-virtualmin-awstats webmin-php-pear webmin-ruby-gems webmin-virtualmin-registrar webmin-virtualmin-init webmin-jailkit webmin-virtual-server webmin-virtualmin-sqlite webmin-virtualmin-svn
    apt-get remove --assume-yes --purge webmin-virtual-server-mobile
    apt-get remove --assume-yes --purge fail2ban
    apt-get remove --assume-yes --purge apache2*
    apt-get remove --assume-yes --purge nginx*
    apt-get remove --assume-yes --purge webmin usermin
    apt-get autoremove --assume-yes
    os_type="debian"
    apt-get clean
    ;;
  *)
    echo "I don't know how to uninstall on this operating system."
    ;;
  esac
  echo 'Removing Virtualmin repo configuration'
  remove_virtualmin_release
  virtualmin_license_file="/etc/virtualmin-license"
  if [ -f "$virtualmin_license_file" ]; then
    echo "Removing Virtualmin license"
    rm "$virtualmin_license_file"
  fi
  echo "Done.  There's probably quite a bit of related packages and such left behind"
  echo "but all of the Virtualmin-specific packages have been removed."
  exit 0
}
if [ "$mode" = "uninstall" ]; then
  uninstall
fi

# Calculate disk space requirements (this is a guess, for now)
if [ "$mode" = 'minimal' ]; then
  disk_space_required=500
else
  disk_space_required=650
fi

# Message to display in interactive mode
install_msg() {
  cat <<EOF

  Welcome to the Virtualmin ${GREEN}$PRODUCT${NORMAL} installer, version ${GREEN}$VER${NORMAL}

  This script must be run on a freshly installed supported OS. It does not
  perform updates or upgrades (use your system package manager) or license
  changes (use the "virtualmin change-license" command).

  The systems currently supported by install script are:

EOF
  supported_all=$supported
  if [ -n "$unstable" ]; then
    unstable_rhel="${YELLOW}- Fedora Server 36+ on x86_64\\n \
     - CentOS Stream 8 and 9 on x86_64\\n \
     - Oracle Linux 8 and 9 on x86_64\\n \
          ${NORMAL}"
    supported_all=$(echo "$supported_all" | sed "s/UNSTABLERHEL/$unstable_rhel/")
  else
    supported_all=$(echo "$supported_all" | sed 's/UNSTABLERHEL//')
  fi
  echo "$supported_all"
  cat <<EOF

  If your OS/version/arch is not listed, installation ${BOLD}${RED}will fail${NORMAL}. More
  details about the systems supported by the script can be found here:

    ${UNDERLINE}https://www.virtualmin.com/os-support${NORMAL}

  The selected package bundle is ${CYAN}${bundle}${NORMAL} and the size of install is
  ${CYAN}${mode}${NORMAL}. It will require up to ${CYAN}${disk_space_required} MB${NORMAL} of disk space.

  Exit and re-run this script with ${CYAN}--help${NORMAL} flag to see available options.

EOF

  printf " Continue? (y/n) "
  if ! yesno; then
    exit
  fi
}
if [ "$skipyesno" -ne 1 ] && [ -z "$setup_only" ]; then
  install_msg
fi

preconfigured_system_msg() {
  # Double check if installed, just in case above error ignored.
  is_preconfigured_rs=$(is_preconfigured)
  if [ -n "$is_preconfigured_rs" ]; then
    cat <<EOF

  ${BRIGHTWHITEBG}${RED}${BOLD} ATTENTION! ${NORMAL}

  Pre-installed software detected: $is_preconfigured_rs

  It is highly advised ${BOLD}${RED}not to pre-install or pre-configure${NORMAL} any additional packages on your OS.
  The installer expects a freshly installed OS, and anything you do differently might cause
  conflicts or configuration errors. If you need to enable third-party package repositories,
  do so after installation of Virtualmin, and only with extreme caution.

EOF
    printf " Continue? (y/n) "
    if ! yesno; then
      exit
    fi
  fi
}

already_installed_msg() {
  # Double check if installed, just in case above error ignored.
  if is_installed; then
    cat <<EOF

  ${BRIGHTWHITEBG}${RED}${BOLD} WARNING! ${NORMAL}

  Virtualmin may already be installed. This can happen if an installation failed,
  and can be ignored in that case.

  However, if Virtualmin has already been successfully installed you ${BOLD}${RED}must not${NORMAL}
  run this script again! It will cause breakage to your existing configuration.

  Virtualmin repositories can be fixed using ${WHITEBG}${BLACK}${BOLD}${0##*/} -s${NORMAL} command.

  License details can be changed using ${WHITEBG}${BLACK}${BOLD}virtualmin change-license${NORMAL} command.
  Changing the license never requires re-installation.

  Updates and upgrades must be performed from within either Virtualmin or using
  system package manager on the command line.

EOF
    printf " Continue? (y/n) "
    if ! yesno; then
      exit
    fi
  fi
}
if [ "$skipyesno" -ne 1 ] && [ -z "$setup_only" ]; then
  preconfigured_system_msg
  already_installed_msg
fi

# Check memory
if [ "$mode" = "full" ]; then
  minimum_memory=1610613
else
  # minimal mode probably needs less memory to succeed
  minimum_memory=1048576
fi
if ! memory_ok "$minimum_memory"; then
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
    fatal "Failed to download Virtualmin release package. Cannot continue. Check your network connection and DNS settings."
  else
    return 0
  fi
}

# Only root can run this
id | grep -i "uid=0(" >/dev/null
if [ "$?" != "0" ]; then
  uname -a | grep -i CYGWIN >/dev/null
  if [ "$?" != "0" ]; then
    fatal "${RED}Fatal:${NORMAL} The Virtualmin install script must be run as root"
  fi
fi

if [ -n "$setup_only" ]; then
  # If Virtualmin 6 is installed and a user needs to fix repos make,
  # sure that we don't switch 6 to 7 to keep the same stack packages
  reposfile="/etc/yum.repos.d/virtualmin.repo /etc/apt/sources.list.d/virtualmin.list /etc/apt/sources.list"
  vm_version_already_installed=$((vm_version - 1))
  for repofile in $reposfile; do
    if [ -f "$repofile" ]; then
      if grep -F -q "universal" "$repofile"; then
        vm_version=$vm_version_already_installed

        # Fix for Virtualmin 6 repos
        if [ "$vm_version" = "6" ]; then
          if [ "$SERIAL" != "GPL" ]; then
            repopath=""
          fi
          vm6_repos=1
        fi
      fi
    fi
  done
  log_info "Started Virtualmin $vm_version $PRODUCT software repositories setup"
  printf "${YELLOW}▣${NORMAL} Phase ${YELLOW}1${NORMAL} of ${GREEN}1${NORMAL}: Setup\\n"
else
  log_info "Started installation log in $log"
  log_debug "Phase 1 of 3: Setup"
  printf "${YELLOW}▣${CYAN}◻◻${NORMAL} Phase ${YELLOW}1${NORMAL} of ${GREEN}3${NORMAL}: Setup\\n"
fi

# Print out some details that we gather before logging existed
log_debug "Install mode: $mode"
log_debug "Product: Virtualmin $PRODUCT"
log_debug "install.sh version: $VER"

# Check for a fully qualified hostname
log_debug "Checking for fully qualified hostname .."
name="$(hostname -f)"
if [ -n "$forcehostname" ]; then
  set_hostname "$forcehostname"
elif ! is_fully_qualified "$name"; then
  set_hostname
fi

# Insert the serial number and password into /etc/virtualmin-license
log_debug "Installing serial number and license key into /etc/virtualmin-license"
echo "SerialNumber=$SERIAL" >/etc/virtualmin-license
echo "LicenseKey=$KEY" >>/etc/virtualmin-license
chmod 700 /etc/virtualmin-license
cd ..

# Populate some distro version globals
get_distro
log_debug "Operating system name:    $os_real"
log_debug "Operating system version: $os_version"
log_debug "Operating system type:    $os_type"
log_debug "Operating system major:   $os_major_version"

install_virtualmin_release() {
  # Grab virtualmin-release from the server
  log_debug "Configuring package manager for ${os_real} ${os_version} .."
  case "$os_type" in
  rhel | centos | centos_stream | rocky | almalinux | ol | fedora)
    case "$os_type" in
    rhel | centos | centos_stream)
      if [ "$os_type" = "centos_stream" ]; then
        if [ "$os_major_version" -lt 8 ] || [ -z "$unstable" ]; then
          printf "${RED}${os_real} ${os_version} is not supported by this installer.${NORMAL}\\n"
          exit 1
        fi
      else
        if [ "$os_major_version" -lt 7 ]; then
          printf "${RED}${os_real} ${os_version} is not supported by this installer.${NORMAL}\\n"
          exit 1
        fi
      fi
      ;;
    rocky | almalinux | ol)
      if [ "$os_major_version" -lt 8 ] || [ -z "$unstable" ] && [ "$os_type" = "ol" ]; then
        printf "${RED}${os_real} ${os_version} is not supported by this installer.${NORMAL}\\n"
        exit 1
      fi
      ;;
    fedora)
      if [ "$os_version" -lt 35 ] || [ -z "$unstable" ] && [ "$os_type" = "fedora" ]  ; then
        printf "${RED}${os_real} ${os_version} is not supported by this installer.${NORMAL}\\n"
        exit 1
      fi
      ;;
    *)
      printf "${RED}This OS/version is not recognized. Cannot continue.${NORMAL}\\n"
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
    if command -pv dnf 1>/dev/null 2>&1; then
      install="dnf -y install"
      update="dnf -y update"
      install_cmd="dnf"
      install_group="dnf -y --quiet --skip-broken group install --setopt=group_package_types=mandatory,default"
      install_config_manager="dnf config-manager"
      # Do not use package manager when fixing repos
      if [ -z "$setup_only" ]; then
        run_ok "$install dnf-plugins-core" "Installing core plugins for package manager"
      fi
    else
      install="/usr/bin/yum -y install"
      update="/usr/bin/yum -y update"
      install_cmd="/usr/bin/yum"
      if [ "$os_major_version" -ge 7 ]; then
        # Do not use package manager when fixing repos
        if [ -z "$setup_only" ]; then
          run_ok "yum --quiet groups mark convert" "Updating groups metadata"
        fi
      fi
      install_group="yum -y --quiet --skip-broken groupinstall --setopt=group_package_types=mandatory,default"
      install_config_manager="yum-config-manager"
    fi

    # Download release file
    if [ -n "$vm6_repos" ] && [ "$vm6_repos" -eq 1 ]; then
      rpm_release_file_download="virtualmin-release-latest.noarch.rpm"
      download "https://${LOGIN}$upgrade_virtualmin_host/vm/$vm_version/${repopath}${os_type}/${os_major_version}/${arch}/$rpm_release_file_download" "Downloading Virtualmin $vm_version release package"
    else
      rpm_release_file_download="virtualmin-$packagetype-release.noarch.rpm"
      download "https://${LOGIN}$upgrade_virtualmin_host/vm/$vm_version/rpm/$rpm_release_file_download" "Downloading Virtualmin $vm_version release package"
    fi
    
    # Remove existing pkg files as they will not
    # be replaced upon replease package upgrade
    if [ -x "/usr/bin/rpm" ]; then
      rpm_release_files="$(rpm -qal virtualmin*release)"
      rpm_release_files=$(echo "$rpm_release_files" | tr '\n' ' ')
      if [ -n "$rpm_release_files" ]; then
        for rpm_release_file in $rpm_release_files; do
           rm -f "$rpm_release_file"
        done
      fi
    fi

    # Remove releases first, as the system can
    # end up having both GPL and Pro installed
    rpm -e --nodeps --quiet "$(rpm -qa virtualmin*release)" >>${RUN_LOG} 2>&1

    # Install release file
    run_ok "rpm -U --replacepkgs --replacefiles --quiet $rpm_release_file_download" "Installing Virtualmin $vm_version release package"

    # Fix login credentials if fixing repos
    if [ -n "$setup_only" ]; then
      sed -i "s/SERIALNUMBER:LICENSEKEY@/$LOGIN/" /etc/yum.repos.d/virtualmin.repo
      sed -i 's/http:\/\//https:\/\//' /etc/yum.repos.d/virtualmin.repo
    fi
    ;;
  debian | ubuntu)
    case "$os_type" in
    ubuntu)
      if [ "$os_version" != "18.04" ] && [ "$os_version" != "20.04" ] && [ "$os_version" != "22.04" ] && [ -z "$vm6_repos" ]; then
        printf "${RED}${os_real} ${os_version} is not supported by this installer.${NORMAL}\\n"
        exit 1
      fi
      ;;
    debian)
      if [ "$os_major_version" -lt 10 ] && [ -z "$vm6_repos" ]; then
        printf "${RED}${os_real} ${os_version} is not supported by this installer.${NORMAL}\\n"
        exit 1
      fi
      ;;
    esac
    package_type="deb"
    if [ "$os_type" = "ubuntu" ]; then
      deps="$ubudeps"
      if [ "$vm6_repos" = 1 ]; then
        case "$os_version" in
        16.04*)
          repos="virtualmin-xenial virtualmin-universal"
          ;;
        18.04*)
          repos="virtualmin-bionic virtualmin-universal"
          ;;
        20.04*)
          repos="virtualmin-focal virtualmin-universal"
          ;;
        22.04*)
          repos="virtualmin-focal virtualmin-universal"
          ;;
        esac
      else
        repos="virtualmin"
      fi
    else
      deps="$debdeps"
      if [ "$vm6_repos" = 1 ]; then
        case "$os_version" in
        9*)
          repos="virtualmin-stretch virtualmin-universal"
          ;;
        10*)
          repos="virtualmin-buster virtualmin-universal"
          ;;
        11*)
          repos="virtualmin-buster virtualmin-universal"
          ;;
        esac
      else
        repos="virtualmin"
      fi
    fi
    log_debug "apt-get repos: ${repos}"
    if [ -z "$repos" ]; then # Probably unstable with no version number
      log_fatal "No repos available for this OS. Are you running unstable/testing?"
      exit 1
    fi
    # Remove any existing repo config, in case it's a reinstall
    remove_virtualmin_release
    apt_auth_dir='/etc/apt/auth.conf.d'
    LOGINREAL=$LOGIN
    if [ -d "$apt_auth_dir" ]; then
      if [ -n "$LOGIN" ]; then
        LOGINREAL=""
        printf "machine $upgrade_virtualmin_host login $SERIAL password $KEY\\n" >>"$apt_auth_dir/virtualmin.conf"
      fi
    fi
    for repo in $repos; do
      printf "deb [signed-by=/usr/share/keyrings/debian-virtualmin-$vm_version.gpg] https://${LOGINREAL}$upgrade_virtualmin_host/vm/${vm_version}/${repopath}apt ${repo} main\\n" >>/etc/apt/sources.list.d/virtualmin.list
    done

    # Install our keys
    log_debug "Installing Webmin and Virtualmin package signing keys .."
    download "https://$upgrade_virtualmin_host/lib/RPM-GPG-KEY-virtualmin-$vm_version" "Downloading Virtualmin $vm_version key"
    run_ok "gpg --import RPM-GPG-KEY-virtualmin-$vm_version && cat RPM-GPG-KEY-virtualmin-$vm_version | gpg --dearmor > /usr/share/keyrings/debian-virtualmin-$vm_version.gpg" "Installing Virtualmin $vm_version key"
    download "https://$upgrade_virtualmin_host/lib/RPM-GPG-KEY-webmin" "Downloading Webmin key"
    run_ok "gpg --import RPM-GPG-KEY-webmin && cat RPM-GPG-KEY-webmin | gpg --dearmor > /usr/share/keyrings/debian-webmin.gpg" "Installing Webmin key"

    run_ok "apt-get update" "Downloading repository metadata"
    # Make sure universe repos are available
    # XXX Test to make sure this run_ok syntax works as expected (with single quotes inside double)
    if [ $os_type = "ubuntu" ]; then
      if [ -x "/bin/add-apt-repository" ] || [ -x "/usr/bin/add-apt-repository" ]; then
        run_ok "add-apt-repository -y universe" \
          "Enabling universe repositories, if not already available"
      else
        run_ok "sed -ie '/backports/b; s/#*[ ]*deb \\(.*\\) universe$/deb \\1 universe/' /etc/apt/sources.list" \
          "Enabling universe repositories, if not already available"
      fi
    fi
    # XXX Is this still enabled by default on Debian/Ubuntu systems?
    run_ok "sed -ie 's/^deb cdrom:/#deb cdrom:/' /etc/apt/sources.list" "Disabling cdrom: repositories"
    install="DEBIAN_FRONTEND='noninteractive' /usr/bin/apt-get --quiet --assume-yes --install-recommends -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' -o Dpkg::Pre-Install-Pkgs::='/usr/sbin/dpkg-preconfigure --apt' install"
    update="DEBIAN_FRONTEND='noninteractive' /usr/bin/apt-get --quiet --assume-yes --install-recommends -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' -o Dpkg::Pre-Install-Pkgs::='/usr/sbin/dpkg-preconfigure --apt' upgrade"
    #export DEBIAN_FRONTEND=noninteractive
    install_updates="$install $deps"
    run_ok "apt-get clean" "Cleaning up software repo metadata"
    sed -i "s/\\(deb[[:space:]]file.*\\)/#\\1/" /etc/apt/sources.list
    ;;
  *)
    log_error " Your OS is not currently supported by this installer."
    log_error " You can probably run Virtualmin Professional on your system, anyway,"
    log_error " but you'll have to install it using the manual installation process."
    exit 1
    ;;
  esac

  return 0
}

# Setup repos only
if [ -n "$setup_only" ]; then
  if install_virtualmin_release; then
    log_success "Repository configuration successful. You can now install Virtualmin"
    log_success "components using your OS package manager."
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
    run_ok "$update" "Checking and installing system packages updates"
  fi

  # Silently purge packages that may cause issues upon installation
  /usr/bin/apt-get --quiet --assume-yes purge ufw >>${RUN_LOG} 2>&1

  # Install Webmin/Usermin first, because it needs to be already done
  # for the deps. Then install Virtualmin Core and then Stack packages
  # Do it all in one go for the nicer UI
  run_ok "$install webmin && $install usermin && $install $debvmpackages && $install $deps" "Installing Virtualmin $vm_version and all related packages"
  if [ $? -ne 0 ]; then
    log_warning "apt-get seems to have failed. Are you sure your OS and version is supported?"
    log_warning "https://www.virtualmin.com/os-support"
    fatal "Installation failed: $?"
  fi

  # Make sure the time is set properly
  /usr/sbin/ntpdate-debian >>${RUN_LOG} 2>&1

  return 0
}

install_with_yum() {
  # Enable CodeReady and EPEL on RHEL 8+
  if [ "$os_major_version" -ge 8 ] && [ "$os_type" = "rhel" ]; then
    # Important Perl packages are now hidden in CodeReady repo
    run_ok "$install_config_manager --set-enabled codeready-builder-for-rhel-$os_major_version-x86_64*-rpms" "Enabling Red Hat CodeReady package repository"
    # Install EPEL
    download "https://dl.fedoraproject.org/pub/epel/epel-release-latest-$os_major_version.noarch.rpm"
    run_ok "rpm -U --replacepkgs --quiet epel-release-latest-$os_major_version.noarch.rpm" "Installing EPEL $os_major_version release package"
  # Install EPEL on RHEL 7
  elif [ "$os_major_version" -eq 7 ] && [ "$os_type" = "rhel" ]; then
    download "https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm"
    run_ok "rpm -U --replacepkgs --quiet epel-release-latest-7.noarch.rpm" "Installing EPEL 7 release package"
  # Install EPEL on CentOS/Alma/Rocky
  elif [ "$os_type" = "centos" ] || [ "$os_type" = "centos_stream" ] || [ "$os_type" = "rocky" ] || [ "$os_type" = "almalinux" ]; then  
    run_ok "$install epel-release" "Installing EPEL release package"
  # Install EPEL on Oracle 7+
  elif [ "$os_type" = "ol" ]; then
    run_ok "$install oracle-epel-release-el$os_major_version" "Installing EPEL release package"
  fi

  # Important Perl packages are now hidden in PowerTools repo
  if [ "$os_major_version" -ge 8 ] && [ "$os_type" = "centos" ] || [ "$os_type" = "centos_stream" ] || [ "$os_type" = "rocky" ] || [ "$os_type" = "almalinux" ]; then
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
    run_ok "$update" "Checking and installing system packages updates"
  fi

  # Install core and stack
  run_ok "$install_group $rhgroup" "Installing dependencies and system packages"
  run_ok "$install_group $vmgroup" "Installing Virtualmin $vm_version and all related packages"
  if [ $? -ne 0 ]; then
    fatal "Installation failed: $?"
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
  if [ $? -eq 0 ]; then
    return 0
  else
    return $?
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
  if [ "$skippedpackages" != "" ]; then
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
install_virtualmin_release
echo
log_debug "Phase 2 of 3: Installation"
printf "${GREEN}▣${YELLOW}▣${CYAN}◻${NORMAL} Phase ${YELLOW}2${NORMAL} of ${GREEN}3${NORMAL}: Installation\\n"
install_virtualmin
if [ "$?" != "0" ]; then
  errorlist="${errorlist}  ${YELLOW}◉${NORMAL} Package installation returned an error.\\n"
  errors=$((errors + 1))
fi

# We want to make sure we're running our version of packages if we have
# our own version.  There's no good way to do this, but we'll
run_ok "$install_updates" "Installing Virtualmin $vm_version and all related packages updates"
if [ "$?" != "0" ]; then
  errorlist="${errorlist}  ${YELLOW}◉${NORMAL} Installing updates returned an error.\\n"
  errors=$((errors + 1))
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
log_debug "Phase 3 of 3: Configuration"
printf "${GREEN}▣▣${YELLOW}▣${NORMAL} Phase ${YELLOW}3${NORMAL} of ${GREEN}3${NORMAL}: Configuration\\n"
if [ "$mode" = "minimal" ]; then
  bundle="Mini${bundle}"
fi
virtualmin-config-system --bundle "$bundle"
if [ "$?" != "0" ]; then
  errorlist="${errorlist}  ${YELLOW}◉${NORMAL} Postinstall configuration returned an error.\\n"
  errors=$((errors + 1))
fi
config_system_pid=$!

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
"fedora" | "centos" | "centos_stream" | "rhel" | "rocky" | "almalinux" | "ol")
  disable_selinux
  ;;
esac

# kill the virtualmin config-system command, if it's still running
kill "$config_system_pid" 1>/dev/null 2>&1

# Make sure the cursor is back (if spinners misbehaved)
if [ "${INTERACTIVE_MODE}" != "off" ];then
  tput cnorm
fi

printf "${GREEN}▣▣▣${NORMAL} Cleaning up\\n"
# Cleanup the tmp files
if [ "$tempdir" != "" ] && [ "$tempdir" != "/" ]; then
  log_debug "Cleaning up temporary files in $tempdir."
  find "$tempdir" -delete
else
  log_error "Could not safely clean up temporary files because TMPDIR set to $tempdir."
fi

if [ -n "$QUOTA_FAILED" ]; then
  log_warning "Quotas were not configurable. A reboot may be required. Or, if this is"
  log_warning "a VM, configuration may be required at the host level."
fi
echo
if [ $errors -eq "0" ]; then
  hostname=$(hostname -f)
  detect_ip
  if [ "$package_type" = "rpm" ]; then
    yum_check_skipped
  fi
  log_success "Installation Complete!"
  log_success "If there were no errors above, Virtualmin should be ready"
  log_success "to configure at https://${hostname}:10000 (or https://${address}:10000)."
  log_success "You may receive a security warning in your browser on your first visit."
  log_success "Chromium based browsers, to bypass security warning screen may require"
  log_success "you to type \`thisisunsafe\` to get to the login page."
  TIME=$(date +%s)
  echo "$VER=$TIME" > "/etc/webmin/virtual-server/installed"
else
  log_warning "The following errors occurred during installation:"
  echo
  printf "${errorlist}"
fi

exit 0
