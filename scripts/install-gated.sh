#!/bin/zsh
# Builds, tests and installs this checkout's OpenShelf into /Applications, safely:
# - refuses with uncommitted changes, or if the tree changes during the run;
# - the full suite must pass (the focus-dependent shelf test excepted) within 10 minutes;
#   a hung suite is killed with its swiftpm-testing-helper and nothing is installed;
# - waits (up to 15 min) until the running OpenShelf reports it is idle, never relaunching
#   it under the user;
# - the new build must satisfy the code requirement macOS stored for OpenShelf's
#   Accessibility grant (else the installed app's own requirement), so the grant survives.
# Logs go to $INSTALL_LOGS (default: build/install.noindex). Prints the commit, the pid and
# both binaries' sha256.
set -u
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel) || exit 1
cd "$ROOT" || exit 1
LOGS=${INSTALL_LOGS:-$ROOT/build/install.noindex}
mkdir -p "$LOGS"
APP=build/OpenShelf.noindex/OpenShelf.app
[ -z "$(git status --porcelain)" ] || { echo "REFUSED: uncommitted changes"; exit 1; }
start_head=$(git rev-parse HEAD)

perl -e 'alarm shift; exec @ARGV' 600 swift test > "$LOGS/suite.log" 2>&1
rc=$?
[ $rc -eq 142 ] && { pkill -f "swiftpm-testing-helper.*$ROOT/"; pkill -f "$ROOT/.build/.*OpenShelfTests"; echo "REFUSED: the suite hung (killed after 10 minutes)"; exit 1; }
other=$(grep "recorded an issue" "$LOGS/suite.log" | grep -v "managerReportsFocusedAndRecentSelections" | head -5)
ran=$(grep -E "Test run with [0-9]+ tests" "$LOGS/suite.log" | tail -1)
[ -n "$ran" ] || { echo "REFUSED: the suite didn't finish"; tail -5 "$LOGS/suite.log"; exit 1; }
[ -z "$other" ] || { echo "REFUSED: failing tests:"; echo "$other"; exit 1; }
echo "suite: $ran (only the focus-dependent shelf test may fail)"

make app > "$LOGS/build.log" 2>&1 || { echo "REFUSED: make app failed"; exit 1; }
[ -z "$(git status --porcelain)" ] && [ "$(git rev-parse HEAD)" = "$start_head" ] || { echo "REFUSED: the tree changed during the build"; exit 1; }

# The requirement the new build must meet, from macOS's Accessibility grant if readable.
req=$(sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "select hex(csreq) from access where service='kTCCServiceAccessibility' and client='com.djnesmith.OpenShelf'" 2>/dev/null | head -1 | xxd -r -p | csreq -r- -t 2>/dev/null)
[ -n "$req" ] || req=$(codesign -d -r- /Applications/OpenShelf.app 2>/dev/null | sed -n 's/^designated => //p')
[ -n "$req" ] || { echo "REFUSED: no code requirement to check the build against"; exit 1; }
codesign --verify -R="$req" "$APP" || { echo "REFUSED: the build doesn't meet the Accessibility grant's requirement"; exit 1; }

# Idle gate: the running app writes its state; exit 0 idle, 1 busy, 2 can't tell.
idle() {
  python3 -I - <<'PY'
import json, os, subprocess, sys, datetime as dt
path = os.path.expanduser("~/Library/Application Support/OpenShelf/state.json")
pid = subprocess.run(["pgrep", "-x", "OpenShelf"], capture_output=True, text=True).stdout.split()
if not pid: print("not running: idle"); sys.exit(0)
try: s = json.load(open(path))
except Exception as e: print(f"no state file ({e})"); sys.exit(2)
now = dt.datetime.now(dt.timezone.utc)
parse = lambda t: dt.datetime.fromisoformat(t.replace("Z", "+00:00"))
if str(s.get("pid")) not in pid: print(f"state is from pid {s.get('pid')}, running {pid}"); sys.exit(2)
if (now - parse(s["updatedAt"])).total_seconds() > 15: print("state file is stale"); sys.exit(1)
if s["busy"]: print("busy: " + ", ".join(s["reasons"])); sys.exit(1)
quiet = (now - parse(s["lastInputAt"])).total_seconds()
if quiet < 120: print(f"input {int(quiet)} s ago"); sys.exit(1)
print(f"idle, no input for {int(quiet)} s"); sys.exit(0)
PY
}
waited=0
while true; do
  why=$(idle); code=$?
  [ $code -eq 0 ] && { echo "idle gate: $why"; break; }
  [ $code -eq 2 ] && { echo "NOT INSTALLED: $why"; exit 3; }
  [ $waited -ge 900 ] && { echo "NOT INSTALLED: still in use after 15 min ($why)"; exit 3; }
  sleep 30; waited=$((waited + 30))
done

osascript -e 'tell application id "com.djnesmith.OpenShelf" to quit'
for i in {1..10}; do pgrep -x OpenShelf >/dev/null || break; sleep 1; done
rsync -a --delete "$APP/" /Applications/OpenShelf.app/ || exit 1
codesign --verify --strict /Applications/OpenShelf.app && codesign --verify -R="$req" /Applications/OpenShelf.app && echo "codesign ok" || exit 1
open /Applications/OpenShelf.app; sleep 3
echo "commit $(git log --oneline -1)"; echo "pid $(pgrep -x OpenShelf)"
shasum -a 256 /Applications/OpenShelf.app/Contents/MacOS/OpenShelf "$APP/Contents/MacOS/OpenShelf"
