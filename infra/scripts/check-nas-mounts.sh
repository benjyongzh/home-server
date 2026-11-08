#!/bin/sh
set -eu

: "${NAS_HOST:?Set NAS_HOST in /opt/shared/.env}"
: "${NAS_DATA_ROOT:?Set NAS_DATA_ROOT in /opt/shared/.env}"
: "${NAS_NEXTCLOUD_ROOT:?Set NAS_NEXTCLOUD_ROOT in /opt/shared/.env}"
: "${NEXTCLOUD_DATA_PATH:?Set NEXTCLOUD_DATA_PATH in /opt/shared/.env}"

case "$NEXTCLOUD_DATA_PATH" in
    "$NAS_NEXTCLOUD_ROOT"/*) ;;
    *) echo "ERROR: Nextcloud data path must be inside the NAS Nextcloud mount" >&2; exit 1 ;;
esac

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
    "$NAS_DATA_ROOT" \
    "$NAS_HOST:/volume1/data"

check_mount \
    "$NAS_NEXTCLOUD_ROOT" \
    "$NAS_HOST:/volume1/nextcloud-data"

if [ ! -f "$NEXTCLOUD_DATA_PATH/.ncdata" ]; then
    echo "ERROR: Nextcloud data marker is missing" >&2
    exit 1
fi

echo "All required NAS mounts verified."
