#!/bin/bash
set -eu

show_help()
{
    echo "Bind mounts the following paths to a virtual \"home dir\":

 * /var/lib/libvirt
 * /var/lib/lxd
 * /var/lib/uvtool
 * /var/snap/docker/common
 * /var/snap/lxd/common
 * /var/snap/multipass/common

Useful if you have a separate boot drive with limited space.

Note: Old paths are backed up as (path).bak

Usage: $(basename $0) [options] <virtual home dir>

Options:
    -e: If the new path already exists, map to it anyway (but don't copy)."
}

#####################################################################


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
    map_existing=$3
    old_path_bak="${old_path}.bak"
    copy_old_path=true

    if is_bind_mounted "$old_path" "$new_path"; then
        echo "Path [$old_path] is already bind mounted to [$new_path], skipping."
        return 0
    fi

    if [ ! -d "$old_path" ]; then
        echo "Old path [$old_path] doesn't exist, skipping."
        return 0
    fi

    if [ -d "$new_path" ]; then
        if [ "$map_existing" == "true" ]; then
            copy_old_path=false
        else
            echo "New path [$new_path] already exists, skipping. Use -e to map existing new path."
            return 0
        fi
    fi

    if [ "$copy_old_path" == "true" ]; then
        if [ -d "$old_path_bak" ]; then
            echo "Backup path [$old_path_bak] already exists, skipping."
            return 0
        fi

        echo "Bind mounting [${old_path}] to [${new_path}], and creating backup [${old_path_bak}]."
        copy_directory_contents "$old_path" "$new_path"
        mv "${old_path}" "${old_path}.bak"
        mkdir -p "${old_path}"
    else
        echo "Re-attaching [${old_path}] to [${new_path}], and creating backup [${old_path_bak}]."
    fi

    write_fstab_entry "$old_path" "$new_path"
}

usage()
{
    show_help 1>&2
    exit 1
}

#####################################################################

MAP_EXISTING=false

while getopts "?e" o; do
    case "$o" in
        \?)
            show_help
            exit 0
            ;;
        e)
            MAP_EXISTING=true
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

if [ "$EUID" -ne 0 ]; then
    echo "$(basename $0) must run using sudo"
    exit 1
fi

VIRT_HOME_DIR="$1"

echo "Backing up /etc/fstab to /etc/fstab.bak"
 cp -a /etc/fstab /etc/fstab.bak

map_path /var/lib/libvirt           "$VIRT_HOME_DIR/lib/libvirt"    $MAP_EXISTING
map_path /var/lib/lxd               "$VIRT_HOME_DIR/lib/lxd"        $MAP_EXISTING
map_path /var/lib/uvtool            "$VIRT_HOME_DIR/lib/uvtool"     $MAP_EXISTING
map_path /var/snap/docker/common    "$VIRT_HOME_DIR/snap/docker"    $MAP_EXISTING
map_path /var/snap/lxd/common       "$VIRT_HOME_DIR/snap/lxd"       $MAP_EXISTING
map_path /var/snap/multipass/common "$VIRT_HOME_DIR/snap/multipass" $MAP_EXISTING

echo "Paths mapped. Re-mounting..."
mount -a
echo "You should reboot now."
