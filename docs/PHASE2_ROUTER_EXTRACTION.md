# Phase 2: Compare with OpenShift Ingress / router-rendered HAProxy

Optional **byte-level** parity with the cluster router (per plan choice **C**, phase 2).

## Extract live router config from OCP

1. Identify the default router pods:

   ```bash
   kubectl -n openshift-ingress get pods -l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=default
   ```

2. Copy the rendered HAProxy config from a router pod (pod name will differ):

   ```bash
   ROUTER_POD=$(kubectl -n openshift-ingress get pods -l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=default -o jsonpath='{.items[0].metadata.name}')
   kubectl -n openshift-ingress exec "$ROUTER_POD" -c router -- cat /var/lib/haproxy/conf/haproxy.config
   ```

3. Copy map files if you need full routing behaviour:

   ```bash
   kubectl -n openshift-ingress exec "$ROUTER_POD" -c router -- ls /var/lib/haproxy/conf/
   ```

4. For a **single** Route/Ingress that mirrors bench scenario (edge vs reencrypt), diff the relevant `backend` / `frontend` stanzas against `ansible/roles/haproxy_server/templates/haproxy.cfg.j2`.

## Optional Go harness

Building a small binary that imports `github.com/openshift/router` template packages with fixture `State` is possible but heavy; prefer extraction from a running router pod for audits.

## Ingress / Route alignment

Create **Route** or **Ingress** with:

- **Edge**: TLS terminates at router → Service HTTP (like scenarios b/c).
- **Reencrypt**: TLS at router → TLS to pod (like d/e); provide `destinationCACertificate` or equivalent.

See manifests under `kubernetes/` in this repo for examples.
