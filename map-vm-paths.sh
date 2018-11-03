#!/bin/bash
set -eu

# /var/lib/libvirt
# /var/snap/lxd/common/lxd
# /var/snap/multipass/common/data

# $virt_home/system/libvirt
# $virt_home/system/lxd
# $virt_home/system/multipass
# $virt_home/iso
# $virt_home/mounts


copy_directory_contents()
{
    src_dir=$1
    dst_dir=$2
    shopt -s dotglob
    rsync -a ${src_dir}/* ${dst_dir}/
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
    echo "$(generate_fstab_entry "$old_path" "$new_path")" | tee -a /etc/fstab
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

    echo "Bind mounting [$old_path] to [$new_path]"

    if [ -d "$old_path" ]; then
        echo "Backup path [$old_path_bak] already exists! Aborting."
    fi

    if [ ! -d "$new_path" ]; then
        mkdir -p "${new_path}"
        if [ -d "$old_path" ]; then
            echo "Copying contents of [$old_path] to [$new_path]..."
            copy_directory_contents "$old_path" "$new_path"
        fi
    fi

    if [ -d "$old_path" ]; then
        echo "Backing up existing [${old_path}] to [${old_path}.bak]"
        mv "${old_path}" "${old_path}.bak"
    else
        echo "Old path [$old_path] doesn't exist yet. Creating it..."
    fi

    mkdir -p "${old_path}"
    write_fstab_entry "$old_path" "$new_path"
}

show_help()
{
    echo "Bind mounts the following paths to a virtual \"home dir\":

 * /var/lib/libvirt
 * /var/snap/lxd/common/lxd
 * /var/snap/multipass/common/data

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

map_path /var/snap/docker/common    "$VIRT_HOME_DIR/system/docker"
map_path /var/lib/libvirt           "$VIRT_HOME_DIR/system/libvirt"
map_path /var/lib/lxd               "$VIRT_HOME_DIR/system/lxd"
map_path /var/snap/multipass/common "$VIRT_HOME_DIR/system/multipass"
map_path /var/lib/uvtool            "$VIRT_HOME_DIR/system/uvtool"

echo "Paths mapped. Re-mounting..."
mount -a
