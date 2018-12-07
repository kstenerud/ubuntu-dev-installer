#!/bin/sh

# Set up a VPN connection via NetworkManager.
# You must download the credentials files first.

set -eu

get_homedir()
{
    user=$1
    eval echo "~$user"
}

if [ $# -ne 4 ]; then
	echo "Usage: $(basename $0) <linux username> <canonical username> <region> <path to canonical-vpn-credentials.zip>"
	echo "Where region is one of: tw, us, uk"
	echo "Get your VPN credentials from https://enigma.admin.canonical.com"
	exit 1
fi

LINUX_USER=$1
CANONICAL_USER=$2
REGION=$3
ZIPFILE=$4
VPN_DIR="$(get_homedir ${LINUX_USER})/.sesame"
CONF_FILE="${VPN_DIR}/${REGION}-${CANONICAL_USER}.conf"

if nmcli con | grep "${REGION}-${CANONICAL_USER}" >/dev/null; then
	echo "VPN ${REGION}-${CANONICAL_USER} already exists:"
	echo -n "  "
	nmcli con | grep "${REGION}-${CANONICAL_USER}"
	echo "Please remove it using sudo nmcli con delete <name> if you want to start over."
	exit 1
fi

unzip -o "${ZIPFILE}" -d "${VPN_DIR}"
chown -R $LINUX_USER:$LINUX_USER "$VPN_DIR"
for file in $(ls "$VPN_DIR"); do
    sed -i "s/\/home\/$CANONICAL_USER/\/home\/$LINUX_USER/g" "$VPN_DIR/$file"
done

echo "Setting NetworkManager managed to true..."
sed -i 's/managed=false/managed=true/g' /etc/NetworkManager/NetworkManager.conf

if [ -f /etc/netplan/10-lxc.yaml ]; then
	if ! grep "renderer: NetworkManager" /etc/netplan/10-lxc.yaml >/dev/null; then
		echo "Enabling NetworkManager renderer..."
		echo "  renderer: NetworkManager" |sudo tee -a /etc/netplan/10-lxc.yaml
		sudo netplan apply
		sudo service network-manager restart
	fi
fi

nmcli con import type openvpn file "${CONF_FILE}"

echo "You can now start and stop the VPN by calling:"
echo "  sudo nmcli con up ${REGION}-${CANONICAL_USER}"
echo "  sudo nmcli con down ${REGION}-${CANONICAL_USER}"

# TODO: Sometimes nmcli con up <name> fails.
# Need reboot maybe?
