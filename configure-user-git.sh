#!/bin/bash
set -eu

show_help()
{
    echo \
"Configures git for use with launchpad.

Usage: $(basename $0) <username> <full name> <email> <launchpad username>"
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

if (( $# != 4 )); then usage; fi
USERNAME=$1
FULL_NAME="$2"
EMAIL="$3"
LAUNCHPAD_NAME="$4"

assert_user_exists $USERNAME

gitconfig="$(path_from_homedir $USERNAME .gitconfig)"

add_to_file_if_not_found $USERNAME "$gitconfig" "[log]" \
"[log]
    decorate = short"

add_to_file_if_not_found $USERNAME "$gitconfig" "[user]" \
"[user]
    name = ${FULL_NAME}
    email = ${EMAIL}"

add_to_file_if_not_found $USERNAME "$gitconfig" "[gitubuntu]" \
"[gitubuntu]
    lpuser = ${LAUNCHPAD_NAME}"
