#!/bin/bash
set -eu

DEFAULT_TIMEZONE=Europe/Berlin
DEFAULT_LANGUAGE_REGION=en:US
DEFAULT_KEYBOARD_LAYOUT_MODEL=us:pc105
DEFAULT_VIRTUAL_RESOLUTION=1920x1080
USER_GROUPS="adm sudo"

show_help()
{
    echo \
"Install a virtual desktop inside a VM or container.

Usage: $(basename $0) [options]
Options:
    -r <resolution>: Chrome Remote Desktop screen resolution (default $DEFAULT_VIRTUAL_RESOLUTION)
    -t <timezone>: Set timezone (default $DEFAULT_TIMEZONE)
    -l <language:region>: Set language and region (default $DEFAULT_LANGUAGE_REGION)
    -k <layout:model>: Set keyboard layout and model (default $DEFAULT_KEYBOARD_LAYOUT_MODEL)
    -u <user>: Add the specified user to groups: $USER_GROUPS
    -U: Create user if it doesn't exist.
    -p: Allow ssh users to log in using passwords.
    -L: Install lubuntu desktop instead of mate."
}

#####################################################################
SCRIPT_HOME=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
source $SCRIPT_HOME/common.sh "$SCRIPT_HOME"


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
    wants_lubuntu_desktop=$2
    desktop_package=ubuntu-mate-desktop
    if (( $wants_lubuntu_desktop )); then
        desktop_package=lubuntu-desktop
    fi

    echo "Installing virtual desktop software..."

    # Force bluetooth to install and then disable it so that it doesn't break the rest of the install.
    install_packages bluez || true
    disable_services bluetooth
    install_packages

    install_packages software-properties-common openssh-server $desktop_package
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
            echo ${user}:${user} | chpasswd
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

WANTS_SSH_PASSWORD_AUTH=0
SET_TIMEZONE=$DEFAULT_TIMEZONE
SET_LANGUAGE_REGION=$DEFAULT_LANGUAGE_REGION
SET_KEYBOARD_LAYOUT_MODEL=$DEFAULT_KEYBOARD_LAYOUT_MODEL
SETUP_FOR_USER=
FORCE_CREATE_USER=0
VIRTUAL_RESOLUTION=$DEFAULT_VIRTUAL_RESOLUTION
WANTS_LUBUNTU_DESKTOP=0

while getopts "?pr:t:l:k:u:UL" o; do
    case "$o" in
        \?)
            show_help
            exit 0
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
        L)
            WANTS_LUBUNTU_DESKTOP=1
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))


assert_is_root

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

install_desktop_environment $VIRTUAL_RESOLUTION $WANTS_LUBUNTU_DESKTOP

if [ ! -z "$SETUP_FOR_USER" ]; then
    add_user_to_groups $SETUP_FOR_USER $USER_GROUPS
fi

if (( $WANTS_SSH_PASSWORD_AUTH )); then
    sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
    service ssh restart
fi


echo "Virtual desktop install completed successfully. Your IP address is $(get_default_ip_address)."
