"""Offline developer checks. Python is NOT used by the router script.

Run from the repository root:
  python openwrt_sh/tests/test_shell.py --shell /bin/dash
On Windows, pass the full path to Git's usr/bin/dash.exe or bash.exe.
"""
import argparse
import importlib.util
from pathlib import Path
import random
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("reference", ROOT / "tests" / "protocol_reference.py")
reference = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reference)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--shell", required=True)
    args = parser.parse_args()
    for name in ("campus-login.sh", "buaa-campus-login.init", "tests/protocol_driver.sh"):
        subprocess.run([args.shell, "-n", str(ROOT / "openwrt_sh" / name)], check=True)
    rng = random.Random(2100)
    cases = [
        ("testuser", "testpass", "0123456789abcdef" * 4, "10.1.2.3", "67"),
        ('u"\\&=+ 空格', 'p"\\&=+ %中文\t', "f" * 64, "172.16.0.2", "67"),
        ("$(do_not_execute)", "`no_execution`'\"\\ $PATH", "1", "192.168.1.100", "1"),
    ]
    # Packing boundaries, varying rounds, short/padded and long keys, UTF-8.
    for size in (1, 2, 3, 4, 7, 8, 15, 16, 31, 32, 63, 64, 127, 128, 255, 256):
        cases.append(("user" + str(size), "".join(rng.choice("aZ09!@#$%^&*()_+-= /\\\"'") for _ in range(size)),
                      "".join(rng.choice("0123456789abcdef") for _ in range(rng.choice((1, 15, 16, 17, 32, 64)))),
                      "10.254.128.7", "67"))
    with tempfile.TemporaryDirectory(prefix="shell-test-", dir=ROOT / "openwrt_sh") as temp:
        relative = Path(temp).relative_to(ROOT).as_posix()
        started = time.monotonic()
        proc = subprocess.run([args.shell, "openwrt_sh/tests/protocol_driver.sh", relative],
                              cwd=ROOT, input="".join("\n".join(c) + "\n" for c in cases).encode(),
                              capture_output=True, timeout=240)
        if proc.returncode:
            raise AssertionError(proc.stderr.decode(errors="replace"))
        lines = proc.stdout.decode().splitlines()
        assert len(lines) == 3 * len(cases), (len(lines), proc.stderr)
        for index, case in enumerate(cases):
            expected = reference.login_parameters(*case)
            actual = lines[index * 3:index * 3 + 3]
            assert actual == [expected["password"][5:], expected["info"], expected["chksum"]], f"case {index} mismatch"
        print(f"PASS: syntax and {len(cases)} protocol vectors ({time.monotonic()-started:.2f}s, developer machine only)")


if __name__ == "__main__":
    main()
