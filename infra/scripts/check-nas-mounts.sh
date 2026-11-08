#!/bin/sh
set -eu

check_mount() {
    path="$1"
    expected="$2"

    echo "Checking $path ..."

    # Trigger systemd automount if necessary
    if ! timeout 20 ls -A "$path" > /dev/null; then
        echo "ERROR: Cannot access $path"
        exit 1
    fi

    # Verify the actual NFS source
    actual=$(findmnt -rn -M "$path" -t nfs,nfs4 -o SOURCE) || {
        echo "ERROR: $path is not an NFS mount"
        exit 1
    }

    if [ "$actual" != "$expected" ]; then
        echo "ERROR: Unexpected mount source: $actual"
        exit 1
    fi

    echo "OK: $path"
}

check_mount \
    /mnt/nas/data \
    192.168.0.220:/volume1/data

check_mount \
    /mnt/nas/nextcloud \
    192.168.0.220:/volume1/nextcloud-data

echo "All required NAS mounts verified."
