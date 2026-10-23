#!/usr/bin/env bash
# Ubah STATE sebuah site (aktif/standby) di overlay, untuk failover/failback.
#   active  -> sample-web replicas=2, sample-vm runStrategy=Always
#   standby -> sample-web replicas=0, sample-vm runStrategy=Halted
# Usage: scripts/set-state.sh <dc|dr> <active|standby> [replicas]
# Script hanya mengedit file; commit & push (atau buat PR) dilakukan manual.
set -euo pipefail
[ $# -ge 2 ] || { sed -n '2,8p' "$0"; exit 1; }
SITE="$1"; STATE="$2"; REPLICAS="${3:-2}"
case "$SITE" in dc|dr) ;; *) echo "site harus dc atau dr"; exit 1;; esac
cd "$(dirname "$0")/.."
case "$STATE" in
  active)  REP="$REPLICAS"; RUN="Always";;
  standby) REP=0;           RUN="Halted";;
  *) echo "state harus active atau standby"; exit 1;;
esac
sed -i -E "s/^(  replicas:) .*/\1 ${REP}/"    "apps/sample-web/overlays/${SITE}/patch-state.yaml"
sed -i -E "s/^(  runStrategy:) .*/\1 ${RUN}/" "apps/sample-vm/overlays/${SITE}/patch-state.yaml"
echo "Site ${SITE^^} -> ${STATE}: sample-web replicas=${REP}, sample-vm runStrategy=${RUN}"
echo "Langkah berikut: git add -A && git commit -m 'DR: ${SITE} ${STATE}' && git push  (atau buat PR)"
