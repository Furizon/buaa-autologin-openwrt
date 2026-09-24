"""Pure protocol reference for developer tests only; no account configuration."""

import base64
import hashlib
import hmac
import json
import struct

ALPHABET = "LVoJPiCN2R8G90yg+hmFHuacZ1OWMnrsSTXkYpUq/3dlbfKwv6xztjI7DeBE45QA"

STANDARD = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

def xencode(data, key):
    """SRun's modified XXTEA (not interchangeable with generic XXTEA)."""
    if not data:
        return b""
    def words(b):
        return list(struct.unpack("<%dI" % ((len(b) + 3) // 4),
                                  b + b"\0" * ((-len(b)) % 4)))
    v = words(data) + [len(data)]
    k = words(key)
    k += [0] * max(0, 4 - len(k))
    n = len(v) - 1
    z, total = v[n], 0
    for _ in range(6 + 52 // (n + 1)):
        total = (total + 0x9E3779B9) & 0xFFFFFFFF
        e = (total >> 2) & 3
        for p in range(n + 1):
            y = v[p + 1] if p < n else v[0]
            m = (z >> 5) ^ ((y << 2) & 0xFFFFFFFF)
            m += ((y >> 3) ^ ((z << 4) & 0xFFFFFFFF)) ^ (total ^ y)
            m += k[(p & 3) ^ e] ^ z
            v[p] = (v[p] + m) & 0xFFFFFFFF
            z = v[p]
    return struct.pack("<%dI" % len(v), *v)

def login_parameters(username, password, token, ip, ac_id):
    info_raw = json.dumps(dict(username=username, password=password, ip=ip,
                               acid=str(ac_id), enc_ver="srun_bx1"),
                          separators=(",", ":"), ensure_ascii=False)
    encrypted = xencode(info_raw.encode("utf-8"), token.encode("ascii"))
    info = "{SRBX1}" + base64.b64encode(encrypted).decode().translate(
        str.maketrans(STANDARD, ALPHABET))
    digest = hmac.new(token.encode(), password.encode(), hashlib.md5).hexdigest()
    checksum = hashlib.sha1("".join(token + s for s in
        (username, digest, str(ac_id), ip, "200", "1", info)).encode()).hexdigest()
    return dict(action="login", username=username, password="{MD5}" + digest,
                os="Windows+10", name="Windows", nas_ip="", double_stack="0",
                chksum=checksum, info=info, ac_id=str(ac_id), ip=ip, n="200",
                type="1", captchaVal="", ap_id="", ap_ip="", mac="")
