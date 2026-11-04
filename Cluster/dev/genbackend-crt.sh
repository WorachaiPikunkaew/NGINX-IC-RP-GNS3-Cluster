#!/bin/sh
# Issue a backend server certificate signed by internal-ca (via cert-manager).
# Run on the control plane (needs kubectl + KUBECONFIG). POSIX sh, works on Alpine.
#
# Examples:
#   ./gen-backend-cert.sh -d web1.example.net -i 10.0.24.24
#   ./gen-backend-cert.sh -d web2.example.net -d web2 -i 10.0.24.28 -t 365 -o /root/certs

set -eu

NS="proxy"
ISSUER="internal-ca-issuer"
DAYS=90
OUT="./certs"
NAME=""
DNS=""
IPS=""
CLEANUP=0

usage() {
  cat <<EOF
Usage: $0 [-d domain]... [-i ip]... [-n name] [-t days] [-o outdir] [-C]
  -d  DNS name for the SAN (repeatable, or comma-separated). First one becomes the CN.
  -i  IP address for the SAN (repeatable, or comma-separated)
  -n  Certificate/resource name (default: derived from first domain or IP)
  -t  Validity in days (default: $DAYS)
  -o  Output directory (default: $OUT)
  -C  Delete the Certificate and Secret from the cluster after exporting
At least one -d or -i is required.
EOF
  exit 1
}

while getopts "d:i:n:t:o:Ch" opt; do
  case "$opt" in
    d) DNS="$DNS $(echo "$OPTARG" | tr ',' ' ')" ;;
    i) IPS="$IPS $(echo "$OPTARG" | tr ',' ' ')" ;;
    n) NAME="$OPTARG" ;;
    t) DAYS="$OPTARG" ;;
    o) OUT="$OPTARG" ;;
    C) CLEANUP=1 ;;
    *) usage ;;
  esac
done

[ -n "$DNS$IPS" ] || usage
case "$DAYS" in ''|*[!0-9]*) echo "Error: -t must be a number of days" >&2; exit 1 ;; esac

CN=$(echo "$DNS $IPS" | awk '{print $1}')

if [ -z "$NAME" ]; then
  NAME=$(echo "$CN" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9\n' '-' | sed 's/^-*//;s/-*$//')
  NAME="srv-$NAME"
fi

HOURS=$((DAYS * 24))

# Build the Certificate manifest
MANIFEST=$(
  cat <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: $NAME
  namespace: $NS
spec:
  secretName: $NAME-tls
  commonName: "$CN"
  duration: ${HOURS}h
  privateKey:
    algorithm: ECDSA
    size: 256
    rotationPolicy: Always
  usages:
    - digital signature
    - key encipherment
    - server auth
  issuerRef:
    name: $ISSUER
    kind: Issuer
EOF
  if [ -n "$(echo $DNS)" ]; then
    echo "  dnsNames:"
    for d in $DNS; do echo "    - \"$d\""; done
  fi
  if [ -n "$(echo $IPS)" ]; then
    echo "  ipAddresses:"
    for ip in $IPS; do echo "    - \"$ip\""; done
  fi
)

echo "$MANIFEST" | kubectl apply -f -
kubectl wait --for=condition=Ready "certificate/$NAME" -n "$NS" --timeout=90s

DEST="$OUT/$NAME"
mkdir -p "$DEST"
umask 077
kubectl get secret "$NAME-tls" -n "$NS" -o jsonpath='{.data.tls\.crt}' | base64 -d > "$DEST/tls.crt"
kubectl get secret "$NAME-tls" -n "$NS" -o jsonpath='{.data.tls\.key}' | base64 -d > "$DEST/tls.key"
kubectl get secret "internal-ca-secret" -n "$NS" -o jsonpath='{.data.ca\.crt}' | base64 -d > "$DEST/ca.crt"
chmod 644 "$DEST/tls.crt" "$DEST/ca.crt"
chmod 600 "$DEST/tls.key"

echo
echo "Issued: $DEST/{tls.crt,tls.key,ca.crt}"
if command -v openssl >/dev/null 2>&1; then
  openssl x509 -in "$DEST/tls.crt" -noout -subject -enddate -ext subjectAltName
fi

if [ "$CLEANUP" -eq 1 ]; then
  kubectl delete certificate "$NAME" -n "$NS"
  kubectl delete secret "$NAME-tls" -n "$NS" --ignore-not-found
  echo "Removed $NAME from the cluster."
fi
