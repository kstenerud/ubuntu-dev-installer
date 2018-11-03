#!/bin/bash
set -eu

# Modify a container to make it capable of hosting VMs and other containers.

if [ "$EUID" -ne 0 ]; then
    echo "$(basename $0) must run as root"
    exit 1
fi

mount_host() {
	container_name=$1
    device_name="$2"
    host_path="$3"
    mount_point="$4"

    lxc exec $container_name -- mkdir -p "$mount_point"
    lxc config device add $container_name $device_name disk source="$host_path" path="$mount_point"
}

mark_privileged()
{
	container_name=$1
    lxc config set $container_name security.privileged true
}

allow_nesting()
{
	container_name=$1
    # Allows running an LXC container inside another LXC container
    lxc config set $container_name security.nesting true
}

allow_kvm()
{
	container_name=$1
    # KVM needs access to /dev/kvm and /dev/vhost-net
    lxc config device add $container_name kvm unix-char path=/dev/kvm
    lxc config device add $container_name vhost-net unix-char path=/dev/vhost-net
    lxc config device set $container_name vhost-net mode 0600
}

allow_snap()
{
    container_name=$1
    mount_host $container_name lib-modules "/lib/modules" "/lib/modules"
}

show_help()
{
    echo "Modifies a container to make it able to host VMs, containers, and snaps

Usage: $(basename $0) <container name>"
}

usage()
{
    show_help 1>&2
    exit 1
}

#####################################################################

while getopts "?" o; do
    case "$o" in
        \?)
            show_help
            exit 0
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ $# -ne 1 ]; then
    usage
fi

CONTAINER_NAME=$1


allow_nesting $CONTAINER_NAME
allow_kvm $CONTAINER_NAME
allow_snap $CONTAINER_NAME
mark_privileged $CONTAINER_NAME

echo "Container $CONTAINER_NAME is now hostable."
