#!/bin/sh

[ "$1" = "-" ] || exit 64
shift
script=$(cat)
if [ "$#" -gt 0 ]; then
    command_name=$1
    shift
else
    command_name=pippin-fixture
fi
exec /bin/sh -c "$script" "$command_name" "$@"
