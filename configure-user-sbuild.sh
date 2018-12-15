#!/bin/bash
set -eu

show_help()
{
    echo \
"Configures schroot and sdbuild, adding a mount point, .sbuildrc, and .mk-sbuild.rc if needed.

Usage: $(basename $0) [options] <username> <maintainer's name> <maintainer's email>

Options:
  -d <distribution>: Set the default distribution (default bionic)
  -k: Run as the user: sbuild-update --keygen
  -h: Bind mount the user's homedir into schroot
  -s: Bind mount /scratch into ~/schroot/scratch
"
}

#####################################################################
SCRIPT_HOME=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
source $SCRIPT_HOME/common.sh "$0"

add_schroot_mount()
{
    outside_path="$1"
    inside_path="$2"
    mount_line="$outside_path  $inside_path          none  rw,bind  0  0"

    add_to_file_if_not_found root /etc/schroot/sbuild/fstab "$inside_path" "$mount_line"
}

usage()
{
    show_help 1>&2
    exit 1
}
#####################################################################

assert_is_root

DEFAULT_DISTRIBUTION=bionic
WANTS_KEYGEN=0
WANTS_HOME_DIR_MOUNT=0
WANTS_SCRATCH_MOUNT=0

while getopts "?kshd:" o; do
    case "$o" in
        \?)
            show_help
            exit 0
            ;;
        d)
            DEFAULT_DISTRIBUTION=$OPTARG
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
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if (( $# != 3 )); then usage; fi
USERNAME=$1
MAINTAINER_NAME="$2"
MAINTAINER_EMAIL="$3"

assert_user_exists $USERNAME

home_dir="$(get_homedir $USERNAME)"
mount_point="$home_dir/schroot"

if (( $WANTS_HOME_DIR_MOUNT )); then
    add_schroot_mount "$home_dir" "$home_dir"
fi

create_dir $USERNAME "$mount_point/build"
create_dir $USERNAME "$mount_point/logs"

if (( $WANTS_SCRATCH_MOUNT )); then
    create_dir $USERNAME "$mount_point/scratch"
    add_schroot_mount "$mount_point/scratch" "/scratch"
fi

init_file_with_contents $USERNAME "$(path_from_homedir $USERNAME .sbuildrc)" \
"# Name to use as override in .changes files for the Maintainer: field
# (mandatory, no default!).
\$maintainer_name='$MAINTAINER_NAME <$MAINTAINER_EMAIL>';

# Default distribution to build.
\$distribution = \"$DEFAULT_DISTRIBUTION\";
# Build arch-all by default.
\$build_arch_all = 1;

# When to purge the build directory afterwards; possible values are 'never',
# 'successful', and 'always'.  'always' is the default. It can be helpful
# to preserve failing builds for debugging purposes.  Switch these comments
# if you want to preserve even successful builds, and then use
# 'schroot -e --all-sessions' to clean them up manually.
\$purge_build_directory = 'successful';
\$purge_session = 'successful';
\$purge_build_deps = 'successful';
# \$purge_build_directory = 'never';
# \$purge_session = 'never';
# \$purge_build_deps = 'never';

# Directory for writing build logs to
\$log_dir=\"$mount_point/logs\";

# don't remove this, Perl needs it:
1;
"

init_file_with_contents $USERNAME "$(path_from_homedir $USERNAME .mk-sbuild.rc)" \
"SCHROOT_CONF_SUFFIX=\"source-root-users=root,sbuild,admin
source-root-groups=root,sbuild,admin
preserve-environment=true\"
# you will want to undo the below for stable releases, read \`man mk-sbuild\` for details
# during the development cycle, these pockets are not used, but will contain important
# updates after each release of Ubuntu
SKIP_UPDATES=\"1\"
SKIP_PROPOSED=\"1\"
# if you have e.g. apt-cacher-ng around
DEBOOTSTRAP_PROXY=http://127.0.0.1:3142/
"

if (( $WANTS_KEYGEN )); then
    su -c "sbuild-update --keygen" $USERNAME
fi
