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

# Essentials

git config --global user.name "${FULL_NAME}"
git config --global user.email "${EMAIL}"

git config --global gitubuntu.lpuser "${LAUNCHPAD_NAME}"

# Optional but useful

git config --global log.decorate "short"

git config --global core.excludesfile ~/.gitignore_global

gitignore="$(path_from_homedir $USERNAME .gitignore_global)"
touch "$gitignore"

# .pc is an artifact from quilt
ensure_file_contains $USERNAME "$gitignore" ".pc"
