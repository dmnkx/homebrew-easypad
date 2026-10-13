#!/bin/sh
# Waits for the latest Actions run of this repo and prints its result and error annotations.
REPO=dmnkx/notepad-mac
API=https://api.github.com/repos/$REPO
sha=$(git rev-parse HEAD)
while :; do
    run=$(curl -s "$API/actions/runs?head_sha=$sha&per_page=1")
    state=$(echo "$run" | python3 -I -c "import sys,json; w=json.load(sys.stdin).get('workflow_runs') or [{}]; print(w[0].get('status'), w[0].get('conclusion'), w[0].get('id'))")
    case "$state" in completed*) break ;; esac
    sleep 20
done
echo "$state"
id=${state##* }
job=$(curl -s "$API/actions/runs/$id/jobs" | python3 -I -c "import sys,json; j=json.load(sys.stdin)['jobs'][0]; print(j['id']); [sys.stderr.write('  %s: %s\n' % (s['name'], s['conclusion'])) for s in j['steps']]")
curl -s "$API/check-runs/$job/annotations" | python3 -I -c "
import sys,json
for a in json.load(sys.stdin):
    if a.get('title') == 'build log': print(a['message'])"
