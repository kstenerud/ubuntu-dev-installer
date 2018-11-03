#!/bin/bash
set -eu

# Install ubuntu development software inside a guest

if [ "$EUID" -ne 0 ]; then
    echo "$(basename $0) must run as root"
    exit 1
fi

sanitize_filename()
{
    filename="$(basename "$1" | tr -cd 'A-Za-z0-9_.')"
    echo "$filename"
}

install_snaps()
{
    snaps="$@"
    echo "Installing snaps: $snaps"
    for snap in $snaps; do
        snap install $snap
    done
}

install_classic_snaps()
{
    snaps="$@"
    echo "Installing classic snaps: $snaps"
    for snap in $snaps; do
        snap install $snap --classic
    done
}

install_packages()
{
    packages="$@"
    echo "Installing packages: $packages"
    bash -c "(export DEBIAN_FRONTEND=noninteractive; apt install -y $packages)"
}

install_packages_from_urls()
{
    urls="$@"
    echo "Installing URL packages: $urls"
    for url in $urls; do
        tmpfile="/tmp/tmp_deb_pkg_$(sanitize_filename $url).deb"
        wget -qO $tmpfile "$url"
        install_packages "$tmpfile"
        rm "$tmpfile"
    done
}

add_user_to_groups()
{
    username=$1
    shift
    groups=$@
    echo "Adding $username to groups: $groups"
    for group in $groups; do
        if grep $group /etc/group >/dev/null; then
            usermod -a -G $group $username
        else
            echo "WARNING: Not adding group $group because it doesn't exist."
        fi
    done
}

apply_bluetooth_fix()
{
    # Force bluetooth to install and then disable it so that it doesn't break the rest of the install.
    install_packages bluez || true
    disable_services bluetooth
    install_packages
}

install_console()
{
    echo "Installing console software..."

    install_packages \
        autoconf \
        autopkgtest \
        bison \
        bridge-utils \
        build-essential \
        cmake \
        cpu-checker \
        curl \
        debconf-utils \
        devscripts \
        docker.io \
        dpkg-dev \
        flex \
        fuse \
        git \
        git-buildpackage \
        libvirt-bin \
        lxd \
        mtools \
        nmap \
        net-tools \
        nfs-common \
        ovmf \
        pkg-config \
        python-pip \
        python3-argcomplete \
        python3-lazr.restfulclient \
        python3-debian \
        python3-distro-info \
        python3-launchpadlib \
        python3-pygit2 \
        python3-ubuntutools \
        python3-pkg-resources \
        python3-pytest \
        python3-petname \
        qemu \
        qemu-kvm \
        quilt \
        rsnapshot \
        snapcraft \
        snapd \
        squashfuse \
        ubuntu-dev-tools \
        uvtool \
        virtinst

    # Disabled until lxd snaps are fixed.
    # https://discuss.linuxcontainers.org/t/how-to-install-lxd-in-a-lxd-container-that-is-being-built-in-a-lxd-container/1651
    # install_snaps \
    #     docker \
    #     lxd

    snap install multipass --beta --classic

    install_classic_snaps \
        git-ubuntu \
        ustriage
}

install_gui()
{
    echo "Installing GUI software..."

    echo "wireshark-common  wireshark-common/install-setuid boolean true" | debconf-set-selections

    install_packages \
        filezilla \
        hexchat \
        meld \
        virt-manager \
        wireshark

    install_snaps \
        telegram-desktop

    install_classic_snaps \
        sublime-text
}

install_desktop()
{
    echo "Installing virtual desktop software..."

    apply_bluetooth_fix
    install_packages software-properties-common ubuntu-mate-desktop
    remove_packages light-locker
    
    install_packages_from_urls \
            https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
            https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb

    disable_services \
        apport \
        cpufrequtils \
        hddtemp \
        lm-sensors \
        network-manager \
        speech-dispatcher \
        ufw \
        unattended-upgrades

    echo "First time connection to the virtual desktop must be done using x2go. Once logged in, you can set up chrome remote desktop."
    echo
    echo "SSH Password authentication may be disabled by default. To enable it:"
    echo " * modify PasswordAuthentication in /etc/ssh/sshd_config"
    echo " * systemctl restart sshd"
}

set_timezone()
{
    timezone=$1

    echo "Setting timezone: $timezone"

    echo "$timezone" > /etc/timezone && dpkg-reconfigure -f noninteractive tzdata
}

set_language_region()
{
    language=$1
    region=$2

    lang_base=${language}_${region}
    lang_full=${lang_base}.UTF-8

    echo "Setting locale: $lang_full"

    locale-gen ${lang_base} ${lang_full}
    # update-locale LANG=${lang_full}
    # Only LANG seems to be necessary
    update-locale LANG=${lang_full} LANGUAGE=${lang_base}:${language} LC_ALL=${lang_full}
}

set_keyboard_layout_model()
{
    kb_layout=$1
    kb_model=$2

    echo "Setting keyboard layout: $1, model: $2"

    echo "keyboard-configuration keyboard-configuration/layoutcode string ${kb_layout}" | debconf-set-selections
    echo "keyboard-configuration keyboard-configuration/modelcode string ${kb_model}" | debconf-set-selections
}

does_user_exist()
{
    user=$1
    id -u $user >/dev/null 2>&1
}

check_user()
{
    user=$1
    force_create=$2

    if ! does_user_exist $user && [ "$force_create" != "true" ]; then
        echo "User $user doesn't exist. Please use -U switch to create." 1>&2
        return 1
    fi
}

setup_user()
{
    user=$1
    force_create=$2

    if ! does_user_exist $user && [ "$force_create" == "true" ]; then
        useradd --create-home --shell /bin/bash --user-group $user
    fi

    add_user_to_groups $user \
        adm \
        kvm \
        lxd \
        libvirt
}

show_help()
{
    echo "Install software for an ubuntu server development environment inside a VM or container.

Usage: $(basename $0) [options]
Options:
    -c: Install console software
    -g: Install GUI (as well as console) software
    -d: Install a virtual desktop environment
    -t <timezone>: Set timezone (e.g. America/Vancouver)
    -l <language:region>: Set language and region (e.g. en:US)
    -k <layout:model>: Set keyboard layout and model (e.g. us:pc105)
    -u <user>: Add the specified user to groups: adm kvm libvirt lxd
    -U: Create user if it doesn't exist."
}

usage()
{
    show_help 1>&2
    exit 1
}

#####################################################################

if [ $# -eq 0 ]; then
    usage
fi

INSTALL_CONSOLE=false
INSTALL_GUI=false
INSTALL_DESKTOP=false
SET_TIMEZONE=
SET_LANGUAGE_REGION=
SET_KEYBOARD_LAYOUT_MODEL=
SETUP_USER=
FORCE_CREATE_USER=false

while getopts "?cgdt:l:k:u:U" o; do
    case "$o" in
        \?)
            show_help
            exit 0
            ;;
        c)
            INSTALL_CONSOLE=true
            ;;
        g)
            INSTALL_GUI=true
            ;;
        d)
            INSTALL_DESKTOP=true
            ;;
        t)
            SET_TIMEZONE=$OPTARG
            ;;
        l)
            SET_LANGUAGE_REGION=$OPTARG
            ;;
        k)
            SET_KEYBOARD_LAYOUT_MODEL=$OPTARG
            ;;
        u)
            SETUP_USER=$OPTARG
            ;;
        U)
            FORCE_CREATE_USER=true
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))


if [ ! -z "$SETUP_USER" ]; then
    check_user "$SETUP_USER" $FORCE_CREATE_USER
fi

apt update

if [ ! -z "$SET_TIMEZONE" ] || [ ! -z "$SET_LANGUAGE_REGION" ] || [ ! -z "$SET_KEYBOARD_LAYOUT_MODEL" ]; then
    install_packages locales tzdata debconf software-properties-common

    if [ ! -z "$SET_TIMEZONE" ]; then
        set_timezone "$SET_TIMEZONE"
    fi

    if [ ! -z "$SET_LANGUAGE_REGION" ]; then
        set_language_region $(echo $SET_LANGUAGE_REGION | tr ":" " ")
    fi

    if [ ! -z "$SET_KEYBOARD_LAYOUT_MODEL" ]; then
        set_keyboard_layout_model $(echo $SET_KEYBOARD_LAYOUT_MODEL | tr ":" " ")
    fi
fi

if [ "$INSTALL_CONSOLE" == "true" ] ||  [ "$INSTALL_GUI" == "true" ]; then
    install_console
fi

if [ "$INSTALL_GUI" == "true" ]; then
    install_gui
fi

if [ "$INSTALL_DESKTOP" == "true" ]; then
    install_desktop
fi

if [ ! -z "$SETUP_USER" ]; then
    setup_user "$SETUP_USER" $FORCE_CREATE_USER
fi


echo "Guest install completed successfully."
