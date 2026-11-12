#!/bin/sh

if [ "$#" -lt 2 ]; then
    printf 'Error: filesdir and searchstr are required.\n' >&2
    exit 1
fi

filesdir=$1
searchstr=$2

if [ ! -d "$filesdir" ]; then
    printf 'Error: "%s" is not a directory.\n' "$filesdir" >&2
    exit 1
fi

num_files=$(find "$filesdir" -type f | wc -l | tr -d '[:space:]')
matching_lines=$(find "$filesdir" -type f |
    while IFS= read -r file; do
        grep -F -c -e "$searchstr" "$file" || :
    done |
    awk '{ total += $1 } END { print total + 0 }')

printf 'The number of files are %s and the number of matching lines are %s\n' \
    "$num_files" "$matching_lines"
