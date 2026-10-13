# AI-USAGE

I used an agentic CLI assistant (opencode: Claude/GLM) as my implementation
sidekick. The ideas, design choices and trade-offs were mine; the AI wrote most
of the code, YAML and doc drafts, and I verified everything by running it
before committing. Anything that didn't survive a test or a drill got fixed:
most `fix:`/`ci:` commits in `git log` are exactly that loop.

Prompts that moved work forward:
1. "3 replicas, prefer spot, always keep ≥1 on on-demand, spread soft enough
   to reschedule when a node drains: think what a hard constraint does during
   the drill." → the affinity + dual topology-spread shape in the chart.
2. "CI failed in the trivy job: did the gate fire for real CVEs or is my
   config wrong?" → real finding: 25 stdlib CVEs → fixed the toolchain, kept
   the gate.
3. "The grader has only docker; route everything through a toolbox container
   so no local kubectl is ever trusted." → the whole harness design.

Where AI was wrong (caught by running things, not reading harder):
- Cloudflare TF draft used 4.x names (`cloudflare_record`, `rules {}` blocks);
  provider 5.x wants `cloudflare_dns_record` + `rules = [...]`. Caught by
  `scripts/50-validate-tf.sh`, fixed and re-checked against current docs.
- First ArgoCD/kubeconfig rewrite also hardcoded the wrong port; only a full
  `k3d cluster delete` + `docker compose up` made that visible.
- The k8s "stable" kubectl URL is `stable.txt` (a pointer), not a binary:
  misconfirmed by the AI; caught when the build failed.
- First placement draft let all 3 pods drift onto spot nodes; caught with
  `kubectl get pods -o wide`, fixed with a hard hostname spread +
  `nodeTaintsPolicy: Honor`. Now drill-proven.
