#!/bin/sh

set -eu

NUMFILES=${1:-10}
WRITESTR=${2:-AELD_IS_FUN}
WRITEDIR=${WRITEDIR:-/tmp/aeld-data}

case $NUMFILES in
    ''|*[!0-9]*)
        printf 'Error: numfiles must be a non-negative integer.\n' >&2
        exit 1
        ;;
esac

if [ "$#" -ge 3 ]; then
    case $3 in
        ''|.|..|*/*)
            printf 'Error: the optional directory name must be a simple name.\n' >&2
            exit 1
            ;;
    esac
    WRITEDIR=$WRITEDIR/$3
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$SCRIPT_DIR"

username=$(cat conf/username.txt)
assignment=$(cat conf/assignment.txt)
MATCHSTR="The number of files are ${NUMFILES} and the number of matching lines are ${NUMFILES}"

printf 'Writing %s files containing string %s to %s\n' \
    "$NUMFILES" "$WRITESTR" "$WRITEDIR"
rm -rf -- "$WRITEDIR"
if [ "$assignment" != assignment1 ]; then
    mkdir -p -- "$WRITEDIR"
fi
trap 'rm -rf -- "$WRITEDIR"' EXIT

i=1
while [ "$i" -le "$NUMFILES" ]; do
    ./writer "$WRITEDIR/${username}${i}.txt" "$WRITESTR"
    i=$((i + 1))
done

OUTPUTSTRING=$(./finder.sh "$WRITEDIR" "$WRITESTR")
if [ "$OUTPUTSTRING" = "$MATCHSTR" ]; then
    printf 'success\n'
else
    printf 'failed: expected "%s" but got "%s"\n' \
        "$MATCHSTR" "$OUTPUTSTRING" >&2
    exit 1
fi
