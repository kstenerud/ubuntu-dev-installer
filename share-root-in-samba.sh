#!/bin/bash
set -eu

show_help()
{
    echo "Starts a samba service to share the root directory AS root.
WARNING: This gives root access over samba! Only use for debugging a VM that will be destroyed afterwards!
If you really want to do this, call the script again with -y

Usage: $(basename $0) -y"
}

#####################################################################


configure_avahi()
{
    sed -i 's/\(rlimit-nproc\)/#\1/g' /etc/avahi/avahi-daemon.conf
    sed -i 's/#enable-dbus=yes/enable-dbus=no/g' /etc/avahi/avahi-daemon.conf
    sed -i 's/need dbus/use dbus/g' /etc/init.d/avahi-daemon
    rm /etc/avahi/services/ssh.service /etc/avahi/services/sftp-ssh.service
    printf "%s" '<?xml version="1.0" standalone="no"?><!--*-nxml-*-->
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h</name>
  <service>
    <type>_smb._tcp</type>
    <port>445</port>
  </service>
</service-group>
' | tee /etc/avahi/services/samba.service >/dev/null
}

configure_samba()
{
	netbios_name=$(hostname)
    share_path=/
    share_name=root
    writable=true
    smbconf="/etc/samba/smb.conf"

    printf "%s" "[global]

    # Identification
    netbios name = $netbios_name
    workgroup = WORKGROUP
    server string = Samba Server Version %v

    # Network
    name resolve order = bcast host lmhosts wins

    # Protocol
    server role = standalone server
    disable netbios = no
    wins support = yes
    dns proxy = yes
    domain master = yes
    local master = yes
    preferred master = yes
    os level = 31

    # Security
    security = user
    map to guest = Bad User
    guest ok = yes
    guest only = yes
    guest account = root

    # Needed by some Windows installs
    server signing = auto

    # Printing
    load printers = No
    printing = bsd
    printcap name = /dev/null
    disable spoolss = Yes

    # Files
    directory mask = 0755
    force create mode = 0644
    force directory mode = 0755
    case sensitive = True
    default case = lower
    preserve case = yes
    short preserve case = yes

    # Performance
    socket options = TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072
    read raw = yes
    write raw = yes
    server signing = no
    strict locking = no
    min receivefile size = 16384
    use sendfile = Yes
    aio read size = 16384
    aio write size = 16384

    # Logging
    syslog = 0
    max log size = 100
" | tee $smbconf >/dev/null

    echo "Mounting path $path as $name (writable=$writable)"
    echo "" >> $smbconf
    echo "[$share_name]" >> $smbconf
    echo "    path = $share_path" >> $smbconf
    echo "    writable = $writable" >> $smbconf
    echo "    browsable = yes" >> $smbconf
    echo "    guest ok = yes" >> $smbconf
}

usage()
{
    show_help 1>&2
    exit 1
}

#####################################################################

if [ "$EUID" -ne 0 ]; then
    echo "$(basename $0) must run using sudo"
    exit 1
fi

REALLY_INSTALL=false

while getopts "?y" o; do
    case "$o" in
        \?)
            show_help
            exit 0
            ;;
        y)
            REALLY_INSTALL=true
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ "$REALLY_INSTALL" != "true" ]; then
    usage
fi


apt update
DEBIAN_FRONTEND=noninteractive apt install -y samba avahi

configure_avahi
configure_samba

echo "Samba server is now giving guest access to / via \"\\\\$(hostname)\\root\" USING ROOT PRIVILEGES!"
echo "NEVER USE THIS IN AN INSECURE ENVIRONMENT!"
