#!/bin/sh

set -u

ACTION="${1:-}"
PORTS="${2:-}"
QBIT_URL="${QBIT_URL:-http://127.0.0.1:8080}"

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

case "$ACTION" in
    up)
        # Gluetun may provide one port or a comma-separated list.
        PORT="$(printf '%s' "$PORTS" | cut -d',' -f1 | tr -d '[:space:]')"

        case "$PORT" in
            ''|*[!0-9]*)
                log "ERROR: Invalid forwarded port received: '$PORTS'"
                exit 1
                ;;
        esac

        if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
            log "ERROR: Forwarded port is outside the valid range: $PORT"
            exit 1
        fi

        log "Waiting for qBittorrent Web API at $QBIT_URL"

        ATTEMPT=1
        MAX_ATTEMPTS=60

        while [ "$ATTEMPT" -le "$MAX_ATTEMPTS" ]; do
            if wget -q -O /dev/null \
                "$QBIT_URL/api/v2/app/version" 2>/dev/null; then
                break
            fi

            log "qBittorrent unavailable; retry $ATTEMPT/$MAX_ATTEMPTS"
            ATTEMPT=$((ATTEMPT + 1))
            sleep 2
        done

        if [ "$ATTEMPT" -gt "$MAX_ATTEMPTS" ]; then
            log "ERROR: qBittorrent did not become available"
            exit 1
        fi

        log "Setting qBittorrent listening port to $PORT"

        RESPONSE="$(
            wget -q -O - \
                --header='Content-Type: application/x-www-form-urlencoded' \
                --post-data="json={\"listen_port\":$PORT,\"random_port\":false,\"upnp\":false}" \
                "$QBIT_URL/api/v2/app/setPreferences" 2>&1
        )"
        STATUS=$?

        if [ "$STATUS" -ne 0 ]; then
            log "ERROR: qBittorrent API request failed: $RESPONSE"
            exit 1
        fi

        sleep 1

        PREFERENCES="$(
            wget -q -O - "$QBIT_URL/api/v2/app/preferences" 2>/dev/null
        )"

        if printf '%s' "$PREFERENCES" |
            grep -Eq "\"listen_port\"[[:space:]]*:[[:space:]]*$PORT([,}])"; then
            log "SUCCESS: qBittorrent listening port is now $PORT"
            exit 0
        fi

        log "ERROR: qBittorrent did not report listening port $PORT"
        exit 1
        ;;

    down)
        # There is no replacement port during teardown.
        # Leave qBittorrent unchanged until the next UP event supplies a new port.
        log "VPN port forwarding stopped; waiting for the next forwarded port"
        exit 0
        ;;

    *)
        log "Usage: $0 up <port-or-ports> | down"
        exit 2
        ;;
esac
