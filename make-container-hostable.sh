#!/bin/bash
set -eu

show_help()
{
    echo "Modifies a container to make it able to host VMs, containers, and snaps

Usage: $(basename $0) [options] <container name>
Options:
    -c: Allow container hosting
    -v: Allow VM hosting
    -s: Allow snaps
    -p: Mark privileged
    -a: All (enable everything)"
}

#####################################################################


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

has_allowed_kvm()
{
    container_name=$1
    lxc config device get $container_name kvm unix-char >/dev/null 2>&1
}

allow_kvm()
{
	container_name=$1

    if ! has_allowed_kvm $container_name; then
        # KVM needs access to /dev/kvm and /dev/vhost-net
        lxc config device add $container_name kvm unix-char path=/dev/kvm
        lxc config device add $container_name vhost-net unix-char path=/dev/vhost-net
        lxc config device set $container_name vhost-net mode 0600
    fi
}

has_allowed_snaps()
{
    container_name=$1
    device_name="$2"

    lxc config device get $container_name $device_name disk >/dev/null 2>&1
}

allow_snaps()
{
    container_name=$1
    device_name="lib-modules"

    if ! has_allowed_snaps $container_name $device_name; then
        mount_host $container_name $device_name "/lib/modules" "/lib/modules"
    fi
}

usage()
{
    show_help 1>&2
    exit 1
}

#####################################################################

if [ $# -lt 2 ]; then
    echo "Please specify at least one option."
    usage
fi

if [ "$EUID" -ne 0 ]; then
    echo "$(basename $0) must run using sudo"
    exit 1
fi

ALLOW_CONTAINER_HOSTING=false
ALLOW_VM_HOSTING=false
ALLOW_SNAPS=false
MAKE_PRIVILEGED=false

while getopts "?cvspa" o; do
    case "$o" in
        \?)
            show_help
            exit 0
            ;;
        c)
            ALLOW_CONTAINER_HOSTING=true
            ;;
        v)
            ALLOW_VM_HOSTING=true
            ;;
        s)
            ALLOW_SNAPS=true
            ;;
        p)
            MAKE_PRIVILEGED=true
            ;;
        a)
            ALLOW_CONTAINER_HOSTING=true
            ALLOW_VM_HOSTING=true
            ALLOW_SNAPS=true
            MAKE_PRIVILEGED=true
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


if [ "$ALLOW_CONTAINER_HOSTING" == "true" ]; then
    echo "Allowing container nesting..."
    allow_nesting $CONTAINER_NAME
fi

if [ "$ALLOW_VM_HOSTING" == "true" ]; then
    echo "Allowing VM hosting..."
    allow_kvm $CONTAINER_NAME
fi

if [ "$ALLOW_SNAPS" == "true" ]; then
    echo "Allowing snaps..."
    allow_snaps $CONTAINER_NAME
fi

if [ "$MAKE_PRIVILEGED" == "true" ]; then
    echo "Marking privileged..."
    mark_privileged $CONTAINER_NAME
fi
