#!/bin/bash

set -e

# check for root permissions
if [[ "$(id -u)" != 0 ]]; then
  echo "E: Requires root permissions" > /dev/stderr
  exit 1
fi

# get config
if [ -n "$1" ]; then
  CONFIG_FILE="$1"
else
  CONFIG_FILE="etc/terraform.conf"
fi
BASE_DIR="$PWD"
source "$BASE_DIR"/"$CONFIG_FILE"

echo -e "
#----------------------#
# INSTALL DEPENDENCIES #
#----------------------#
"

apt-get update
apt-get install -y live-build patch gnupg2 binutils zstd
dpkg -i debs/*.deb

# TODO: workaround a bug in lb by increasing number of blocks for creating efi.img
patch /usr/lib/live/build/binary_grub-efi < binary_grub-efi.patch

# TODO: Remove this once debootstrap has a script to build lunar images in our container:
# https://salsa.debian.org/installer-team/debootstrap/blob/master/debian/changelog
ln -sfn /usr/share/debootstrap/scripts/gutsy /usr/share/debootstrap/scripts/lunar

build () {
  BUILD_ARCH="$1"

  mkdir -p "$BASE_DIR/tmp/$BUILD_ARCH"
  cd "$BASE_DIR/tmp/$BUILD_ARCH" || exit

  # remove old configs and copy over new
  rm -rf config auto
  cp -r "$BASE_DIR"/etc/* .
  # Make sure conffile specified as arg has correct name
  cp -f "$BASE_DIR"/"$CONFIG_FILE" terraform.conf

  # Symlink chosen package lists to where live-build will find them
  ln -s "package-lists.$PACKAGE_LISTS_SUFFIX" "config/package-lists"

  echo -e "
#------------------#
# LIVE-BUILD CLEAN #
#------------------#
"
  lb clean

  echo -e "
#-------------------#
# LIVE-BUILD CONFIG #
#-------------------#
"
  lb config

  echo -e "
#------------------#
# LIVE-BUILD BUILD #
#------------------#
"
  lb build

  echo -e "
#---------------------------#
# MOVE OUTPUT TO BUILDS DIR #
#---------------------------#
"
# update isolinux configuration file
sed -i 's/Ubuntu/mROS/g' $ISO_DIR/isolinux/txt.cfg
sed -i "s#file=/cdrom/preseed/ubuntu.seed#file=/cdrom/preseed/mros.seed#g" $ISO_DIR/isolinux/txt.cfg

# create new ISO image
genisoimage -D -r -V "mROS" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o $ISO_NAME $ISO_DIR

# copy live ISO and kernel to build directory
cp $ISO_DIR/casper/filesystem.squashfs $BUILD_DIR/casper/filesystem.squashfs
cp $ISO_DIR/casper/vmlinuz $BUILD_DIR/casper/vmlinuz

echo "Build complete!"

if [[ "$ARCH" == "all" ]]; then
    build amd64
else
    build "$ARCH"
fi
