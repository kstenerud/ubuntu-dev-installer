Ubuntu Development Environment Installer
========================================

Scripts to help setting up a development environment primarily for ubuntu server development, troubleshooting, and bug fixing.

The environment is split into a **host** environment, which then hosts a **guest** environment, although you can forego the host side and just install the guest environment directly. Setting up a host environment makes it easier to destroy and rebuild your dev environment if you break things (basically a couple of script calls and you're back in business).


Scripts
-------

All scripts are idempotent.


#### configure-dev-user.sh

Configure a user for development, adding various configuration files for git, quilt, etc, and modifying their `.profile`.


#### download-virtual-images.sh

Pre-download various VM and container images for currently active Ubuntu releases.


#### install-guest.sh

This script sets up the actual development environment inside a guest environment. You can run this on anything from bare metal to a VM to a container.


#### install-host.sh

This script sets up a virtualization host so that it can host other containers and VMs.
Currently, a containerized host cannot host containers that attempt to install snaps.


#### make-container-hostable.sh

Modifies a container to allow it to run VMs and containers.


#### map-vm-paths.sh

Relocates and bind-mounts all existing VM and container directories on a host to save space on a boot drive:

 * /var/lib/libvirt
 * /var/lib/lxd
 * /var/lib/uvtool
 * /var/snap/docker/common
 * /var/snap/lxd/common
 * /var/snap/multipass/common


#### share-root-in-samba.sh

A very dangerous script that installs samba server and shares / as root, over a samba guest account, read-write.

This is only meant for debugging a broken virtual system.

YOU HAVE BEEN WARNED.


Typical Use
-----------

Typically, I set up my main machine as a host, and then host a virtual guest which I connect to as a thin client using Chrome RD (works on desktop and server). You can also forego the entire hosting side and just run the guest and user configuration scripts directly.


### Create a Host

You can create a metal, VM, or container host. Note that container hosts have some limitations.

#### Multipass

    multipass launch --name host
    multipass exec host bash
    sudo su

#### LXD

If you use LXD for the host, guests won't be able to install snaps due to a bug: https://discuss.linuxcontainers.org/t/how-to-install-lxd-in-a-lxd-container-that-is-being-built-in-a-lxd-container/1651

    lxc launch ubuntu:bionic host
    ./make_container_hostable.sh -a host
    lxc exec host bash

#### Metal

Install via installation media.


#### Install Host Software

Note: I'm installing GUI components (-g), but they won't be usable unless your host has a desktop environment set up. If your host doesn't have a GUI set up, just use console install (-c).

    git clone https://github.com/kstenerud/ubuntu-dev-installer.git
    useradd --create-home --shell /bin/bash --user-group karl
    cd ubuntu-dev-installer
    ./install-host.sh -g -b br0 -u karl


### Create a Guest

You can create a metal, VM, or container guest. Generally, you'll want to install in a virtualized guest environment rather than on bare metal, so that you can more quickly and easily rebuild after breaking things (just save your homedir).

You can install the guest as console-only, GUI (if your guest already has a desktop installed), or as a virtual desktop that you connect to via x2go or Chrome Remote Desktop.

#### Multipass

    multipass launch --name guest
    multipass exec guest bash
    sudo su

#### LXD

    lxc launch ubuntu:bionic guest
    # Needed to make snaps work:
    ./make_container_hostable.sh -s guest
    lxc exec guest bash

#### Metal

Install via installation media.


#### Install Guest Software

This will create a fully virtualized Mate desktop environment with Ubuntu dev tools, x2go, and Chrome Remote Desktop installed. You'll need to connect first via x2go in order to log in to Chrome and enable Chrome Remote Desktop.

    git clone https://github.com/kstenerud/ubuntu-dev-installer.git
    cd ubuntu-dev-installer
    ./install-guest.sh -d -t Europe/Berlin -l en:US -k us:pc105 -u karl -U
    ./configure-dev-user.sh -g karl
