#!/bin/bash
# Snapshot everything a build run exposes, on a loop, into a dated directory.
#
# Several things a run produces cannot be recovered once it ends:
#   - every artifact is deleted by the purge-artifact job as soon as image succeeds
#     (which is why only a cancelled run ever leaves its aarch64 tree behind)
#   - the runner filesystem goes with the runner
# Job logs themselves survive the usual retention, but pulling them as they land
# costs nothing and means a later analysis never depends on the API still having
# them, or on remembering which run id it was.
#
# Usage:  nohup bash .github/scripts/capture-run.sh <run_id> [repo] &
# Output: ./capture-<run_id>/  (run.json, jobs.json, artifacts.json, one log per job)
#
# jobs.json is the valuable one: it carries each job's started_at/completed_at,
# which is the only trustworthy source of per-stage timing. Do not use the
# duration reported by `gh run list`, and always check run_attempt -- a re-run
# returns jobs from BOTH attempts mixed together, which makes parallel jobs look
# strictly serial.
set -u

RID=${1:?usage: capture-run.sh <run_id> [repo]}
R=${2:-w2xg2022/rocknix}
OUT="capture-${RID}"
mkdir -p "${OUT}"
export GH_TOKEN=${GH_TOKEN:-$(gh auth token 2>/dev/null)}

say(){ echo "[$(date +%H:%M:%S)] $*"; }
slug(){ echo "$1" | tr -c 'A-Za-z0-9._-' '_'; }

pull_logs() {
  # A running job's log is partial but grows, so keep re-pulling until the job
  # reports a conclusion; then mark it and leave it alone.
  while read -r id name; do
    f="${OUT}/${id}-$(slug "${name}").log"
    [ -f "${f}.done" ] && continue
    if gh api "repos/${R}/actions/jobs/${id}/logs" > "${f}.tmp" 2>/dev/null; then
      mv "${f}.tmp" "${f}"
    else
      rm -f "${f}.tmp"
    fi
  done < <(jq -r '.jobs[] | "\(.id) \(.name)"' "${OUT}/jobs.json" 2>/dev/null)
}

while :; do
  gh api "repos/${R}/actions/runs/${RID}" > "${OUT}/run.json" 2>/dev/null || true
  gh api "repos/${R}/actions/runs/${RID}/jobs?per_page=100" > "${OUT}/jobs.json" 2>/dev/null || true
  gh api "repos/${R}/actions/runs/${RID}/artifacts" > "${OUT}/artifacts.json" 2>/dev/null || true

  pull_logs

  while read -r id; do
    for f in "${OUT}/${id}-"*.log; do [ -e "$f" ] && touch "${f}.done"; done
  done < <(jq -r '.jobs[] | select(.conclusion != null) | .id' "${OUT}/jobs.json" 2>/dev/null)

  ST=$(jq -r '.status // ""' "${OUT}/run.json" 2>/dev/null || echo "")
  say "status=${ST:-?} jobs=$(jq -r '.jobs|length' "${OUT}/jobs.json" 2>/dev/null) logs=$(ls "${OUT}"/*.log 2>/dev/null | wc -l)"
  [ "${ST}" = "completed" ] && break
  sleep 120
done

# Final sweep: the last jobs' logs are only complete now.
gh api "repos/${R}/actions/runs/${RID}/jobs?per_page=100" > "${OUT}/jobs.json" 2>/dev/null || true
rm -f "${OUT}"/*.done
pull_logs
say "done -> ${OUT}"
