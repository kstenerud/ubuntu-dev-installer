SCRIPT_NAME=$1

disable_services()
{
    service_names="$@"
    for service in $service_names; do
        echo "Disabling service $service"
        systemctl disable $service || true
    done
}

get_default_ip_address()
{
    default_iface=$(grep "^\w*\s*00000000" /proc/net/route | sed 's/\([a-z0-9]*\).*/\1/')
    ip addr show dev "$default_iface" | grep "inet " | sed 's/[^0-9]*\([0-9.]*\).*/\1/'
}


# -----
# Files
# -----

does_file_contain()
{
    file="$1"
    text="$2"

    fgrep "$text" "$file" >/dev/null 2>&1
}

add_to_file_if_not_found()
{
    owner="$1"
    file="$2"
    test="$3"
    contents="$4"

    if ! does_file_contain "$file" "$test"; then
        echo "$contents" >> "$file"
        chown $owner:$owner "$file"
    fi
}

ensure_file_contains()
{
    owner="$1"
    file="$2"
    contents="$3"
    add_to_file_if_not_found "$owner" "$file" "$contents" "$contents"
}

create_dir()
{
    username=$1
    path=$2

    mkdir -p "$path"
    chown $username:$username "$path"
}

init_file_with_contents()
{
    owner="$1"
    file="$2"
    contents="$3"

    if [ ! -f "$file" ]; then
        echo "$contents" >> "$file"
        chown $owner:$owner "$file"
    else
        echo "$file already exists, not replacing."
    fi
}

sanitize_filename()
{
    filename="$(basename "$1" | tr -cd 'A-Za-z0-9_.')"
    echo "$filename"
}


# ------------
# Installation
# ------------

install_snaps()
{
    snaps="$@"
    echo "Installing snaps: $snaps"
    for snap in $snaps; do
        snap install $(echo $snap | sed 's/:/ --/g')
    done
}

add_repositories()
{
    repositories="$@"
    echo "Adding repositories $repositories"
    for repo in $repositories; do
        add-apt-repository -y $repo
    done
    apt update
}

install_packages()
{
    packages="$@"
    echo "Installing packages: $packages"
    bash -c "(export DEBIAN_FRONTEND=noninteractive; apt install -y $packages)"
}

remove_packages()
{
    packages="$@"
    echo "Removing packages $packages"
    apt remove -y $packages
}

install_packages_from_repository()
{
    repo="$1"
    shift
    packages="$@"
    add_repositories $repo
    install_packages $packages
}

install_packages_from_urls()
{
    urls="$@"
    echo "Installing URL packages: $urls"
    for url in $urls; do
        tmpfile="/tmp/tmp_deb_pkg_$(sanitize_filename $url).deb"
        wget -qO $tmpfile "$url"
        install_packages "$tmpfile"
        rm "$tmpfile"
    done
}


# -----
# Users
# -----

assert_is_root()
{
    if [ "$EUID" -ne 0 ]; then
        echo "$(basename $SCRIPT_NAME) must run using sudo"
        exit 1
    fi
}

does_user_exist()
{
    username=$1
    id -u $username >/dev/null 2>&1
}

assert_user_exists()
{
    username=$1
    if ! does_user_exist $username; then
        echo "$username: No such user"
        return 1
    fi
}

get_homedir()
{
    username=$1
    if ! does_user_exist $username; then
        echo "$username: No such user"
        echo "USER_NOT_FOUND"
        return 1
    fi
    eval echo "~$username"
}

path_from_homedir()
{
    username=$1
    file=$2

    echo "$(get_homedir $username)/$file"
}

chown_homedir()
{
    username=$1

    chown -R $username:$(id -g $username) "$(get_homedir $username)" || true
}

add_user_to_groups()
{
    username=$1
    shift
    groups=$@
    echo "Adding $username to groups: $groups"
    for group in $groups; do
        if grep $group /etc/group >/dev/null; then
            usermod -a -G $group $username
        else
            echo "WARNING: Not adding group $group because it doesn't exist."
        fi
    done
}


# ------
# Locale
# ------

set_timezone()
{
    timezone=$1

    echo "Setting timezone: $timezone"

    echo "$timezone" > /etc/timezone && dpkg-reconfigure -f noninteractive tzdata
}

set_language_region()
{
    language=$1
    region=$2

    lang_base=${language}_${region}
    lang_full=${lang_base}.UTF-8

    echo "Setting locale: $lang_full"

    locale-gen ${lang_base} ${lang_full}
    # update-locale LANG=${lang_full}
    # Only LANG seems to be necessary
    update-locale LANG=${lang_full} LANGUAGE=${lang_base}:${language} LC_ALL=${lang_full}
}

set_keyboard_layout_model()
{
    kb_layout=$1
    kb_model=$2

    echo "Setting keyboard layout: $1, model: $2"

    echo "keyboard-configuration keyboard-configuration/layoutcode string ${kb_layout}" | debconf-set-selections
    echo "keyboard-configuration keyboard-configuration/modelcode string ${kb_model}" | debconf-set-selections
}
