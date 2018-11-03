#!/bin/bash
set -eu

# Map various VM and container technology paths to somewhere else

if [ "$EUID" -ne 0 ]; then
    echo "$(basename $0) must run as root"
    exit 1
fi

copy_directory_contents()
{
    src_dir=$1
    dst_dir=$2
    parent_dir="$(dirname "$dst_dir")"
    #shopt -s dotglob
    mkdir -p "$parent_dir"
    rsync -a "${src_dir}" "${parent_dir}"
    if [ "$(basename "$src_dir")" != "$(basename "$dst_dir")" ]; then
        mv "$parent_dir/$(basename "$src_dir")" "$parent_dir/$(basename "$dst_dir")"
    fi
}

generate_fstab_entry()
{
    src_dir="$1"
    dst_dir="$2"
    echo "$new_path $old_path none bind 0 0"
}

write_fstab_entry()
{
    src_dir="$1"
    dst_dir="$2"
    echo "$(generate_fstab_entry "$old_path" "$new_path")" | tee -a /etc/fstab >/dev/null
}

is_bind_mounted()
{
    src_dir="$1"
    dst_dir="$2"
    grep "$(generate_fstab_entry "$src_dir" "$dst_dir")" /etc/fstab >/dev/null
}

map_path()
{
    old_path="$1"
    new_path="$2"
    old_path_bak="${old_path}.bak"

    if is_bind_mounted "$old_path" "$new_path"; then
        echo "Path [$old_path] is already bind mounted to [$new_path]. Skipping."
        return 0
    fi

    if [ ! -d "$old_path" ]; then
        echo "Path [$old_path] doesn't exist. Skipping."
        return 0
    fi

    if [ -d "$new_path" ]; then
        echo "Path [$new_path] already exists. Skipping."
        return 0
    fi

    if [ -d "$old_path_bak" ]; then
        echo "Backup path [$old_path_bak] already exists. Skipping."
        return 0
    fi

    echo "Bind mounting [${old_path}] to [${new_path}], and creating backup [${old_path_bak}]."
    copy_directory_contents "$old_path" "$new_path"
    mv "${old_path}" "${old_path}.bak"
    mkdir -p "${old_path}"
    write_fstab_entry "$old_path" "$new_path"
}

show_help()
{
    echo "Bind mounts the following paths to a virtual \"home dir\":

Useful if you have a separate boot drive with limited space.

 * /var/lib/libvirt
 * /var/lib/lxd
 * /var/lib/uvtool
 * /var/snap/docker/common
 * /var/snap/lxd/common
 * /var/snap/multipass/common

Usage: $(basename $0) <virtual home dir>"
}

usage()
{
    show_help 1>&2
    exit 1
}

#####################################################################

COPY_CONTENTS=false

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

VIRT_HOME_DIR="$1"

echo "Backing up /etc/fstab to /etc/fstab.bak"
 cp -a /etc/fstab /etc/fstab.bak

map_path /var/lib/libvirt           "$VIRT_HOME_DIR/lib/libvirt"
map_path /var/lib/lxd               "$VIRT_HOME_DIR/lib/lxd"
map_path /var/lib/uvtool            "$VIRT_HOME_DIR/lib/uvtool"
map_path /var/snap/docker/common    "$VIRT_HOME_DIR/snap/docker"
map_path /var/snap/lxd/common       "$VIRT_HOME_DIR/snap/lxd"
map_path /var/snap/multipass/common "$VIRT_HOME_DIR/snap/multipass"

echo "Paths mapped. Re-mounting..."
mount -a
echo "You should reboot now."
