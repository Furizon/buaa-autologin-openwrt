#!/bin/sh
# BUAA SRun client for OpenWrt BusyBox ash. No Python on the router.
# Requires: curl, openssl, jsonfilter and standard BusyBox applets.

LC_ALL=C
export LC_ALL
umask 077
set -f

log() { printf '%s\n' "$*" >&2; }
die() { log "$*"; exit 1; }

# JSON string quoting, byte-preserving for UTF-8 (same as ensure_ascii=False).
json_string() {
    printf '%s' "$1" | od -An -v -tu1 | awk '
    BEGIN { printf "\"" }
    { for (i=1;i<=NF;i++) {
        b=$i+0
        if (b==34) printf "\\\""
        else if (b==92) printf "\\\\"
        else if (b==8) printf "\\b"
        else if (b==9) printf "\\t"
        else if (b==10) printf "\\n"
        else if (b==12) printf "\\f"
        else if (b==13) printf "\\r"
        else if (b<32) printf "\\u%04x", b
        else printf "%c", b
    }}
    END { printf "\"" }'
}

urlencode() {
    printf '%s' "$1" | od -An -v -tu1 | awk '
    { for (i=1;i<=NF;i++) {
        b=$i+0
        if ((b>=48 && b<=57)||(b>=65 && b<=90)||(b>=97 && b<=122)||b==45||b==46||b==95||b==126)
            printf "%c",b
        else printf "%%%02X",b
    }}'
}

# SRun modified XXTEA, NOT standard XXTEA. Only generated numeric values
# enter eval. A subshell keeps the numeric pseudo-arrays local.
# Binary output goes directly to stdout, never through a shell variable.
xencode() (
    data=$1 key=$2
    [ -n "$data" ] || exit 0
    k_0=0 k_1=0 k_2=0 k_3=0
    idx=0 shiftbits=0 word=0
    set -- $(printf '%s' "$key" | od -An -v -tu1)
    for byte do
        [ "$idx" -lt 4 ] || break
        word=$((word | (byte << shiftbits)))
        shiftbits=$((shiftbits + 8))
        eval "k_$idx=$word"
        if [ "$shiftbits" -eq 32 ]; then
            idx=$((idx + 1)); shiftbits=0; word=0
        fi
    done
    idx=0 shiftbits=0 word=0 length=0
    set -- $(printf '%s' "$data" | od -An -v -tu1)
    for byte do
        word=$((word | (byte << shiftbits)))
        shiftbits=$((shiftbits + 8)); length=$((length + 1))
        eval "v_$idx=$word"
        if [ "$shiftbits" -eq 32 ]; then
            idx=$((idx + 1)); shiftbits=0; word=0
        fi
    done
    [ "$shiftbits" -eq 0 ] || idx=$((idx + 1))
    n=$idx
    eval "v_$n=$length"
    z=$length total=0 rounds=$((6 + 52 / (n + 1)))
    while [ "$rounds" -gt 0 ]; do
        total=$(((total + 2654435769) & 4294967295))
        e=$(((total >> 2) & 3)); p=0
        while [ "$p" -le "$n" ]; do
            next=$((p + 1))
            [ "$p" -lt "$n" ] || next=0
            eval "y=\${v_$next}"
            ki=$(((p & 3) ^ e))
            eval "kw=\${k_$ki}"
            m=$(((z >> 5) ^ ((y << 2) & 4294967295)))
            m=$((m + (((y >> 3) ^ ((z << 4) & 4294967295)) ^ (total ^ y))))
            m=$((m + (kw ^ z)))
            eval "old=\${v_$p}"
            z=$(((old + m) & 4294967295))
            eval "v_$p=$z"
            p=$((p + 1))
        done
        rounds=$((rounds - 1))
    done
    p=0 escaped=
    while [ "$p" -le "$n" ]; do
        eval "word=\${v_$p}"
        # Build octal escapes with arithmetic, avoiding a subshell per word.
        for shiftbits in 0 8 16 24; do
            byte=$(((word >> shiftbits) & 255))
            escaped=$escaped\\0$((byte / 64))$(((byte / 8) % 8))$((byte % 8))
        done
        p=$((p + 1))
    done
    printf '%b' "$escaped"
)

# Sets digest, info, checksum. Inputs are shell variables, not process argv.
make_parameters() {
    raw=$(printf '{"username":%s,"password":%s,"ip":%s,"acid":%s,"enc_ver":"srun_bx1"}' \
        "$(json_string "$username")" "$(json_string "$password")" \
        "$(json_string "$ip")" "$(json_string "$ac_id")")
    xencode "$raw" "$token" > "$work/encoded" || return 1
    encoded=$(openssl base64 -A < "$work/encoded" 2>/dev/null) || return 1
    info='{SRBX1}'$(printf '%s' "$encoded" | tr \
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/' \
        'LVoJPiCN2R8G90yg+hmFHuacZ1OWMnrsSTXkYpUq/3dlbfKwv6xztjI7DeBE45QA')
    # The HMAC key is the server challenge, never the password.
    digest=$(printf '%s' "$password" | openssl dgst -md5 -hmac "$token" 2>/dev/null) || return 1
    digest=${digest##* }
    checksum=$(printf '%s' "$token$username$token$digest$token$ac_id$token$ip${token}200${token}1$token$info" \
        | openssl dgst -sha1 2>/dev/null) || return 1
    checksum=${checksum##* }
    case "$digest$checksum" in *[!0-9a-f]*) return 1;; esac
    [ "${#digest}" -eq 32 ] && [ "${#checksum}" -eq 40 ]
}

add_param() { query="$query&$1=$(urlencode "$2")"; }

api() {
    endpoint=$1
    query="callback=campus_callback&_=$(date +%s)000${query:+&$query}"
    set -- --disable --silent --show-error --noproxy '*' --proto '=https' \
        --connect-timeout 8 --max-time 15 --max-filesize 1048576 \
        --output "$work/reply" --write-out '%{http_code}' \
        --user-agent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' \
        --referer "$server/" --header 'Accept: application/json, */*'
    [ -z "$interface" ] || set -- "$@" --interface "$interface"
    [ -z "$ca_file" ] || set -- "$@" --cacert "$ca_file"
    # Feed the URL through stdin; no password or authentication query in argv.
    http=$(printf 'url = "%s/cgi-bin/%s?%s"\n' "$server" "$endpoint" "$query" \
        | curl "$@" --config - 2>/dev/null)
    rc=$?
    if [ "$rc" -ne 0 ]; then
        if [ "$rc" -eq 60 ]; then log 'HTTPS certificate check failed: check router time and CA certificates.'
        else log "Portal request failed (curl=$rc)."; fi
        return 1
    fi
    [ "$http" = 200 ] || { log "Portal HTTP $http (redirects are not followed)."; return 1; }
    reply=$(tr -d '\r\n' < "$work/reply" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    # Strip only the callback that this client requested. Never execute JSONP.
    case "$reply" in
        campus_callback\(*\)\;) reply=${reply#campus_callback(}; reply=${reply%\);};;
        campus_callback\(*\)) reply=${reply#campus_callback(}; reply=${reply%\)};;
    esac
    case "$reply" in \{*\}) ;; *) log 'Unexpected portal response.'; return 1;; esac
    printf '%s' "$reply" > "$work/json"
    jsonfilter -i "$work/json" -e '@' >/dev/null 2>&1 || { log 'Invalid portal JSON.'; return 1; }
}

field() { jsonfilter -i "$work/json" -e "@.$1" 2>/dev/null; }

status() {
    query=
    state=unknown
    api rad_user_info || return 1
    error=$(field error)
    case "$error" in
        not_online|not_online_error|user_not_online) state=offline;;
        ok) name=$(field user_name); [ -n "$name" ] || name=$(field username)
            [ -z "$name" ] || state=online;;
    esac
    return 0
}

valid_ipv4() {
    printf '%s\n' "$1" | awk -F. '
    NF!=4 { exit 1 }
    { for(i=1;i<=4;i++) if($i !~ /^[0-9]+$/ || length($i)>3 || $i+0>255 || (length($i)>1 && substr($i,1,1)=="0")) exit 1 }'
}

login() {
    query=
    add_param username "$username"; add_param ip ''
    api get_challenge || return 1
    [ "$(field error)" = ok ] || { log 'Challenge request rejected.'; return 1; }
    token=$(field challenge)
    case "$token" in ''|*[!A-Za-z0-9]*) log 'Invalid challenge.'; return 1;; esac
    [ "${#token}" -le 256 ] || return 1
    ip=$(field client_ip); [ -n "$ip" ] || ip=$(field online_ip)
    valid_ipv4 "$ip" || { log 'Portal returned an invalid IPv4 address.'; return 1; }
    make_parameters || { log 'Cannot calculate authentication parameters.'; return 1; }
    query=
    add_param action login; add_param username "$username"; add_param password "{MD5}$digest"
    add_param os 'Windows+10'; add_param name Windows; add_param nas_ip ''
    add_param double_stack 0; add_param chksum "$checksum"; add_param info "$info"
    add_param ac_id "$ac_id"; add_param ip "$ip"; add_param n 200; add_param type 1
    add_param captchaVal ''; add_param ap_id ''; add_param ap_ip ''; add_param mac ''
    api srun_portal || return 1
    if [ "$(field error)" = ok ] && [ "$(field res)" = ok ]; then
        log 'Portal accepted login.'; return 0
    fi
    code=$(field ecode)
    case "$code" in ''|*[!A-Za-z0-9_-]*) code=unknown;; esac
    [ "${#code}" -le 32 ] || code=unknown
    log "Login rejected (ecode=$code). Check the browser portal."
    return 1
}

load_config() {
    username= password= server=https://gw.buaa.edu.cn ac_id=67 interval=60 interface= ca_file=
    [ -f "$config" ] || die "Run: sh $0 --setup"
    cr=$(printf '\r')
    while IFS= read -r line || [ -n "$line" ]; do
        line=${line%"$cr"}
        case "$line" in ''|\#*) continue;; *=*) ;; *) die 'Invalid config line.';; esac
        key=${line%%=*}; value=${line#*=}
        case "$key" in
            username) username=$value;; password) password=$value;; server) server=$value;;
            ac_id) ac_id=$value;; interval) interval=$value;; interface) interface=$value;;
            ca_file) ca_file=$value;; *) die "Unknown config key.";;
        esac
    done < "$config"
    [ -n "$username" ] && [ -n "$password" ] || die 'Empty username/password; run --setup.'
    [ "${#username}" -le 256 ] && [ "${#password}" -le 256 ] || die 'Credentials exceed 256 bytes.'
    server=${server%/}
    printf '%s\n' "$server" | awk '
    /^https:\/\/[A-Za-z0-9.-]+(:[0-9]+)?$/ { ok=1 }
    END { exit !ok }' || die 'server must be https://hostname[:port]'
    case "$ac_id" in ''|*[!0-9]*) die 'Invalid ac_id.';; esac
    case "$interval" in ''|*[!0-9]*) die 'Invalid interval.';; esac
    [ "${#interval}" -le 4 ] || die 'interval must be 30..3600 seconds.'
    # Convert decimal without interpreting a leading zero as shell octal.
    interval=$(printf '%s\n' "$interval" | awk '{printf "%d",$0+0}')
    [ "$interval" -ge 30 ] && [ "$interval" -le 3600 ] || die 'interval must be 30..3600 seconds.'
}

cleanup() {
    [ -z "$sleeper" ] || kill "$sleeper" 2>/dev/null
    [ -z "$tty_state" ] || stty "$tty_state" 2>/dev/null
    if [ -n "$work" ]; then
        rm -f "$work/encoded" "$work/reply" "$work/json"
        rmdir "$work" 2>/dev/null
    fi
    [ "$locked" != 1 ] || rmdir "$lockdir" 2>/dev/null
    return 0
}

setup() {
    [ -t 0 ] || die '--setup requires an interactive terminal.'
    [ ! -L "$config" ] || die 'Refusing to overwrite a config symlink.'
    if [ -e "$config" ] && [ ! -f "$config" ]; then die 'Config path is not a regular file.'; fi
    printf 'Campus username: '; IFS= read -r username || exit 1
    tty_state=$(stty -g) || exit 1
    printf 'Campus password (hidden): '; stty -echo || exit 1
    IFS= read -r password
    rc=$?
    stty "$tty_state"; tty_state=
    printf '\n'
    [ "$rc" -eq 0 ] && [ -n "$username" ] && [ -n "$password" ] || die 'Empty or interrupted input.'
    [ ! -e "$config" ] || chmod 600 "$config" || exit 1
    { printf 'username=%s\npassword=%s\n' "$username" "$password"
      printf 'server=https://gw.buaa.edu.cn\nac_id=67\ninterval=60\ninterface=\nca_file=\n'
    } > "$config" || die 'Cannot save config.'
    log "Saved $config (plaintext, mode 600). Test with --once."
}

main() {
    config=/etc/buaa-campus-login.conf mode=--once
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --setup|--once|--watch|--status|--check) mode=$1;;
            --config) shift; [ "$#" -gt 0 ] || die 'Missing config path.'; config=$1;;
            *) die 'Usage: campus-login.sh [--setup|--check|--once|--status|--watch] [--config PATH]';;
        esac
        shift
    done
    work= locked=0 sleeper= tty_state= lockdir=/tmp/buaa-campus-login.lock
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    if [ "$mode" = --setup ]; then setup; return; fi
    for tool in curl openssl jsonfilter od awk tr sed mktemp date; do
        command -v "$tool" >/dev/null 2>&1 || die "Missing command: $tool. See README.md."
    done
    [ "$(((4294967295 + 1) >> 32))" = 1 ] || die 'This script requires shell 64-bit arithmetic.'
    if [ "$mode" = --check ]; then
        printf 'test' | openssl dgst -md5 -hmac test >/dev/null 2>&1 || die 'HMAC-MD5 unavailable.'
        printf 'test' | openssl dgst -sha1 >/dev/null 2>&1 || die 'SHA-1 unavailable.'
        probe=$(xencode abc abc | od -An -v -tx1 | tr -d ' \n')
        [ "$probe" = 4692d47f0107c60f ] || die 'SRun encoding self-test failed on this shell.'
        log 'Required commands, shell arithmetic and SRun encoding self-test passed.'; return 0
    fi
    load_config
    work=$(mktemp -d /tmp/buaa-campus.XXXXXX) || die 'Cannot create temporary directory.'
    if [ "$mode" = --status ]; then
        status || return 1
        log "Portal status: $state"
        [ "$state" = online ]; return
    fi
    mkdir "$lockdir" 2>/dev/null || die 'Another instance is running, or /tmp/buaa-campus-login.lock is stale. See README.md.'
    locked=1 failures=0 previous=
    while :; do
        delay=$interval
        if status; then
            if [ "$state" != "$previous" ]; then log "Portal status: $state"; previous=$state; fi
            if [ "$state" = online ]; then failures=0
            elif [ "$state" = offline ] || [ "$mode" = --once ]; then
                if login; then
                    # A successful login response alone does not reset failures.
                    if status && [ "$state" = online ]; then
                        failures=0; previous=online; log 'Online status confirmed.'
                    else
                        failures=$((failures + 1)); log 'Login accepted but online status is not confirmed.'
                    fi
                else failures=$((failures + 1)); fi
                if [ "$mode" = --once ]; then [ "$failures" -eq 0 ]; return; fi
            else log 'Unknown status; no automatic login this round.'; fi
        elif [ "$mode" = --once ]; then return 1
        fi
        [ "$mode" = --watch ] || return 0
        [ "$failures" -lt 5 ] || die 'Stopped after 5 unconfirmed login attempts. Check portal, then restart manually.'
        if [ "$failures" -gt 0 ]; then
            delay=$((interval << failures)); [ "$delay" -le 900 ] || delay=900
        fi
        sleep "$delay" & sleeper=$!
        wait "$sleeper"; sleeper=
    done
}

# Developers may source the protocol functions for offline tests.
if [ "${CAMPUS_LIBRARY:-0}" != 1 ]; then main "$@"; fi
