#!/bin/bash

#Defaults
VERBOSE=0
RELEASE="pyro"
BASE_PATH="/tmp"
YOCTO_TARGET="raspberrypi3"
YOCTO_BUILD_USER=$(whoami)

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
    -u  set yocto build user
    -v  verbose output

EOF
}

while getopts ':h :v r: t: b: u:' option; do
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
        u) YOCTO_BUILD_USER="${OPTARG}"
           ;;
        :) printf "missing argument for -%s\n" "${OPTARG}"
           _usage
           exit 1
           ;;
    esac
done
shift $((OPTIND - 1))

_debug "Checking if build user: ${YOCTO_BUILD_USER} exists..."
if [ $(id -u "${YOCTO_BUILD_USER}" 2>/dev/null || echo -1) -ge 0 ]; then
    _debug "Build user already exists"
else
    _log "User: ${YOCTO_BUILD_USER} does not exist. Creating..."
    sudo useradd "${YOCTO_BUILD_USER}" || _die "Failed to create user: ${YOCTO_BUILD_USER}"
    sudo passwd -d "${YOCTO_BUILD_USER}" || _die "Failed to delete password for user: ${YOCTO_BUILD_USER}"
    sudo usermod -aG sudo "${YOCTO_BUILD_USER}" || _die "Failed to add user: "${YOCTO_BUILD_USER}" to group: sudo"

    #Only append line if it's absent from the file
    line="${YOCTO_BUILD_USER} ALL=(ALL) NOPASSWD: ALL"
    if [ grep -Fxq "${line}" /etc/sudoers ]; then
        sudo echo "${line}" >> /etc/sudoers
    fi
    unset line
fi

_debug "Installing package dependencies..."
#Install fedora dependencies
command -v dnf >/dev/null 2>&1 && sudo dnf update -y && sudo dnf install -y "${dnf_dependencies[@]}"

#Install ubuntu/debian dependencies
command -v apt >/dev/null 2>&1 && sudo apt update -y && sudo apt install -y "${apt_dependencies[@]}"

#Check if directory doesn't exist
if [ ! -d "${BASE_PATH}" ]; then
    _die "Directory ${BASE_PATH} does not exist!"
fi

YOCTO_TEMP_DIR=$(mktemp -t yocto.XXXXXXXX -p "${BASE_PATH}" --directory --dry-run) #There are better ways of doing this.

_debug "Creating temporary directory: ${TEMP_DIR}"
mkdir "${YOCTO_TEMP_DIR}" || _die "Failed to create temporary directory: ${YOCTO_TEMP_DIR}"

_debug "Cloning poky..."
git clone -b "${RELEASE}" git://git.yoctoproject.org/poky "${YOCTO_TEMP_DIR}"/poky || _die "Failed to clone poky repository"

_debug "Cloning meta-openembedded..."
git clone -b "${RELEASE}" git://git.openembedded.org/meta-openembedded "${YOCTO_TEMP_DIR}"/poky/meta-openembedded || _die "Failed to clone meta-openembedded repository"

_debug "Cloning meta-raspberrypi..."
git clone -b "${RELEASE}" git://git.yoctoproject.org/meta-raspberrypi "${YOCTO_TEMP_DIR}"/poky/meta-raspberrypi || _die "Failed to clone meta-raspberrypi repository"

#Create custom bblayers.conf
mkdir -p "${YOCTO_TEMP_DIR}"/rpi/build/conf
sudo chmod -R 777 "${YOCTO_TEMP_DIR}" || _die "Failed to change directory: ${YOCTO_TEMP_DIR} permissions"

cat << EOF >> "${YOCTO_TEMP_DIR}"/rpi/build/conf/bblayers.conf || _die "Failed to create ${YOCTO_TEMP_DIR}/rpi/build/conf/bblayers.conf"
# POKY_BBLAYERS_CONF_VERSION is increased each time build/conf/bblayers.conf
# changes incompatibly
POKY_BBLAYERS_CONF_VERSION = "2"

BBPATH = "\${TOPDIR}"
BBFILES ?= ""

BBLAYERS ?= " \
  ${YOCTO_TEMP_DIR}/poky/meta \
  ${YOCTO_TEMP_DIR}/poky/meta-poky \
  ${YOCTO_TEMP_DIR}/poky/meta-yocto-bsp \
  ${YOCTO_TEMP_DIR}/poky/meta-openembedded/meta-oe \
  ${YOCTO_TEMP_DIR}/poky/meta-openembedded/meta-multimedia \
  ${YOCTO_TEMP_DIR}/poky/meta-openembedded/meta-networking \
  ${YOCTO_TEMP_DIR}/poky/meta-openembedded/meta-python \
  ${YOCTO_TEMP_DIR}/poky/meta-raspberrypi \
  "

BBLAYERS_NON_REMOVABLE ?= " \
  ${YOCTO_TEMP_DIR}/poky/meta \
  ${YOCTO_TEMP_DIR}/poky/meta-poky \
  "

EOF

#Quick hack that if we're totally honest, probably won't be fixed
#I was having problems preserving env variables across su (and yeah I know there's a param that SHOULD allow this)
echo "${YOCTO_TEMP_DIR}" > /tmp/YOCTO_TEMP_DIR || _die "Failed to write to file"
echo "${YOCTO_TARGET}" > /tmp/YOCTO_TARGET || _die "Failed to write to file"

_debug "Building image. Additional images can be found in ${YOCTO_TEMP_DIR}/meta*/recipes*/images/*.bb"
sudo su "${YOCTO_BUILD_USER}" -p -c '\
    source "$(cat /tmp/YOCTO_TEMP_DIR)"/poky/oe-init-build-env "$(cat /tmp/YOCTO_TEMP_DIR)"/rpi/build && \
    echo MACHINE ??= \"$(cat /tmp/YOCTO_TARGET)\" >> "$(cat /tmp/YOCTO_TEMP_DIR)"/rpi/build/conf/local.conf && \
    cat "$(cat /tmp/YOCTO_TEMP_DIR)"/rpi/build/conf/local.conf && bitbake rpi-basic-image' || {
        _die "Failed to build image"
}

_success "The image can be found in the following directory: ${YOCTO_TEMP_DIR}/rpi/build/tmp/deploy/images/${TARGET}/rpi-basic-image-${YOCTO_TARGET}.rpi-sdimg"
