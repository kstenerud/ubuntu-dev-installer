SCRIPT_NAME=$1

is_numeric()
{
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

get_colon_separated_arguments()
{
    subargcount="$1"
    argument="$2"

    pattern="\\(.*\\)"
    replace="\1"
    if [ $subargcount -gt 1 ]; then
        for i in $(seq 2 $subargcount); do
            pattern="\\([^:]*\\):$pattern"
            replace="$replace \\$i"
        done
    fi

    sed_cmd="s/$pattern/$replace/g"
    params="$(echo "$argument"|sed "$sed_cmd")"
    if [ "$params" != "$argument" ]; then
        echo "$params"
    else
        echo
    fi
}

disable_services()
{
    service_names="$@"
    for service in $service_names; do
        echo "Disabling service $service"
        sudo systemctl disable $service || true
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
        sudo chown $owner:$owner "$file"
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
        sudo snap install $(echo $snap | sed 's/:/ --/g')
    done
}

add_repositories()
{
    repositories="$@"
    echo "Adding repositories $repositories"
    for repo in $repositories; do
        sudo add-apt-repository -y $repo
    done
    sudo apt update
}

install_packages()
{
    packages="$@"
    echo "Installing packages: $packages"
    bash -c "(export DEBIAN_FRONTEND=noninteractive; sudo apt install -y $packages)"
}

remove_packages()
{
    packages="$@"
    echo "Removing packages $packages"
    sudo apt remove -y $packages
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

    sudo chown -R $username:$(id -g $username) "$(get_homedir $username)" || true
}

add_user_to_groups()
{
    username=$1
    shift
    groups=$@
    echo "Adding $username to groups: $groups"
    for group in $groups; do
        if grep $group /etc/group >/dev/null; then
            sudo usermod -a -G $group $username
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


# ---
# LXD
# ---

lxc_is_guest_network_up()
{
    guest_name="$1"
    lxc exec "$guest_name" -- grep $'\t0003\t' /proc/net/route >/dev/null
}

lxc_wait_for_guest_network()
{
    guest_name="$1"
    until lxc_is_guest_network_up "$guest_name";
    do
        echo "Waiting for network"
        sleep 1
    done
}

lxc_warn_if_uid_gid_map_not_enabled()
{
    id="$1"
    file="$2"

    user=root
    while read line; do
        if [ -z "$line" ]; then continue; fi
        fields=($(get_colon_separated_arguments 3 $line))
        if [ "${fields[0]}" != "$user" ]; then continue; fi
        if [ "${fields[1]}" == "$id" ]; then return; fi
    done < "$file"
    echo "WARNING: You'll need to add permission for $user to share id $id in $file:"
    echo "    $user:$id:1"
    echo "The container may fail to operate correctly without it."
}

lxc_get_host_uid()
{
    name="$1"
    if is_numeric "$name"; then
        echo "$name"
    else
        id -u "$name"
    fi
}

lxc_get_host_gid()
{
    group="$1"
    if is_numeric "$group"; then
        echo "$group"
    else
        id -g "$group"
    fi
}

lxc_get_guest_uid()
{
    container_name="$1"
    name="$2"
    if is_numeric "$name"; then
        echo "$name"
    else
        lxc exec $container_name -- id -u "$name"
    fi
}

lxc_get_guest_gid()
{
    container_name="$1"
    group="$2"
    if is_numeric "$group"; then
        echo "$group"
    else
        lxc exec $container_name -- id -g "$group"
    fi
}

lxc_map_guest_user_to_host()
{
    container_name="$1"
    guest_user="$2"
    guest_group="$3"
    host_user="$4"
    host_group="$5"

    guest_uid="$(lxc_get_guest_uid $container_name $guest_user)"
    host_uid="$(lxc_get_host_uid $host_user)"
    guest_gid="$(lxc_get_guest_gid $container_name $guest_group)"
    host_gid="$(lxc_get_host_gid $host_group)"

    lxc_warn_if_uid_gid_map_not_enabled $host_uid /etc/subuid
    lxc_warn_if_uid_gid_map_not_enabled $host_gid /etc/subgid

    current_idmap="$(lxc config get $container_name raw.idmap)"
    new_idmap=$(printf "uid %s %s\ngid %s %s" $host_uid $guest_uid $host_gid $guest_gid)
    if [ ! -z "$current_idmap" ]; then
        new_idmap=$(printf "%s\n%s" "$current_idmap" "$new_idmap")
    fi

    echo "Mapping guest $guest_user:$guest_group ($guest_uid:$guest_gid) to host $host_user:$host_group ($host_uid:$host_gid)"
    lxc config set $container_name raw.idmap "$new_idmap"
}

lxc_mount_host() {
    container_name="$1"
    device_name="$2"
    host_path="$3"
    mount_point="$4"

    mkdir -p "$host_path"
    lxc exec $container_name -- mkdir -p "$mount_point"
    lxc config device add $container_name $device_name disk source="$host_path" path="$mount_point"
}

lxc_set_autostart()
{
    container_name="$1"
    lxc config set $container_name boot.autostart 1
}