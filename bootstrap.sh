#!/bin/bash

#Defaults
VERBOSE=0
UPLOAD=0
ENABLE_GPG_SIGNING=0
BASE_PATH="/tmp"
YOCTO_TARGET="raspberrypi3"
CURRENT_WORKING_DIR=$(pwd)
YOCTO_BUILD_USER=$(whoami)
YOCTO_TEMP_DIR=""
YOCTO_RESULTS_DIR=""
BITBAKE_RECIPE="rpi-basic-image"
AWS_S3_BUCKET="s3://build.s3.aatlive.net"
AWS_S3_BUCKET_PATH=""
GIT_REPO_NAME=""
GIT_REPO_BRANCH=""
GIT_COMMIT_HASH=""
S3CMD_DOWNLOAD_CHECKSUM="d7477e7000a98552932d23e279d69a11"
S3CMD_DOWNLOAD_URL="http://ufpr.dl.sourceforge.net/project/s3tools/s3cmd/1.6.1/s3cmd-1.6.1.tar.gz"
S3CMD_VERSION_MINIMUM="1.6.1"
S3CMD_VERSION_ACTUAL=""
PGP_EMAIL=""

export YOCTO_RELEASE="pyro"

RED="\033[0;31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
NC="\033[0m" #No color

#The following variables are defined in shippable.yml
#  - AWS_ACCESS_KEY: The AWS IAM public key
#  - AWS_SECRET_KEY: The AWS IAM private key
#  - PGP_PRIVATE_KEY_BASE64: Used to sign sha256sum
#  - SSH_PRIVATE_KEY_BASE64: Used to clone private github repo

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

_install_s3cmd() {
    #Install s3cmd manually as the version in the apt repository is terribly out-of-date
    _debug "Installing s3cmd manually..."
    wget -P "${YOCTO_TEMP_DIR}" "${S3CMD_DOWNLOAD_URL}" || _die "Failed to download s3cmd"

    S3CMD_DOWNLOAD_NAME=$(basename "${S3CMD_DOWNLOAD_URL}")
    S3CMD_DOWNLOAD_PATH="${YOCTO_TEMP_DIR}"/"${S3CMD_DOWNLOAD_NAME}"

    #Validate download integrity before proceeding...
    S3CMD_DOWNLOAD_CHECKSUM_ACTUAL=$( md5sum "${S3CMD_DOWNLOAD_PATH}" | cut -d' ' -f1 )
    [ "${S3CMD_DOWNLOAD_CHECKSUM}" != "${S3CMD_DOWNLOAD_CHECKSUM_ACTUAL}" ] && _die "Checksum does not match!"

    tar xzf "${S3CMD_DOWNLOAD_PATH}" -C "${YOCTO_TEMP_DIR}" || _die "Failed to uncompress s3cmd download"
    pip install setuptools
    cd "${YOCTO_TEMP_DIR}"/$(basename "${S3CMD_DOWNLOAD_NAME}" .tar.gz)
    sudo python setup.py install || _die "Failed to install s3cmd"
    cd "${CURRENT_WORKING_DIR}"
}

_compare_versions () {
    if [ ! -z $3 ]; then
        _die  "More than two arguments were passed in!"
    fi

    if [ $1 = $2 ]; then
        echo 0 && return
    fi

    if [[ $2 = $(echo $@ | tr " " "\n" | sort -V | head -n1) ]]; then
        echo 1 && return
    fi

    if [[ $1 = $(echo $@ | tr " " "\n" | sort -V | head -n1) ]]; then
        echo -1 && return
    fi
}

#Check if the script is ran with elevated permissions
if [ "${EUID}" -eq 1 ]; then
    _die "${0##*/} should not be ran with sudo"
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
    "python-pip"
    "gnupg"
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
    "gpg2"
)

_usage() {
    cat << EOF

${0##*/} [-h] [-s] [-v] [-g] [-r string] [-p string] [-b path/to/directory] [-t string] -- setup yocto and compile/upload image
where:
    -h  show this help text
    -r  set yocto project release (default: pyro)
    -b  set path for temporary files (default: /tmp)
    -t  set target (default: raspberrypi3)
    -p  set bitbake recipe (default: rpi-basic-image)
    -u  set yocto build user
    -v  verbose output
    -g  gpg sign sha256sums
    -e  set pgp email
    -s  upload results to S3

EOF
}

while getopts ':h :v :s r: t: b: e: u: p:' option; do
    case "${option}" in
        h|\?) _usage
           exit 0
           ;;
        v) VERBOSE=1
           ;;
        s) UPLOAD=1
           ;;
        g) ENABLE_GPG_SIGNING=1
           ;;
        r) YOCTO_RELEASE="${OPTARG}"
           ;;
        b) BASE_PATH="${OPTARG}"
           ;;
        e) PGP_EMAIL="${OPTARG}"
           ;;
        t) TARGET="${OPTARG}"
           ;;
        p) BITBAKE_RECIPE="${OPTARG}"
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

GIT_REPO_NAME=$(basename $(git rev-parse --show-toplevel))
GIT_COMMIT_HASH=$(git rev-parse --short HEAD)

if [ "${CI}" = "true" ]; then
    GIT_REPO_BRANCH="${BRANCH}" #BRANCH is an environment variable provided by shippable
else
    GIT_REPO_BRANCH=$(git branch 2>/dev/null | grep '^*' | cut -d' ' -f2)
fi

_debug "repo name: ${GIT_REPO_NAME}"
_debug "repo branch: ${GIT_REPO_BRANCH}"
_debug "commit hash: ${GIT_COMMIT_HASH}"

_debug "Checking if build user: ${YOCTO_BUILD_USER} exists..."
if [ $(id -u "${YOCTO_BUILD_USER}" 2>/dev/null || echo -1) -ge 0 ]; then
    _debug "Build user already exists. Proceeding..."
else
    _log "User: ${YOCTO_BUILD_USER} does not exist. Creating..."
    sudo useradd "${YOCTO_BUILD_USER}" || _die "Failed to create user: ${YOCTO_BUILD_USER}"
    sudo passwd -d "${YOCTO_BUILD_USER}" || _die "Failed to delete password for user: ${YOCTO_BUILD_USER}"
    sudo usermod -aG sudo "${YOCTO_BUILD_USER}" || _die "Failed to add user: "${YOCTO_BUILD_USER}" to group: sudo"
fi

_debug "Installing package dependencies..."
#Install fedora dependencies
if [ $(command -v dnf) ]; then
    function gpg () {
        gpg2 "$@"
    }
    sudo dnf update -y && sudo dnf install -y "${dnf_dependencies[@]}"
fi

#Install ubuntu/debian dependencies
command -v apt-get >/dev/null 2>&1 && sudo apt-get update -y && sudo apt-get install -y "${apt_dependencies[@]}"

#Check for pgp key
if [ -z "${PGP_PRIVATE_KEY_BASE64}" ]; then
    if [ $(gpg --list-keys "${PGP_EMAIL}" ) ]; then
        _debug "Hell yeah, the gpg private keys is already imported"
    else
        _debug "PGP_PRIVATE_KEY_BASE64 is undefined and the private key hasnt been previously imported"
        _debug "Disabling GPG signing..."
        ENABLE_GPG_SIGNING=0
    fi
else
    _debug "Importing pgp private key..."
    echo "${PGP_PRIVATE_KEY_BASE64}" > infrastructure.private.asc.base64
    cat infrastructure.private.asc.base64 | base64 --decode > infrastructure.private.asc || _die "Failed to decode base64 file."
    gpg --import infrastructure.private.asc || _die "Failed to import private pgp key."
    rm infrastructure.private.asc* || _die "Failed to remove file."
fi

#Check for ssh key
if [ -z "${SSH_PRIVATE_KEY_BASE64}" ]; then
    _debug "SSH_PRIVATE_KEY_BASE64 is undefined."
else
    _debug "Importing ssh private key..."
    echo "${SSH_PRIVATE_KEY_BASE64}" > infrastructure.private.ssh.base64
    cat infrastructure.private.ssh.base64 | base64 --decode > infrastructure.private.ssh || _die "Failed to decode base64 file."
    mv infrastructure.private.ssh ~/.ssh/id_rsa || _die "Failed to move private ssh key."
    chmod 600 ~/.ssh/id_rsa || _die "Failed to change file permissions."
fi

#Check if directory doesn't exist
if [ ! -d "${BASE_PATH}" ]; then
    _die "Directory: ${BASE_PATH} does not exist!"
fi

export YOCTO_TEMP_DIR=$(mktemp -t yocto.XXXXXXXX -p "${BASE_PATH}" --directory --dry-run) #There are better ways of doing this.

_debug "Creating temporary directory: ${TEMP_DIR}"
mkdir "${YOCTO_TEMP_DIR}" || _die "Failed to create temporary directory: ${YOCTO_TEMP_DIR}"

_debug "Yocto Project Release: ${YOCTO_RELEASE}"

_debug "Cloning poky..."
git clone -b "${YOCTO_RELEASE}" git://git.yoctoproject.org/poky "${YOCTO_TEMP_DIR}"/poky || _die "Failed to clone poky repository"

_debug "Cloning meta-openembedded..."
git clone -b "${YOCTO_RELEASE}" git://git.openembedded.org/meta-openembedded "${YOCTO_TEMP_DIR}"/poky/meta-openembedded || _die "Failed to clone meta-openembedded repository"

_debug "Cloning meta-raspberrypi..."
git clone -b "${YOCTO_RELEASE}" git://git.yoctoproject.org/meta-raspberrypi "${YOCTO_TEMP_DIR}"/poky/meta-raspberrypi || _die "Failed to clone meta-raspberrypi repository"

_debug "Cloning meta-aatlive..."
if [ -n "${SSH_PRIVATE_KEY_BASE64}" -a "${CI}" = "true" ]; then #CI is an environment variable provided by Shippable
    _debug "Using provided ssh key..."
    ssh-agent bash -c 'ssh-add ~/.ssh/id_rsa; git clone -b "${YOCTO_RELEASE}" git@github.com:ableat/meta-aatlive.git "${YOCTO_TEMP_DIR}"/poky/meta-aatlive' || _die "Failed to clone meta-aatlive repository"
else
    git clone -b "${YOCTO_RELEASE}" git@github.com:ableat/meta-aatlive.git "${YOCTO_TEMP_DIR}"/poky/meta-aatlive || _die "Failed to clone meta-aatlive repository"
fi

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
  ${YOCTO_TEMP_DIR}/poky/meta-aatlive \
  "

BBLAYERS_NON_REMOVABLE ?= " \
  ${YOCTO_TEMP_DIR}/poky/meta \
  ${YOCTO_TEMP_DIR}/poky/meta-poky \
  "

EOF

#Quick hack that if we're totally honest, probably won't be fixed
#I was having problems preserving env variables across su (and yeah I know there's a param that SHOULD allow this)
mkdir -p /tmp/env
variables=(
    "YOCTO_TEMP_DIR"
    "YOCTO_TARGET"
    "BITBAKE_RECIPE"
)
for var in ${variables[@]}; do
    if [ -z $(eval echo \$$var) ]; then
        _die "One or more variables are not valid. Only reference variables that have been previously defined."
    fi
    echo $(eval echo \$$var) > /tmp/env/"${var}" || _die "Failed to write to file."
done

_debug "Building image. Additional images can be found in ${YOCTO_TEMP_DIR}/meta*/recipes*/images/*.bb"
sudo su "${YOCTO_BUILD_USER}" -p -c '\
    YOCTO_TEMP_DIR="$(cat /tmp/env/YOCTO_TEMP_DIR)" && \
    YOCTO_TARGET="$(cat /tmp/env/YOCTO_TARGET)" && \
    BITBAKE_RECIPE="$(cat /tmp/env/BITBAKE_RECIPE)" && \

    source "${YOCTO_TEMP_DIR}"/poky/oe-init-build-env "${YOCTO_TEMP_DIR}"/rpi/build && \
    echo MACHINE ??= \"${YOCTO_TARGET}\" >> "${YOCTO_TEMP_DIR}"/rpi/build/conf/local.conf && \
    bitbake "${BITBAKE_RECIPE}"' || {
        _die "Failed to build image ಥ﹏ಥ"
    }

_success "The image was successfully compiled ♥‿♥"

YOCTO_RESULTS_DIR="${YOCTO_TEMP_DIR}/rpi/build/tmp/deploy/images/${YOCTO_TARGET}"
YOCTO_RESULTS_BASENAME=$(basename "${YOCTO_RESULTS_SDIMG}" .rpi-sdimg)
YOCTO_RESULTS_SDIMG=$(ls "${YOCTO_RESULTS_DIR}"/*.rootfs.ext3)
YOCTO_RESULTS_EXT3=$(ls "${YOCTO_RESULTS_DIR}"/*.rootfs.rpi-sdimg)

_debug "Generating sha256sums..."
echo $(sha256sum "${YOCTO_RESULTS_SDIMG}" "${YOCTO_RESULTS_EXT3}") > "${YOCTO_RESULTS_DIR}"/$(basename "${YOCTO_RESULTS_SDIMG}" .rpi-sdimg).sha256sums || _die "Failed to generate sha256sums."

if [ "${ENABLE_GPG_SIGNING}" -eq 1 -a -n "${PGP_EMAIL}" ]; then
    _debug "Signing sha256sums..."
    gpg -vv --no-tty -u "${PGP_EMAIL}" --output "${YOCTO_RESULTS_BASENAME}".sha256sums.sig --detach-sig "${YOCTO_RESULTS_BASENAME}".sha256sums || _die "Failed to sign sha256sums."
else
    _debug "Skipping gpg signing..."
fi

if [ "${UPLOAD}" -eq 1 ]; then
    if [ -z "${AWS_ACCESS_KEY}" -o -z "${AWS_SECRET_KEY}" ]; then
        if [ $(ls "${HOME}"/.s3cfg* | head -c1 | wc -c) -eq 0 ]; then
            _die "One or more environmental variables are not set."
        fi
    fi

    if [ $(command -v s3cmd) ]; then
        S3CMD_VERSION_ACTUAL=$(s3cmd --version | cut -d' ' -f1)
        if [ $(_compare_versions "${S3CMD_VERSION_MINIMUM}" "${S3CMD_VERSION_ACTUAL}") -eq 1 ]; then
            _die "The s3cmd version doesn't meet the minimum requirements. Please install version "${S3CMD_VERSION_MINIMUM}" or greater."
        fi
    else
        _install_s3cmd
    fi

    _debug "$(s3cmd --version)"
    _debug "Uploading results to ${AWS_S3_BUCKET}"
    UPLOAD_TIME=$(date +%s)
    AWS_S3_BUCKET_PATH=Images/"${GIT_REPO_NAME}"/"${UPLOAD_TIME}"-"${GIT_COMMIT_HASH}"-"${GIT_REPO_BRANCH}"

    destination="${AWS_S3_BUCKET}"/"${AWS_S3_BUCKET_PATH}"/
    s3cmd put --acl-private --follow-symlinks --recursive --access_key="${AWS_ACCESS_KEY}" --secret_key="${AWS_SECRET_KEY}" "${YOCTO_RESULTS_DIR}" "${destination}" || _die "Failed to upload file: ${path}"
    unset destination
fi
