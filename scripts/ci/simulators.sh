#!/usr/bin/env bash
# Creates (idempotently) the simulators used for tests/screenshots and prints their UDIDs.
#   iPad mini 6 (744×1133 pt, the primary design baseline)
#   iPad Pro 13-inch (largest iPad)
set -euo pipefail
RUNTIME=$(xcrun simctl list runtimes -j | /usr/bin/python3 -c '
import json,sys
rs=[r for r in json.load(sys.stdin)["runtimes"] if r["platform"]=="iOS" and r["isAvailable"]]
rs.sort(key=lambda r:[int(x) for x in r["version"].split(".")])
print(rs[-1]["identifier"])')
create() {
  local name="$1" type="$2"
  local udid
  udid=$(xcrun simctl list devices -j | /usr/bin/python3 -c "
import json,sys
d=json.load(sys.stdin)['devices'].get('$RUNTIME',[])
m=[x['udid'] for x in d if x['name']=='$name' and x['isAvailable']]
print(m[0] if m else '')")
  if [[ -z "$udid" ]]; then
    udid=$(xcrun simctl create "$name" "$type" "$RUNTIME")
  fi
  echo "$udid"
}
pick_type() {
  # First available device type matching a pattern.
  xcrun simctl list devicetypes -j | /usr/bin/python3 -c "
import json,sys,re
ts=[t['identifier'] for t in json.load(sys.stdin)['devicetypes'] if re.search(r'$1', t['identifier'])]
print(ts[-1] if ts else '')"
}
MINI_TYPE=$(pick_type 'iPad-mini-6th-generation')
[[ -z "$MINI_TYPE" ]] && MINI_TYPE=$(pick_type 'iPad-mini')
PRO_TYPE=$(pick_type 'iPad-Pro-13-inch')
[[ -z "$PRO_TYPE" ]] && PRO_TYPE=$(pick_type 'iPad-Pro.*12-9')
echo "runtime=$RUNTIME"
echo "MINI_UDID=$(create 'VN iPad mini 6' "$MINI_TYPE")"
echo "PRO_UDID=$(create 'VN iPad Pro 13' "$PRO_TYPE")"
