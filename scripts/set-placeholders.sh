#!/usr/bin/env bash
# Ganti placeholder di seluruh repo dengan nilai environment Anda.
# Usage: scripts/set-placeholders.sh <REPO_URL> <WEB_HOST> <VM_HOST> [STORAGE_CLASS]
# Contoh: scripts/set-placeholders.sh https://git.corp.local/poc/dc-dr-gitops.git web.poc.corp.local vm.poc.corp.local ocs-storagecluster-ceph-rbd
set -euo pipefail
if [ $# -lt 3 ]; then
  sed -n '2,5p' "$0"; exit 1
fi
cd "$(dirname "$0")/.."
REPO_URL="$1"; WEB_HOST="$2"; VM_HOST="$3"; SC="${4:-}"
FILES=$(grep -rlE 'git.example.com|sample-web.example.com|sample-vm.example.com|REPLACE_STORAGE_CLASS' \
        --include='*.yaml' --include='*.md' . || true)
for f in $FILES; do
  sed -i \
    -e "s#https://git.example.com/team/dc-dr-gitops.git#${REPO_URL}#g" \
    -e "s#sample-web.example.com#${WEB_HOST}#g" \
    -e "s#sample-vm.example.com#${VM_HOST}#g" "$f"
  [ -n "$SC" ] && sed -i -e "s#REPLACE_STORAGE_CLASS#${SC}#g" "$f"
done
echo "Selesai. Periksa dengan: git diff"
