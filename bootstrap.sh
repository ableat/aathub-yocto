#!/bin/bash

#Defaults
VERBOSE=0
RELEASE="pyro"
BASE_PATH="/tmp"
TARGET="raspberrypi3"

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

#Check if the script is ran with elevated permissions
if [[ "${EUID}" -eq 1 ]]; then
    _die "${0##*/} should not be ran as sudo"
fi

apt_dependencies=(
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

_usage() {
    cat << EOF

${0##*/} [-h] [-v] [-r string] [-b path/to/directory] [-t string] -- setup yocto and compile target image
where:
    -h  show this help text
    -r  set yocto project release (default: pyro)
    -b  set path for temporary files (default: /tmp)
    -t  set target (default: raspberrypi3)
    -v  verbose output

EOF
}

while getopts ':h :v r: t: b:' option; do
    case "${option}" in
        h|\?) _usage
           exit 0
              ;;
        v) VERBOSE=1
           ;;
        r) RELEASE="${OPTARG}"
           ;;
        b) BASE_PATH="${OPTARG}"
           ;;
        t) TARGET="${OPTARG}"
           ;;
        :) printf "missing argument for -%s\n" "${OPTARG}"
           _usage
           exit 1
           ;;
    esac
done
shift $((OPTIND - 1))

_debug "Installing package dependencies..."
#Install fedora dependencies
command -v dnf >/dev/null 2>&1 && sudo dnf update -y && sudo dnf install -y "${dnf_dependencies[@]}"

#Install ubuntu/debian dependencies
command -v apt >/dev/null 2>&1 && sudo apt update -y && sudo apt install -y "${apt_dependencies[@]}"

TEMP_DIR=$(mktemp -t yocto.XXXXXXXX -p "${BASE_PATH}" --directory --dry-run) #There are better ways of doing this.

_debug "Creating temporary directory: ${TEMP_DIR}"
mkdir "${TEMP_DIR}" || _die "Failed to create temporary directory"

_debug "Cloning poky..."
git clone -b "${RELEASE}" git://git.yoctoproject.org/poky "${TEMP_DIR}"/poky || _die "Failed to clone poky repository"

_debug "Cloning meta-openembedded..."
git clone -b "${RELEASE}" git://git.openembedded.org/meta-openembedded "${TEMP_DIR}"/poky/meta-openembedded || _die "Failed to clone meta-openembedded repository"

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
  ${TEMP_DIR}/poky/meta-openembedded/meta-oe \
  ${TEMP_DIR}/poky/meta-openembedded/meta-multimedia \
  ${TEMP_DIR}/poky/meta-openembedded/meta-networking \
  ${TEMP_DIR}/poky/meta-openembedded/meta-python \
  ${TEMP_DIR}/poky/meta-raspberrypi \
  "

BBLAYERS_NON_REMOVABLE ?= " \
  ${TEMP_DIR}/poky/meta \
  ${TEMP_DIR}/poky/meta-poky \
  "

EOF

#Append local.conf
cat << EOF >> "${TEMP_DIR}"/rpi/build/conf/local.conf || _die "Failed to append ${TEMP_DIR}/rpi/build/conf/local.conf"
MACHINE ??= "${TARGET}"
EOF

_debug "Building image. Additional images can be found in ${TEMP_DIR}/meta*/recipes*/images/*.bb"
bitbake rpi-hwup-image || _die "Failed to build image"
_success "The image can be found in the following directory: ${TEMP_DIR}/rpi/build/tmp/deploy/images/${TARGET}/rpi-basic-image-${TARGET}.rpi-sdimg"


