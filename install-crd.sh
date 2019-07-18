#!/bin/bash
set -eu

# https://cloud.google.com/solutions/chrome-desktop-remote-on-compute-engine

DEFAULT_VIRTUAL_RESOLUTION=1920x1080

show_help()
{
    echo \
"Install Chrome Remote Desktop and x2go.

Usage: $(basename $0) [options]
Options:
    -r <resolution>: Chrome Remote Desktop screen resolution (default $DEFAULT_VIRTUAL_RESOLUTION)
"
    show_after_help
}

#####################################################################
SCRIPT_HOME=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
source $SCRIPT_HOME/common.sh "$SCRIPT_HOME"

show_after_help()
{
    echo "To authorize CRD, go to https://remotedesktop.google.com/headless"
    echo
    echo "SSH Password authentication might be disabled by default. To enable it:"
    echo "sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config"
    echo "systemctl restart sshd"
    echo
    echo "To set up CRD default resolution in your home dir:"
    echo "echo \"export CHROME_REMOTE_DESKTOP_DEFAULT_DESKTOP_SIZES=$VIRTUAL_RESOLUTION\" >> ~/.profile"
}

crd_set_resolution()
{
    resolution=$1
    echo "Setting Chrome Remote Desktop resolution to $resolution"
    sed_command="s/DEFAULT_SIZE_NO_RANDR = \"[0-9]*x[0-9]*\"/DEFAULT_SIZE_NO_RANDR = \"$resolution\"/g"
    sudo sed -i "$sed_command" /opt/google/chrome-remote-desktop/chrome-remote-desktop
}

install_crd()
{
    resolution=$1
    install_packages_from_repository ppa:x2go/stable \
        x2goserver \
        x2goserver-xsession \
        x2goclient

    install_packages_from_urls \
            https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
            # https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \

    crd_set_resolution $resolution

    show_after_help
}

usage()
{
    show_help 1>&2
    exit 1
}

#####################################################################

VIRTUAL_RESOLUTION=$DEFAULT_VIRTUAL_RESOLUTION

while getopts "?r:" o; do
    case "$o" in
        \?)
            show_help
            exit 0
            ;;
        r)
            VIRTUAL_RESOLUTION=$OPTARG
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))


install_crd $VIRTUAL_RESOLUTION
