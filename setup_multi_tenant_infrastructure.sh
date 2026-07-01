#!/bin/bash
#
# Multi-Tenant CA Infrastructure Setup Script
# Creates isolated tenant environments for gateway, iot, and freeradius
#

set -e

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
TENANTS_DIR="$REPO_ROOT/tenants"
TENANTS=("gateway" "iot" "freeradius")

echo "===================================================================="
echo " Multi-Tenant CA Infrastructure Setup"
echo "===================================================================="
echo

# Create base tenants directory
mkdir -p "$TENANTS_DIR"
echo "✓ Created base tenants directory: $TENANTS_DIR"

for TENANT in "${TENANTS[@]}"; do
    echo
    echo "--------------------------------------------------------------------"
    echo " Setting up tenant: $TENANT"
    echo "--------------------------------------------------------------------"
    
    TENANT_DIR="$TENANTS_DIR/$TENANT"
    
    # Create directory structure
    mkdir -p "$TENANT_DIR/private"
    mkdir -p "$TENANT_DIR/newcerts"
    
    # Initialize index.txt and serial files
    touch "$TENANT_DIR/index.txt"
    echo "01" > "$TENANT_DIR/serial"
    
    echo "  ✓ Created directory structure"
    
    # Generate CA private key (4096-bit RSA)
    openssl genrsa -out "$TENANT_DIR/private/cakey.pem" 4096 2>/dev/null
    chmod 600 "$TENANT_DIR/private/cakey.pem"
    echo "  ✓ Generated CA private key (4096-bit RSA)"
    
    # Create CA certificate (self-signed, 10 year validity)
    openssl req -new -x509 -days 3650 -key "$TENANT_DIR/private/cakey.pem" \
        -out "$TENANT_DIR/cacert.crt" -sha256 \
        -subj "/C=US/ST=CA/L=SanJose/O=Cisco/OU=$TENANT/CN=${TENANT}-CA" 2>/dev/null
    echo "  ✓ Generated CA certificate (10 year validity)"
    
    # Create tenant-specific OpenSSL configuration file
    cat > "$TENANT_DIR/${TENANT}.cnf" <<EOF
#
# OpenSSL CA Configuration for Tenant: $TENANT
# Multi-Tenant Isolation - DO NOT MODIFY
#

[ ca ]
default_ca = CA_default

[ CA_default ]
# Tenant-specific paths (complete isolation)
dir            = $TENANT_DIR
database       = \$dir/index.txt
new_certs_dir  = \$dir/newcerts
certificate    = \$dir/cacert.crt
serial         = \$dir/serial
private_key    = \$dir/private/cakey.pem
RANDFILE       = \$dir/private/.rnd

# Certificate parameters
default_days   = 365
default_crl_days = 30
default_md     = sha256

# Policy and extensions
policy         = policy_any
email_in_dn    = no
name_opt       = ca_default
cert_opt       = ca_default
copy_extensions = none
x509_extensions = client_cert

# Disable unique subject checking (allows re-enrollment)
unique_subject = no

[ policy_any ]
commonName     = supplied
countryName    = optional
stateOrProvinceName = optional
localityName   = optional
organizationName = optional
organizationalUnitName = optional
serialNumber   = optional

[ client_cert ]
# Extensions for client certificates
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid

[ req_distinguished_name ]
countryName            = Country Name (2 letter code)
stateOrProvinceName    = State or Province Name
localityName           = Locality Name
organizationName       = Organization Name
commonName             = Common Name

[ req ]
default_bits       = 2048
distinguished_name = req_distinguished_name
EOF

    echo "  ✓ Created OpenSSL configuration: ${TENANT}.cnf"
    
    # Verify setup
    if [ -f "$TENANT_DIR/cacert.crt" ] && [ -f "$TENANT_DIR/private/cakey.pem" ] && \
       [ -f "$TENANT_DIR/index.txt" ] && [ -f "$TENANT_DIR/serial" ]; then
        echo "  ✓ Tenant '$TENANT' setup verified successfully"
    else
        echo "  ✗ ERROR: Tenant '$TENANT' setup incomplete!"
        exit 1
    fi
done

echo
echo "===================================================================="
echo " Infrastructure Setup Complete!"
echo "===================================================================="
echo
echo "Summary:"
echo "  - Created 3 isolated tenant environments"
echo "  - Each tenant has its own CA certificate and key"
echo "  - Each tenant has separate index.txt and serial tracking"
echo "  - Each tenant has dedicated OpenSSL configuration"
echo
echo "Tenant directories:"
for TENANT in "${TENANTS[@]}"; do
    echo "  - $TENANTS_DIR/$TENANT/"
done
echo
echo "Next step: Implement multi-tenant enrollment callback in estserver.c"
echo
