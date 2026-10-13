# OPS-ANSWERS

## 1. Zero-downtime EKS 1.33 -> 1.35 upgrade

The order that matters (and where zero downtime is decided):

**Pre-flight (while still on 1.33, this is the only low-risk window):**
audit everything that will die or drift during the upgrade: run
`kubectl deprecations`, grep all manifests/CRDs/addon configs for APIs that
1.34/1.35 removed, verify every addon/subchart has a version supported on
1.35 (vpc-cni, coredns, kube-proxy, EBS/EFS CSI), warm a spare node group
per AZ to catch spot/needle issues, and take the ArgoCD Application health
as your canary: it tells you if anything in the cluster made a silent drift.

**Ordering:** addons first (they bridge API versions), then the control
plane one minor at a time (1.33 -> 1.34 -> 1.35, no skipping minors because
kubelet skew constraints apply), then node groups in waves of at most one
node per AZ for the same app (respecting the PDB math), then post-run the
deprecation audit again. After every hop validate: every service resolved
endpoints, each Ingress returned 200, node groups drains were clean (evicted
pods restarted). Zero downtime here is a verification loop, not a hope.

The two risks that actually decide success:

**Beta API deprecations.** This is the biggest single risk of a 1.33->1.35
jump because old beta groups are removed silently: controllers stop
admitting them, ArgoCD self-heal tears down pods of a manifest that
references an old API, and stateful things lose their admission via webhook.
So I audit with `kubectl deprecations` against all namespaces *before*
starting, do not stop at "our own code": every CRD/3rd-party tool (Karpenter,
cert-manager, velero) gets pinned to a version that supports 1.35, and the
manifests are migrated on a branch and pre-staged so ArgoCD auto-heal can't
slip in a broken apply mid-upgrade. If the pre-cutover audit isn't clean,
I'd rather postpone the upgrade than discover a manifest break in the
window where there is no rollback.

**PDBs.** Node group rolling upgrades respect PodDisruptionBudgets during
drains, and the failure mode is quiet: with a PDB missing, eviction kills
whatever the scheduler's kindness allows (and with `maxUnavailable: 1` on a
stateful app or web tier, the drain stalls forever and the upgrade window
hangs). Practical sweep I'd run: every Deploy/StatefulSet in the blast
radius has an explicit PDB whose number is justified from the replica count
and the probe timings, the wave's `maxUnavailable` stays inside what the
PDB lets the app survive, and spot group drains retry until the PDB allows
them. If a drain stalls, the cause is the PDB, the readiness probes, or
missing spare capacity. Removing the PDB to force progress just moves the
outage to a later hour.

## 2. 3 a.m. `KubeNodeUnreachable` storms from spot reclaims

Goal: real node loss pages, spot churn does not.

- Correlate before alerting: a `KubeNodeUnreachable` alone never pages. A
  page fires only if node NotReady sustained > 5-10m AND additional signal
  agrees (probe events / node lease objects). Expected spot churn; the EC2
  spot 2-minute warning and the shutdown drain both precede the unreachable
  state, so the alert eval window covers both.
- Route EC2 lifecycle events through EventBridge/SNS: `instanceInterruption`
  is info/metric only, never a page. Real hardware/hygiene evictions (which
  also hit on-demand) come from separate events and do page.
- Aggregate: one incident per pool when >N% of nodes reconcile churn at
  once (batch reclaims look like storms in a few minutes), rather than one
  page per pod.
- Distinct rule set for on-demand: interruption is not expected there, so
  a single-node unreachable still pages quickly.

## 3. Mobile LCP 5s behind Cloudflare: HTML cache diagnosis

1. Check `cf-cache-status` on the HTML response for a mobile UA
   (`curl -sI https://site/ -H 'user-agent: <mobile UA>'`). `DYNAMIC` or
   `MISS` means the edge is not serving HTML from cache at all.
2. Read the response and check whether the origin sends
   `Cache-Control: no-store/private` or lots of `Set-Cookie`; Cloudflare
   honors that and refuses to cache by default.
3. Audit cache rules/page rules that affect `/`: earlier rules may bypass
   or ignore (e.g., a `bypass` for `/api/*` was broadened to match HTML, or
   a session-cookie rule excludes all pages that set cookies).
4. Measure origin timing vs. edge timing: add `server-timing` or APM sampling.
   If origin render is ~4 s (coupled to underscaled app resources or heavy
   queries), cache cannot fix this, since an uncached visit pays it.
5. Then apply the actual fix: cache-anonymous route in Cache Control
   (e.g., "cache HTML for anyone without a session cookie", with a short
   Edge TTL like 5-10 min), letting logged-in users go via a cookie
   match rule. If personalization demands fresh HTML, use HTML client-side
   hydration or fetch the template with changed pieces client-side.
6. Finish by rechecking LCP; the next biggest ticket is usually a hero
   image, then move on to image CDN optimization (AVIF/WebP, resized).

## 4. Service secrets on EKS: two approaches, one pick

**A. External Secrets Operator reading AWS Secrets Manager.** Secrets live in
Secrets Manager; ESO syncs them into K8s Secrets, apps keep consuming them
as env vars or volume mounts, and sync is declarative (an ArgoCD-tracked
CRD). Downsides: secrets land in etcd (needs etcd encryption-at-rest), and
rotation behavior depends on external refresh intervals.

**B. Secrets Store CSI driver** (via IRSA) mounting AWS Secrets Manager as
files in the pod. Secrets never touch etcd, tight replication and auth model,
nice for file-based needing consumers (certs). Downsides: mount is largely
immutable per pod (rotation needs a restart or an extra reloader), and
volume mounts are awkward for many containers where an env var fits better.

For a startup running multiple prod EKS clusters I pick **A (ESO + Secrets
Manager)**: declarative sync is GitOps friendly, cross-cluster is nearly
free (install ESO, point the resource at the same per-env secret); zero app
changes workloads are comfortable with env-var injection and the audit story
lives in one place. Pair it with etcd/KMS encryption-at-rest and per-cluster
KMS keys, and use CSI only where the mount semantics genuinely pay (cert
reloading, sidecar-styles over file config).

## 5. Running out of IPs in the subnet

With the default VPC CNI in secondary-IP mode, pods and nodes attach IPs from
the ENI pool, so a busy /24 burns out faster than you expect: one m5.xlarge
with 30 pods eats an ENI plus spare warm IPs, and nodegroups in one AZ
multiply that fast.

What I would do, in order:

1. **Plan capacity per AZ**, not per cluster: peak node count times
   maxNetworkInterfaces, plus ELB/NAT ENIs, should fit in the /24 with a
   buffer. Put this number in the runbook next to the quota dashboard.
2. **Add a secondary CIDR to the cluster VPC** and create new subnets in the
   free range, tagged for cluster discovery so the scheduler picks them up.
   New nodes (and their ENIs) land there; old ones keep working. Least
   invasive fix, works with any IP mode.
3. **Turn on prefix delegation** in the VPC CNI
   (`ENABLE_PREFIX_DELEGATION=true`, `WARM_PREFIX_TARGET=1`): each ENI gets
   a /28 instead of single IPs, so pod density jumps without more ENIs.
4. **Dual-stack / IPv6** for long-term headroom, especially on internal
   service meshes where pods don't need public IPv4 egress each.
5. Two things that bite people: attaching new subnets but leaving the
   cluster's node termination settings on the old AZ; and forgetting that
   NAT/ELB ENIs also consume the pool (they do, and they don't scale down
   on their own).

