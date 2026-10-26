# Runbook: Failover VM Stateful (GitOps + OADP)

Pelengkap `docs/runbook-failover.md`. Tambahan: data disk VM dipulihkan di DR **sebelum** VM DR dinyalakan.

Bukti data selamat: halaman `sample-vm-data` menampilkan baris heartbeat. Setelah failover, baris lama bertanda `site=DC`, baris baru `site=DR`.
Selisih antara baris DC terakhir dan waktu bencana = RPO yang terukur.

## 0. Baseline (DC aktif)

```bash
# Record DNS vmdata + pemantau
# di server FreeIPA:  ipa-flip.sh dc        (membuat record vmdata bila belum ada)
curl -k https://vmdata.poc.imid.local      # SITE: DC, daftar heartbeat bertambah
oc get backup -n openshift-adp             # di DC: data-dc-<timestamp> Completed
```
Pantau: `scripts/watch-site.sh https://vmdata.poc.imid.local 2 | tee ~/failover-vmdata.txt`

## A. Failover TIDAK terencana (DC mati)

Data yang dipulihkan = backup terjadwal terakhir (RPO kasar = interval schedule, 15 menit).

Di **DR**:
```bash
oc get backup -n openshift-adp | grep data-dc      # backup dari DC tersinkron (tunggu 1-2 menit setelah login)
oc get pvc -n sample-vm-data                       # harus kosong; jika ada PVC lama: oc delete pvc vmdata -n sample-vm-data
scripts/oadp-restore-latest.sh dc                  # restore PVC vmdata dari backup DC terbaru
oc get pvc -n sample-vm-data                       # vmdata Bound
```
Aktifkan DR lewat Git (satu commit untuk kedua site):
```bash
scripts/set-state.sh dr active
scripts/set-state.sh dc standby
git add -A && git commit -m "DR: failover stateful" && git push
oc annotate application sample-vm-data-dr -n openshift-gitops argocd.argoproj.io/refresh=hard --overwrite
oc annotate application sample-web-dr     -n openshift-gitops argocd.argoproj.io/refresh=hard --overwrite
oc annotate application sample-vm-dr      -n openshift-gitops argocd.argoproj.io/refresh=hard --overwrite
oc get vmi -n sample-vm-data -w
```
Setelah VM Running, balikkan DNS di server FreeIPA: `ipa-flip.sh dr`

Validasi: `curl -k https://vmdata.poc.imid.local` menampilkan `SITE: DR`, jumlah baris heartbeat **tidak nol**, dan baris lama bertanda `site=DC` terlihat.

## B. Failover TERENCANA (RPO nyaris nol)

1. Hentikan VM di DC lewat Git: `scripts/set-state.sh dc standby`, commit, push, refresh Application `-dc`. Tunggu VM berhenti (disk dalam keadaan bersih).
2. Di DC: `scripts/oadp-backup-now.sh dc` (tunggu Completed).
3. Di DR: restore seperti pada bagian A, lalu aktifkan DR dan balikkan DNS.

## C. Failback DR → DC

Data terbaru ada di DR, jadi arah backup dan restore berbalik.

1. Hentikan VM di DR lewat Git (`set-state.sh dr standby`, commit, push, refresh).
2. Di DR: `scripts/oadp-backup-now.sh dr` (tunggu Completed).
3. Di DC (VM Halted): hapus PVC lama yang usang: `oc delete pvc vmdata -n sample-vm-data`, lalu `scripts/oadp-restore-latest.sh dr`.
4. Aktifkan DC: `set-state.sh dc active`, commit, push, refresh. Tunggu VM Running.
5. DNS: `ipa-flip.sh dc`. Pastikan `SITE: DC` dan data heartbeat lengkap (baris DC, DR, lalu DC lagi).
6. Di DR, PVC lama sekarang usang. Hapus sebelum failover berikutnya: `oc delete pvc vmdata -n sample-vm-data`.

## Aturan penting

- **Hapus PVC usang di sisi tujuan sebelum restore.** Restore tidak menimpa PVC yang sudah ada, dan script berhenti jika PVC ada.
- **Restore sebelum VM dinyalakan.** Urutan benar: data siap, commit `active`, VM menyala, DNS dibalik.
- **Satu commit untuk dua site** (`X active` + `Y standby`) agar tidak terjadi dua site aktif.
- Backup dari site yang sedang standby tidak dipakai. Restore selalu dari site yang aktif atau baru mati.

## Catat untuk laporan

| Metrik | Cara ambil |
|---|---|
| RTO stateful | Dari bencana/commit sampai halaman `vmdata` menjawab `SITE: DR` dengan data terpulihkan (termasuk waktu restore) |
| Waktu restore | Dari `oc get restore -n openshift-adp` (start dan completion) |
| RPO | Waktu bencana dikurangi timestamp baris `site=DC` terakhir di halaman |
| Integritas | Heartbeat tidak hilang di tengah, baris lama utuh |
