# Runbook Uji Failover DC -> DR dan Failback

Prasyarat: Fase 1 dan 2 selesai (kedua Argo CD Synced/Healthy), `watch-site.sh` siap, TTL DNS sudah rendah (mis. 60 detik).

## 0. Baseline
```bash
scripts/watch-site.sh https://<WEB_HOST> 2 | tee failover-log.txt   # biarkan berjalan di terminal terpisah
oc get pods -n sample-web            # DC: 2 pod Running
oc get vmi -n sample-vm              # DC: VM Running
# Di cluster DR: pod 0, VM Halted
```
Catat waktu mulai: `T0 = ______`

## 1. Simulasi bencana di DC
Pilih salah satu (jangan scale-down manual: self-heal Argo CD akan mengembalikannya):
- Matikan ingress/jaringan DC, atau matikan node/cluster DC (simulasi paling realistis), atau
- Set DC ke standby lewat Git: `scripts/set-state.sh dc standby` lalu commit/push, atau
- Nonaktifkan auto-sync Application di DC sebelum mematikan workload.

Waktu bencana: `T1 = ______`

## 2. (Jika stateful) Promote data di DR
Langkah ini bergantung mekanisme replikasi (ODF DR, storage vendor, DB replica). GitOps tidak menanganinya.

## 3. Aktifkan DR lewat Git
```bash
scripts/set-state.sh dr active
git add -A && git commit -m "DR: failover ke DR" && git push    # atau buat PR lalu merge
```
Argo CD di DR melakukan sync otomatis. Pantau:
```bash
oc get pods -n sample-web -w
oc get vmi  -n sample-vm  -w
```
Waktu workload Ready di DR: `T2 = ______`

## 4. Reroute traffic
- GSLB: biarkan health check memindahkan, atau paksa pindah.
- DNS manual: ubah record `<WEB_HOST>` dan `<VM_HOST>` ke VIP/ingress DR.

Waktu traffic terjawab DR (output `watch-site.sh` berubah ke `site=DR`): `T3 = ______`

## 5. Validasi
| Item | Cara cek | Hasil |
|---|---|---|
| Argo CD DR Synced/Healthy | Dashboard / `oc get applications -n openshift-gitops` | |
| Pod web & VM Running di DR | `oc get pods,vmi` | |
| Endpoint menjawab SITE=DR | `watch-site.sh` / `curl` | |
| RTO = T3 - T1 | Hitung dari log | |
| RPO (jika stateful) | Bandingkan data terakhir DC vs DR | |
| Tidak ada drift config DC vs DR | `argocd app diff` / status Synced | |

## 6. Failback
1. Pulihkan DC. Pastikan Argo CD DC Synced.
2. (Jika stateful) sinkronkan balik data DR -> DC.
3. `scripts/set-state.sh dc active` dan `scripts/set-state.sh dr standby`, commit/push.
4. Kembalikan DNS/GSLB ke DC. Verifikasi `site=DC`.

## 7. Feedback customer
- RTO terukur vs target?
- Kenyamanan alur "failover = perubahan terreview di Git"?
- Gap: replikasi data, GSLB, sertifikat, ketersediaan Git saat bencana.
- Kebutuhan lanjutan: RHACM, ApplicationSet, ODF DR, Ansible Automation Platform untuk orkestrasi.
