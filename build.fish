#!/usr/bin/env fish

for arg in $argv
    switch $arg
        case arm arm64
            set arch $arg

        case '*'
            set krnl_src (realpath $arg)
    end
end

set bin_folder (status dirname)/bin

set --path path_overrides $bin_folder/$arch $bin_folder/host

if not set -q krnl_src
    set krnl_src (realpath $PWD)
end

set out .build/$arch
set full_out $krnl_src/$out

set common_make_args \
    -C $krnl_src \
    HOSTLDFLAGS=-fuse-ld=lld \
    INSTALL_DTBS_PATH=rootfs \
    INSTALL_MOD_PATH=rootfs \
    INSTALL_MOD_STRIP=1 \
    KCFLAGS=-Werror \
    LLVM=1 \
    LLVM_IAS=1 \
    O=$out

# This is not cleaned up by 'distclean' so do it manually here
rm -rf $out/rootfs

switch $arch
    case arm
        set arch_make_args ARCH=arm CROSS_COMPILE=arm-linux-gnueabi-

        set kernel_image zImage

    case arm64
        set arch_make_args ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-

        set kernel_image Image
end

PO="$path_overrides" kmake \
    $arch_make_args \
    $common_make_args \
    distclean defconfig all dtbs_install modules_install; or exit

set kernel $full_out/arch/$arch/boot/$kernel_image
if test -f $kernel
    printf '\n\e[01;32mKernel is now available at:\e[0m %s\n' $kernel
end
