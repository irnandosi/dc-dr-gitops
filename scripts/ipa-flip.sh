#!/usr/bin/env bash
# Balikkan DNS web, vm, dan vmdata ke site tertentu. Jalankan di server FreeIPA (sudah: kinit admin).
# Usage: ipa-flip.sh <dc|dr>
set -euo pipefail
DC_IP=192.168.51.191; DR_IP=192.168.51.161; ZONE=poc.imid.local
case "${1:-}" in dc) IP=$DC_IP;; dr) IP=$DR_IP;; *) echo "Usage: $0 <dc|dr>"; exit 1;; esac
for h in web vm vmdata; do
  ipa dnsrecord-show "$ZONE" "$h" >/dev/null 2>&1 || ipa dnsrecord-add "$ZONE" "$h" --a-rec="$IP" --ttl=60 >/dev/null
  ipa dnsrecord-mod "$ZONE" "$h" --a-rec="$IP" --ttl=60 >/dev/null
  echo "$h.$ZONE -> $IP"
done
