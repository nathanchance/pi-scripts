#!/usr/bin/env bash

set -eu

BASE=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")

function die() {
    printf "\n\033[01;31m%s\033[0m\n" "${1}"
    exit "${2:-33}"
}

# Get parameters
function parse_parameters() {
    MY_TARGETS=()
    while ((${#})); do
        case ${1} in
            *config) CONFIG=${1} ;;
            */ | *.i | *.ko | *.o | vmlinux | zImage | modules) MY_TARGETS=("${MY_TARGETS[@]}" "${1}") ;;
            *=*) export "${1?}" ;;
            -d | --debug) DEBUG_INFO=true ;;
            -i | --incremental) INCREMENTAL=true ;;
            -j | --jobs) JOBS=${1} ;;
            -k | --kernel-src) shift && KERNEL_SRC=$(readlink -f "${1}") ;;
            -n | --no-hardening) NO_HARDENING=true ;;
            -u | --update-config-only) UPDATE_CONFIG_ONLY=true ;;
            -v | --verbose) VERBOSE=true ;;
        esac
        shift
    done
    [[ -z ${KERNEL_SRC:-} ]] && KERNEL_SRC=$(readlink -f "${PWD}")
    [[ -f ${KERNEL_SRC}/Makefile ]] || die "Not in a kernel folder?"
    [[ -z ${MY_TARGETS[*]} ]] && MY_TARGETS=(all dtbs_install modules_install)

    # If V=, make sure -v is also set
    [[ -n ${V:-} ]] && VERBOSE=true

    # Handle architecture specific variables
    case ${ARCH:=arm64} in
        arm)
            CROSS_COMPILE=arm-linux-gnueabi-
            [[ -f ${KERNEL_SRC}/arch/arm/configs/bcm2709_defconfig ]] && CONFIG=bcm2709_defconfig
            CONFIG=arch/arm/configs/${CONFIG:-multi_v7_defconfig}
            KERNEL_IMAGE=zImage
            ;;

        arm64)
            CROSS_COMPILE=aarch64-linux-gnu-
            CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
            CONFIG=arch/arm64/configs/${CONFIG:-defconfig}
            KERNEL_IMAGE=Image
            LLVM_IAS=1
            ;;

        *) die "\${ARCH} value of '${ARCH}' is not supported!" ;;
    esac
}

function set_toolchain() {
    # Add toolchain folders to PATH and request path override (PO environment variable)
    HERMETIC_PATH=${BASE}/bin/${ARCH}:${BASE}/bin/host:
    export PATH="${PO:+${PO}:}${CBL_LLVM:+${CBL_LLVM}:}${HERMETIC_PATH}${CBL_BNTL:+${CBL_BNTL}:}${PATH}"

    # Use ccache if it exists
    CCACHE=$(command -v ccache)

    # Resolve O=
    O=$(readlink -f -m "${O:=${KERNEL_SRC}/out/${ARCH}}")

    : "${CC:=clang}"
    printf '\n\e[01;32mToolchain location:\e[0m %s\n\n' "$(dirname "$(command -v "${CC##* }")")"
    printf '\e[01;32mToolchain version:\e[0m %s \n\n' "$("${CC##* }" --version | head -n1)"
}

function kmake() {
    set -x
    time make \
        -C "${KERNEL_SRC}" \
        -"${SILENT_MAKE_FLAG:-}"kj"${JOBS:="$(nproc)"}" \
        ${AR:+AR="${AR}"} \
        ARCH="${ARCH}" \
        ${CCACHE:+CC="ccache ${CC}"} \
        ${CROSS_COMPILE:+CROSS_COMPILE="${CROSS_COMPILE}"} \
        ${CROSS_COMPILE_COMPAT:+CROSS_COMPILE_COMPAT="${CROSS_COMPILE_COMPAT}"} \
        ${HOSTAR:+HOSTAR="${HOSTAR}"} \
        ${CCACHE:+HOSTCC="ccache ${HOSTCC:-clang}"} \
        ${HOSTLD:+HOSTLD="${HOSTLD}"} \
        HOSTLDFLAGS="${HOSTLDFLAGS--fuse-ld=lld}" \
        INSTALL_DTBS_PATH=rootfs \
        INSTALL_MOD_PATH=rootfs \
        KCFLAGS="${KCFLAGS--Werror}" \
        ${LD:+LD="${LD}"} \
        LLVM="${LLVM:=1}" \
        ${LLVM_IAS:+LLVM_IAS="${LLVM_IAS}"} \
        ${NM:+NM="${NM}"} \
        O="$(realpath -m --relative-to="${KERNEL_SRC}" "${O}")" \
        ${OBJCOPY:+OBJCOPY="${OBJCOPY}"} \
        ${OBJDUMP:+OBJDUMP="${OBJDUMP}"} \
        ${OBJSIZE:+OBJSIZE="${OBJSIZE}"} \
        ${READELF:+READELF="${READELF}"} \
        ${STRIP:+STRIP="${STRIP}"} \
        ${V:+V=${V}} \
        "${@}"
    set +x
}

function clang_hardening() {
    set -x
    ${NO_HARDENING:=false} || "${KERNEL_SRC}"/scripts/config \
        --file "${O}"/.config \
        -e SHADOW_CALL_STACK \
        -d LTO_NONE \
        -e LTO_CLANG \
        -e LTO_CLANG_THIN \
        -e CFI_CLANG
    set +x
}

function debug_info() {
    set -x
    ${DEBUG_INFO:=false} || "${KERNEL_SRC}"/scripts/config --file "${O}"/.config -d CONFIG_DEBUG_INFO
    set +x
}

function build_kernel() {
    # Build silently by default
    ${VERBOSE:=false} || SILENT_MAKE_FLAG=s

    # Build list of configure targets
    CONFIG_MAKE_TARGETS=("${CONFIG##*/}")
    ${INCREMENTAL:=false} || CONFIG_MAKE_TARGETS=(distclean "${CONFIG_MAKE_TARGETS[@]}")

    # Build list of build targets
    ${UPDATE_CONFIG_ONLY:=false} && FINAL_MAKE_TARGETS=(savedefconfig)
    [[ -z ${FINAL_MAKE_TARGETS[*]} ]] && FINAL_MAKE_TARGETS=("${MY_TARGETS[@]}")
    FINAL_MAKE_TARGETS=(olddefconfig "${FINAL_MAKE_TARGETS[@]}")

    # Build the kernel with targets
    rm -rf "${O}"/rootfs
    kmake "${CONFIG_MAKE_TARGETS[@]}"
    clang_hardening
    debug_info
    kmake "${FINAL_MAKE_TARGETS[@]}"

    # Copy over new config if needed
    if ${UPDATE_CONFIG_ONLY}; then
        cp -v "${O}"/defconfig "${KERNEL_SRC}"/"${CONFIG}"
        exit 0
    fi

    # Let the user know where the kernel will be (if we built one)
    KERNEL=${O}/arch/${ARCH}/boot/${KERNEL_IMAGE}
    [[ -f ${KERNEL} ]] && printf '\n\e[01;32mKernel is now available at:\e[0m %s\n' "${KERNEL}"
}

parse_parameters "${@}"
set_toolchain
build_kernel
