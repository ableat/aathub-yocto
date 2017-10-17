#!/bin/bash

TEMP_DIR=$(mktemp --directory --dry-run) #There are better ways of doing this.
VERBOSE=0

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
    "getopts"
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

#Install fedora dependencies
command -v dnf >/dev/null 2>&1 && dnf update && dnf install -y "${dnf_dependencies[@]}"

#Install ubuntu/debian dependencies
command -v apt >/dev/null 2>&1 && apt update && apt install -y "${apt_dependencies[@]}"



_usage() {
    cat << EOF

${0##*/} [-h] [-v] -- setup yocto development environment
where:
    -h  show this help text
    -v  verbose

EOF
}

while getopts ':h :v' option; do
    case "${option}" in
        h|\?) _usage
           exit 0
              ;;
        v) VERBOSE=1
           ;;
        :) printf "missing argument for -%s\n" "${OPTARG}"
           _usage
           exit 1
           ;;
    esac
done
shift $((OPTIND - 1))

mkdir "${TEMP_DIR}" || _die "Failed to create temporary directory"

git clone git://git.yoctoproject.org/poky "${TEMP_DIR}"/poky || _die "Failed to clone yocto repository"
cd "${TEMP_DIR}"/poky
git checkout pyro
