# MIGRATION-NOTES: GitLab CI → GitHub Actions

Legacy source: [`ci/legacy.gitlab-ci.yml`](ci/legacy.gitlab-ci.yml).
Migration target: [`.github/workflows/ci.yml`](.github/workflows/ci.yml).
We migrate the *intent* of each job, not the file. Findings by finding:

## What we dropped on purpose

### 1. Credentials in pipeline variables: the "AKIAIOSFODNN7EXAMPLE" pattern
The legacy `variables:` block ships AWS keys + region in plain file text. Even
if they are (as commented) documentation examples, this pattern invites real
leaks and instant audit failure.

**Migrated to:** no cloud credentials anywhere in the pipeline. For a real
project: GitHub Actions uses **OIDC federation** (`permissions.id-token: write`,
an `aws-actions/configure-aws-credentials` step), so no static AWS key exists
at all. GitLab's equivalent is the JWT/OIDC token, not `variables:`. Real
secret values live in the tenant's secret manager, never in YAML.

### 2. A quality "gate" that can never fail
`sonar_check` has `allow_failure: true` and no quality gate. It is decoration:
red badge never appears, findings never block a merge.

**Migrated to:** **Semgrep**, run in-repo with `--config p/golang --config
p/security-audit --error`: findings hard-fail the run. MIT/self-hosted SonarQube
CE (as planned in the legacy) forces a second deploy surface and connection
config in the pipeline; Semgrep's rule packs + exit codes are dependency-light
and can't be silently waived. (Chosen over SonarCloud also because the scan
runs in the same container and results are visible right in the CI logs.)

### 3. "Tests flaky, continuing"
`npm test || echo "tests flaky, continuing"` means the pipeline always passes:
a red flag we are explicitly migrating away from.

**Migrated to:** `go test -v ./...`: real assertions on the HTTP contract
(probes, simulated CPU latency, Prometheus counters). No escape hatch.

## What we upgraded rather than translated

### 4. `only: master` → `on: push + pull_request`
Branch-scoped pipelines on master only meant PRs ship with **no checks**.
GitHub Actions builds and SAST-scans every PR; push of images stays
master-only. `concurrency` cancels superseded runs to save runner minutes.

### 5. `docker:20.10` + `dind` on a huge runner → Buildx + cache
Legacy pulled `docker:20.10-dind` into a privileged sub-service the standard
runner now has the build engine. Migrated: `docker buildx` with a GHA cache
back end (`type=gha`), so subsequent builds reuse layer caches; no dind
service containers to schedule or un-schedule.

### 6. Floating `:latest` alone → immutable SHA + latest
Legacy pushed exactly one tag (`$IMAGE_NAME:latest`) after builds: no way to
roll back or pin. Migrated: `ghcr.io/<owner>/quote-api:<full-sha>` plus a
master-only `:latest`, with PR arms built but pushed to `pr-<num>`; the
volume-side image that ArgoCD references is always a SHA (see
`config/argocd/application.yaml`).

### 7. Imperative `kubectl set image` deploy → GitOps handoff
The legacy deploy step `echo "$KUBECONFIG_CONTENT" > /tmp/kubeconfig` +
`kubectl set image -n production` hands cluster-admin credentials to runners,
silently bypasses GitOps, and leaves no audit trail for who changed prod.

**Migrated to:** ArgoCD drives the deployment: this repo's chart is deployed
by `scripts/20-deploy.sh`, then continuously synced out of band from git. CI
holds no kubeconfig at all; prod changes have a first-class audit trail
(commits), and rollback = revert commit. (Multi-env would be ArgoCD
ApplicationSets with per-env value overlays, not branch counting.)

### 8. Old registry name → GHCR via `github.repository_owner`
`registry.gitlab.com/acme/quote-api` → `ghcr.io/benhuhaudau/quote-api` bound
using `github.repository_owner`: the workflow self-locates without plumbing
config.

### 9. Pinpointed old tool versions → version-managed toolchains
`node:16`, `kubectl:1.24`, `sonar-scanner 4.6` pin known CVEs and had drifted.
Migrated: `actions/setup-go` with cache, no versioned `kubectl` stage needed at
all (step 7), `semgrep/semgrep` image managed by the upstream team, plus a
Trivy and cosign option in the bonus below.

## Bonus delivered

- **Trivy image gate**: `image-scan` job fails the run on HIGH/CRITICAL
  (unfixed-vulns only) after each successful master build.
- **Not done: cosign signing**: the natural pattern here is keyless OIDC
  signing (`cosign sign` + `permissions: id-token`) plus a verify policy gate;
  deliberately left out to keep the pipeline surface minimal: happy to walk
  through it in the live session.

## Migrating the GitLab variables/secrets for a real project

1. Inventory each legacy variable; classify CI/CD-only values vs. prod secrets.
2. CI/CD-only values (registry URLs, image names, feature flags): map
   directly to GitHub Actions `env:` or `vars:`; nothing sensitive lives in code.
3. Production secrets (kubeconfigs, deploy keys, cloud creds): **do not**
   round-trip through plain text. Prefer (a) GitHub OIDC → cloud IAM (AWS EKS
   token for K8s via `aws eks create access-entry` at runtime),
   or (b) an ESO/Vault pull secret. Rotate anything that was in GitLab.
4. Environment protection: `environment: production` with required reviewers
   replaces `when: manual`.
5. Audit: `gh secret list` (placeholder as it is a GitLab → variable file) and
   revoke every value found in the legacy repo's history (including the
   AKIA... example is fine only because it's documented: anything real gets
   assumed compromised).

