#!/usr/bin/env bash
# Restore disk data VM (PVC vmdata) dari backup Completed TERBARU milik site lawan.
# Jalankan di cluster TUJUAN. <peer> = site asal data (site yang aktif/baru mati).
# Usage: scripts/oadp-restore-latest.sh <peer: dc|dr>
# Syarat: PVC vmdata di cluster tujuan TIDAK ada (VM Halted). Jika ada (data lama),
# script berhenti agar Anda menghapusnya sendiri dengan sadar: oc delete pvc vmdata -n sample-vm-data
set -euo pipefail
PEER="${1:?Usage: $0 <dc|dr>}"; NS=openshift-adp; APPNS=sample-vm-data
echo "Mencari backup Completed terbaru dari site ${PEER}..."
BK=""
for i in $(seq 1 12); do
  BK=$(oc get backup -n "$NS" --sort-by=.status.completionTimestamp \
        -o custom-columns=NAME:.metadata.name,PHASE:.status.phase --no-headers 2>/dev/null \
      | awk -v p="data-${PEER}-" 'index($1,p)==1 && $2=="Completed"{n=$1} END{print n}')
  [ -n "$BK" ] && break
  echo "  belum ada backup dari ${PEER} (sinkronisasi BSL bisa 1-2 menit)..."; sleep 10
done
[ -n "$BK" ] || { echo "Tidak ada backup Completed dari ${PEER}. Cek: oc get backup,backupstoragelocation -n ${NS}"; exit 1; }
echo "Memakai backup: ${BK}"
if oc get pvc vmdata -n "$APPNS" >/dev/null 2>&1; then
  echo "PVC vmdata sudah ada di ${APPNS} (berisi data lama)."
  echo "Pastikan VM Halted, lalu hapus: oc delete pvc vmdata -n ${APPNS}   dan jalankan ulang script ini."
  exit 1
fi
RN="restore-vmdata-$(date +%Y%m%d%H%M%S)"
cat <<YAML | oc apply -f -
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: ${RN}
  namespace: ${NS}
spec:
  backupName: ${BK}
  includedNamespaces:
    - ${APPNS}
  includedResources:
    - persistentvolumeclaims
  restorePVs: true
YAML
echo "Restore ${RN} dibuat; menunggu selesai..."
for i in $(seq 1 90); do
  P=$(oc get restore "$RN" -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  echo "  phase: ${P:-pending}"
  case "$P" in
    Completed) echo "OK"; oc get pvc -n "$APPNS"; exit 0;;
    PartiallyFailed|Failed|FailedValidation) echo "GAGAL. Cek: oc describe restore ${RN} -n ${NS}"; exit 1;;
  esac
  sleep 10
done
echo "Timeout menunggu restore"; exit 1
