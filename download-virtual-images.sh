#!/bin/bash
set -eu

# Pre-download various VM and container images for currently active Ubuntu releases.


# -------------
# Configuration
# -------------

ARCHITECTURE=amd64
AUTOPKGTEST_IMAGES_DIR=/var/lib/adt-images


# ------------------
# Installers & Tools
# ------------------

download_lxc_image()
{
    release=$1
    version=$2
    if [ "$release" == "-" ]; then return; fi

    echo "Downloading lxc $release $version"
    if [ "$version" = "daily" ]; then
        lxc image copy ubuntu-daily:$release local:
    else
        lxc image copy ubuntu:$release local:
    fi
}

download_uvt_image()
{
    release=$1
    version=$2
    if [ "$release" == "-" ]; then return; fi

    echo "Downloading uvt $release $version"
    if [ "$version" = "daily" ]; then
        uvt-simplestreams-libvirt sync arch=$ARCHITECTURE release=$release --source http://cloud-images.ubuntu.com/daily
    else
        uvt-simplestreams-libvirt sync arch=$ARCHITECTURE release=$release
    fi
}

download_adt_image()
{
    release=$1
    version=$2
    if [ "$release" == "-" ]; then return; fi

    echo "Downloading adt $release $version"
    mkdir -p "$AUTOPKGTEST_IMAGES_DIR"
    if [ "$version" = "daily" ]; then
        autopkgtest-buildvm-ubuntu-cloud -o "$AUTOPKGTEST_IMAGES_DIR" -r $release --cloud-image-url http://cloud-images.ubuntu.com/daily/server
        autopkgtest-build-lxd ubuntu-daily:$release/$ARCHITECTURE
    else
        autopkgtest-buildvm-ubuntu-cloud -o "$AUTOPKGTEST_IMAGES_DIR" -r $release
        autopkgtest-build-lxd ubuntu:$release/$ARCHITECTURE
    fi
}

download_image_sets()
{
    version=$1
    shift
    releases=$@
    for release in $releases; do
        download_lxc_image $release $version
        download_uvt_image $release $version
        download_adt_image $release $version
    done
}

# ------
# Images
# ------

echo "Installing VM and container images."

download_image_sets daily     cosmic
download_image_sets release   cosmic bionic xenial trusty

echo
echo "VM and container images have been installed."
