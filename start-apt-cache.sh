#!/bin/bash
set -eu

show_help()
{
    echo \
"Starts an LXD container running apt-cacher-ng

Usage: $(basename $0) [options]

Options:
  -c <path>: Set the cache path to use (host side) (default $HOME/apt-cache)
  -d <distribution>: Set the distribution to launch (default bionic)
  -n <name>: Set the name of the container (default apt-cache)"
}

#####################################################################
SCRIPT_HOME=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
source $SCRIPT_HOME/common.sh "$SCRIPT_HOME"


CONTAINER_NAME=apt-cache
CACHE_DIR=$HOME/apt-cache
DISTRIBUTION=bionic

while getopts "?hn:c:d:" o; do
    case "$o" in
        \?)
            show_help
            exit 0
            ;;
        h)
            show_help
            exit 0
            ;;
        c)
            CACHE_DIR=$OPTARG
            ;;
        d)
            DISTRUBUTION=$OPTARG
            ;;
        n)
            CONTAINER_NAME=$OPTARG
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

echo "Deleting container $CONTAINER_NAME..."
lxc delete -f $CONTAINER_NAME || true
lxc launch ubuntu-daily:bionic $CONTAINER_NAME
lxc_set_autostart $CONTAINER_NAME
lxc_wait_for_guest_network $CONTAINER_NAME

lxc exec $CONTAINER_NAME -- apt update
lxc exec $CONTAINER_NAME -- apt install -y apt-cacher-ng avahi-daemon
lxc exec $CONTAINER_NAME -- service apt-cacher-ng stop
lxc_map_guest_user_to_host $CONTAINER_NAME apt-cacher-ng apt-cacher-ng $(id -u) $(id -g)
lxc_mount_host $CONTAINER_NAME apt-cache "$CACHE_DIR" /var/cache/apt-cacher-ng
lxc restart $CONTAINER_NAME
echo "$CONTAINER_NAME configured and started"
