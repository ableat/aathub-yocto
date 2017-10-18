#!/bin/bash

VERBOSE=0
RELEASE="pyro" #This can be overwritten with a command line parameter
BASE_PATH="/tmp"

RED="\033[0;31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
NC="\033[0m" #No color

_log() {
    echo -e ${0##*/}: "${@}" 1>&2
}

_debug() {
    if [ "${VERBOSE}" -eq 1 ]; then
        _log "${CYAN}DEBUG:${NC} ${@}"
    fi
}

_warn() {
    _log "${YELLOW}WARNING:${NC} ${@}"
}

_success() {
    _log "${GREEN}SUCCESS:${NC} ${@}"
}

_die() {
    _log "${RED}FATAL:${NC} ${@}"
    _cleanup
    exit 1
}
_cleanup() {
    rm -rf ${TEMP_DIR}
}

#Check if the script is ran without permissions
if [[ "${EUID}" -ne 0 ]]; then
    _die "${0##*/} must be ran as sudo"
fi

apt_dependencies=(
    "getopts"
    "gawk"
    "wget"
    "git-core"
    "diffstat"
    "unzip"
    "texinfo"
    "gcc-multilib"
    "build-essential"
    "chrpath"
    "socat"
    "cpio"
    "python"
    "python3"
    "python3-pip"
    "python3-pexpect"
    "xz-utils"
    "debianutils"
    "iputils-ping"
    "libsdl1.2-dev"
    "xterm"
)
dnf_dependencies=(
    "gawk"
    "make"
    "wget"
    "tar"
    "bzip2"
    "gzip"
    "python3"
    "unzip"
    "perl"
    "patch"
    "diffutils"
    "diffstat"
    "git"
    "cpp"
    "gcc"
    "gcc-c++"
    "glibc-devel"
    "texinfo"
    "chrpath"
    "ccache"
    "perl-Data-Dumper"
    "perl-Text-ParseWords"
    "perl-Thread-Queue"
    "perl-bignum"
    "socat"
    "python3-pexpect"
    "findutils"
    "which"
    "file"
    "cpio"
    "python"
    "python3-pip"
    "xz"
    "SDL-devel"
    "xterm"
)

_debug "Installing package dependencies..."
#Install fedora dependencies
command -v dnf >/dev/null 2>&1 && dnf update && dnf install -y "${dnf_dependencies[@]}"

#Install ubuntu/debian dependencies
command -v apt >/dev/null 2>&1 && apt update && apt install -y "${apt_dependencies[@]}"

_usage() {
    cat << EOF

${0##*/} [-h] [-v] [-r string] [-t path/to/directory] -- setup yocto development environment on host
where:
    -h  show this help text
    -r  set yocto project release (default: pyro)
    -t  set path for temporary files (default: /tmp)
    -v  verbose

EOF
}

while getopts ':h :v r: t:' option; do
    case "${option}" in
        h|\?) _usage
           exit 0
              ;;
        v) VERBOSE=1
           ;;
        r) RELEASE="${OPTARG}"
           ;;
        t) BASE_PATH="${OPTARG}"
           ;;
        :) printf "missing argument for -%s\n" "${OPTARG}"
           _usage
           exit 1
           ;;
    esac
done
shift $((OPTIND - 1))

TEMP_DIR=$(mktemp -t yocto.XXXXXXXX -p "${BASE_PATH}" --directory --dry-run) #There are better ways of doing this.

_debug "Creating temporary directory: ${TEMP_DIR}"
mkdir "${TEMP_DIR}" || _die "Failed to create temporary directory"

_debug "Cloning poky..."
git clone -b "${RELEASE}" git://git.yoctoproject.org/poky "${TEMP_DIR}"/poky || _die "Failed to clone poky repository"

_debug "Cloning meta-raspberrypi..."
git clone -b "${RELEASE}" git://git.yoctoproject.org/meta-raspberrypi "${TEMP_DIR}"/poky/meta-raspberrypi || _die "Failed to clone meta-raspberrypi repository"

_debug "Setup yocto build..."
mkdir -p "${TEMP_DIR}"/rpi/build
source "${TEMP_DIR}"/poky/oe-init-build-env "${TEMP_DIR}"/rpi/build

#Overwrite default bblayers.conf
rm "${TEMP_DIR}"/rpi/build/conf/bblayers.conf
cat << EOF >> "${TEMP_DIR}"/rpi/build/conf/bblayers.conf || _die "Failed to create ${TEMP_DIR}/rpi/build/conf/bblayers.conf"
# POKY_BBLAYERS_CONF_VERSION is increased each time build/conf/bblayers.conf
# changes incompatibly
POKY_BBLAYERS_CONF_VERSION = "2"

BBPATH = "\${TOPDIR}"
BBFILES ?= ""

BBLAYERS ?= " \
  ${TEMP_DIR}/poky/meta \
  ${TEMP_DIR}/poky/meta-poky \
  ${TEMP_DIR}/poky/meta-yocto-bsp \
  ${TEMP_DIR}/poky/meta-raspberrypi \
  "
EOF

#Append local.conf
cat << EOF >> "${TEMP_DIR}"/rpi/build/conf/local.conf || _die "Failed to append ${TEMP_DIR}/rpi/build/conf/local.conf"
MACHINE ?= "raspberrypi"
EOF

cat << EOF >> "${TEMP_DIR}"/rpi/build/conf/sanity.conf || _die "Failed to create ${TEMP_DIR}/rpi/build/conf/sanity.conf"
MACHINE ?= "raspberrypi"
EOF

_debug "Configure bitbake to run as root..."
sed -e '/INHERIT/ s/^#*/#/' -i "${TEMP_DIR}"/poky/meta/conf/sanity.conf || _die "Failed to comment out line in sanity.conf"

_debug "Building image..."
bitbake core-image-minimal


