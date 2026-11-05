# Replacing a chart's StatefulSet in place, keeping its volume

Use this when a StatefulSet created by a Helm chart (or any manifest source)
must move to a different source, such as plain manifests, another chart or
another image, without losing the data on its PersistentVolumeClaim.

## The constraint

On update, the API server rejects any StatefulSet spec change outside
`replicas`, `ordinals`, `template`, `updateStrategy`, `revisionHistoryLimit`,
`persistentVolumeClaimRetentionPolicy` and `minReadySeconds`:

```
The StatefulSet "<name>" is invalid: spec: Forbidden: updates to statefulset spec for fields other than ...
```

So `selector`, `serviceName` and `volumeClaimTemplates` are fixed for the
object's life. A new StatefulSet under a **different** name gets a different
PVC (`<template>-<statefulset>-<ordinal>`), so its data has to be copied.

## The in-place switch

Keep the StatefulSet's **name, selector, serviceName and volumeClaimTemplates
identical** to the live object, and change only the pod template (image,
command, config mounts, probes, security context). The apply is then an
ordinary rolling update. The controller replaces the pod, and the new pod
mounts the same PVC. The old and new pods never share the volume, which
matters for a ReadWriteOnce disk that two pods on one node could otherwise
both mount.

1. **Copy the immutable fields from what the apply will diff against.** For
   client-side apply (the default, and ArgoCD without `ServerSideApply=true`),
   that is the `kubectl.kubernetes.io/last-applied-configuration` annotation,
   not the defaulted live spec:

   ```bash
   kubectl --context <ctx> -n <ns> get sts <name> -o yaml > live.yaml
   yq '.metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"]' live.yaml \
     | jq '.spec | {selector, serviceName, volumeClaimTemplates}'
   ```

   Reproduce `volumeClaimTemplates` from it exactly, including the template
   labels and the explicit `apiVersion`/`kind` keys. Do not add defaulted
   fields such as `volumeMode`, and never copy the live `status`. If the
   three-way patch finds the list unchanged, it leaves it out.
2. **Keep the Service names and selectors** so clients and the ClusterIP do not
   change. Re-declare anything else the old source created that you still
   want: ServiceAccount, NetworkPolicy, PodDisruptionBudget, ConfigMap.
3. **Match the volume's file ownership.** Bitnami images write as uid 1001; a
   replacement image must run with that uid or `fsGroup`, or it cannot open its
   own data files.
4. **Check the retention policy.** A PVC created from `volumeClaimTemplates`
   carries no GitOps tracking label, so ArgoCD prune leaves it alone, and
   `persistentVolumeClaimRetentionPolicy: Retain` (the default) keeps it if the
   StatefulSet is ever deleted.

## Prove it before merging: a dry run with a control

```bash
kubectl --context <ctx> -n <ns> apply --dry-run=server -f manifests/
```

Every object should report `configured (server dry run)`. That alone proves
little, so run the control too: change one byte of `volumeClaimTemplates`
(for example `storage: 8Gi` to `9Gi`) in a copy and dry-run that. It must fail
with `spec: Forbidden`. If the control passes, the dry run is not checking what
you think, and the real result means nothing.

Before switching, also load a copy of the data into the new image locally
(`kubectl cp` the data directory, run the image against it with the same
uid, read-only root filesystem and config). A format or module mismatch, such
as Redis data written with modules the new image does not load, fails there
instead of in production.

## Rollback

Reverting restores the old source's identical StatefulSet identity, so the
apply works. Whether the old software can read data the new one has
rewritten is a separate question (a newer on-disk format), so keep the
pre-switch copy until the new version has run for a while.

## Worked example

ForumViriumHelsinki/infrastructure#2699 (2026-11-04): the shared Redis moved
from the bitnami chart (`bitnamilegacy` images, never rebuilt) to plain
manifests on `redis:8.10.3-alpine3.23`. The StatefulSet `redis-master` kept its
selector, `redis-headless` service name and the `redis-data` template. The
server-side dry run reported all seven objects `configured`, the 9Gi control
was rejected, and the new pod replayed the existing AOF with 0 restarts.
