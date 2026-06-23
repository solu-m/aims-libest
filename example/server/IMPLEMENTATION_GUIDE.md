# Role-Based EST Server - Implementation Guide

## Quick Start

This implementation adds **role-based certificate enrollment** to Cisco libEST multi-tenant server, enabling:

✅ **Gateway** → `clientAuth` certificates  
✅ **FreeRADIUS** → `serverAuth` certificates  
✅ **802.1X** authentication with proper EKU validation

## Files Added/Modified

| File | Type | Purpose |
|------|------|---------|
| `client-auth.cnf` | NEW | OpenSSL config for clientAuth certificates |
| `server-auth.cnf` | NEW | OpenSSL config for serverAuth certificates |
| `ossl_srv_role_based.c` | NEW | Role-based enrollment implementation |
| `est_multi_tenant.h` | MODIFIED | Added role field to TENANT_CLIENT |
| `tenants.json` | MODIFIED | Added role to each client |
| `ROLE_BASED_ENROLLMENT.md` | NEW | Complete architecture documentation |
| `test-role-based-enrollment.sh` | NEW | Test script for role-based enrollment |

## Installation

### Prerequisites

```bash
# Ubuntu/Debian
sudo apt-get install libest-dev libssl-dev openssl autoconf automake

# macOS
brew install openssl libest
```

### Build

```bash
cd /path/to/aims-libest

# Generate configure script
./autogen.sh

# Configure with multi-tenant support
./configure --enable-est-server

# Build
make clean
make

# EST example server
cd example/server
make
```

### Setup CA

```bash
cd example/server

# Create CA infrastructure
./createCA.sh

# Verify CA was created
ls -la estCA/
```

## Configuration

### tenants.json

Each client should have a **role** field:

```json
{
  "client_id": "gateway-1",
  "role": "client",           // ← clientAuth for gateways
  "password": "secret123",
  "server_id": "company-a"
}
```

```json
{
  "client_id": "freeradius-1",
  "role": "server",           // ← serverAuth for servers
  "password": "secret456",
  "server_id": "company-a"
}
```

## Running the EST Server

### Start EST Server

```bash
cd example/server

# Set environment variables
export EST_OPENSSL_CACONFIG=./estExampleCA.cnf
export EST_OPENSSL_CADIR=./estCA

# Start server (port 8085, verbose logging)
./estserver -p 8085 -v

# Output:
# EST Server started on port 8085
# Loading tenants from tenants.json
# Tenant 'company-a' loaded
#   - gateway-1 (role: client)
#   - freeradius-1 (role: server)
```

## Testing

### Run Test Script

```bash
cd example/server

# Make test script executable
chmod +x test-role-based-enrollment.sh

# Run tests
./test-role-based-enrollment.sh

# Expected output:
# [✓] Generated gateway CSR
# [✓] EST enrollment request succeeded
# [✓] Certificate has clientAuth EKU (correct for Gateway)
# [✓] Generated FreeRADIUS CSR
# [✓] EST enrollment request succeeded
# [✓] Certificate has serverAuth EKU (correct for FreeRADIUS)
# [✓] All tests passed!
```

### Manual Enrollment Test

**1. Gateway (Client Certificate)**

```bash
#!/bin/bash

TENANT="company-a"
CLIENT="gateway-1"
PASSWORD="gateway_secret_001"

# Create CSR
openssl req -new -keyout gw-key.pem -out gw.csr \
  -subj "/CN=$CLIENT/O=$TENANT/C=US"

# Enroll
TOKEN=$(echo -n "${TENANT}:${CLIENT}:${PASSWORD}" | base64 | tr -d '\n')
curl -X POST \
  --cacert estCA/cacert.crt \
  --data-binary @gw.csr \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/pkcs10" \
  https://localhost:8085/.well-known/est/simpleenroll \
  -o gw-cert.p7m

# Extract and verify
openssl pkcs7 -in gw-cert.p7m -inform DER -print_certs -out gw-cert.pem
openssl x509 -in gw-cert.pem -noout -text | grep -A 2 "Extended Key Usage"

# Should show: TLS Web Client Authentication
```

**2. FreeRADIUS (Server Certificate)**

```bash
#!/bin/bash

TENANT="company-a"
CLIENT="freeradius-1"
PASSWORD="freeradius_secret_001"

# Create CSR
openssl req -new -keyout rad-key.pem -out rad.csr \
  -subj "/CN=$CLIENT/O=$TENANT/C=US"

# Enroll
TOKEN=$(echo -n "${TENANT}:${CLIENT}:${PASSWORD}" | base64 | tr -d '\n')
curl -X POST \
  --cacert estCA/cacert.crt \
  --data-binary @rad.csr \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/pkcs10" \
  https://localhost:8085/.well-known/est/simpleenroll \
  -o rad-cert.p7m

# Extract and verify
openssl pkcs7 -in rad-cert.p7m -inform DER -print_certs -out rad-cert.pem
openssl x509 -in rad-cert.pem -noout -text | grep -A 2 "Extended Key Usage"

# Should show: TLS Web Server Authentication
```

## 802.1X Integration

### FreeRADIUS Configuration

```bash
# 1. Download CA certificates
curl -k -H "Authorization: Bearer company-a:freeradius-1:freeradius_secret_001" \
  https://localhost:8085/.well-known/est/cacerts \
  -o ca-chain.p7m

openssl pkcs7 -in ca-chain.p7m -inform DER -print_certs -out ca-chain.pem

# 2. Enroll server certificate (see above)

# 3. Configure FreeRADIUS
#    /etc/raddb/certs/ca.pem = ca-chain.pem
#    /etc/raddb/certs/server.pem = freeradius-1 cert
#    /etc/raddb/certs/server.key = freeradius-1 key

# 4. Start FreeRADIUS
radiusd -X
```

### Gateway Configuration

```bash
# 1. Download CA certificates
curl -k -H "Authorization: Bearer company-a:gateway-1:gateway_secret_001" \
  https://localhost:8085/.well-known/est/cacerts \
  -o ca-chain.p7m

openssl pkcs7 -in ca-chain.p7m -inform DER -print_certs -out ca-chain.pem

# 2. Enroll client certificate (see above)

# 3. Configure for 802.1X
#    /etc/wpa_supplicant/wpa_supplicant.conf
#    ca_cert=/path/to/ca-chain.pem
#    client_cert=/path/to/gateway-1-cert.pem
#    private_key=/path/to/gateway-1-key.pem

# 4. Connect to network
wpa_supplicant -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf
```

## Verification

### Check Certificate Extensions

```bash
# View all extensions
openssl x509 -in certificate.pem -noout -text

# Check specific extension
openssl x509 -in certificate.pem -noout -text | grep -A 2 "Extended Key Usage"

# For client cert:
# X509v3 Extended Key Usage: TLS Web Client Authentication

# For server cert:
# X509v3 Extended Key Usage: TLS Web Server Authentication
```

### Verify Certificate Chain

```bash
# Verify issued by CA
openssl verify -CAfile estCA/cacert.crt certificate.pem

# Should output: certificate.pem: OK
```

## Troubleshooting

### EST Server Won't Start

```bash
# Check environment variables
echo $EST_OPENSSL_CACONFIG
echo $EST_OPENSSL_CADIR

# Should point to config and CA directory

# Create if missing
export EST_OPENSSL_CACONFIG=$(pwd)/estExampleCA.cnf
export EST_OPENSSL_CADIR=$(pwd)/estCA
```

### Certificate Has Wrong EKU

```bash
# Check OpenSSL config files exist
ls -la client-auth.cnf server-auth.cnf

# Verify tenants.json has correct role
grep -A 2 '"client_id"' tenants.json | grep '"role"'

# Re-enroll and check
openssl x509 -in new-cert.pem -noout -text | grep -A 2 "Extended Key Usage"
```

### FreeRADIUS Rejects Certificate

```bash
# Enable FreeRADIUS verbose logging
radiusd -X

# Check certificate validation
# Should see: [tls] Certificate verification: PASSED

# If fails, verify:
# 1. CA certificate is correct
openssl verify -CAfile ca-chain.pem server-cert.pem

# 2. Certificate not expired
openssl x509 -in server-cert.pem -noout -dates

# 3. Certificate has serverAuth EKU
openssl x509 -in server-cert.pem -noout -text | grep -A 2 "Extended Key Usage"
```

## Architecture Diagram

```
┌─────────────────────────────────────────────────┐
│        EST Server (libEST + Role-Based)         │
│─────────────────────────────────────────────────│
│                                                 │
│  /.well-known/est/cacerts                      │
│    └─ Returns CA certificate chain             │
│                                                 │
│  /.well-known/est/simpleenroll                 │
│    ├─ Extract: tenant_id:client_id:password   │
│    ├─ Look up: client role in tenants.json    │
│    ├─ Load: client-auth.cnf OR server-auth.cnf│
│    ├─ Sign: CSR with role-specific EKU        │
│    └─ Return: PKCS#7 certificate              │
│                                                 │
└─────────────────────────────────────────────────┘
    ↑                              ↑
    │                              │
    │                              │
┌───┴─────────────────────────┬────┴──────────────┐
│                             │                  │
▼                             ▼                  ▼
Gateway              FreeRADIUS            Hostapd
(role: client)      (role: server)       (Authenticator)
clientAuth          serverAuth
```

## Next Steps

1. ✅ Review ROLE_BASED_ENROLLMENT.md for complete architecture
2. ✅ Run test-role-based-enrollment.sh to verify setup
3. ✅ Integrate with your FreeRADIUS and Hostapd setup
4. ✅ Configure 802.1X authentication flow
5. ✅ Test complete end-to-end authentication

## Support

For issues or questions:

1. Check ROLE_BASED_ENROLLMENT.md for detailed documentation
2. Run test script with verbose output: `bash -x test-role-based-enrollment.sh`
3. Check EST server logs: `./estserver -p 8085 -v`
4. Check certificate details: `openssl x509 -in cert.pem -text -noout`

## References

- **libEST:** https://github.com/cisco/libest
- **RFC 5280:** X.509 Certificate Extensions
- **IEEE 802.1X:** Port-Based Network Access Control
- **OpenSSL:** https://www.openssl.org/

---

**Version:** 1.0  
**Date:** June 2026  
**Status:** Ready for Testing
