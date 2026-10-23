#!/usr/bin/env bash
# Validasi lokal sebelum push: render semua overlay/cluster.
# Memakai 'kustomize', 'oc kustomize', atau 'kubectl kustomize' (yang tersedia).
set -euo pipefail
cd "$(dirname "$0")/.."
if command -v kustomize >/dev/null; then KB="kustomize build"
elif command -v oc >/dev/null; then KB="oc kustomize"
elif command -v kubectl >/dev/null; then KB="kubectl kustomize"
else echo "Install kustomize/oc/kubectl terlebih dahulu"; exit 1; fi
rc=0
for d in apps/sample-web/overlays/dc apps/sample-web/overlays/dr \
         apps/sample-vm/overlays/dc  apps/sample-vm/overlays/dr \
         clusters/dc clusters/dr; do
  if $KB "$d" >/dev/null 2>/tmp/kb.err; then echo "OK    $d"
  else echo "GAGAL $d"; cat /tmp/kb.err; rc=1; fi
done
exit $rc
