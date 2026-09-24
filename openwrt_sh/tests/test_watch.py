"""Fast watch-policy tests, with in-process shell stubs for network calls."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--shell", required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="watch-test-", dir=ROOT / "openwrt_sh") as temp:
        temp = Path(temp)
        relative = temp.relative_to(ROOT).as_posix()
        (temp / "config").write_text("username=test\npassword=test\n", encoding="utf-8", newline="\n")
        for scenario in ("unknown", "unconfirmed"):
            events = temp / scenario
            result = subprocess.run([args.shell, "openwrt_sh/tests/watch_driver.sh", scenario,
                                     relative + "/" + scenario, relative + "/config"],
                                    cwd=ROOT, capture_output=True, timeout=60)
            assert result.returncode == 1, (scenario, result.stderr)
            assert b"Stopped after 5" in result.stderr, (scenario, result.stderr)
            actual = events.read_text().splitlines()
            expected = ["status", "sleep:60"] if scenario == "unknown" else []
            for index in range(5):
                expected += ["status", "login"]
                if scenario == "unconfirmed":
                    expected += ["status"]
                if index < 4:
                    expected += ["sleep:" + str((120, 240, 480, 900)[index])]
            assert actual == expected, (scenario, actual)
            print(f"PASS: {scenario} watch policy", flush=True)


if __name__ == "__main__":
    main()
