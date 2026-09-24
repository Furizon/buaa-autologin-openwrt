#!/bin/sh
PATH=/usr/bin:/bin:$PATH
export PATH
CAMPUS_LIBRARY=1
. ./openwrt_sh/campus-login.sh
work=$1
while IFS= read -r username && IFS= read -r password && IFS= read -r token && IFS= read -r ip && IFS= read -r ac_id; do
    make_parameters || exit 1
    printf '%s\n%s\n%s\n' "$digest" "$info" "$checksum"
done
