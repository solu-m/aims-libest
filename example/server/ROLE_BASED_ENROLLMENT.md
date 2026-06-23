# Role-Based EST Certificate Enrollment Implementation

## Overview

This implementation adds **role-based certificate enrollment** to the Cisco libEST multi-tenant EST server. It enables:

- **Gateway devices** → Receive **clientAuth** certificates
- **FreeRADIUS servers** → Receive **serverAuth** certificates
- **Complete 802.1X integration** with proper certificate validation

## Architecture

### Components Added

1. **OpenSSL Configuration Files**
   - `client-auth.cnf` - Configuration for client certificates
   - `server-auth.cnf` - Configuration for server certificates

2. **Role-Based Enrollment Function**
   - `ossl_srv_role_based.c` - Implements role-aware signing with correct EKU extensions

3. **Multi-Tenant Header Update**
   - `est_multi_tenant.h` - Added `role` field to `TENANT_CLIENT` struct

4. **Client Configuration**
   - `tenants.json` - Updated with role definitions for each client

## How It Works

### 1. Bearer Token Format (Enhanced)

The Bearer token now includes the role:

```
Format: BASE64(tenant_id:client_id:password:role)
or
Format: tenant_id:client_id:password (role extracted from tenants.json)
```

**Example:**
```
Authorization: Bearer company-a:gateway-1:gateway_secret_001
```

During authentication:
1. Token is decoded
2. Client is looked up in tenants.json
3. Role is extracted from client configuration
4. Role is stored in tenant context for enrollment

### 2. Certificate Signing Flow

```
CSR Request
    ↓
Parse tenant_id:client_id:password
    ↓
Look up client in tenants.json
    ↓
Extract role ("client" or "server")
    ↓
Call ossl_role_based_enroll(csr, role)
    ↓
Load role-specific OpenSSL config:
    ├─ "client" → load client-auth.cnf
    ├─ "server" → load server-auth.cnf
    ↓
Apply role-specific extensions:
    ├─ clientAuth → extendedKeyUsage = clientAuth
    ├─ serverAuth → extendedKeyUsage = serverAuth
    ↓
Sign certificate with tenant's CA
    ↓
Return signed certificate in PKCS#7
```

### 3. Certificate EKU Verification

After enrollment, certificates are verified:

**Client Certificate (Gateway)**
```
X509v3 Extended Key Usage: 
    TLS Web Client Authentication ✅
```

**Server Certificate (FreeRADIUS)**
```
X509v3 Extended Key Usage: 
    TLS Web Server Authentication ✅
```

## Configuration

### tenants.json Format

Each tenant client now has a `role` field:

```json
{
  "tenant_id": "company-a",
  "clients": [
    {
      "client_id": "gateway-1",
      "password": "gateway_secret_001",
      "server_id": "company-a",
      "role": "client",  // ← NEW: Client role for clientAuth
      "description": "Gateway device"
    },
    {
      "client_id": "freeradius-1",
      "password": "freeradius_secret_001",
      "server_id": "company-a",
      "role": "server",  // ← NEW: Server role for serverAuth
      "description": "FreeRADIUS server"
    }
  ]
}
```

### Supported Roles

- `"client"` - Issues certificates with **clientAuth** EKU
  - Use for: Gateways, client devices, IoT sensors
  - Extensions: digitalSignature, keyEncipherment

- `"server"` - Issues certificates with **serverAuth** EKU
  - Use for: FreeRADIUS, authentication servers, RADIUS servers
  - Extensions: digitalSignature, keyEncipherment, dataEncipherment

## OpenSSL Configuration

### client-auth.cnf

Defines extensions for client certificates:

```ini
[client_cert]
basicConstraints       = CA:FALSE
keyUsage               = critical, digitalSignature, keyEncipherment
extendedKeyUsage       = critical, clientAuth
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always
```

### server-auth.cnf

Defines extensions for server certificates:

```ini
[server_cert]
basicConstraints       = CA:FALSE
keyUsage               = critical, digitalSignature, keyEncipherment, dataEncipherment
extendedKeyUsage       = critical, serverAuth
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always
```

## Usage Examples

### 1. Enroll Gateway (Client Certificate)

```bash
#!/bin/bash
TENANT="company-a"
CLIENT="gateway-1"
PASSWORD="gateway_secret_001"

# Create CSR
openssl req -new -keyout gateway-key.pem -out gateway.csr \
  -subj "/CN=gateway-1/O=company-a"

# Enroll via EST (role is looked up from tenants.json)
curl -X POST \
  --data-binary @gateway.csr \
  --cacert ca.pem \
  -H "Content-Type: application/pkcs10" \
  -H "Authorization: Bearer $(echo -n '${TENANT}:${CLIENT}:${PASSWORD}' | base64)" \
  https://est-server:8085/.well-known/est/simpleenroll \
  -o gateway-cert.p7m

# Verify certificate EKU
openssl pkcs7 -in gateway-cert.p7m -inform DER -print_certs -out gateway-cert.pem
openssl x509 -in gateway-cert.pem -text -noout | grep -A 1 "Extended Key Usage"
# Output: Extended Key Usage: TLS Web Client Authentication ✅
```

### 2. Enroll FreeRADIUS (Server Certificate)

```bash
#!/bin/bash
TENANT="company-a"
CLIENT="freeradius-1"
PASSWORD="freeradius_secret_001"

# Create CSR
openssl req -new -keyout freeradius-key.pem -out freeradius.csr \
  -subj "/CN=freeradius-1/O=company-a"

# Enroll via EST (role is looked up from tenants.json)
curl -X POST \
  --data-binary @freeradius.csr \
  --cacert ca.pem \
  -H "Content-Type: application/pkcs10" \
  -H "Authorization: Bearer $(echo -n '${TENANT}:${CLIENT}:${PASSWORD}' | base64)" \
  https://est-server:8085/.well-known/est/simpleenroll \
  -o freeradius-cert.p7m

# Verify certificate EKU
openssl pkcs7 -in freeradius-cert.p7m -inform DER -print_certs -out freeradius-cert.pem
openssl x509 -in freeradius-cert.pem -text -noout | grep -A 1 "Extended Key Usage"
# Output: Extended Key Usage: TLS Web Server Authentication ✅
```

## 802.1X Integration

### Complete Authentication Flow

```
┌─ Docker Container (EST Server)
│
├─ Step-CA / libEST (EST Server)
│  ├─ /cacerts endpoint → Returns CA chain
│  ├─ /simpleenroll endpoint → Signs certificates with role-specific EKU
│
├─ FreeRADIUS (Authentication Server)
│  └─ At startup:
│     ├─ Downloads CA certificates (/cacerts)
│     ├─ Enrolls server certificate (role: "server")
│     ├─ Verifies certificate has serverAuth EKU
│     └─ Configured to validate client certificates
│
├─ Hostapd (Authenticator)
│  └─ Relays authentication to FreeRADIUS
│
└─ Gateway (EST Client)
   └─ At startup:
      ├─ Downloads CA certificates (/cacerts)
      ├─ Enrolls client certificate (role: "client")
      ├─ Verifies certificate has clientAuth EKU
      └─ Connects to Hostapd/802.1X network
```

### 802.1X Authentication Sequence

```
1. Gateway → Hostapd: EAPOL-Start

2. Hostapd → FreeRADIUS: Access-Request
   (Includes gateway's client certificate)

3. FreeRADIUS Validates:
   ✓ Certificate signed by trusted CA
   ✓ EKU = clientAuth (not serverAuth)
   ✓ Certificate not expired
   ✓ CN matches allowed client

4. FreeRADIUS → Hostapd: Access-Accept

5. Hostapd → Gateway: EAPOL-Success

6. Gateway: Authenticated! ✅
```

## Files Modified/Created

```
example/server/
├─ client-auth.cnf          [NEW] OpenSSL config for client certs
├─ server-auth.cnf          [NEW] OpenSSL config for server certs
├─ ossl_srv_role_based.c    [NEW] Role-based enrollment implementation
├─ est_multi_tenant.h       [MODIFIED] Added role field
├─ tenants.json             [MODIFIED] Added role to clients
└─ estserver_multi_tenant_callbacks.c [REVIEW/UPDATE NEEDED]
   - May need to extract and pass role to enrollment
```

## Integration Steps

### Step 1: Update Callbacks
Modify `estserver_multi_tenant_callbacks.c` to:
- Extract role from tenant client config
- Pass role to enrollment function
- Use `ossl_role_based_enroll()` instead of `ossl_simple_enroll()`

### Step 2: Update Makefiles
Add `ossl_srv_role_based.c` to compilation:
```makefile
estserver_SOURCES = ... ossl_srv_role_based.c ...
```

### Step 3: Test Enrollment
```bash
./test-role-based-enroll.sh
```

Expected output:
```
[✓] Client certificate enrolled with clientAuth EKU
[✓] Server certificate enrolled with serverAuth EKU
[✓] FreeRADIUS validation: PASS
[✓] Gateway validation: PASS
[✓] 802.1X authentication: SUCCESS
```

## Verification

### Check Certificate Extensions

```bash
# View certificate details
openssl x509 -in certificate.pem -text -noout

# Look for:
# X509v3 Extended Key Usage: 
#     TLS Web Client Authentication (for role: "client")
# OR
#     TLS Web Server Authentication (for role: "server")
```

### Verify with FreeRADIUS

```bash
# FreeRADIUS validates with radiusd -X (verbose mode)
# Look for: Certificate verification: PASSED
```

## Troubleshooting

### Issue: Wrong EKU in Certificate

**Symptom:** Certificate has wrong Extended Key Usage

**Solution:**
1. Verify `tenants.json` has correct role for client
2. Check OpenSSL config files are present
3. Verify estExampleCA.cnf points to correct x509_extensions section

### Issue: FreeRADIUS Rejects Certificate

**Symptom:** "Certificate validation failed" in FreeRADIUS logs

**Causes:**
- Certificate signed by wrong CA
- Certificate has wrong EKU
- Certificate expired
- CA chain not trusted

**Solution:**
```bash
# Verify certificate CA
openssl verify -CAfile ca.pem cert.pem

# Check EKU
openssl x509 -in cert.pem -noout -text | grep -A 1 "Extended Key Usage"

# Check expiration
openssl x509 -in cert.pem -noout -dates
```

## Testing

### Unit Tests

```bash
# Compile with role-based enrollment
make clean
make estserver

# Run server
./estserver -p 8085

# Run test script
./test-role-based-enrollment.sh
```

### Integration Tests

```bash
# Complete 802.1X flow test
docker-compose up -d
./tests/test-802-1x-complete.sh
```

## Future Enhancements

1. **Additional Roles**
   - Could add "intermediate", "ca", "admin" roles

2. **Role Validation**
   - Validate role matches client type (device vs. server)

3. **Audit Logging**
   - Log all role-based enrollments for compliance

4. **Dynamic Role Assignment**
   - Allow role changes via API without restart

## References

- RFC 5280: Certificate Extensions and Attributes
  - Extended Key Usage (2.5.29.37)
  - OID 1.3.6.1.5.5.7.3.2 = clientAuth
  - OID 1.3.6.1.5.5.7.3.1 = serverAuth

- IEEE 802.1X: Port-Based Network Access Control

- Cisco libEST: https://github.com/cisco/libest
