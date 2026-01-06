This note groups the commands into a logical runbook flow (AWS identity → DNS checks → EKS access → cluster health/add-ons → Jenkins access & troubleshooting → cleanup). Commands are shown without your terminal prompt, and outputs are shown as *expected examples*.


---

# 1) AWS Account + CLI Sanity Checks (Configuration)

### 1.1 Confirm which AWS identity you are using (important for permissions)

```bash
aws sts get-caller-identity
```

**Expected output (example)**

```json
{
  "UserId": "…",
  "Account": "253484721204",
  "Arn": "arn:aws:iam::253484721204:user/Admin"
}
```

### 1.2 Set default region (avoids repeating `--region` everywhere)

```bash
aws configure set region ap-south-1
```

**Expected output**

* No output on success.

### 1.3 Quick S3 permission / account sanity check

```bash
aws s3api list-buckets
```

**Expected output (example)**

```json
{
  "Buckets": [],
  "Owner": { "ID": "…" }
}
```

**Interpretation**

* `Buckets: []` usually means either **no buckets exist** in that account/region scope (buckets are global but listed per account), or **permissions are limited** (less common if you still got an Owner block).

---

# 2) Route53 DNS Verification (Configuration + Debug)

### 2.1 Verify the hosted zone for root domain exists

```bash
aws route53 list-hosted-zones-by-name --dns-name rdhcloudlab.com --max-items 1
```

**Expected output (example)**

```json
{
  "HostedZones": [
    {
      "Id": "/hostedzone/Z001903711JO3EW5QTC55",
      "Name": "rdhcloudlab.com.",
      "Config": { "PrivateZone": false },
      "ResourceRecordSetCount": 3
    }
  ],
  "DNSName": "rdhcloudlab.com",
  "IsTruncated": true,
  "NextDNSName": "poc.rdhcloudlab.com."
}
```

### 2.2 Confirm subdomain delegation record exists in the root hosted zone

(Example: validating the `NS` record for `poc.rdhcloudlab.com.` inside `rdhcloudlab.com` zone)

```bash
aws route53 list-resource-record-sets \
  --hosted-zone-id "Z001903711JO3EW5QTC55" \
  --query "ResourceRecordSets[?Name=='poc.rdhcloudlab.com.']"
```

**Expected output (example)**

```json
[
  {
    "Name": "poc.rdhcloudlab.com.",
    "Type": "NS",
    "TTL": 300,
    "ResourceRecords": [
      { "Value": "ns-1492.awsdns-58.org" },
      { "Value": "ns-1782.awsdns-30.co.uk" },
      { "Value": "ns-200.awsdns-25.com" },
      { "Value": "ns-645.awsdns-16.net" }
    ]
  }
]
```

✅ **Debug value:** If your subdomain-based apps (Ingress/ExternalDNS) don’t resolve later, this is one of the first checks.

---

# 3) EKS Kubeconfig + Access (Configuration + Debug)

### 3.1 Update kubeconfig for the cluster

```bash
aws eks update-kubeconfig --name platform-dev-eks --region ap-south-1
```

**Expected output (example)**

* First time:

  * `Added new context arn:aws:eks:...:cluster/platform-dev-eks to ~/.kube/config`
* Later runs:

  * `Updated context arn:aws:eks:...:cluster/platform-dev-eks in ~/.kube/config`

### 3.2 Confirm current kubectl contexts and active cluster

```bash
kubectl config get-contexts
```

**Expected output (example)**

* A list of contexts; the current one has a `*` in the `CURRENT` column.

### 3.3 Validate cluster node access

```bash
kubectl get nodes
```

**Expected output (example)**

```text
NAME                                          STATUS   ROLES    AGE   VERSION
ip-10-20-12-111.ap-south-1.compute.internal   Ready    <none>   …     v1.28.x-eks-…
```

---

## 3.4 Fix/ensure EKS API access for an IAM principal (Configuration + Debug)

These are useful when `kubectl` fails with authorization errors (common with EKS access entries).

### Create access entry for IAM user

```bash
aws eks create-access-entry \
  --cluster-name platform-dev-eks \
  --principal-arn arn:aws:iam::253484721204:user/Admin \
  --type STANDARD \
  --region ap-south-1
```

**Expected output (example)**

* Returns an `accessEntry` JSON including `principalArn`, timestamps, and an `accessEntryArn`.

### Associate admin policy (cluster-scope)

```bash
aws eks associate-access-policy \
  --cluster-name platform-dev-eks \
  --principal-arn arn:aws:iam::253484721204:user/Admin \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster \
  --region ap-south-1
```

**Expected output (example)**

* Returns a JSON with `associatedAccessPolicy` showing the policy ARN and scope.

✅ **Debug value:** After these, run `aws eks update-kubeconfig ...` again, then re-try `kubectl get nodes`.

---

# 4) Cluster Add-on Health Checks (Debug / Verification)

### 4.1 EBS CSI driver (storage provisioning)

```bash
kubectl get pod -n kube-system -l "app.kubernetes.io/name=aws-ebs-csi-driver,app.kubernetes.io/instance=aws-ebs-csi-driver"
```

**Expected output (example)**

```text
NAME                                  READY   STATUS    RESTARTS   AGE
ebs-csi-controller-...                5/5     Running   0          …
ebs-csi-controller-...                5/5     Running   0          …
ebs-csi-node-...                      3/3     Running   0          …
```

### 4.2 AWS Load Balancer Controller + ExternalDNS

```bash
kubectl get pods -n kube-system -l 'app.kubernetes.io/name in (aws-load-balancer-controller,external-dns)'
```

**Expected output (example)**

```text
NAME                                            READY   STATUS    RESTARTS   AGE
aws-load-balancer-controller-...                1/1     Running   0          …
external-dns-...                                1/1     Running   0          …
```

✅ **Debug value:**

* If LoadBalancer/Ingress is not getting an ALB, check `aws-load-balancer-controller` pods first.
* If DNS records are not appearing/updating, check `external-dns` pods.

---

# 5) Jenkins Access (Helm-installed) (Configuration)

### 5.1 Fetch Jenkins admin password (from Kubernetes secret file)

```bash
kubectl exec --namespace ci -it svc/jenkins -c jenkins -- /bin/cat /run/secrets/additional/chart-admin-password && echo
```

**Expected output**

* Prints the admin password (single line).

### 5.2 Port-forward Jenkins service locally

```bash
kubectl --namespace ci port-forward svc/jenkins 8080:8080
```

**Expected output (example)**

```text
Forwarding from 127.0.0.1:8080 -> 8080
Forwarding from [::1]:8080 -> 8080
```

### 5.3 URL reference

```bash
echo http://127.0.0.1:8080
```

**Expected output**

```text
http://127.0.0.1:8080
```

---

# 6) Jenkins Troubleshooting Commands (Explicit Debug Section)

These are the “go-to” commands when Jenkins isn’t coming up cleanly (e.g., stuck in Init, CrashLoopBackOff, pending volumes, etc.).

### 6.1 See Jenkins pod placement, IP, and init status

```bash
kubectl get pods -n ci -o wide
```

**Expected output (example)**

* Shows `READY`, `STATUS` (e.g., `Init:1/2`, `Running`, `CrashLoopBackOff`) and node placement.

### 6.2 Check previous logs of a specific container (when it restarted)

```bash
kubectl logs jenkins-0 -n ci -c jenkins --previous
```

**Expected output (example)**

* If no previous terminated container exists:

```text
Error from server (BadRequest): previous terminated container "jenkins" in pod "jenkins-0" not found
```

### 6.3 Check previous logs for *all* containers in the pod

```bash
kubectl logs jenkins-0 -n ci --all-containers=true --previous
```

**Expected output (example)**

* Similar “previous terminated container not found” message if nothing restarted yet.

### 6.4 The single most important debug command (events + volume + init failures)

```bash
kubectl describe pod jenkins-0 -n ci
```

**Expected output (high-signal sections you look for)**

* `Init Containers:` status and failure reasons
* `Events:` section (e.g., BackOff, FailedMount, ImagePullBackOff)
* Volume attach/mount messages (PVC binding, attach success, mount errors)

### 6.5 Verify Jenkins PVC is bound (storage check)

```bash
kubectl get pvc -n ci
```

**Expected output (example)**

```text
NAME      STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
jenkins   Bound    pvc-...                                     20Gi       RWO            gp3            …
```

---

# 7) Cleanup / Reinstall Prep (Operational)

### Uninstall Jenkins release from namespace (safe cleanup pattern)

```bash
helm uninstall jenkins -n ci || true
```

**Expected output (example)**

* If installed:

  * `release "jenkins" uninstalled`
* If not installed:

  * It won’t fail the shell due to `|| true`.

✅ **Debug value:** This is useful when you want a clean reinstall after a broken/partial deployment.

## 1) Cluster access & kubeconfig (configuration)

### Update kubeconfig for the EKS cluster

```bash
aws eks update-kubeconfig --name platform-dev-eks --region ap-south-1
```

**Expected output**

* Kubeconfig updated (context added/updated for the cluster)

### Switch to the correct kubectl context

```bash
kubectl config use-context arn:aws:eks:ap-south-1:253484721204:cluster/platform-dev-eks
```

**Expected output**

* “Switched to context …platform-dev-eks”

✅ **Useful for debugging**

* If you’re “seeing nothing” or “wrong namespace/resources”, first confirm you are on the right context.

---

## 2) Jenkins admin access & basic health (configuration + debugging)

### Get Jenkins admin password from the chart secret mount

```bash
kubectl exec -n ci -it svc/jenkins -c jenkins -- /bin/cat /run/secrets/additional/chart-admin-password && echo
```

**Expected output**

* Prints the password (example you saw: `ChangeMe123!`)

### Watch Jenkins pod come up (quick readiness check)

```bash
kubectl -n ci get pods -w
```

**Expected output**

* `jenkins-0` moves to `Running` and shows `READY 2/2`

### Inspect Jenkins service + persistent volume claim

```bash
kubectl get pods,svc,ingress,pvc -n ci
```

**Expected output**

* `pod/jenkins-0` Running
* `service/jenkins` (typically ClusterIP) on `8080`
* `persistentvolumeclaim/jenkins` is `Bound` (example: 20Gi, `gp3`)

✅ **Useful for debugging**

* If Jenkins UI is slow/down: check pod status + PVC bound first.

---

## 3) Platform add-ons health checks (debugging)

### Confirm worker nodes are ready

```bash
kubectl get nodes
```

**Expected output**

* Nodes show `STATUS Ready`

### Verify core add-on pods (ALB controller, external-dns, EBS CSI)

```bash
kubectl get pods -n kube-system -l 'app.kubernetes.io/name in (aws-load-balancer-controller,external-dns,aws-ebs-csi-driver)'
```

**Expected output**

* All listed pods are `Running` (EBS CSI controller often shows `5/5` ready)

✅ **Useful for debugging**

* If ingress ALB doesn’t appear, start by verifying **aws-load-balancer-controller** pods are healthy.
* If DNS records don’t update, verify **external-dns** is healthy.

---

## 4) Ingress / ALB / DNS validation (configuration + debugging)

### List ingresses (all namespaces)

```bash
kubectl get ingress -A
```

**Expected output**

* Shows Jenkins ingress with:

  * `CLASS alb`
  * `HOSTS jenkins.poc.<ROOT_DOMAIN>`
  * `ADDRESS <something>.elb.amazonaws.com`

### Deep inspect the Jenkins ingress (most useful command here)

```bash
kubectl describe ingress jenkins -n ci
```

**Expected output (high-signal fields)**

* `Ingress Class: alb`
* `Address: k8s-...ap-south-1.elb.amazonaws.com`
* `Host: jenkins.poc.rdhcloudlab.com`
* Annotations like:

  * `alb.ingress.kubernetes.io/listen-ports: [{"HTTPS":443}]`
  * `alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...`
  * `alb.ingress.kubernetes.io/scheme: internet-facing`
  * `alb.ingress.kubernetes.io/target-type: ip`
* Events include: `SuccessfullyReconciled`

### Check TargetGroupBinding objects (only if your setup creates them)

```bash
kubectl get targetgroupbinding -n ci
```

**Expected output**

* Either a list of TargetGroupBindings **or**
* `No resources found in ci namespace.` (which you observed)

✅ **Useful for debugging**

* `kubectl describe ingress ...` is the best single command to confirm:

  * ALB created
  * TLS cert attached
  * host rule matches
  * controller reconciled successfully

---

## 5) Metrics & resource usage (debugging / observability)

### Install/refresh Metrics Server (enables `kubectl top`)

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

**Expected output**

* `deployment.apps/metrics-server configured` (or created)

### Node and pod resource usage

```bash
kubectl top nodes
kubectl top pods -A
```

**Expected output**

* Node CPU% / Memory% table
* Pod CPU/Memory per namespace (example: Jenkins ~hundreds of MiB)

### Remove Metrics Server

```bash
kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

**Expected output**

* Resources deleted

### Verify Metrics Server is gone + API removed (optional verification)

```bash
kubectl get pods -n kube-system | grep metrics-server || true
kubectl api-resources | grep metrics.k8s.io || true
```

**Expected output**

* No results (empty)

✅ **Useful for debugging**

* If `kubectl top` fails, metrics-server is missing or unhealthy.

---

## 6) PoC discovery & lifecycle (configuration + operations)

### Discover what PoCs exist (your convention)

```bash
helm list -A
kubectl get ns | grep '^poc-'
kubectl get ingress -A
```

**Expected output**

* Helm releases include platform components and optional PoC releases
* PoC namespaces follow `poc-<id>`
* Ingress hosts follow `<id>.poc.<ROOT_DOMAIN>`

### Destroy a single PoC by ID (repo script)

```bash
POC_ID=github scripts/95_destroy_poc.sh
```

**Expected output**

* If release exists: helm uninstall succeeds, namespace deleted
* If release does NOT exist: you may see `release: not found`, but namespace deletion can still happen (as you observed)

✅ **Useful for debugging**

* If a PoC partially exists, the “release not found” error tells you Helm has no release record, so cleanup is mainly namespace/resources.

---

## 7) Destroy everything (platform teardown) — repo-level operations

### Full teardown (Jenkins + add-ons + Terraform platform)

```bash
scripts/90_destroy_all.sh
```

**Expected output**

* Jenkins uninstalled + `ci` namespace deleted
* Add-ons uninstalled (ALB controller, external-dns, EBS CSI)
* Terraform destroy starts; if variables are not provided via files/env, it prompts for values

✅ **Helpful note (prevents getting stuck)**

* If you see repeated prompts for `var.*`, it usually means Terraform variables aren’t being loaded from a `.tfvars` / `-var-file` / environment variables.

---

## 8) Cleanup leftover Terraform state bucket objects (debugging)

### Remove all current objects (non-versioned cleanup)

```bash
aws s3 rm s3://$BUCKET --recursive
```

**Expected output**

* Objects removed (or nothing to delete)

### Delete versioned objects (Versions) and delete markers

```bash
BUCKET=rdhlab-platform-tf-state-dev

aws s3api delete-objects --bucket "$BUCKET" --delete "$(aws s3api list-object-versions --bucket "$BUCKET" --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}')"

aws s3api delete-objects --bucket "$BUCKET" --delete "$(aws s3api list-object-versions --bucket "$BUCKET" --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')"
```

**Expected output**

* If versions/markers exist: delete response with removed items
* If you get:

  * `Invalid type for parameter Delete.Objects, value: None`

  …that typically means **there were no Versions** or **no DeleteMarkers** to delete (empty result).

✅ **Useful for debugging**

* That `NoneType` validation error is a signal that the query returned nothing (not necessarily a failure of permissions).

---

## 9) Cleanup Route53 hosted zone records (bulk delete non-NS/SOA)

### Build a delete change batch for everything except NS and SOA

```bash
HZ=Z05501943V3NP0B430CP6

aws route53 list-resource-record-sets --hosted-zone-id "$HZ" \
  --query "ResourceRecordSets[?Type!='NS' && Type!='SOA']" --output json \
| jq '{Changes: map({Action:"DELETE", ResourceRecordSet:.})}' > /tmp/rr-delete.json
```

**Expected output**

* A `/tmp/rr-delete.json` file containing a `Changes` array

### Apply the deletion batch

```bash
aws route53 change-resource-record-sets --hosted-zone-id "$HZ" --change-batch file:///tmp/rr-delete.json
```

**Expected output**

* A `ChangeInfo` block with `Status: PENDING` and a `SubmittedAt` timestamp

✅ **Useful for debugging**

* If deletions “don’t reflect immediately,” Route53 changes can remain `PENDING` briefly before becoming `INSYNC`.

---

# Quick “most useful” commands to remember (config + debug)

* **Context/cluster sanity:** `aws eks update-kubeconfig ...` + `kubectl config use-context ...`
* **Jenkins password:** `kubectl exec ... cat /run/secrets/.../chart-admin-password`
* **Ingress/ALB truth source:** `kubectl describe ingress jenkins -n ci`
* **Add-ons running:** `kubectl get pods -n kube-system -l 'app.kubernetes.io/name in (...)'`
* **Resource pressure:** `kubectl top nodes` + `kubectl top pods -A` (needs metrics-server)

