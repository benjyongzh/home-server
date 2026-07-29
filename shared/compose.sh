#!/bin/sh

set -eu

usage() {
    echo "Usage: $0 <stack-name> <docker-compose-arguments...>" >&2
    echo "Example: $0 homepage up -d" >&2
    exit 2
}

[ "$#" -ge 2 ] || usage

stack_name=$1
shift

case "$stack_name" in
    *[!A-Za-z0-9_-]*|'')
        echo "Invalid stack name: $stack_name" >&2
        exit 2
        ;;
esac

shared_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
install_root=$(dirname -- "$shared_dir")
stack_dir=$install_root/stacks/$stack_name

if [ -f "$stack_dir/compose.yaml" ]; then
    compose_file=$stack_dir/compose.yaml
elif [ -f "$stack_dir/compose.yml" ]; then
    compose_file=$stack_dir/compose.yml
else
    echo "No Compose file found for stack: $stack_name" >&2
    exit 2
fi

if [ ! -f "$shared_dir/.env" ]; then
    echo "Missing $shared_dir/.env; copy .env.example and configure this machine first." >&2
    exit 2
fi

if [ ! -f "$stack_dir/.env" ]; then
    echo "Missing $stack_dir/.env; copy .env.example and configure the stack first." >&2
    exit 2
fi

# The actual checkout location wins over INSTALL_ROOT in shared/.env, allowing
# the whole tree to be moved while preserving all relative stack paths.
export INSTALL_ROOT="$install_root"

exec docker compose \
    --project-directory "$stack_dir" \
    --env-file "$shared_dir/.env" \
    --env-file "$stack_dir/.env" \
    -f "$compose_file" \
    "$@"
