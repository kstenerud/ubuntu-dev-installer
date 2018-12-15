#!/bin/bash
set -eu

show_help()
{
    echo \
"Configures dput, adding a default .dput.cf if it doesn't exist.

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

init_file_with_contents $USERNAME "$(path_from_homedir $USERNAME .dput.cf)" \
'[DEFAULT]
default_host_main = unspecified

[unspecified]
fqdn = SPECIFY.A.TARGET
incoming = /

[ppa]
fqdn            = ppa.launchpad.net
method          = ftp
incoming        = ~%(ppa)s/ubuntu'
