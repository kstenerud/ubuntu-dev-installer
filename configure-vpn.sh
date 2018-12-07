#!/bin/sh

# Set up a VPN connection via NetworkManager.
# You must download the credentials files first.

set -eu

show_help()
{
    echo "Usage: $(basename $0) [options] <linux username> <canonical username> <region>"
    echo "Where region is one of: tw, us, uk"
    echo
    echo "Options:"
    echo "  -f <path-to-zipfile> Extract credentials from this zip file"
    echo
    echo "Get your VPN credentials from https://enigma.admin.canonical.com"
}

get_homedir()
{
    user=$1
    eval echo "~$user"
}

check_for_existing_vpn()
{
    canonical_user=$1
    region=$2

    if nmcli con | grep "${region}-${canonical_user}" >/dev/null; then
        echo "VPN ${region}-${canonical_user} already exists:"
        echo -n "  "
        nmcli con | grep "${region}-${canonical_user}"
        echo "Please remove it using sudo nmcli con delete <name> if you want to start over."
        exit 1
    fi
}

get_vpn_dir()
{
    linux_user=$1
    echo "$(get_homedir ${linux_user})/.sesame"
}

extract_credentials()
{
    file=$1
    canonical_user=$2
    linux_user=$3
    vpn_dir="$(get_vpn_dir $linux_user)"

    unzip -o "${file}" -d "${vpn_dir}"
    chown -R $linux_user:$linux_user "$vpn_dir"
    for file in $(ls "$vpn_dir"); do
        sed -i "s/\/home\/$canonical_user/\/home\/$linux_user/g" "$vpn_dir/$file"
    done
}

enable_network_manager_management()
{
    if grep "managed=false" /etc/NetworkManager/NetworkManager.conf >/dev/null; then
        echo "Setting NetworkManager managed to true..."
        sed -i 's/managed=false/managed=true/g' /etc/NetworkManager/NetworkManager.conf
        sudo service network-manager restart
    fi
}

enable_network_manager_renderer_in_lxc()
{
    if [ -f /etc/netplan/10-lxc.yaml ]; then
        if ! grep "renderer: NetworkManager" /etc/netplan/10-lxc.yaml >/dev/null; then
            echo "Enabling NetworkManager renderer..."
            echo "  renderer: NetworkManager" |sudo tee -a /etc/netplan/10-lxc.yaml
            sudo netplan apply
        fi
    fi
}

import_vpn_config()
{
    canonical_user=$1
    region=$2
    linux_user=$3

    conf_file="$(get_vpn_dir $linux_user)/${region}-${canonical_user}.conf"
    nmcli con import type openvpn file "${conf_file}"
}

usage()
{
    show_help
    exit 1
}

CONFIG_ARCHIVE_FILE=

while getopts "?f:" o; do
    case "$o" in
        \?)
            show_help
            exit 0
            ;;
        f)
            CONFIG_ARCHIVE_FILE=$OPTARG
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ $# -ne 3 ]; then
    usage
fi

LINUX_USER=$1
CANONICAL_USER=$2
REGION=$3

check_for_existing_vpn $CANONICAL_USER $REGION

if [ ! -z "$CONFIG_ARCHIVE_FILE" ]; then
    if [ ! -f "$CONFIG_ARCHIVE_FILE" ]; then
        echo "$CONFIG_ARCHIVE_FILE: File not found"
    fi
    extract_credentials "$CONFIG_ARCHIVE_FILE" $CANONICAL_USER $LINUX_USER
fi

enable_network_manager_management
enable_network_manager_renderer_in_lxc
import_vpn_config $CANONICAL_USER $REGION $LINUX_USER

echo "You can now start and stop the VPN by calling:"
echo "  sudo nmcli con up ${REGION}-${CANONICAL_USER}"
echo "  sudo nmcli con down ${REGION}-${CANONICAL_USER}"
echo
echo 'Note: "nmcli con up" may fail when you first configure the VPN. If you get "Error: Connection activation failed: Could not find source connection.", reboot.'
