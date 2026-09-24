#!/bin/sh
PATH=/usr/bin:/bin:$PATH
export PATH
CAMPUS_LIBRARY=1
. ./openwrt_sh/campus-login.sh
policy=$1 events=$2 test_config=$3 calls=0
# Isolate watch policy from transport/JSON process startup. Those are covered
# by test_flow.py. Every override below exists only in this test driver.
curl() { :; }
openssl() { :; }
jsonfilter() { :; }
status() {
    calls=$((calls + 1))
    printf 'status\n' >> "$events"
    state=offline
    if [ "$policy" = unknown ] && [ "$calls" -eq 1 ]; then state=unknown; fi
    return 0
}
login() {
    printf 'login\n' >> "$events"
    [ "$policy" = unconfirmed ]
}
sleep() { printf 'sleep:%s\n' "$1" >> "$events"; }
main --watch --config "$test_config"
