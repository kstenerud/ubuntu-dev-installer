#!/bin/bash
set -eu

show_help()
{
    echo \
"Install software for hosting VMs and containers as a top level host.

Usage: $(basename $0) [options]
Options:
    -c: Install console software
    -g: Install GUI (as well as console) software
    -u <user>: Set the host user to map to container users that need host mounted access
    -U: Create user if it doesn't exist.
    -b <name>: Create a virtual bridge (doesn't work in lxd container)"
}

#####################################################################
SCRIPT_HOME=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
source $SCRIPT_HOME/common.sh "$SCRIPT_HOME"

make_user_paths()
{
    user=$1
    shift
    paths=$@
    echo "Creating user $user paths: $paths"
    for path in $paths; do
        mkdir -p "$path"
        chown -R ${user}:$(id -g ${user}) "$path"
    done
}

add_subuid_subgid_mapping()
{
    user=$1
    uid_mapping="root:$(id -u $1):1"
    gid_mapping="root:$(id -g $1):1"
    if ! grep "$uid_mapping" /etc/subuid >/dev/null; then
        echo "$uid_mapping" >> /etc/subuid
    fi
    if ! grep "$gid_mapping" /etc/subgid >/dev/null; then
        echo "$gid_mapping" >> /etc/subgid
    fi
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
        docker \
        kvm \
        lxd \
        libvirt

    add_subuid_subgid_mapping $user

    make_user_paths $user \
        "$(get_homedir $user)/bin"
}

install_console()
{
    install_packages \
        git \
        libnss-libvirt \
        libvirt-clients \
        libvirt-daemon-system \
        qemu-kvm \
        tree \
        uvtool \
        virtinst

    install_snaps \
        docker

    # Needed because the snap doesn't add it
    groupadd docker

    # Use LIBVIRT instead of QEMU due to bug launching disco
    # snap set multipass driver=LIBVIRT
}

install_gui()
{
    install_snaps \
        sublime-text:classic

    install_packages \
        remmina \
        virt-manager \
        x2goclient

    install_packages_from_urls \
        https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
        https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
}

install_real_bridge()
{
    eth_device=$1
    echo "bridges:
    br0:
      interfaces: [$eth_device]
      dhcp4: true
      parameters:
        stp: false
        forward-delay: 0" >> /etc/netplan/01-with-bridge.yaml
}

install_virtual_bridge()
{
    bridge_name=$1
    eth_name=eth0

    echo "Setting up bridge $bridge_name on $eth_name"

    cat <<EOF | lxd init --preseed
config: {}
cluster: null
networks:
- config:
    ipv4.address: auto
    ipv6.address: none
  description: ""
  managed: false
  name: ${bridge_name}
  type: ""
storage_pools:
- config: {}
  description: ""
  name: default
  driver: dir
profiles:
- config: {}
  description: ""
  devices:
    ${eth_name}:
      name: ${eth_name}
      nictype: bridged
      parent: ${bridge_name}
      type: nic
    root:
      path: /
      pool: default
      type: disk
  name: default
EOF

    if ! virsh net-uuid ${bridge_name} > /dev/null 2>&1; then
        echo "<network>
          <name>${bridge_name}</name>
          <bridge name=\"${bridge_name}\"/>
          <forward mode=\"bridge\"/>
        </network>
        " >/tmp/${bridge_name}.xml
        virsh net-define /tmp/${bridge_name}.xml
        rm /tmp/${bridge_name}.xml
        virsh net-start ${bridge_name}
        virsh net-autostart ${bridge_name}
    fi

    # Keeps bridge alive
    echo "Setting up frankenbridge..."
    lxc launch images:alpine/3.8 frankenbridge-${bridge_name}
    lxc config device add frankenbridge-${bridge_name} eth1 nic name=eth1 nictype=bridged parent=${bridge_name}

}

usage()
{
    show_help 1>&2
    exit 1
}

#####################################################################

assert_is_root

if [ $# -eq 0 ]; then
    usage
fi

INSTALL_CONSOLE=false
INSTALL_GUI=false
INSTALL_VIRTUAL_BRIDGE=
SETUP_USER=
FORCE_CREATE_USER=false

while getopts "?cgu:Ub:" o; do
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
        u)
            SETUP_USER=$OPTARG
            ;;
        U)
            FORCE_CREATE_USER=true
            ;;
        b)
            INSTALL_VIRTUAL_BRIDGE=$OPTARG
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

if [ "$INSTALL_CONSOLE" == "true" ] ||  [ "$INSTALL_GUI" == "true" ]; then
    install_console
fi

if [ ! -z "$INSTALL_VIRTUAL_BRIDGE" ]; then
    install_virtual_bridge "$INSTALL_VIRTUAL_BRIDGE"
fi

if [ ! -z "$SETUP_USER" ]; then
    setup_user "$SETUP_USER" $FORCE_CREATE_USER
fi

if [ "$INSTALL_GUI" == "true" ]; then
    install_gui
fi


echo "Host install completed successfully. Restart the machine to ensure everything's loaded."
