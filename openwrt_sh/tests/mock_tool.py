"""Test doubles only: curl transport, jsonfilter CLI, sleep. Never ship as runtime dependencies."""
import importlib.util
import json
import os
from pathlib import Path
import re
import sys
import traceback
from urllib.parse import parse_qs, urlsplit

sys.stdout.reconfigure(encoding="utf-8", newline="\n")

ROOT = Path(__file__).resolve().parents[2]
def report_error(kind, value, tb):
    Path(os.environ["CAMPUS_TEST_STATE"]).with_suffix(".error").write_text(
        "".join(traceback.format_exception(kind, value, tb)), encoding="utf-8")
sys.excepthook = report_error
spec = importlib.util.spec_from_file_location("reference", ROOT / "tests" / "protocol_reference.py")
ref = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ref)

kind, *args = sys.argv[1:]
if kind == "jsonfilter":
    try:
        value = json.loads(Path(args[args.index("-i") + 1]).read_text(encoding="utf-8"))
        expr = args[args.index("-e") + 1]
        if expr == "@":
            print(json.dumps(value))
        elif expr.startswith("@.") and expr[2:] in value:
            print(value[expr[2:]])
    except (ValueError, OSError, TypeError):
        sys.exit(1)
    sys.exit(0)

state_path = Path(os.environ["CAMPUS_TEST_STATE"])
state = json.loads(state_path.read_text(encoding="utf-8"))
if kind == "sleep":
    state.setdefault("delays", []).append(int(args[0]))
    state_path.write_text(json.dumps(state), encoding="utf-8")
    sys.exit(0)

assert kind == "curl"
assert args[0] == "--disable"
assert args[args.index("--proto") + 1] == "=https"
assert args[args.index("--noproxy") + 1] == "*"
assert not {"-L", "--location", "-k", "--insecure"}.intersection(args)
assert all(state["password"] not in a and "{SRBX1}" not in a for a in args)
line = sys.stdin.read()
match = re.fullmatch(r'url = "([^"\n]+)"\n', line)
assert match, line
url = urlsplit(match[1])
assert url.scheme == "https"
endpoint = url.path.rsplit("/", 1)[-1]
query = {k: v[0] for k, v in parse_qs(url.query, keep_blank_values=True).items()}
assert query.pop("callback") == "campus_callback"
query.pop("_")
state.setdefault("calls", []).append(endpoint)
scenario = state["scenario"]
response = {"error": "not_online"}
if endpoint == "rad_user_info":
    assert not query
    if scenario == "online" or (state.get("logged_in") and scenario != "unconfirmed"):
        response = {"error": "ok", "user_name": state["username"]}
    elif scenario == "unknown" or (scenario == "unknown_then_rejected" and len(state["calls"]) == 1):
        response = {"error": "unexpected"}
elif endpoint == "get_challenge":
    assert query == {"username": state["username"], "ip": ""}
    response = {"error": "ok", "challenge": "0123456789abcdef" * 4,
                "client_ip": "999.1.2.3" if scenario == "invalid_ip" else "10.1.2.3"}
elif endpoint == "srun_portal":
    expected = ref.login_parameters(state["username"], state["password"], "0123456789abcdef" * 4, "10.1.2.3", "67")
    assert query == expected, "login parameters differ from reference"
    if scenario in ("rejected", "unknown_then_rejected"):
        response = {"error": "fail", "ecode": "E2553"}
    else:
        response = {"error": "ok", "res": "ok"}
        state["logged_in"] = True
else:
    raise AssertionError(endpoint)
state_path.write_text(json.dumps(state), encoding="utf-8")
if scenario == "certificate":
    sys.exit(60)
if scenario == "redirect":
    print("302", end="")
    sys.exit(0)
text = json.dumps(response, ensure_ascii=False)
if scenario == "html":
    text = "<html>Login required</html>"
elif scenario != "plain_json":
    text = "campus_callback(" + text + ");"
Path(args[args.index("--output") + 1]).write_text(text, encoding="utf-8")
print("200", end="")
