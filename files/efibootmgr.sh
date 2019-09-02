#!/bin/sh

die() {
    echo "$*" >&2
    exit 1
}

run_device() {
    local devdir="$1" label= label_set=
    local devname= dev= partition=
    shift

    if [ "x$1" = "x-L" ]; then
        label_set=true
        label="$2"
        shift 2
    fi

    devdir="$(cd "$devdir" && pwd -P)"

    if [ -s "$devdir/partition" ]; then
        read partition < "$devdir/partition"
        devname="${devdir##*/}"
        devdir="${devdir%/*}"
    fi
    dev="/dev/${devdir##*/}"

    if [ -n "$label_set" -a -z "$label" ]; then
        label=$devname
    else
        [ -n "$label" ] || label="$(lsb_release -si)"

        label="$label ($devname)"
    fi

    set -x
    "${0%.sh}.real" "$@" -L "$label" -d "$dev" ${partition:+-p $partition}
}

run_raid() {
    local x= argv=
    local label= label_set= label_next=
    local device= devdir=
    local md_level= md_disks=

    # extract label
    for x; do
        if [ "$x" = "-L" ]; then
            label_next=true
            label_set=
            label=
        elif [ -n "$label_next" ]; then
            label_next=
            label_set=true
            label="$x"
        else
            x=$(echo -n "$x" | sed -e 's|"|\\"|g')
            argv="$argv \"$x\""
        fi
    done

    if [ -n "$label_set" ]; then
        x=$(echo -n "$label" | sed -e 's|"|\\"|g')
        argv="-L \"$x\" $argv"
    fi

    device="$(grep ' /boot/efi ' /proc/mounts | cut -d' ' -f1)"
    [ -b "$device" ] || die "ESP not mounted"
    device="$(readlink -f "$device")"
    devdir=/sys/class/block/${device##*/}

    if read md_level < $devdir/md/level 2> /dev/null; then
        if [ "$md_level" = raid1 ]; then
            read md_disks < $devdir/md/raid_disks
            for i in `seq $md_disks`; do
                set +x
                eval "run_device '$devdir/md/rd$(($i - 1))/block' $argv"
            done
        else
            die "RAID $md_level not supported"
        fi
    else
        # not RAID
        set -x
        eval "run_device '$devdir' $argv"
    fi
    exit 0
}

run_normal() {
    exec "${0%.sh}.real" "$@"
}

set -eu

argv=
i=1
for x; do
    if [ "$x" = "-d" -a $i -eq $# ]; then
        # /boot/efi is /dev/md and grub-install can't handle it yet
        eval "run_raid $argv"
        die "never reached"
    fi

    : $((i = i+1))
    x=$(echo -n "$x" | sed -e 's|"|\\"|g')
    argv="$argv \"$x\""
done

set -x
eval "run_normal $argv"
