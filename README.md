# DC-DR Synchronization with GitOps (POC)

Repo ini mensinkronkan konfigurasi workload antara **DC** dan **DR** memakai OpenShift GitOps (Argo CD).
Model: active-passive / pilot light. DC aktif, DR standby (replicas 0 / VM Halted) dengan manifest identik.

> **Penting:** GitOps menyinkronkan *konfigurasi*, bukan *data*. Replikasi data (PV, disk VM, database)
> harus ditangani terpisah (ODF DR, replikasi storage vendor, replika DB, atau backup/restore).

## Struktur

```
bootstrap/                    # sekali apply per cluster
  00-gitops-operator-subscription.yaml
  01-repo-secret.example.yaml # credential repo private (contoh)
  dc/root-app.yaml            # app-of-apps untuk DC
  dr/root-app.yaml            # app-of-apps untuk DR
clusters/
  dc/  dr/                    # Application per app untuk tiap cluster
apps/
  sample-web/                 # contoh container (nginx UBI)
    base/                     # sama untuk DC & DR
    overlays/dc|dr/           # beda: identitas site + patch-state.yaml (replicas)
  sample-vm/                  # contoh VM (OpenShift Virtualization)
    base/
    overlays/dc|dr/           # beda: cloud-init (identitas site) + patch-state.yaml (runStrategy)
    variants/datavolume/      # opsional: disk persisten (DataVolume) sebagai Kustomize Component
scripts/                      # set-placeholders, set-state, watch-site, validate
docs/runbook-failover.md      # langkah uji failover, checklist validasi, feedback
```

## Prasyarat
- 2 cluster OpenShift (DC dan DR). Untuk `sample-vm`: OpenShift Virtualization terpasang di keduanya.
- Git server yang terjangkau dari kedua cluster; branch `main`.
- Registry: `registry.access.redhat.com` dan `quay.io` terjangkau, atau mirror image ke registry internal
  (`ubi9/nginx-124`, `containerdisks/fedora`) lalu ubah image di manifest.
- DNS/GSLB untuk hostname global (atau ubah record DNS manual saat uji).

## Langkah cepat

1. **Ganti placeholder** lalu push ke Git Anda:
   ```bash
   scripts/set-placeholders.sh https://git.corp.local/poc/dc-dr-gitops.git web.poc.corp.local vm.poc.corp.local <storage-class>
   git init && git add -A && git commit -m "init" && git branch -M main
   git remote add origin <REPO_URL> && git push -u origin main
   ```
2. **Install operator** (di DC *dan* DR):
   ```bash
   oc apply -f bootstrap/00-gitops-operator-subscription.yaml
   oc get pods -n openshift-gitops          # tunggu Running
   ```
3. **Credential repo** jika private (di DC dan DR): isi lalu `oc apply -f bootstrap/01-repo-secret.example.yaml`.
4. **Bootstrap app-of-apps**:
   ```bash
   oc apply -f bootstrap/dc/root-app.yaml   # jalankan di cluster DC
   oc apply -f bootstrap/dr/root-app.yaml   # jalankan di cluster DR
   ```
5. **Verifikasi**:
   ```bash
   oc get applications -n openshift-gitops          # Synced / Healthy
   oc get route -n sample-web                       # Route langsung per-site (uji tanpa DNS)
   curl -k https://<route-host>                     # halaman menampilkan SITE: DC atau DR
   ```
   - DC: 2 pod `sample-web` Running, VM `sample-vm` Running.
   - DR: namespace dan resource ada, tapi pod 0 dan VM Halted (standby).

## Cara kerja perbedaan DC vs DR
Semua perbedaan ada di `overlays/<site>/`:
- `patch-state.yaml`: **state** site (`replicas` atau `runStrategy`). Inilah yang diubah saat failover.
- `index.html` / `cloud-init.yaml`: identitas site (DC/DR) agar mudah dibuktikan saat uji.

Failover = perubahan kecil di Git:
```bash
scripts/set-state.sh dr active      # DR aktif
scripts/set-state.sh dc standby     # (jika DC masih hidup) DC standby
git add -A && git commit -m "DR: failover" && git push
```
Detail pengujian: `docs/runbook-failover.md`.

## Catatan penting
- **Self-heal**: scale-down/hapus manual di DC akan dikembalikan Argo CD. Untuk simulasi bencana gunakan
  cara di runbook (matikan ingress/node, ubah via Git, atau nonaktifkan auto-sync).
- **Prune & data**: DataVolume/PVC diberi `Prune=false,Delete=false`. Jangan hilangkan untuk resource stateful.
- **Root app tanpa finalizer**: menghapus Application tidak ikut menghapus VM/data (disengaja).
- **Disk persisten VM** (`variants/datavolume`): aktifkan dengan membuka komentar `components:` di overlay.
  Di DR, DataVolume akan mengimpor disk baru, bukan menyalin data DC.
- **Sertifikat**: Route global memakai hostname kustom; pastikan sertifikat TLS cocok di DC dan DR.
- **Git server**: jangan hanya berada di DC. Letakkan di site netral atau punya mirror di DR.
- **OutOfSync berulang pada VM**: cek `argocd app diff`, lalu tambahkan `ignoreDifferences` hanya untuk field
  spesifik yang diubah controller.
- Versi operator/channel dan nama field bisa berbeda antar versi OCP/GitOps; sesuaikan dengan environment Anda.
