"""Mock transport/JSON CLI tests. These do not validate a real TLS server or OpenWrt jsonfilter."""
import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--shell", required=True)
    parser.add_argument("--case", action="append", help="Run only the named scenarios")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="flow-test-", dir=ROOT / "openwrt_sh") as temp:
        temp = Path(temp)
        relative = temp.relative_to(ROOT).as_posix()
        for tool in ("curl", "jsonfilter", "sleep"):
            mock = temp / tool
            mock.write_text("#!/bin/sh\nexec " + shlex.quote(Path(sys.executable).as_posix()) +
                            " openwrt_sh/tests/mock_tool.py " + tool + ' "$@"\n', encoding="utf-8", newline="\n")
            mock.chmod(0o700)
        config = temp / "config"
        username = 'testuser&=+中文'
        password = "a'\\\"&=+ $x `do_not_execute`"
        config.write_text(f"username={username}\npassword={password}\nserver=https://portal.invalid\n", encoding="utf-8")
        state_path = temp / "state.json"
        env = dict(os.environ, CAMPUS_TEST_STATE=str(state_path))
        runner = temp / "run.sh"
        runner.write_text(f"#!/bin/sh\nPATH='{relative}':/usr/bin:/bin:$PATH\nexport PATH\n"
                          'exec "$@"\n', encoding="utf-8", newline="\n")
        shell = Path(args.shell).as_posix()
        check = subprocess.run([args.shell, str(runner), shell, "openwrt_sh/campus-login.sh", "--check"],
                               cwd=ROOT, env=env, capture_output=True, timeout=60)
        assert check.returncode == 0, check.stderr
        print("PASS: --check self-test", flush=True)
        cases = [
            ("online", "--once", 0, ["rad_user_info"]),
            ("offline", "--once", 0, ["rad_user_info", "get_challenge", "srun_portal", "rad_user_info"]),
            ("plain_json", "--once", 0, ["rad_user_info", "get_challenge", "srun_portal", "rad_user_info"]),
            ("rejected", "--once", 1, ["rad_user_info", "get_challenge", "srun_portal"]),
            ("invalid_ip", "--once", 1, ["rad_user_info", "get_challenge"]),
            ("redirect", "--once", 1, ["rad_user_info"]),
            ("certificate", "--once", 1, ["rad_user_info"]),
            ("html", "--once", 1, ["rad_user_info"]),
            ("online", "--status", 0, ["rad_user_info"]),
            ("unknown", "--status", 1, ["rad_user_info"]),
            ("unconfirmed", "--once", 1, ["rad_user_info", "get_challenge", "srun_portal", "rad_user_info"]),
            ("rejected", "--watch", 1, ["rad_user_info", "get_challenge", "srun_portal"] * 5),
        ]
        for scenario, mode, expected_rc, expected_calls in cases:
            if args.case and scenario not in args.case:
                continue
            state_path.write_text(json.dumps(dict(scenario=scenario, username=username, password=password)), encoding="utf-8")
            result = subprocess.run([args.shell, str(runner), shell, "openwrt_sh/campus-login.sh",
                                     mode, "--config", relative + "/config"],
                                    cwd=ROOT, env=env, capture_output=True, timeout=180)
            state = json.loads(state_path.read_text(encoding="utf-8"))
            error_path = state_path.with_suffix(".error")
            assert result.returncode == expected_rc, (scenario, result.returncode, result.stderr,
                error_path.read_text(encoding="utf-8") if error_path.exists() else "")
            assert state.get("calls") == expected_calls, (scenario, state, result.stderr)
            assert password.encode() not in result.stdout + result.stderr
            if mode == "--watch":
                expected_delays = ([60] if scenario == "unknown_then_rejected" else []) + [120, 240, 480, 900]
                assert state["delays"] == expected_delays, state
            print(f"PASS: {scenario} {mode}", flush=True)


if __name__ == "__main__":
    main()
