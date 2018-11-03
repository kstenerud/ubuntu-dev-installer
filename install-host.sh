#!/bin/bash
set -eu

# Install and configure a host machine for VMs and containers

if [ "$EUID" -ne 0 ]; then
    echo "$(basename $0) must run as root"
    exit 1
fi

get_homedir()
{
    user=$1
    eval echo "~$user"
}

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
            echo "WARNING: Not adding $username to group $group because it doesn't exist."
        fi
    done
}

make_user_paths()
{
    user=$1
    shift
    paths=$@
    echo "Creating user $user paths: $paths"
    for path in $paths; do
        mkdir -p "$path"
        chown ${user}:$(id -g ${user}) "$path"
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
    install_snaps \
        docker \
        lxd

    # Needed because the snap doesn't add it
    groupadd docker

    snap install multipass --beta --classic

    install_packages \
        git \
        libvirt-clients \
        libvirt-daemon-system \
        qemu-kvm \
        uvtool \
        virtinst
}

install_gui()
{
    install_classic_snaps \
        sublime-text

    install_packages \
        remmina \
        virt-manager \
        x2goclient

    install_packages_from_urls \
        https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
        https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
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

show_help()
{
    echo "Install software for hosting VMs and containers as a top level host.

Usage: $(basename $0) [options]
Options:
    -c: Install console software
    -g: Install GUI (as well as console) software
    -u <user>: Set the host user to map to container users that need host mounted access
    -U: Create user if it doesn't exist.
    -b <name>: Create a virtual bridge (doesn't work in lxd container)"
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
