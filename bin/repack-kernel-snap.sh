#!/bin/bash -e

# output dir to try to copy the build snap to when we're done
# TODO: make this an option?
OUT_DIR=$PWD

# make a random pattern to use in $SNAP_DATA so we don't conflict with previous
# runs
RUN_NUM=$RANDOM

# get the snap file name with the extension so we can add "-repacked" on the end
# when we build the repacked snap
ORIG_SNAP_FILE=$(basename -- "$1")
SNAP_FILE="${ORIG_SNAP_FILE%.*}"


SNAP_UNPACK_DIR=$SNAP_DATA/repacked-kernel-$RUN_NUM
SNAP_INITRD=$SNAP_DATA/repacked-initrd-$RUN_NUM
SNAP_KERNEL_EFI=$SNAP_DATA/repacked-kernel.efi-$RUN_NUM

# unpack the snap file we were provided
# TODO:UC20: filter out just dirs we want to be more efficient
unsquashfs -d "$SNAP_UNPACK_DIR" "$1"

# get the kernel version from the config-* file in the snap
KERNEL_VER=$(ls "$SNAP_UNPACK_DIR/config"-* | grep -Po 'config-\K.*')

# copy some module assets to ubuntu-core-initramfs's dir because it's silly and 
# doesn't use the root dir for these things 
mkdir -p /usr/lib/ubuntu-core-initramfs/main/lib/modules
cp -ar "$SNAP_UNPACK_DIR/lib/modules/$KERNEL_VER" /usr/lib/ubuntu-core-initramfs/main/lib/modules
cp -ar "$SNAP_UNPACK_DIR/lib/modules/$KERNEL_VER" /usr/lib/modules

# first rebuild initrd with $SNAP_DATA's copy of ubuntu-core-initramfs

# TODO: maybe patch upstream ubuntu-core-initramfs to make --root work better?
# original with --root arg and no layout
# ubuntu-core-initramfs create-initrd \
#     --root "$SNAP/" \
#     --skeleton "$SNAP_DATA/usr/lib/ubuntu-core-initramfs" \
#     --kernelver "$KERNEL_VER" \
#     --output "$SNAP_INITRD"  \
#     --kerneldir "$SNAP_UNPACK_DIR/lib/modules"

ubuntu-core-initramfs create-initrd \
    --kernelver "$KERNEL_VER" \
    --output "$SNAP_INITRD"  \
    --kerneldir "$SNAP_UNPACK_DIR/lib/modules" \
    --firmwaredir "$SNAP_UNPACK_DIR/lib/firmware"


# ubuntu-core-initramfs create-efi assumes that the --kernel arg really is the
# pattern of the real kernel filename with the version number appended to the 
# filename, so we have to extract the .linux section to a filename like 
# "vmlinuz-$KERNEL_VER"
objcopy \
    -O binary \
    --only-section=.linux \
    "$SNAP_UNPACK_DIR/kernel.efi" \
    "$SNAP_UNPACK_DIR/vmlinuz-$KERNEL_VER"

# now build the efi with the vmlinuz linux elf section and the initrd we built 
# previously

# original with --root and no layout
# ubuntu-core-initramfs create-efi \
#     --root "$SNAP/" \
#     --stub "$SNAP/usr/lib/ubuntu-core-initramfs/efi/linuxx64.efi.stub" \
#     --key "$SNAP/usr/lib/ubuntu-core-initramfs/snakeoil/PkKek-1-snakeoil.key" \
#     --cert "$SNAP/usr/lib/ubuntu-core-initramfs/snakeoil/PkKek-1-snakeoil.pem" \
#     --kernelver "$KERNEL_VER" \
#     --output "$SNAP_KERNEL_EFI" \
#     --initrd "$SNAP_INITRD" \
#     --kernel "$SNAP_UNPACK_DIR/kernel.efi"

ubuntu-core-initramfs create-efi \
    --kernelver "$KERNEL_VER" \
    --output "$SNAP_KERNEL_EFI" \
    --initrd "$SNAP_INITRD" \
    --kernel "$SNAP_UNPACK_DIR/vmlinuz"

# cleanup intermediate vmlinuz
rm "$SNAP_UNPACK_DIR/vmlinuz-$KERNEL_VER"

# mv the output kernel efi into the kernel snap and re-pack it
mv "$SNAP_KERNEL_EFI-$KERNEL_VER" "$SNAP_UNPACK_DIR/kernel.efi"

# ideally we would do this with `snap pack`, but for now this will do
mksquashfs \
    "$SNAP_UNPACK_DIR" \
    "$OUT_DIR/$SNAP_FILE-repacked.snap" \
    -noappend \
    -no-fragments \
    -all-root \
    -no-xattrs \
    -comp xz

echo ">>> re-packed as $OUT_DIR/$SNAP_FILE-repacked.snap"
