# Adoption record — splunk-connect-for-kubernetes (chart fork)

Upstream `splunk/splunk-connect-for-kubernetes` reached End of Support on 2024-01-01 and was
archived on 2025-06-24; separately, all four published `splunk/*` images were deleted from Docker
Hub, which breaks every existing install on its next image pull. This fork was adopted to keep the
connector deployable, and the rebuild was used to fix the accumulated bugs properly.

## What changed in this fork

- **Image references**: the chart pins rebuilt, hardened images under `docker.io/ephico2real/*`
  (mirrored with identical digests at `quay.io/ephico2real/*`), replacing the deleted `splunk/*`
  references. Current defaults:

  | subchart | image | tag |
  |---|---|---|
  | splunk-kubernetes-logging | `ephico2real/fluentd-hec` | `1.3.3-h2-g1f6f8fb` |
  | splunk-kubernetes-objects | `ephico2real/kube-objects` | `1.2.3-h2-g7cbf93d` |
  | splunk-kubernetes-metrics | `ephico2real/k8s-metrics` | `1.2.3-h1-g97015ed` |
  | splunk-kubernetes-metrics (imageAgg) | `ephico2real/k8s-metrics-aggr` | `1.2.3-h1-g3231765` |

  `h1` is the fully shell-less hardened pass; `h2` (logging/objects) additionally carries jq and a
  minimal shell because their rendered config uses `jq_transformer`, which executes the external
  jq binary through a shell. Findings per image dropped from ~880 to 5 in the migration.
- **jq-free chart variant**: branch `feat/jq-free-chart` renders the same enrichment with
  `record_transformer` (no jq, no shell needed — verified with live indexed data) and pairs with
  the images' `h1`/`feat/jq-free` builds.
- **values documentation**: the `customFilters` examples in the values files are annotated for the
  hardened images; the pre-adoption originals are preserved verbatim as `old-jq-values.yaml`
  beside each values file.
- **Functional-test environment brought back to life** (`ci_scripts/`, `test/` consumers):
  Kubernetes pinned to v1.31.2 (measured: newer kubelets drop the per-container cAdvisor metrics
  the tests assert), minikube pinned on the docker runtime, and the CI Splunk pod fixed for
  Splunk 10 (General Terms acceptance, non-root, a sudoers drop-in for a measured PAM failure on
  GitHub runners).

## Branch map

| branch | contents |
|---|---|
| `develop` / `main` | jq-based product config, jq-capable image pins (the default) |
| `feat/jq-free-chart` | record_transformer config + shell-less image pins |

## Related repositories

Image sources, adopted together with this chart:
[fluentd-hec](https://github.com/ephico2real2/fluentd-hec),
[kube-objects](https://github.com/ephico2real2/kube-objects),
[k8s-metrics](https://github.com/ephico2real2/k8s-metrics),
[k8s-metrics-aggr](https://github.com/ephico2real2/k8s-metrics-aggr) — each with its own
`docs/ADOPTION.md`.
