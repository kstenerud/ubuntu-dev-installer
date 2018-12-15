#!/bin/bash
set -eu

show_help()
{
    echo \
"Configures the user's .profile.

Usage: $(basename $0) [options] <username> <full name> <email>

Options:
  -g: Add GUI support
"
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

WANTS_GUI_SUPPORT=0

while getopts "?g" o; do
    case "$o" in
        \?)
            show_help
            exit 0
            ;;
        g)
            WANTS_GUI_SUPPORT=1
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if (( $# != 3 )); then usage; fi
USERNAME=$1
FULL_NAME="$2"
EMAIL="$3"

assert_user_exists $USERNAME

profile="$(path_from_homedir $USERNAME .profile)"

ensure_file_contains $USERNAME "$profile" "export DEBFULLNAME=\"${FULL_NAME}\""
ensure_file_contains $USERNAME "$profile" "export DEBEMAIL=\"${EMAIL}\""

# Fix "clear-sign failed: Inappropriate ioctl for device"
ensure_file_contains $USERNAME "$profile" "export GPG_TTY=\$(tty)"

if (( $WANTS_GUI_SUPPORT )); then
    ensure_file_contains $USERNAME "$profile" 'eval `dbus-launch --sh-syntax`'
fi
