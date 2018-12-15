#!/bin/bash
set -eu

show_help()
{
    echo \
"Add the user to all required dev and admin groups.

Usage: $(basename $0) <username>"
}

#####################################################################
SCRIPT_HOME=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
source $SCRIPT_HOME/common.sh "$0"

usage()
{
    show_help 1>&2
    exit 1
}
#####################################################################


assert_is_root

if (( $# != 1 )); then usage; fi
USERNAME=$1

assert_user_exists $USERNAME

add_user_to_groups $USERNAME \
    adm \
    sudo \
    lxd \
    kvm \
    libvirt \
    sbuild
