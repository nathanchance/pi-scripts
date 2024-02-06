#!/usr/bin/env fish

for arg in $argv
    switch $arg
        case arm arm64
            set arch $arg

        case '*'
            set krnl_src (realpath $arg)
    end
end

set bin_folder (realpath (status dirname))/bin

set path_overrides $bin_folder/$arch $bin_folder/host

if set -q PO
    set -p path_overrides (string split : $PO)
end

if not set -q krnl_src
    set krnl_src (realpath $PWD)
end

set out (tbf $krnl_src)/$arch

set common_make_args \
    -C $krnl_src \
    HOSTLDFLAGS=-fuse-ld=lld \
    LLVM=1 \
    O=$out

rm -rf $out

switch $arch
    case arm
        set arch_make_args ARCH=arm

        set kernel_image zImage

    case arm64
        set arch_make_args ARCH=arm64

        set kernel_image Image
end

kmake \
    --prepend-to-path=$path_overrides \
    $common_make_args \
    $arch_make_args \
    defconfig tarzst-pkg; or exit

set kernel $out/arch/$arch/boot/$kernel_image
if test -f $kernel
    printf '\n\e[01;32mKernel is now available at:\e[0m %s\n' $kernel
end
