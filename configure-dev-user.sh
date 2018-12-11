#!/bin/bash
set -eu

show_help()
{
    echo "Configures tooling and defaults for ubuntu development."
    echo
    echo "Usage: $(basename $0) [options] <username> <full name> <email> <git username> <lp username>"
    echo "or:    $(basename $0) -r <username>"
    echo
    echo "Options:"
    echo "  -r: Reinstall system-level config only (if you've reinstalled the OS and moved your homedir over)."
    echo "  -h: Map the user's homedir to schroot"
    echo "  -k: Run as the user: sbuild-update --keygen"
    echo "  -c: This is a console only user."
    echo "  -g: This is a GUI user."
    echo
    echo "Help Pages:"
    echo " - https://wiki.ubuntu.com/SimpleSbuild"
    echo " - https://wiki.debian.org/UsingQuilt"
    echo " - http://manpages.ubuntu.com/manpages/cosmic/en/man1/dput.1.html"
    echo " - https://git-scm.com/book/en/v2"
}

#####################################################################


file_contains()
{
    file="$1"
    contents="$2"

    grep "$contents" "$file" >/dev/null 2>&1
}

get_homedir()
{
    username=$1
    eval echo "~$username"
}

chown_homedir()
{
    username=$1

    chown -R $username:$(id -g $username) "$(get_homedir $username)" || true
}

add_to_file()
{
    file="$1"
    contents="$2"

    if ! file_contains "$file" "$contents"; then
        echo "$contents" >> "$file"
    fi
}

add_user_to_groups()
{
    username=$1
    shift
    groups=$@
    for group in $groups; do
        if grep $group /etc/group >/dev/null; then
            usermod -a -G $group $username
        else
            echo "WARNING: Not adding group $group because it doesn't exist."
        fi
    done
}

modify_profile()
{
    username=$1
    full_name="$2"
    email="$3"
    install_mode=$4
    profile="$(get_homedir $username)/.profile"

    add_to_file "$profile" "export DEBFULLNAME=\"${full_name}\""
    add_to_file "$profile" "export DEBEMAIL=\"${email}\""

    # Fix "clear-sign failed: Inappropriate ioctl for device"
    add_to_file "$profile" "export GPG_TTY=\$(tty)"

    if [ "$install_mode" == "gui" ]; then
        add_to_file "$profile" 'eval `dbus-launch --sh-syntax`'
    fi
}

configure_quilt()
{
    username=$1
    quiltrc="$(get_homedir $username)/.quiltrc"

    if [ ! -f "$quiltrc" ]; then
        echo 'd=. ; while [ ! -d $d/debian -a `readlink -e $d` != / ]; do d=$d/..; done
if [ -d $d/debian ] && [ -z $QUILT_PATCHES ]; then
    # if in Debian packaging tree with unset $QUILT_PATCHES
    QUILT_PATCHES="debian/patches"
    QUILT_PATCH_OPTS="--reject-format=unified"
    QUILT_DIFF_ARGS="-p ab --no-timestamps --no-index --color=auto"
    QUILT_REFRESH_ARGS="-p ab --no-timestamps --no-index"
    QUILT_COLORS="diff_hdr=1;32:diff_add=1;34:diff_rem=1;31:diff_hunk=1;33:diff_ctx=35:diff_cctx=33"
    if ! [ -d $d/debian/patches ]; then mkdir $d/debian/patches; fi
fi' > "$quiltrc"
    fi
}


configure_dput()
{
    username=$1
    dput_cf="$(get_homedir $username)/.dput.cf"

    if [ ! -f "$dput_cf" ]; then
        echo '[DEFAULT]
default_host_main = unspecified

[unspecified]
fqdn = SPECIFY.A.TARGET
incoming = /

[ppa]
fqdn            = ppa.launchpad.net
method          = ftp
incoming        = ~%(ppa)s/ubuntu' > "$dput_cf"
    fi
}

configure_git()
{
    username=$1
    git_username=$2
    full_name="$3"
    email="$4"
    lp_name="$5"
    gitconfig="$(get_homedir $username).gitconfig"

    if ! file_contains "$gitconfig" "[log]"; then
        echo "[log]" >> "$gitconfig"
        echo "decorate = short" >> "$gitconfig"
    fi

    if ! file_contains "$gitconfig" "[user]"; then
        echo "[user]" >> "$gitconfig"
        echo "    name = ${git_username}" >> "$gitconfig"
        echo "    email = ${email}" >> "$gitconfig"
    fi

    if ! file_contains "$gitconfig" "[gitubuntu]"; then
        echo "[gitubuntu]" >> "$gitconfig"
        echo "    lpuser = ${lp_name}" >> "$gitconfig"
    fi
}

add_schroot_mount()
{
    outside_path="$1"
    inside_path="$2"
    mount_line="$outside_path  $inside_path          none  rw,bind  0  0"

    if ! grep "\\w$inside_path\\w" /etc/schroot/sbuild/fstab >>/dev/null; then
        echo "$mount_line" >> /etc/schroot/sbuild/fstab
    fi
}

configure_schroot()
{
    username=$1
    distribution=$2
    maintainer_name="$3"
    maintainer_email="$4"
    wants_keygen="$5"
    wants_home_dir_mount="$6"

    home_dir="$(get_homedir $username)"
    mount_point="$home_dir/schroot"
    sbuildrc="$home_dir/.sbuildrc"
    mk_sbuildrc="$home_dir/.mk-sbuild.rc"

    if [ $wants_keygen -ne 0 ]; then
        su -c "sbuild-update --keygen" $username
    fi

    if [ $wants_home_dir_mount -ne 0 ]; then
        add_schroot_mount "$home_dir" "$home_dir"
    fi

    if [ -d "$mount_point" ]; then
        echo "schroot is already configured. To reconfigure, delete or move:"
        echo " * $mount_point"
        echo " * $sbuildrc"
        echo " * $mk_sbuildrc"
        return 0
    fi

    mkdir -p "$mount_point/build"
    mkdir -p "$mount_point/logs"
    mkdir -p "$mount_point/scratch"

    add_schroot_mount "$mount_point/scratch" "/scratch"

    if [ ! -f "$sbuildrc" ]; then
        echo "# Name to use as override in .changes files for the Maintainer: field
# (mandatory, no default!).
\$maintainer_name='$maintainer_name <$maintainer_email>';

# Default distribution to build.
\$distribution = \"$distribution\";
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
1;" >"$sbuildrc"
    fi

    if [ ! -f "$mk_sbuildrc" ]; then
        echo "SCHROOT_CONF_SUFFIX=\"source-root-users=root,sbuild,admin
source-root-groups=root,sbuild,admin
preserve-environment=true\"
# you will want to undo the below for stable releases, read \`man mk-sbuild\` for details
# during the development cycle, these pockets are not used, but will contain important
# updates after each release of Ubuntu
SKIP_UPDATES=\"1\"
SKIP_PROPOSED=\"1\"
# if you have e.g. apt-cacher-ng around
DEBOOTSTRAP_PROXY=http://127.0.0.1:3142/" >"$mk_sbuildrc"
    fi
}

add_user_to_required_groups()
{
    user=$1
    add_user_to_groups $user \
        adm \
        sudo \
        lxd \
        kvm \
        libvirt \
        docker \
        sbuild
}

usage()
{
    show_help 1>&2
    exit 1
}

#####################################################################

REINSTALL=0
INSTALL_MODE=
DISTRUBUTION=bionic
WANTS_KEYGEN=0
WANTS_HOME_DIR_MOUNT=0

while getopts "gcrkhd:" o; do
    case "$o" in
        \?)
            show_help
            exit 0
            ;;
        c)
            INSTALL_MODE=console
            ;;
        g)
            INSTALL_MODE=gui
            ;;
        r)
            REINSTALL=1
            ;;
        k)
            WANTS_KEYGEN=1
            ;;
        h)
            WANTS_HOME_DIR_MOUNT=1
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

if [ "$EUID" -ne 0 ]; then
    echo "$(basename $0) must run using sudo"
    exit 1
fi

if [ "$REINSTALL" -ne 0 ]; then
    if (( $# != 1 )); then
        usage
    fi
    USERNAME=$1

    echo "Reinstalling system level settings for $USERNAME..."
    add_user_to_required_groups
    exit 0
fi

if [ -z "$INSTALL_MODE" ]; then
    echo "Must select either -c -g or -G option." 1>&2
    usage
fi

if (( $# != 5 )); then
    usage
fi

USERNAME=$1
FULL_NAME="$2"
EMAIL=$3
GIT_USERNAME=$4
LP_NAME=$5

if [ "$INSTALL_MODE" == "gui" ]; then
    echo "Configuring user $USERNAME for GUI use..."
else
    echo "Configuring user $USERNAME for CONSOLE use..."
fi

modify_profile ${USERNAME} "${FULL_NAME}" "${EMAIL}" $INSTALL_MODE
configure_quilt ${USERNAME}
configure_dput ${USERNAME}
configure_git ${USERNAME} "${GIT_USERNAME}" "${FULL_NAME}" "${EMAIL}" "${LP_NAME}"
configure_schroot ${USERNAME} ${DISTRUBUTION} "${FULL_NAME}" "${EMAIL}" $WANTS_KEYGEN $WANTS_HOME_DIR_MOUNT

add_user_to_required_groups ${USERNAME}
chown_homedir ${USERNAME}


echo 'Dev user configured successfully. Remember to set:
 * Password
 * SSH keys & authorized-keys
 * GPG keys
'
