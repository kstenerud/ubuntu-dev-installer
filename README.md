Ubuntu Development Environment Installer
========================================

Scripts to help setting up a development environment primarily for ubuntu server development, troubleshooting, and bug fixing.


Scripts
-------

### configure-dev-user.sh

Configure a user for development, adding various configuration files for git, quilt, etc, and modifying their `.profile`.


### download-virtual-images.sh

Pre-download various VM and container images for currently active Ubuntu releases.


### install-guest.sh

This script sets up the actual development environment inside a guest environment. You can run this on anything from bare metal to a VM to a container.


### install-host.sh

This script sets up a virtualization host so that it can host other containers and VMs.
Currently, a containerized host cannot host containers that attempt to install snaps.


### make-container-hostable.sh

Modifies a container to allow it to run VMs and containers.


### map-vm-paths.sh

Relocates and bind-mounts all existing VM and container directories on a host to save space on a boot drive:

 * /var/lib/libvirt
 * /var/lib/lxd
 * /var/lib/uvtool
 * /var/snap/docker/common
 * /var/snap/lxd/common
 * /var/snap/multipass/common


### share-root-in-samba.sh

A very dangerous script that installs samba server and shares / as root, over a samba guest account, read-write.

This is only meant for debugging a broken virtual system.

YOU HAVE BEEN WARNED.


Typical Use
-----------

### Create a Host

You can create a metal, VM, or container host. Note that container hosts have some limitations.

#### Multipass

    multipass launch --name host
    multipass exec host bash
    sudo su

#### LXD

If you use LXD for the host, guests won't be able to install snaps due to a bug: https://discuss.linuxcontainers.org/t/how-to-install-lxd-in-a-lxd-container-that-is-being-built-in-a-lxd-container/1651

    lxc launch ubuntu:bionic host
    ./make_container_hostable.sh host
    lxc exec host bash

#### Metal

Install via installation media.


#### Install Host Software

Note: I'm installing GUI components (-g), but they won't be usable unless your host has a desktop environment set up.

    git clone https://github.com/kstenerud/ubuntu-dev-installer.git
    useradd --create-home --shell /bin/bash --user-group karl
    cd ubuntu-dev-installer
    ./install-host.sh -g -b br0 -u karl


### Create a Guest

You can create a metal, VM, or container guest. Generally, you'll want to install in a virtualized guest environment rather than on bare metal, so that you can easily rebuild after breaking things (just save your homedir).

#### Multipass

    multipass launch --name guest
    multipass exec guest bash
    sudo su

#### LXD

    lxc launch ubuntu:bionic guest
    # Needed if you want the guest to be able to launch VMs and containers:
    ./make_container_hostable.sh guest
    lxc exec guest bash

#### Metal

Install via installation media.


#### Install Guest Software

This will create a fully virtualized Mate desktop environment with Ubuntu dev tools, x2go, and Chrome Remote Desktop installed. You'll need to connect first via x2go in order to log in to Chrome and enable Chrome Remote Desktop.

    git clone https://github.com/kstenerud/ubuntu-dev-installer.git
    cd ubuntu-dev-installer
    ./install-guest.sh -d -t Europe/Berlin -l en:US -k us:pc105 -u karl -U
