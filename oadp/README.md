# Add-on: Sinkronisasi data VM dengan OADP + S3

Tambahan untuk repo `dc-dr-gitops`. Ekstrak di root repo (timpa file yang sama), lalu ikuti urutan di bawah.

## Cara kerja

```
 DC (ocpsno)                          S3 (BUKAN di DC)                      DR (ocpsnodrc)
 VM + disk data (PVC vmdata)          bucket, prefix dc/ dan dr/            VM Halted, PVC belum ada
   | CSI snapshot + Kopia (data mover)    ^                                   |
   +--> Schedule data-dc tiap 15 menit ---+--- BSL dc-site (RO) dibaca -------+--> Restore PVC vmdata
                                                                               saat failover
```

- GitOps mengurus **definisi VM** (VM Halted di DR, Always di DC). OADP mengurus **isi disk data**.
- PVC `vmdata` sengaja **tidak ada di Git**: dibuat sekali di DC, dan dibuat oleh restore di DR. Argo CD tidak berebut dengan restore dan tidak men-prune data.
- Setiap site menulis backup ke prefix sendiri (`dc/` atau `dr/`) dan membaca prefix site lawan (ReadOnly).
- Disk OS VM efemeral (containerDisk). Hanya disk data yang dilindungi.

## Langkah 1: Siapkan S3 (sekali)

Bucket harus bisa dijangkau dari DC dan DR dan **tidak boleh hidup di DC** (jika DC mati, backup ikut hilang). Untuk lab dua SNO, letakkan di DR, di server terpisah, atau di Scality ARTESCA/RING.
Buat bucket (mis. `dcdr-oadp`) dan access key. Lalu isi endpoint dan bucket:

```bash
oadp/set-s3.sh <endpoint[:port]> <bucket>      # tanpa https://
```

## Langkah 2: Di KEDUA cluster

```bash
oc apply -f oadp/00-operator.yaml
oc get csv -n openshift-adp                    # tunggu Succeeded

cp oadp/01-s3-credentials.example.yaml /tmp/s3-cred.yaml    # isi key, JANGAN commit
oc apply -f /tmp/s3-cred.yaml

oc get volumesnapshotclass                     # LVMS: biasanya lvms-vg1 (driver topolvm.io)
oc label volumesnapshotclass lvms-vg1 velero.io/csi-volumesnapshot-class=true --overwrite
```

Hanya boleh ada **satu** VolumeSnapshotClass berlabel untuk driver yang sama.

## Langkah 3: DPA dan Schedule

Di **ocpsno (DC)**:
```bash
oc apply -f oadp/02-dpa-dc.yaml
oc apply -f oadp/03-schedule-dc.yaml
```
Di **ocpsnodrc (DR)**:
```bash
oc apply -f oadp/02-dpa-dr.yaml
oc apply -f oadp/03-schedule-dr.yaml
```

Verifikasi di tiap cluster:
```bash
oc get dpa,backupstoragelocation -n openshift-adp     # BSL: dc-site dan dr-site, PHASE Available
oc get pods -n openshift-adp                          # velero, node-agent-* Running
```
Nama BSL harus `dc-site` dan `dr-site`. Jika operator memberi nama lain, sesuaikan `storageLocation` di Schedule dan script.

## Langkah 4: Aplikasi demo `sample-vm-data`

Di **DC**, buat PVC SEBELUM aplikasi disinkronkan:
```bash
oc create namespace sample-vm-data
oc apply -f seed/vmdata-pvc.yaml
```
Lalu push repo (aplikasi muncul via root-app) dan refresh:
```bash
git add -A && git commit -m "add sample-vm-data + oadp" && git push
oc annotate application root-dc -n openshift-gitops argocd.argoproj.io/refresh=hard --overwrite      # di DC
oc annotate application root-dr -n openshift-gitops argocd.argoproj.io/refresh=hard --overwrite      # di DR
```
Hasil: DC memiliki VM `sample-vm-data` Running. DR memiliki VM Halted dan tidak ada PVC (memang begitu).

Buka halaman VM (heartbeat tiap 10 detik, ada marker `SITE=DC`):
```bash
curl -k https://$(oc get route sample-vm-data -n sample-vm-data -o jsonpath='{.spec.host}')
```

## Langkah 5: Uji

Lanjut ke `docs/runbook-failover-stateful.md`.

## Hal yang perlu diverifikasi di environment Anda

- Versi OADP minimal 1.3 (dukungan OpenShift Virtualization). Cek channel dengan `oc get packagemanifest redhat-oadp-operator`.
- BSL `Available`, dan Backup dari site lawan muncul di `oc get backup -n openshift-adp` dalam 1-2 menit (sinkronisasi BSL).
- Password repository Kopia default sama di kedua cluster. Jika Anda mengubah secret `velero-repo-credentials`, nilainya **harus sama** di DC dan DR, atau restore lintas cluster gagal.
- Resource SNO cukup untuk pod data mover (Kopia) saat backup dan restore.
