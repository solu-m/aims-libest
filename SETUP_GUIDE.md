# Multi-Tenant EST CA - Step-by-Step Setup & Testing Guide

**Complete guide to deploy and test the Multi-Tenant Certificate Authority from scratch.**

---

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [Deployment](#deployment)
4. [Verification](#verification)
5. [Create Your First Tenant](#create-your-first-tenant)
6. [Test Certificate Enrollment](#test-certificate-enrollment)
7. [Advanced Testing](#advanced-testing)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Software

Before starting, ensure you have:

- **Operating System:** Ubuntu 20.04+ or similar Linux distribution
- **Docker:** Version 20.10+
- **Docker Compose:** Version 2.0+
- **Git:** Any recent version
- **OpenSSL:** Pre-installed on most Linux systems

### Check Prerequisites

```bash
# Check Docker
docker --version
# Expected: Docker version 20.10.0 or higher

# Check Docker Compose
docker compose version
# Expected: Docker Compose version v2.0.0 or higher

# Check Git
git --version
# Expected: git version 2.x.x

# Check OpenSSL
openssl version
# Expected: OpenSSL 1.1.1 or higher
```

### Install Prerequisites (if needed)

```bash
# Update package list
sudo apt-get update

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose (if not included with Docker)
sudo apt-get install docker-compose-plugin

# Install Git (if needed)
sudo apt-get install git

# Log out and back in for group changes to take effect
```

---

## Initial Setup

### Step 1: Clone the Repository

```bash
# Navigate to your preferred directory
cd ~

# Clone the repository
git clone https://github.com/solu-m/aims-libest.git

# Navigate into the repository
cd aims-libest

# Checkout the dynamic tenant branch
git checkout feature/dynamic-tenant-api

# Verify you're on the correct branch
git branch
# Should show: * feature/dynamic-tenant-api
```

### Step 2: Review the Configuration

```bash
# View the docker-compose configuration
cat docker-compose.dynamic.yml

# Note the default admin API key (you should change this!)
# Look for: ADMIN_API_KEY=your-secret-key-here
```

### Step 3: (Optional) Change Default Credentials

**For production, change these values!**

```bash
# Edit docker-compose.dynamic.yml
nano docker-compose.dynamic.yml

# Find and change:
# - ADMIN_API_KEY (line ~74)
# Default: your-secret-key-here
# Change to: your-actual-secure-key

# Save and exit: Ctrl+X, Y, Enter
```

---

## Deployment

### Step 4: Build and Start Services

```bash
# Build all Docker images (first time only, takes 5-10 minutes)
docker compose -f docker-compose.dynamic.yml build

# Start all services in detached mode
docker compose -f docker-compose.dynamic.yml up -d

# Watch services start up
docker compose -f docker-compose.dynamic.yml logs -f
# Press Ctrl+C when you see services are ready
```

**What's happening:**
- Building EST server from C source code
- Building Python Admin API
- Setting up nginx gateway
- Creating three static tenants (gateway, iot, freeradius)

### Step 5: Verify Services Are Running

```bash
# Check service status
docker compose -f docker-compose.dynamic.yml ps

# Expected output (all "Up"):
# NAME                  STATUS
# admin-api             Up (healthy)
# est-gateway           Up (healthy)
# est-server-backend    Up (healthy)
```

If any service shows "unhealthy" or "Exited", check logs:

```bash
docker compose -f docker-compose.dynamic.yml logs SERVICE_NAME
```

---

## Verification

### Step 6: Test Gateway Connectivity

```bash
# Test HTTPS gateway is responding
curl -k -I https://localhost:8085/.well-known/est/gateway/cacerts

# Expected: HTTP/1.1 200 OK
```

### Step 7: Test Admin API Health

```bash
# Check admin API health endpoint
curl -k https://localhost:8085/admin/health

# Expected: {"status":"healthy"}
```

### Step 8: Retrieve CA Certificate (Static Tenant)

```bash
# Get the gateway tenant CA certificate
curl -k https://localhost:8085/.well-known/est/gateway/cacerts \
  --output gateway-ca.p7

# Check file size (should be ~1.5KB)
ls -lh gateway-ca.p7

# Verify it's a valid PKCS7 bundle
openssl pkcs7 -in gateway-ca.p7 -inform DER -print_certs -noout

# Expected: No errors, shows certificate info
```

✅ **Checkpoint:** If you got here successfully, your EST server is working!

---

## Create Your First Tenant

### Step 9: List Existing Tenants

```bash
# List all tenants via Admin API
curl -k https://localhost:8085/admin/tenants \
  -H "Authorization: Bearer your-secret-key-here" | jq

# Expected: JSON array showing 3 static tenants (gateway, iot, freeradius)
```

**Note:** Replace `your-secret-key-here` with your actual API key if you changed it.

### Step 10: Create a New Tenant

```bash
# Create a tenant called "production"
curl -k -X POST https://localhost:8085/admin/tenants \
  -H "Authorization: Bearer your-secret-key-here" \
  -H "Content-Type: application/json" \
  -d '{
    "tenant_id": "production",
    "display_name": "Production Environment",
    "ca_config": {
      "common_name": "production-CA",
      "country": "US",
      "state": "CA",
      "locality": "SanJose",
      "organization": "MyCompany",
      "organizational_unit": "Production",
      "key_size": 4096,
      "validity_days": 3650
    },
    "cert_policy": {
      "default_validity_days": 365
    },
    "auth_config": {
      "allowed_users": ["produser"]
    }
  }' | jq

# Expected: JSON response with "status": "success"
```

**What happened:**
- Created a new CA with 4096-bit RSA key
- Generated self-signed CA certificate (valid 10 years)
- Set up OpenSSL configuration
- Initialized certificate database
- Registered tenant in SQLite registry

### Step 11: Verify Tenant Creation

```bash
# List tenants again
curl -k https://localhost:8085/admin/tenants \
  -H "Authorization: Bearer your-secret-key-here" | jq

# Expected: Now shows 4 tenants (including "production")

# Get production tenant CA certificate
curl -k https://localhost:8085/.well-known/est/production/cacerts \
  --output production-ca.p7

# Check size
ls -lh production-ca.p7
# Expected: ~1.5KB

# Verify certificate
openssl pkcs7 -in production-ca.p7 -inform DER -print_certs -text | grep "Subject:"
# Expected: Shows "CN = production-CA"
```

✅ **Checkpoint:** Dynamic tenant creation works!

---

## Test Certificate Enrollment

### Step 12: Generate Device Credentials

```bash
# Create a directory for test files
mkdir -p ~/est-test
cd ~/est-test

# Generate device private key
openssl genrsa -out device.key 2048

# Expected: Generating RSA private key...

# Create Certificate Signing Request (CSR)
openssl req -new -key device.key -out device.csr \
  -subj "/CN=my-device-001/C=US/ST=CA/O=MyCompany/OU=Production"

# Verify CSR was created
ls -lh device.csr
# Expected: ~1KB file

# View CSR details
openssl req -in device.csr -text -noout | head -20
# Expected: Shows device details
```

### Step 13: Convert CSR to EST Format

**EST protocol requires base64-encoded DER format:**

```bash
# Convert PEM CSR to DER format, then base64 encode
openssl req -in device.csr -outform DER | base64 > device.b64

# Verify base64 file
ls -lh device.b64
# Expected: ~900 bytes

# Check it starts with base64 characters
head -c 40 device.b64
# Expected: MIICn... (base64 text)
```

### Step 14: Enroll Device with Production Tenant

```bash
# Enroll device with EST server
curl -k -u estuser:estpwd \
  -H "Content-Type: application/pkcs10" \
  -H "Content-Transfer-Encoding: base64" \
  --data-binary @device.b64 \
  https://localhost:8085/.well-known/est/production/simpleenroll \
  -o device-cert.p7

# Check certificate size
ls -lh device-cert.p7
# Expected: ~2-3KB (PKCS7 bundle with device cert + CA cert)

# If you see only 60-100 bytes, there was an error
# Check: cat device-cert.p7
```

### Step 15: Extract and Verify Certificate

```bash
# Extract certificates from PKCS7 bundle
openssl pkcs7 -in device-cert.p7 -inform DER -print_certs -out device-cert.pem

# View device certificate subject
openssl x509 -in device-cert.pem -text -noout | grep -A2 "Subject:"

# Expected output:
# Subject: CN = my-device-001, C = US, ST = CA, O = MyCompany, OU = Production
# Issuer: C = US, ST = CA, L = SanJose, O = MyCompany, OU = Production, CN = production-CA

# Verify the certificate chain
openssl pkcs7 -in production-ca.p7 -inform DER -print_certs -out production-ca-chain.pem
openssl verify -CAfile production-ca-chain.pem device-cert.pem

# Expected: device-cert.pem: OK
```

✅ **Checkpoint:** Certificate enrollment works end-to-end!

---

## Advanced Testing

### Step 16: Test Multiple Tenants

```bash
# Create another tenant
curl -k -X POST https://localhost:8085/admin/tenants \
  -H "Authorization: Bearer your-secret-key-here" \
  -H "Content-Type: application/json" \
  -d '{
    "tenant_id": "testing",
    "display_name": "Testing Environment",
    "ca_config": {
      "common_name": "testing-CA",
      "country": "US",
      "organization": "MyCompany"
    }
  }' | jq

# Generate another device key
openssl genrsa -out test-device.key 2048

# Create CSR
openssl req -new -key test-device.key -out test-device.csr \
  -subj "/CN=test-device-001/C=US/O=MyCompany"

# Convert and enroll with TESTING tenant
openssl req -in test-device.csr -outform DER | base64 > test-device.b64

curl -k -u estuser:estpwd \
  -H "Content-Type: application/pkcs10" \
  -H "Content-Transfer-Encoding: base64" \
  --data-binary @test-device.b64 \
  https://localhost:8085/.well-known/est/testing/simpleenroll \
  -o test-device-cert.p7

# Verify different CA signed it
openssl pkcs7 -in test-device-cert.p7 -inform DER -print_certs -text | grep "Issuer:"
# Expected: Should show "testing-CA", NOT "production-CA"
```

### Step 17: Test Tenant Isolation

```bash
# Get CA certs from both tenants
curl -k https://localhost:8085/.well-known/est/production/cacerts \
  -o prod-ca.p7
  
curl -k https://localhost:8085/.well-known/est/testing/cacerts \
  -o test-ca.p7

# Convert to PEM
openssl pkcs7 -in prod-ca.p7 -inform DER -print_certs -out prod-ca.pem
openssl pkcs7 -in test-ca.p7 -inform DER -print_certs -out test-ca.pem

# Try to verify production device cert with testing CA (should FAIL)
openssl verify -CAfile test-ca.pem device-cert.pem
# Expected: error... verification failed

# Verify with correct CA (should PASS)
openssl verify -CAfile prod-ca.pem device-cert.pem
# Expected: device-cert.pem: OK
```

✅ **Success:** Tenant isolation is working correctly!

### Step 18: View Tenant Statistics

```bash
# Get detailed tenant information
curl -k https://localhost:8085/admin/tenants \
  -H "Authorization: Bearer your-secret-key-here" | jq

# Each tenant shows:
# - tenant_id
# - display_name
# - status
# - ca_subject
# - certificates_issued
# - created_at
# - last_enrollment
```

---

## Troubleshooting

### Issue: Services Won't Start

**Symptom:** `docker compose ps` shows services as "Exited" or "Unhealthy"

**Solution:**
```bash
# Check logs
docker compose -f docker-compose.dynamic.yml logs

# Common causes:
# 1. Port 8085 already in use
sudo lsof -i :8085
# Kill the process using that port

# 2. Rebuild containers
docker compose -f docker-compose.dynamic.yml down
docker compose -f docker-compose.dynamic.yml build --no-cache
docker compose -f docker-compose.dynamic.yml up -d
```

### Issue: API Returns "Invalid API key"

**Symptom:** Admin API calls fail with 401 error

**Solution:**
```bash
# Check what key is configured
docker exec admin-api env | grep ADMIN_API_KEY

# Use the correct key in your curl commands
# Default: your-secret-key-here
```

### Issue: Enrollment Returns 500 Error

**Symptom:** `device-cert.p7` contains error message, not certificate

**Solution:**
```bash
# Check EST server logs
docker logs est-server-backend 2>&1 | tail -50

# Common causes:
# 1. CSR format incorrect
#    - Must be: PEM -> DER -> base64
#    - Use: openssl req -in X.csr -outform DER | base64 > X.b64

# 2. Permission issues (rare with new setup)
docker exec -u root est-server-backend \
  chown -R estuser:estuser /opt/est/tenants/TENANT_ID/
```

### Issue: Certificate File is Too Small (<100 bytes)

**Symptom:** `device-cert.p7` is only 60-100 bytes

**Solution:**
```bash
# Check what the file contains
cat device-cert.p7

# If it's an error message, check logs
docker logs est-server-backend 2>&1 | grep ERROR

# Verify CSR is valid
openssl req -in device.csr -text -noout

# Ensure base64 encoding is correct
file device.b64
# Should show: ASCII text
```

### Issue: Can't Connect to Gateway

**Symptom:** `curl: (7) Failed to connect to localhost port 8085`

**Solution:**
```bash
# Check if gateway is running
docker ps | grep est-gateway

# Check if port is bound
sudo netstat -tulpn | grep 8085

# Restart gateway
docker compose -f docker-compose.dynamic.yml restart est-gateway
```

---

## Testing Checklist

Use this checklist to verify your deployment:

- [ ] All 3 services show "Up (healthy)"
- [ ] Gateway responds to HTTPS on port 8085
- [ ] Admin API health check returns OK
- [ ] Can list existing tenants via API
- [ ] Can create new tenant via API
- [ ] New tenant CA certificate retrieves successfully (~1.5KB)
- [ ] Can generate device CSR
- [ ] Can enroll device and get certificate (~2-3KB)
- [ ] Device certificate signed by correct tenant CA
- [ ] Cross-tenant verification fails (isolation working)
- [ ] Tenant statistics update correctly

---

## Quick Reference

### Common Commands

```bash
# View logs
docker compose -f docker-compose.dynamic.yml logs -f

# Restart services
docker compose -f docker-compose.dynamic.yml restart

# Stop services
docker compose -f docker-compose.dynamic.yml down

# Start services
docker compose -f docker-compose.dynamic.yml up -d

# Rebuild and restart
docker compose -f docker-compose.dynamic.yml down
docker compose -f docker-compose.dynamic.yml build --no-cache
docker compose -f docker-compose.dynamic.yml up -d
```

### Test Data Cleanup

```bash
# Remove test certificates and keys
cd ~/est-test
rm -f *.key *.csr *.crt *.pem *.p7 *.der *.b64

# Or remove entire test directory
rm -rf ~/est-test
```

---

## Next Steps

Once you've verified everything works:

1. **Change default credentials** in `docker-compose.dynamic.yml`
2. **Replace self-signed certificates** with proper SSL certs
3. **Set up monitoring** and log aggregation
4. **Configure backups** for Docker volumes
5. **Review security hardening** in README.md
6. **Deploy to production** environment

---

## Success!

If you've completed all steps successfully, you now have:

- ✅ Fully operational Multi-Tenant EST CA
- ✅ REST API for dynamic tenant management
- ✅ Working certificate enrollment pipeline
- ✅ Verified tenant isolation
- ✅ Production-ready deployment

**Congratulations!** 🎉

For more details, see:
- **README.md** - Complete documentation
- **DYNAMIC_TENANT_API.md** - Full API reference

---

**Need Help?**

Check logs: `docker compose -f docker-compose.dynamic.yml logs`

Review this guide from the beginning - most issues are covered in troubleshooting.
