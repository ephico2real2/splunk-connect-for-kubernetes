#!/usr/bin/env bash
#
# Set the chart's four image references from what is actually published, instead of by hand.
#
#   ci_scripts/set-image-versions.sh              pin every image to its published :<version>-h<pass>
#   ci_scripts/set-image-versions.sh --digest     pin by DIGEST instead of tag (immutable)
#   ci_scripts/set-image-versions.sh --pass h2    use a different hardening pass
#   ci_scripts/set-image-versions.sh --check      verify only, change nothing (for CI)
#
# WHY A SCRIPT. There are FOUR image references across FOUR values.yaml files — the umbrella chart and
# three bundled subcharts — and the subchart copies are the ones that actually take effect. Editing them
# by hand means four chances to miss one, and a missed one does not fail at install: it fails later,
# when that pod is rescheduled onto a node without the old layer cached. The metrics subchart is the
# usual casualty because it declares TWO images, `image` and `imageAgg`.
#
# WHY IT VERIFIES BEFORE WRITING. Pointing the chart at a tag nobody published is the same outage as
# pointing it at a deleted one — which is exactly how this fork came to exist. Every reference is checked
# against the registry first, and nothing is written unless all four resolve.

set -euo pipefail
cd "$(dirname "$0")/.."

NAMESPACE="ephico2real"
PASS="h1"
MODE="tag"
CHECK_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --digest) MODE="digest"; shift ;;
    --pass)   PASS="$2"; shift 2 ;;
    --check)  CHECK_ONLY=1; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

# image name -> the upstream version it forked from. These are the four the chart declares; keep in step
# with each source repo's VERSION file.
IMAGES="fluentd-hec:1.3.3 kube-objects:1.2.3 k8s-metrics:1.2.3 k8s-metrics-aggr:1.2.3"

echo "==> namespace=${NAMESPACE} pass=${PASS} mode=${MODE}"
echo

# --- 1. resolve and verify every reference BEFORE touching a file -------------------------------
declare -a NAMES=() REFS=()
FAILED=0
for entry in ${IMAGES}; do
  img="${entry%%:*}"; ver="${entry##*:}"
  tag="${ver}-${PASS}"
  full="docker.io/${NAMESPACE}/${img}:${tag}"

  digest="$(skopeo inspect --no-tags --override-os linux --override-arch amd64 \
              "docker://${full}" 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["Digest"])' 2>/dev/null || true)"

  if [ -z "${digest}" ]; then
    printf '  %-46s NOT PUBLISHED\n' "${NAMESPACE}/${img}:${tag}"
    FAILED=1
    continue
  fi

  if [ "${MODE}" = "digest" ]; then
    # A digest cannot be re-pointed, so a rollback lands on the same bytes. Costs readability.
    REFS+=("${tag}@${digest}")
  else
    REFS+=("${tag}")
  fi
  NAMES+=("${img}")
  printf '  %-46s ok  %s\n' "${NAMESPACE}/${img}:${tag}" "${digest:0:20}"
done

if [ "${FAILED}" = 1 ]; then
  echo
  echo "ERROR: not every image is published. Pointing the chart at a tag that does not exist is the" >&2
  echo "       same outage as pointing it at a deleted one. Publish first, then re-run." >&2
  exit 1
fi

if [ "${CHECK_ONLY}" = 1 ]; then
  echo
  echo "==> --check: all four resolve; nothing written."
  exit 0
fi

# --- 2. rewrite every values.yaml under helm-chart/ ---------------------------------------------
echo
NAMESPACE="${NAMESPACE}" python3 - "${NAMES[@]}" "--" "${REFS[@]}" <<'PY'
import sys, os, re, pathlib

argv  = sys.argv[1:]
split = argv.index("--")
names, refs = argv[:split], argv[split+1:]
ns = os.environ["NAMESPACE"]

changed = 0
for p in pathlib.Path("helm-chart").rglob("values.yaml"):
    t = orig = p.read_text()
    for img, ref in zip(names, refs):
        # Anchor on the image NAME and rewrite the `tag:` that follows it, so k8s-metrics and
        # k8s-metrics-aggr cannot be confused for one another — a plain substitution on `1.2.3`
        # would hit whichever came first.
        t = re.sub(
            r'(name:\s*%s/%s\s*\n(?:[^\n]*\n)??\s*tag:\s*)\S+' % (re.escape(ns), re.escape(img)),
            lambda m, r=ref: m.group(1) + r,
            t)
    if t != orig:
        p.write_text(t); changed += 1
        print("  updated %s" % p)

print("  %d file(s) changed" % changed)
PY

echo
echo "==> resulting references:"
python3 - <<'PY'
import yaml
v = yaml.safe_load(open("helm-chart/splunk-connect-for-kubernetes/values.yaml"))
def walk(n, path=""):
    if isinstance(n, dict):
        for k in ("image", "imageAgg"):
            if k in n and isinstance(n[k], dict):
                print("  %-30s %s:%s" % (path, n[k].get("name"), n[k].get("tag")))
        for k, val in n.items():
            walk(val, f"{path}.{k}" if path else k)
walk(v)
PY

echo
echo "    Review with: git diff -- helm-chart/"
