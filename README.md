Ubuntu Development Environment Installer
========================================

Scripts to help setting up a development environment primarily for ubuntu server development, troubleshooting, and bug fixing.


Scripts
-------


### install-guest.sh

This script sets up the actual development environment inside a guest environment. You can run this on anything from bare metal to a VM to a container.


### install-host.sh

This script sets up a virtualization host so that it can host other containers and VMs.
Currently, a containerized host cannot host containers that attempt to install snaps.


### make-container-hostable.sh

Modifies a container to allow it to run VMs and containers.


### map-path.sh

Relocates a path and bind-mounts from the original location. Use this to relocate big directories to another volume.


### share-root-samba.sh

A very dangerous script that shares / as root, over a samba guest account, read-write.


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

Note: I'm installing GUI components (-g), but they won't be usable unless your host environment has a desktop environment set up.

    git clone https://github.com/kstenerud/ubuntu-dev-installer.git
    useradd --create-home --shell /bin/bash --user-group karl
    cd ubuntu-dev-installer
    ./install-host.sh -g -b br0 -u karl


### Create a Guest

You can create a metal, VM, or container guest. Generally, the guest software should be installed in a virtualized guest environment rather than on bare metal.

#### Multipass

    multipass launch --name guest
    multipass exec fuest bash
    sudo su

#### LXD

    lxc launch ubuntu:bionic guest
    # Needed if you want the guest to be able to launch VMs and containers:
    ./make_container_hostable.sh guest
    lxc exec guest bash

#### Metal

Install via installation media.


#### Install Guest Software

This will create a fully virtualized Mate desktop environment with ubuntu dev tools, x2go, and Chrome remote desktop installed. You'll need to connect first via x2go in order to log in to Chrome and enable Chrome remote desktop.

    git clone https://github.com/kstenerud/ubuntu-dev-installer.git
    useradd --create-home --shell /bin/bash --user-group karl
    cd ubuntu-dev-installer
    ./install-guest.sh -g -d -t Europe/Berlin -l en:US -k us:pc105 -u karl
