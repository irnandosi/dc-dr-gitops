#!/usr/bin/env bash
# Isi endpoint dan bucket S3 di file DPA.
# Usage: oadp/set-s3.sh <s3-endpoint-host[:port]> <bucket>   (tanpa https://)
# Contoh: oadp/set-s3.sh s3.poc.imid.local:8000 dcdr-oadp
set -euo pipefail
[ $# -eq 2 ] || { sed -n '2,4p' "$0"; exit 1; }
cd "$(dirname "$0")"
sed -i -e "s#S3_ENDPOINT_HERE#$1#g" -e "s#BUCKET_NAME_HERE#$2#g" 02-dpa-dc.yaml 02-dpa-dr.yaml
echo "Selesai. Periksa: grep -n 's3Url\|bucket' 02-dpa-*.yaml"
