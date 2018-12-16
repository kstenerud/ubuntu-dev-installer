#!/bin/bash
set -eu

DEFAULT_TIMEZONE=Europe/Berlin
DEFAULT_LANGUAGE_REGION=en:US
DEFAULT_KEYBOARD_LAYOUT_MODEL=us:pc105
DEFAULT_VIRTUAL_RESOLUTION=1920x1080
USER_GROUPS="adm sudo lxd kvm libvirt sbuild"

show_help()
{
    echo \
"Install software for an ubuntu server development environment inside a VM or container.

Usage: $(basename $0) [options]
Options:
    -g: Install GUI software as well.
    -d: Install a virtual desktop environment (Ubuntu Mate). Connect first using x2go, then set up Chrome Remote Desktop.
    -r <resolution>: Chrome Remote Desktop screen resolution (default $DEFAULT_VIRTUAL_RESOLUTION)
    -t <timezone>: Set timezone (default $DEFAULT_TIMEZONE)
    -l <language:region>: Set language and region (default $DEFAULT_LANGUAGE_REGION)
    -k <layout:model>: Set keyboard layout and model (default $DEFAULT_KEYBOARD_LAYOUT_MODEL)
    -u <user>: Add the specified user to groups: $USER_GROUPS
    -U: Create user if it doesn't exist.
    -p: Allow ssh users to log in using passwords."
}

#####################################################################
SCRIPT_HOME=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
source $SCRIPT_HOME/common.sh "$SCRIPT_HOME"


install_console_software()
{
    echo "Installing console software..."

    install_snaps \
        docker \
        git-ubuntu:classic:edge \
        lxd \
        multipass:classic:beta \
        ustriage:classic

    install_packages \
        apache2-dev \
        apt-cacher-ng \
        autoconf \
        autopkgtest \
        bison \
        bridge-utils \
        build-essential \
        cmake \
        cpu-checker \
        debconf-utils \
        debmake \
        devscripts \
        dh-make \
        dpkg-dev \
        flex \
        git-buildpackage \
        libvirt-clients \
        libvirt-daemon \
        libvirt-daemon-system \
        mtools \
        net-tools \
        nfs-common \
        nmap \
        ovmf \
        pastebinit \
        piuparts \
        pkg-config \
        python3-argcomplete \
        python3-launchpadlib \
        python3-lazr.restfulclient \
        python3-petname \
        python3-pip \
        python3-pkg-resources \
        python3-pygit2 \
        python3-pytest \
        python3-ubuntutools \
        qemu \
        qemu-kvm \
        quilt \
        rsnapshot \
        sbuild \
        snapcraft \
        squashfuse \
        tshark \
        ubuntu-dev-tools \
        uvtool \
        virtinst

    echo 'Acquire::http::Proxy "http://127.0.0.1:3142";' | sudo tee /etc/apt/apt.conf.d/01acng
}

install_gui_software()
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
        sublime-text:classic \
        telegram-desktop
}

crd_set_resolution()
{
    resolution=$1
    echo "Setting Chrome Remote Desktop resolution to $resolution"
    sed_command="s/DEFAULT_SIZE_NO_RANDR = \"[0-9]*x[0-9]*\"/DEFAULT_SIZE_NO_RANDR = \"$resolution\"/g"
    sed -i "$sed_command" /opt/google/chrome-remote-desktop/chrome-remote-desktop
}

install_desktop_environment()
{
    resolution=$1

    echo "Installing virtual desktop software..."

    # Force bluetooth to install and then disable it so that it doesn't break the rest of the install.
    install_packages bluez || true
    disable_services bluetooth
    install_packages

    install_packages software-properties-common ubuntu-mate-desktop openssh-server
    remove_packages light-locker
    
    install_packages_from_repository ppa:x2go/stable \
        x2goserver \
        x2goserver-xsession \
        x2goclient

    install_packages_from_urls \
            https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
            https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb

    crd_set_resolution $resolution

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

check_user_exists()
{
    user=$1
    force_create=$2

    if ! does_user_exist $user; then
        if (( $force_create )); then
            useradd --create-home --shell /bin/bash --user-group $user
        else
            echo "User $user doesn't exist. Please use -U switch to create." 1>&2
            return 1
        fi
    fi
}

usage()
{
    show_help 1>&2
    exit 1
}

#####################################################################

assert_is_root

WANTS_GUI_SOFTWARE=0
WANTS_DESKTOP_ENVIRONMENT=0
WANTS_SSH_PASSWORD_AUTH=0
SET_TIMEZONE=$DEFAULT_TIMEZONE
SET_LANGUAGE_REGION=$DEFAULT_LANGUAGE_REGION
SET_KEYBOARD_LAYOUT_MODEL=$DEFAULT_KEYBOARD_LAYOUT_MODEL
SETUP_FOR_USER=
FORCE_CREATE_USER=0
VIRTUAL_RESOLUTION=$DEFAULT_VIRTUAL_RESOLUTION

while getopts "?gdpr:t:l:k:u:U" o; do
    case "$o" in
        \?)
            show_help
            exit 0
            ;;
        g)
            WANTS_GUI_SOFTWARE=1
            ;;
        d)
            WANTS_DESKTOP_ENVIRONMENT=1
            ;;
        r)
            VIRTUAL_RESOLUTION=$OPTARG
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
            SETUP_FOR_USER=$OPTARG
            ;;
        U)
            FORCE_CREATE_USER=1
            ;;
        p)
            WANTS_SSH_PASSWORD_AUTH=1
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))


apt update && apt dist-upgrade -y

if [ ! -z "$SETUP_FOR_USER" ]; then
    check_user_exists "$SETUP_FOR_USER" $FORCE_CREATE_USER
fi

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

install_console_software

if (( $WANTS_GUI_SOFTWARE )) || (( $WANTS_DESKTOP_ENVIRONMENT )); then
    install_gui_software
fi

if (( $WANTS_DESKTOP_ENVIRONMENT )); then
    install_desktop_environment $VIRTUAL_RESOLUTION
fi

if [ ! -z "$SETUP_FOR_USER" ]; then
    add_user_to_groups $SETUP_FOR_USER $USER_GROUPS
fi

if (( $WANTS_SSH_PASSWORD_AUTH )); then
    sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
    service ssh restart
fi


echo "Guest install completed successfully. Your IP address is $(get_default_ip_address)."
