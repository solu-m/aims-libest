#!/bin/bash
set -e
cd /mnt/c/Users/Solum/aims-libest/tenants

for tenant in gateway iot freeradius; do
    echo "Setting up $tenant..."
    openssl genrsa -out "$tenant/private/cakey.pem" 4096 2>/dev/null
    openssl req -new -x509 -days 3650 -key "$tenant/private/cakey.pem" \
        -out "$tenant/cacert.crt" -sha256 \
        -subj "/C=US/ST=CA/L=SanJose/O=Cisco/OU=$tenant/CN=$tenant-CA" 2>/dev/null
    echo "  Generated CA cert and key for $tenant"
done
echo "All CA certificates generated successfully!"