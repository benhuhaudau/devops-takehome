# Troubleshooting: Part 3 narrative

Environment: k3d cluster `takehome` (k3s v1.35.5), nodes labeled/tainted by the
provided `troubleshoot/prepare.sh`: 2× spot, 1× on-demand, 1× GPU
(`acme.io/node-type=gpu`, taint `nvidia.com/gpu=true:NoSchedule`).

Started from the untouched `broken-app.yaml`. All commands below were run
inside the toolbox container.

---

## Issue 1: `web` pods: Insufficient memory

**Symptom**

```
$ kubectl get pods -n troubleshoot
No resources found in troubleshoot namespace.
$ kubectl get events -n troubleshoot --sort-by=.metadata.creationTimestamp ...
FailedScheduling  pod/web-7dfd85c595-cbjh5  0/5 nodes are available: 1 node(s) had
untolerated taint(s), 4 Insufficient memory.
```

**Diagnosis**

```
kubectl get deploy web -n troubleshoot -o yaml | grep -A3 resources:
```

Request/limit **16Gi**: more than any node in the cluster has in total.

**Fix**: 64Mi requests / 128Mi limits (nginx + one html file does not need more):

```yaml
resources:
  requests: { cpu: 100m, memory: 64Mi }
  limits:   { cpu: 500m, memory: 128Mi }
```

## Issue 2: `web` pods: nonexistent image tag

**Symptom** after fixing memory, pods went `ErrImagePull`.

**Diagnosis**

```
kubectl describe pod web-…  -n troubleshoot | grep -A2 Failed
```

`nginx:1.25.99` does not exist upstream (1.25.x had no 1.25.99).

**Fix**: `nginx:1.25.5` (existing tag; avoids moving `nginx:latest`).

## Issue 3: probes on the wrong port

**Symptom** pods entered `CrashLoopBackOff`… actually `RESTART` storms:
ready pod then killed by probe checks.

**Diagnosis**

```
kubectl describe pod web-… -n troubleshoot | grep -B2 -A6 Liveness
kubectl logs web-… -n troubleshoot
```

Probes hit `GET /:8080`, nginx listens on **80** (`containerPort: 80`,
target of the Service too). Container never had an app on 8080.

**Fix**: set both probes to `port: 80`.

## Issue 3b (same probe family): `web-svc` had `targetPort: 8080`

**Diagnosis** `kubectl get svc web-svc -n troubleshoot -o jsonpath={.spec.ports[0].targetPort}`
→ 8080 while nginx listens on 80. Fix: `targetPort: 80`.

## Issue 4: ConfigMap mount: nonexistent `web-conf`

**Symptom** `CreateContainerConfigError` / missing volume.

**Diagnosis**

```
kubectl get cm -n troubleshoot       # shows only `web-config`
kubectl get deploy web -n troubleshoot -o jsonpath='{.spec.template.spec.volumes[*].configMap.name}'
# → "web-conf"
```

**Fix**: volume source `configMap.name: web-config`.

## Issue 5: Service selector mismatch

**Symptom** endpoints empty even with the web pods Running.

**Diagnosis**

```
kubectl get endpoints web-svc -n troubleshoot
kubectl get svc web-svc -n troubleshoot -o jsonpath='{.spec.selector}'   # {"app":"webapp"}
kubectl get pods -n troubleshoot -l app=web                               # exists
```

The selector matched nothing (`app: webapp` vs the Deployment's `app: web`).

**Fix**: selector `app: web`.

## Issue 6 + 7: `ai-inference` scheduling to GPU node

**Symptom**

```
FailedScheduling  pod/ai-inference-6fdb9f84d7-g296z  0/5 nodes are available:
1 node(s) had untolerated taint(s), 4 node(s) didn't match Pod's node affinity/selector.
```

Two independent causes:

1. GPU-toleration missing: the GPU node has `nvidia.com/gpu=true:NoSchedule`, the pod has no `tolerations`.
2. `nodeSelector: node-type: gpu` uses the wrong key: `prepare.sh` labels nodes with `acme.io/node-type=gpu`.

**Diagnosis**

```
kubectl get nodes --show-labels | grep gpu
kubectl auth can-i  # n/a
kubectl describe node <gpu-node> | grep -A3 Taints
```

**Fix** (workloads fixed, nodes untouched):

```yaml
nodeSelector:
  acme.io/node-type: gpu     # correct label key
tolerations:
  - key: nvidia.com/gpu
    operator: Equal
    value: "true"
    effect: NoSchedule
```

Result: pod Running on the GPU node (`kubectl get pods -o wide` shows nodeName).

---

## Issue 8: NetworkPolicy: default-deny blocks the smoke test (by design)

**Symptom** smoke-job stuck; `kubectl logs job/smoke-test` shows a timeout.

The `default-deny` policy denies **all** Ingress and Egress in the namespace.
Deleting it is explicitly not allowed: least-privilege allow rules instead:

```yaml
# smoke-job pods → web pods, TCP/80
allow-smoke-to-web  (ingress, podSelector app=web, from app=smoke-client)
# service DNS + web traffic for smoke-job pods:
allow-smoke-egress  (egress, to kube-system DNS udp/tcp53 + app=web tcp/80)
# web pods need DNS egress (nginx resolves), ai pods too:
allow-web-dns / allow-inference-dns  (egress → kube-system tcp/udp 53)
```

**Verification**: `./troubleshoot/verify.sh`:

```
[1/7] default-deny NetworkPolicy must still exist … ok
[2/7] Node labels and taints must be untouched … ok
[3/7] Deployment 'web' fully rolled out … ok
[4/7] Deployment 'ai-inference' fully rolled out … ok
[5/7] ai-inference pod must be running ON the GPU node … ok
[6/7] Service must have ready endpoints … ok
[7/7] In-cluster smoke test through the Service … ok
PASS
```

## Root-cause patterns worth naming

- Do not trust any single manifest value: tags, ports, and volume names drift
  when YAML is copied from different sources.
- Every failure had a distinct symptom: Pending (resources/affinity),
  ImagePullBackOff (tag), CrashLoop (broken probe), Empty endpoints (selector),
  CreateContainerConfigError (volume).
- Taints/labels are environmental truth: verify in the actual cluster state,
  never assume the manifest keys.
