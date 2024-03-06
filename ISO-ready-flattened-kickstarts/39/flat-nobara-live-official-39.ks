# Generated by pykickstart v3.36
#version=F39
# X Window System configuration information
xconfig  --startxonboot
# Keyboard layouts
keyboard 'us'
# Root password
rootpw --iscrypted --lock locked
# System language
lang en_US.UTF-8
# Shutdown after installation
shutdown
# Network information
network  --bootproto=dhcp --device=link --activate
# Firewall configuration
firewall --enabled --service=mdns
# Use network installation
url --mirrorlist="https://mirrors.fedoraproject.org/mirrorlist?repo=fedora-$releasever&arch=$basearch"
repo --name="nobara-baseos" --baseurl=https://nobara-baseos.nobaraproject.org/$releasever/ --cost=50
repo --name="nobara-baseos-multilib" --baseurl=https://nobara-baseos-multilib.nobaraproject.org/$releasever/ --cost=50
repo --name="nobara-appstream" --baseurl=https://nobara-appstream.nobaraproject.org/$releasever/$basearch --cost=50
repo --name="nobara-rocm-official" --baseurl=https://repo.radeon.com/rocm/rhel9/5.6.1/main/ --cost=50
repo --name="fedora" --baseurl=https://nobara-fedora.nobaraproject.org/$releasever/
repo --name="fedora-updates" --baseurl=https://nobara-fedora-updates.nobaraproject.org/$releasever/

# System timezone
timezone US/Eastern
# SELinux configuration
selinux --disabled
# System services
services --disabled="sshd,custom-device-pollrates" --enabled="NetworkManager,ModemManager,supergfxd,akmods"
# System bootloader configuration
bootloader --location=none
# Clear the Master Boot Record
zerombr
# Partition clearing information
clearpart --all
# Disk partitioning information
part / --fstype="ext4" --size=25600
part / --size=25600

%post
# FIXME: it'd be better to get this installed from a package
cat > /etc/rc.d/init.d/livesys << EOF
#!/bin/bash
#
# live: Init script for live image
#
# chkconfig: 345 00 99
# description: Init script for live image.
### BEGIN INIT INFO
# X-Start-Before: display-manager chronyd
### END INIT INFO

. /etc/init.d/functions

if ! strstr "\`cat /proc/cmdline\`" rd.live.image || [ "\$1" != "start" ]; then
    exit 0
fi

if [ -e /.liveimg-configured ] ; then
    configdone=1
fi

exists() {
    which \$1 >/dev/null 2>&1 || return
    \$*
}

livedir="LiveOS"
for arg in \`cat /proc/cmdline\` ; do
  if [ "\${arg##rd.live.dir=}" != "\${arg}" ]; then
    livedir=\${arg##rd.live.dir=}
    continue
  fi
  if [ "\${arg##live_dir=}" != "\${arg}" ]; then
    livedir=\${arg##live_dir=}
  fi
done

# enable swapfile if it exists
if ! strstr "\`cat /proc/cmdline\`" noswap && [ -f /run/initramfs/live/\${livedir}/swap.img ] ; then
  action "Enabling swap file" swapon /run/initramfs/live/\${livedir}/swap.img
fi

mountPersistentHome() {
  # support label/uuid
  if [ "\${homedev##LABEL=}" != "\${homedev}" -o "\${homedev##UUID=}" != "\${homedev}" ]; then
    homedev=\`/sbin/blkid -o device -t "\$homedev"\`
  fi

  # if we're given a file rather than a blockdev, loopback it
  if [ "\${homedev##mtd}" != "\${homedev}" ]; then
    # mtd devs don't have a block device but get magic-mounted with -t jffs2
    mountopts="-t jffs2"
  elif [ ! -b "\$homedev" ]; then
    loopdev=\`losetup -f\`
    if [ "\${homedev##/run/initramfs/live}" != "\${homedev}" ]; then
      action "Remounting live store r/w" mount -o remount,rw /run/initramfs/live
    fi
    losetup \$loopdev \$homedev
    homedev=\$loopdev
  fi

  # if it's encrypted, we need to unlock it
  if [ "\$(/sbin/blkid -s TYPE -o value \$homedev 2>/dev/null)" = "crypto_LUKS" ]; then
    echo
    echo "Setting up encrypted /home device"
    plymouth ask-for-password --command="cryptsetup luksOpen \$homedev EncHome"
    homedev=/dev/mapper/EncHome
  fi

  # and finally do the mount
  mount \$mountopts \$homedev /home
  # if we have /home under what's passed for persistent home, then
  # we should make that the real /home.  useful for mtd device on olpc
  if [ -d /home/home ]; then mount --bind /home/home /home ; fi
  [ -x /sbin/restorecon ] && /sbin/restorecon /home
  if [ -d /home/liveuser ]; then USERADDARGS="-M" ; fi
}

findPersistentHome() {
  for arg in \`cat /proc/cmdline\` ; do
    if [ "\${arg##persistenthome=}" != "\${arg}" ]; then
      homedev=\${arg##persistenthome=}
    fi
  done
}

if strstr "\`cat /proc/cmdline\`" persistenthome= ; then
  findPersistentHome
elif [ -e /run/initramfs/live/\${livedir}/home.img ]; then
  homedev=/run/initramfs/live/\${livedir}/home.img
fi

# if we have a persistent /home, then we want to go ahead and mount it
if ! strstr "\`cat /proc/cmdline\`" nopersistenthome && [ -n "\$homedev" ] ; then
  action "Mounting persistent /home" mountPersistentHome
fi

if [ -n "\$configdone" ]; then
  exit 0
fi

# add liveuser user with no passwd
action "Adding live user" useradd \$USERADDARGS -c "Live System User" liveuser
passwd -d liveuser > /dev/null
usermod -aG wheel liveuser > /dev/null

# Remove root password lock
passwd -d root > /dev/null

# turn off firstboot for livecd boots
systemctl --no-reload disable firstboot-text.service 2> /dev/null || :
systemctl --no-reload disable firstboot-graphical.service 2> /dev/null || :
systemctl stop firstboot-text.service 2> /dev/null || :
systemctl stop firstboot-graphical.service 2> /dev/null || :

# don't use prelink on a running live image
sed -i 's/PRELINKING=yes/PRELINKING=no/' /etc/sysconfig/prelink &>/dev/null || :

# turn off mdmonitor by default
systemctl --no-reload disable mdmonitor.service 2> /dev/null || :
systemctl --no-reload disable mdmonitor-takeover.service 2> /dev/null || :
systemctl stop mdmonitor.service 2> /dev/null || :
systemctl stop mdmonitor-takeover.service 2> /dev/null || :

# don't start cron/at as they tend to spawn things which are
# disk intensive that are painful on a live image
systemctl --no-reload disable crond.service 2> /dev/null || :
systemctl --no-reload disable atd.service 2> /dev/null || :
systemctl stop crond.service 2> /dev/null || :
systemctl stop atd.service 2> /dev/null || :

# turn off abrtd on a live image
systemctl --no-reload disable abrtd.service 2> /dev/null || :
systemctl stop abrtd.service 2> /dev/null || :

# Don't sync the system clock when running live (RHBZ #1018162)
sed -i 's/rtcsync//' /etc/chrony.conf

# Mark things as configured
touch /.liveimg-configured

# add static hostname to work around xauth bug
# https://bugzilla.redhat.com/show_bug.cgi?id=679486
# the hostname must be something else than 'localhost'
# https://bugzilla.redhat.com/show_bug.cgi?id=1370222
hostnamectl set-hostname "localhost-live"

EOF

# bah, hal starts way too late
cat > /etc/rc.d/init.d/livesys-late << EOF
#!/bin/bash
#
# live: Late init script for live image
#
# chkconfig: 345 99 01
# description: Late init script for live image.

. /etc/init.d/functions

if ! strstr "\`cat /proc/cmdline\`" rd.live.image || [ "\$1" != "start" ] || [ -e /.liveimg-late-configured ] ; then
    exit 0
fi

exists() {
    which \$1 >/dev/null 2>&1 || return
    \$*
}

touch /.liveimg-late-configured

# read some variables out of /proc/cmdline
for o in \`cat /proc/cmdline\` ; do
    case \$o in
    ks=*)
        ks="--kickstart=\${o#ks=}"
        ;;
    xdriver=*)
        xdriver="\${o#xdriver=}"
        ;;
    esac
done

# if liveinst or textinst is given, start anaconda
if strstr "\`cat /proc/cmdline\`" liveinst ; then
   plymouth --quit
   /usr/sbin/liveinst \$ks
fi
if strstr "\`cat /proc/cmdline\`" textinst ; then
   plymouth --quit
   /usr/sbin/liveinst --text \$ks
fi

# configure X, allowing user to override xdriver
if [ -n "\$xdriver" ]; then
   cat > /etc/X11/xorg.conf.d/00-xdriver.conf <<FOE
Section "Device"
	Identifier	"Videocard0"
	Driver	"\$xdriver"
EndSection
FOE
fi

EOF

chmod 755 /etc/rc.d/init.d/livesys
/sbin/restorecon /etc/rc.d/init.d/livesys
/sbin/chkconfig --add livesys

chmod 755 /etc/rc.d/init.d/livesys-late
/sbin/restorecon /etc/rc.d/init.d/livesys-late
/sbin/chkconfig --add livesys-late

# enable tmpfs for /tmp
systemctl enable tmp.mount

# make it so that we don't do writing to the overlay for things which
# are just tmpdirs/caches
# note https://bugzilla.redhat.com/show_bug.cgi?id=1135475
cat >> /etc/fstab << EOF
vartmp   /var/tmp    tmpfs   defaults   0  0
EOF

# work around for poor key import UI in PackageKit
rm -f /var/lib/rpm/__db*
echo "Packages within this LiveCD"
rpm -qa --qf '%{size}\t%{name}-%{version}-%{release}.%{arch}\n' |sort -rn
# Note that running rpm recreates the rpm db files which aren't needed or wanted
rm -f /var/lib/rpm/__db*

# go ahead and pre-make the man -k cache (#455968)
/usr/bin/mandb

# make sure there aren't core files lying around
rm -f /core*

# remove random seed, the newly installed instance should make it's own
rm -f /var/lib/systemd/random-seed

# convince readahead not to collect
# FIXME: for systemd

echo 'File created by kickstart. See systemd-update-done.service(8).' \
    | tee /etc/.updated >/var/.updated

# Drop the rescue kernel and initramfs, we don't need them on the live media itself.
# See bug 1317709
rm -f /boot/*-rescue*

# Disable network service here, as doing it in the services line
# fails due to RHBZ #1369794
/sbin/chkconfig network off

# Remove machine-id on pre generated images
rm -f /etc/machine-id
touch /etc/machine-id

%end

%post --nochroot
# For livecd-creator builds only (lorax/livemedia-creator handles this directly)
if [ -n "$LIVE_ROOT" ]; then
    cp "$INSTALL_ROOT"/usr/share/licenses/*-release-common/* "$LIVE_ROOT/"

    # only installed on x86, x86_64
    if [ -f /usr/bin/livecd-iso-to-disk ]; then
        mkdir -p "$LIVE_ROOT/LiveOS"
        cp /usr/bin/livecd-iso-to-disk "$LIVE_ROOT/LiveOS"
    fi
fi

%end

%post

# set default GTK+ theme for root (see #683855, #689070, #808062)
cat > /root/.gtkrc-2.0 << EOF
include "/usr/share/themes/Adwaita-dark/gtk-2.0/gtkrc"
include "/etc/gtk-2.0/gtkrc"
gtk-theme-name="Adwaita-dark"
EOF
mkdir -p /root/.config/gtk-3.0
cat > /root/.config/gtk-3.0/settings.ini << EOF
[Settings]
gtk-theme-name = Adwaita-dark
EOF

# add initscript
cat >> /etc/rc.d/init.d/livesys << EOF

# Make the liveinst run on login
mkdir -p ~liveuser/.config/autostart
cp -a /usr/share/applications/calamares.desktop ~liveuser/.config/autostart/

# Add calamares installer desktop shortcut
mkdir /home/liveuser/Desktop
cp -a /usr/share/applications/calamares.desktop /home/liveuser/Desktop/
chmod a+x /home/liveuser/Desktop/*

# Remove anaconda's liveinst.desktop from live install
rm /etc/xdg/autostart/liveinst-setup.desktop

# Don't automount partitions in live session
rm /etc/xdg/autostart/nobara-automount.desktop

# Remove steam from live environment autostart
rm /etc/xdg/autostart/steam.desktop
rm /etc/skel/Desktop/steam.desktop
rm /etc/skel/Desktop/Return.desktop
rm /etc/skel/Desktop/RemoteHost.desktop
rm /home/liveuser/Desktop/steam.desktop
rm /home/liveuser/Desktop/Return.desktop
rm /home/liveuser/Desktop/RemoteHost.desktop

# make sure to set the right permissions and selinux contexts
chown -R liveuser:liveuser /home/liveuser/
restorecon -R /home/liveuser/

# kde specific

PLASMA_SESSION_FILE="plasma.desktop"

# set up autologin
if [ -f /etc/sddm.conf ]; then
sed -i 's/^#User=.*/User=liveuser/' /etc/sddm.conf
sed -i "s/^#Session=.*/Session=\${PLASMA_SESSION_FILE}/" /etc/sddm.conf
else
cat > /etc/sddm.conf << SDDM_EOF
[Autologin]
User=liveuser
Session=\${PLASMA_SESSION_FILE}
SDDM_EOF
fi

# Set akonadi backend
mkdir -p /home/liveuser/.config/akonadi
cat > /home/liveuser/.config/akonadi/akonadiserverrc << AKONADI_EOF
[%General]
Driver=QSQLITE3
AKONADI_EOF

# "Disable plasma-discover-notifier"
mkdir -p /home/liveuser/.config/autostart
cp -a /etc/xdg/autostart/org.kde.discover.notifier.desktop /home/liveuser/.config/autostart/
echo 'Hidden=true' >> /home/liveuser/.config/autostart/org.kde.discover.notifier.desktop

# Disable baloo
cat > /home/liveuser/.config/baloofilerc << BALOO_EOF
[Basic Settings]
Indexing-Enabled=false
BALOO_EOF

# Disable kres-migrator
cat > /home/liveuser/.kde/share/config/kres-migratorrc << KRES_EOF
[Migration]
Enabled=false
KRES_EOF

# Disable kwallet migrator
cat > /home/liveuser/.config/kwalletrc << KWALLET_EOL
[Migration]
alreadyMigrated=true
KWALLET_EOL

# Disable automount of 'known' devices
# https://bugzilla.redhat.com/show_bug.cgi?id=2073708
cat > /home/liveuser/.config/kded_device_automounterrc << AUTOMOUNTER_EOF
[General]
AutomountEnabled=false
AutomountOnLogin=false
AutomountOnPlugin=false
AUTOMOUNTER_EOF

# make sure to set the right permissions and selinux contexts
chown -R liveuser:liveuser /home/liveuser/
restorecon -R /home/liveuser/

EOF


# update grub, set sddm theme for nobara official
cat << EOF >> /usr/share/calamares/modules/shellprocess.conf
    - command: "sed -i '/\\\[Theme\\\]/a\\\Current=nobara' /etc/sddm.conf"
      timeout: 3600
EOF

chown -R liveuser:liveuser /home/liveuser/
sed -i 's|#Current=.*|Current=nobara|g' /etc/sddm.conf

# Remove anaconda's liveinst.desktop from live install
rm /etc/xdg/autostart/liveinst-setup.desktop

# empty tmp files so anaconda doesn't fail when unmounting /tmp due to kernel modules being installed
rm -Rf /tmp/*

%end

#workaround for successful nvidia graphics driver installation
%pre-install
mkdir -p /mnt/sysimage/etc/default
touch /mnt/sysimage/etc/default/grub
%end

%packages
@^kde-desktop-environment
@anaconda-tools
@fonts
@guest-desktop-agents
@hardware-support
@kde-apps
@kde-media
@multimedia
@printing
@standard
firefox
apparmor-utils
apparmor-parser
aajohan-comfortaa-fonts
anaconda
anaconda-install-env-deps
anaconda-live
apr
apr-util
mesa-libOpenCL
calamares
ark
chkconfig
dracut-live
egl-gbm
egl-wayland
fedora-release-kde
fedora-repos
fedora-workstation-repositories
ffmpegthumbs
flac-libs.x86_64
flac-libs.i686
flatpak
foomatic
fuse
gamemode.x86_64
gamemode.i686
ghc-mountpoints
gamescope
glibc-all-langpacks
goverlay
gstreamer1-plugins-bad-free.i686
gstreamer1-plugins-bad-free.x86_64
gstreamer1-plugins-bad-free-extras.x86_64
gstreamer1-plugins-bad-free-extras.i686
gstreamer1-plugins-base.i686
gstreamer1-plugins-base.x86_64
gstreamer1-plugins-good.i686
gstreamer1-plugins-good.x86_64
gstreamer1-plugins-ugly-free.i686
gstreamer1-plugins-ugly-free.x86_64
gstreamer1.i686
gstreamer1.x86_64
hplip
initscripts
inkscape
kde-runtime
kf5-kimageformats
i2c-tools
libi2c
json-c.x86_64
json-c.i686
kde-l10n
kernel
kernel-modules
kernel-modules-extra
libaom.x86_64
libaom.i686
libICE.x86_64
libICE.i686
libSM.x86_64
libSM.i686
libXtst.x86_64
libXtst.i686
libasyncns.x86_64
libasyncns.i686
liberation-narrow-fonts.noarch
libexif.x86_64
libexif.i686
libgcc.x86_64
libgcc.i686
libieee1284.x86_64
libieee1284.i686
libogg.x86_64
libogg.i686
libsndfile.x86_64
libsndfile.i686
libunity
libuuid.x86_64
libuuid.i686
libva.x86_64
libva.i686
libvorbis.x86_64
libvorbis.i686
libwayland-client.x86_64
libwayland-client.i686
libwayland-server.x86_64
libwayland-server.i686
llvm-libs.x86_64
llvm-libs.i686
lutris
mangohud.x86_64
mangohud.i686
mariadb-connector-c
mariadb-embedded
mariadb-server
mediawriter
memtest86+
mesa-libGLU.x86_64
mesa-libGLU.i686
-musescore
mscore-fonts
neofetch
nobara-login
nobara-login-sysctl
nobara-repos
nobara-controller-config
nss-mdns.x86_64
nss-mdns.i686
ocl-icd.x86_64
ocl-icd.i686
libreoffice
openssl
openssl-libs.x86_64
openssl-libs.i686
pavucontrol-qt
protonup-qt
qemu-device-display-qxl
plasma-lookandfeel-nobara
plasma-lookandfeel-nobara-sddm
plasma-workspace-wallpapers
plasma-discover-flatpak
pulseaudio-libs.x86_64
pulseaudio-libs.i686
rpmfusion-free-release
samba-common-tools.x86_64
samba-libs.x86_64
samba-winbind-clients.x86_64
samba-winbind-modules.x86_64
samba-winbind.x86_64
sane-backends-libs.x86_64
sane-backends-libs.i686
supergfxctl
supergfxctl-plasmoid
sddm-kcm
steam
syslinux
system-config-language
tcp_wrappers-libs.x86_64
tcp_wrappers-libs.i686
unixODBC.x86_64
unixODBC.i686
bsdtar
vim
vkBasalt.x86_64
vkBasalt.i686
python3-vapoursynth
vapoursynth-tools
vulkan-tools
winehq-staging
winetricks
zenity
numactl
timeshift
gcc-gfortran
okular
kate
dnfdaemon
v4l2loopback
akmod-v4l2loopback
yumex
nobara-welcome
noopenh264
openrgb
papirus-icon-theme
libavcodec-free
libavdevice-free
libavfilter-free
libavutil-free
libavformat-free
libpostproc-free
libswscale-free
libswresample-free
xwaylandvideobridge
-dnfdragora
-plasma-welcome
-gstreamer1-plugins-bad-freeworld
-gstreamer1-plugins-ugly
-gstreamer1-libav
-compat-ffmpeg4
-libavdevice
-libfreeaptx
-pipewire-codec-aptx
-libva-intel-driver
-intel-media-driver
power-profiles-daemon
-kolourpaint
-kf5-libksane
-kolourpaint-libs
-akregator
-kontact
-konversation
-krdc
-krfb
-akregator-libs
-grantlee-editor
-grantlee-editor-libs
-kf5-kross-core
-kmail
-kmail-account-wizard
-kmail-libs
-kontact-libs
-korganizer
-korganizer-libs
-pim-data-exporter
-pim-data-exporter-libs
-pim-sieve-editor
-freerdp
-freerdp-libs
-krdc-libs
-libwinpr
-krfb-libs
-kmahjongg
-kmines
-kpat
-freecell-solver-data
-libblack-hole-solver1
-libfreecell-solver
-libkdegames
-libkmahjongg
-libkmahjongg-data
-dragon
-kaddressbook
-akonadi-import-wizard
-cyrus-sasl-md5
-kaddressbook-libs
-kdepim-addons
-kdepim-runtime
-kdepim-runtime-libs
-kdiagram
-kf5-akonadi-calendar
-kf5-akonadi-mime
-kf5-akonadi-notes
-kf5-akonadi-search
-kf5-calendarsupport
-kf5-eventviews
-kf5-incidenceeditor
-kf5-kcalendarcore
-kf5-kcalendarutils
-kf5-kdav
-kf5-kidentitymanagement
-kf5-kimap
-kf5-kitinerary
-kf5-kldap
-kf5-kmailtransport
-kf5-kmailtransport-akonadi
-kf5-kmbox
-kf5-kontactinterface
-kf5-kpimtextedit
-kf5-kpkpass
-kf5-ksmtp
-kf5-ktnef
-kf5-libgravatar
-kf5-libkdepim
-kf5-libkleo
-kf5-libksieve
-kf5-mailcommon
-kf5-mailimporter
-kf5-mailimporter-akonadi
-kf5-messagelib
-kf5-pimcommon
-kf5-pimcommon-akonadi
-f38-backgrounds-kde
-kio-gdrive
-libkgapi
-libkolabxml
-libphonenumber
-qgpgme
-qtkeychain-qt5
-kwrite
-fedora-repos-modular
-fedora-workstation-repositories
-unoconv
-@admin-tools
-@input-methods
-device-mapper-multipath
-digikam
-fcoe-utils
-gnome-disk-utility
-iok
-isdn4k-utils
-k3b
-kdeaccessibility*
-kipi-plugins
-krusader
-ktorrent
-mpage
-nfs-utils
-scim*
-system-config-printer
-system-config-services
-system-config-users
-xsane
-xsane-gimp
-qt5-qtwebengine-freeworld
-sushi
-abrt*
-gnome-abrt
-abrt-desktop
-abrt-java-connector
-abrt-cli
-ffmpeg
-ffmpeg-libs
-qgnomeplatform-qt5
-qgnomeplatform-qt6

%end