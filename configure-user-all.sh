#!/bin/bash
set -eu

show_help()
{
    echo \
"Configures tooling and defaults for ubuntu development.

Usage: $(basename $0) [options] <username> <full name> <email> <launchpad username>
or:    $(basename $0) -r <username>

Options:
  -r: Reinstall system-level config only (if you've reinstalled the OS and moved your homedir over).
  -k: Run as the user: sbuild-update --keygen
  -h: Bind mount the user's homedir into schroot
  -s: Bind mount /scratch into ~/schroot/scratch
  -d <distribution>: Set the default distribution (default bionic)
  -g: This is a GUI user.

Help Pages:
 - https://wiki.ubuntu.com/SimpleSbuild
 - https://wiki.debian.org/UsingQuilt
 - http://manpages.ubuntu.com/manpages/cosmic/en/man1/dput.1.html
 - https://git-scm.com/book/en/v2"
}

#####################################################################
SCRIPT_HOME=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
source $SCRIPT_HOME/common.sh "$SCRIPT_HOME"

configure-user-profile()
{
    username=$1
    full_name="$2"
    email=$3
    wants_gui_support=$4

    options=
    if (( $wants_gui_support )); then options="-g"; fi

    "$SCRIPT_HOME/configure-user-profile.sh" $options $username "${full_name}" $email
}

configure-user-sbuild()
{
    username=$1
    full_name="$2"
    email=$3
    wants_keygen=$4
    wants_home_dir_mount=$5
    wants_scratch_mount=$6
    distribution=
    if [ $# -eq 7 ]; then
        distribution=$7
    fi

    options=
    if (( $wants_keygen )); then options="$options -k"; fi
    if (( $wants_home_dir_mount )); then options="$options -h"; fi
    if (( $wants_scratch_mount )); then options="$options -s"; fi
    if [ ! -z "$distribution" ]; then options="$options -d $distribution"; fi

    "$SCRIPT_HOME/configure-user-sbuild.sh" $options $username "$full_name" $email
}

usage()
{
    show_help 1>&2
    exit 1
}

#####################################################################

assert_is_root

REINSTALL=0
DISTRUBUTION=
WANTS_KEYGEN=0
WANTS_HOME_DIR_MOUNT=0
WANTS_GUI_SUPPORT=0
WANTS_SCRATCH_MOUNT=0

while getopts "gcrkhsd:" o; do
    case "$o" in
        \?)
            show_help
            exit 0
            ;;
        r)
            REINSTALL=1
            ;;
        g)
            WANTS_GUI_SUPPORT=1
            ;;
        k)
            WANTS_KEYGEN=1
            ;;
        h)
            WANTS_HOME_DIR_MOUNT=1
            ;;
        s)
            WANTS_SCRATCH_MOUNT=1
            ;;
        d)
            DISTRUBUTION=$OPTARG
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if (( $REINSTALL )); then
    if (( $# != 1 )); then
        usage
    fi
    USERNAME=$1

    echo "Reinstalling system level settings for $USERNAME..."
    "$SCRIPT_HOME/configure-user-groups.sh" $USERNAME
    exit 0
fi

if (( $# != 4 )); then usage; fi
USERNAME=$1
FULL_NAME="$2"
EMAIL=$3
LAUNCHPAD_NAME=$4

assert_user_exists $USERNAME

if (( $WANTS_GUI_SUPPORT )); then
    echo "Configuring user $USERNAME for GUI use..."
else
    echo "Configuring user $USERNAME for CONSOLE use..."
fi

configure-user-profile ${USERNAME} "${FULL_NAME}" "${EMAIL}" $WANTS_GUI_SUPPORT
"$SCRIPT_HOME/configure-user-quilt.sh" ${USERNAME}
"$SCRIPT_HOME/configure-user-dput.sh" ${USERNAME}
"$SCRIPT_HOME/configure-user-git.sh" ${USERNAME} "${FULL_NAME}" "${EMAIL}" "${LAUNCHPAD_NAME}"
configure-user-sbuild ${USERNAME} "${FULL_NAME}" "${EMAIL}" $WANTS_KEYGEN $WANTS_HOME_DIR_MOUNT $WANTS_SCRATCH_MOUNT $DISTRUBUTION
"$SCRIPT_HOME/configure-user-groups.sh" ${USERNAME}


echo 'Dev user configured successfully. Remember to set:
 * Password
 * SSH keys & authorized-keys
 * GPG keys
'
