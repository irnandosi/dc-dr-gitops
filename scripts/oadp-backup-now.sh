#!/usr/bin/env bash
# Backup on-demand data VM dari site ini ke S3 (untuk failover terencana / failback).
# Jalankan di cluster <site> (cluster tempat data aktif berada).
# Usage: scripts/oadp-backup-now.sh <dc|dr>
set -euo pipefail
SITE="${1:?Usage: $0 <dc|dr>}"; NS=openshift-adp
NAME="data-${SITE}-manual-$(date +%Y%m%d%H%M%S)"
cat <<YAML | oc apply -f -
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: ${NAME}
  namespace: ${NS}
spec:
  includedNamespaces:
    - sample-vm-data
  snapshotMoveData: true
  storageLocation: ${SITE}-site
  ttl: 72h0m0s
YAML
echo "Backup ${NAME} dibuat; menunggu selesai..."
for i in $(seq 1 90); do
  P=$(oc get backup "$NAME" -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  echo "  phase: ${P:-pending}"
  case "$P" in
    Completed) echo "OK: ${NAME}"; exit 0;;
    PartiallyFailed|Failed|FailedValidation) echo "GAGAL. Cek: oc describe backup ${NAME} -n ${NS}"; exit 1;;
  esac
  sleep 10
done
echo "Timeout menunggu backup"; exit 1
