#!/usr/bin/env bash
# CA + server cert for AI Gateway.
# Names and bind IPs come from .env (TLS_CA_CN, TLS_SERVER_CN, TLS_DNS_NAMES, TLS_IP_ADDRS).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi

DIR="${CERT_DIR:-$ROOT/tmp/certs}"
TLS_CA_CN="${TLS_CA_CN:-AI Gateway CA}"
TLS_DNS_NAMES="${TLS_DNS_NAMES:-localhost}"
TLS_IP_ADDRS="${TLS_IP_ADDRS:-127.0.0.1}"
first_dns="${TLS_DNS_NAMES%%,*}"
first_dns="${first_dns#"${first_dns%%[![:space:]]*}"}"
first_dns="${first_dns%"${first_dns##*[![:space:]]}"}"
TLS_SERVER_CN="${TLS_SERVER_CN:-$first_dns}"

mkdir -p "$DIR"
cd "$DIR"

if [[ -f ca.pem && -f ca.key && -f server.pem && -f server.key ]]; then
  echo "certs already exist in $DIR — remove them to regenerate"
  exit 0
fi

openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 \
  -subj "/CN=${TLS_CA_CN}" \
  -out ca.pem

openssl genrsa -out server.key 2048
openssl req -new -key server.key -subj "/CN=${TLS_SERVER_CN}" -out server.csr

{
  cat <<'EOF'
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
EOF
  i=1
  IFS=',' read -ra names <<< "$TLS_DNS_NAMES"
  for name in "${names[@]}"; do
    name="${name#"${name%%[![:space:]]*}"}"
    name="${name%"${name##*[![:space:]]}"}"
    [[ -z "$name" ]] && continue
    echo "DNS.$i = $name"
    i=$((i + 1))
  done
  i=1
  IFS=',' read -ra ips <<< "$TLS_IP_ADDRS"
  for ip in "${ips[@]}"; do
    ip="${ip#"${ip%%[![:space:]]*}"}"
    ip="${ip%"${ip##*[![:space:]]}"}"
    [[ -z "$ip" ]] && continue
    echo "IP.$i = $ip"
    i=$((i + 1))
  done
} > server.ext

openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
  -out server.pem -days 825 -sha256 -extfile server.ext

chmod 600 ca.key server.key
rm -f server.csr
echo "wrote $DIR/ca.pem (install in trust stores)"
echo "wrote $DIR/server.pem + server.key (aigw TLS)"
