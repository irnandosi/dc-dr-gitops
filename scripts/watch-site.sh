#!/usr/bin/env bash
# Pantau endpoint tiap N detik; catat waktu, HTTP code, dan SITE (DC/DR) yang menjawab.
# Berguna untuk mengukur RTO saat failover (lihat kapan SITE berubah dari DC ke DR).
# Usage: scripts/watch-site.sh <URL> [interval_detik]
# Contoh: scripts/watch-site.sh https://sample-web.poc.corp.local 2 | tee failover-log.txt
set -uo pipefail
URL="${1:?Usage: $0 <URL> [interval]}"; INT="${2:-2}"
LAST=""
while true; do
  TS=$(date '+%Y-%m-%d %H:%M:%S')
  BODY=$(curl -ks --max-time 3 -w '\n%{http_code}' "$URL" 2>/dev/null || true)
  CODE=$(printf '%s' "$BODY" | tail -n1)
  SITE=$(printf '%s' "$BODY" | grep -oE 'SITE=[A-Z]+' | head -n1 | cut -d= -f2)
  [ -z "$CODE" ] && CODE="000"
  [ -z "$SITE" ] && SITE="-"
  MARK=""
  [ "$SITE" != "$LAST" ] && MARK="   <== berubah (sebelumnya: ${LAST:-n/a})"
  echo "$TS  http=$CODE  site=$SITE$MARK"
  LAST="$SITE"
  sleep "$INT"
done
