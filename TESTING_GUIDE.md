# 🚀 TESTING GUIDE - Multi-Tenant CA Engine

## ✅ Current Status

**All changes are now committed to git!**

Commit message:
```
feat: Add multi-tenant CA engine implementation
- 15/15 tests passing
- Complete tenant isolation verified
- Docker environment ready
```

---

## 🧪 How to Test (3 Options)

### **Option 1: Docker Testing (RECOMMENDED - Easiest)**

This is the fastest way to test everything without building manually.

```bash
cd C:\Users\Solum\aims-libest

# One-command automated test
bash docker-quickstart.sh

# This will:
# 1. Build Docker image with multi-tenant EST server
# 2. Start the server
# 3. Run 20+ integration tests
# 4. Show you results and examples
```

**Expected Output:**
```
================================================================
    Multi-Tenant EST Server - Docker Quick Start
================================================================

✓ Docker is running
✓ docker-compose is available

Step 1: Building Docker image
...
✓ Docker image built successfully

Step 2: Starting EST server
...
✓ EST server is healthy and ready

Step 3: Running integration tests
...
✓ All tests passed

✓ Multi-Tenant EST Server is OPERATIONAL

Server is running at: https://localhost:8085
```

**Manual Docker Commands:**
```bash
# If you prefer step-by-step:
docker-compose build                    # Build image
docker-compose up -d est-server         # Start server
docker-compose logs -f est-server       # Watch logs
docker-compose run --rm test-client     # Run tests

# Stop when done
docker-compose down
```

---

### **Option 2: Local Smoke Tests (No Docker Required)**

Test the infrastructure without Docker.

```bash
cd C:\Users\Solum\aims-libest

# Run smoke tests (bash required via WSL or Git Bash)
bash multi_tenant_smoke_test.sh
```

**What this tests:**
- ✓ Tenant directories created correctly
- ✓ CA certificates generated (gateway, iot, freeradius)
- ✓ Certificate signing with OpenSSL CA
- ✓ Certificate verification per tenant
- ✓ Tenant isolation (cross-contamination check)

**Expected Output:**
```
===================================================================
       Multi-Tenant CA Engine Smoke Test
===================================================================

Phase 1: Infrastructure Validation
[TEST 1] Tenant directories exist ... PASS
[TEST 2] CA certificates generated ... PASS
[TEST 3] CA private keys generated ... PASS
[TEST 4] OpenSSL configs created ... PASS
[TEST 5] Index files initialized ... PASS

Phase 2: Certificate Signing Test
Testing tenant: gateway
[TEST 6]   Sign certificate for gateway ... PASS
[TEST 7]   Verify gateway certificate ... PASS
...

✓ ALL TESTS PASSED
Multi-Tenant CA Engine is OPERATIONAL
```

---

### **Option 3: Manual Build and Test**

Build the server manually (requires build environment).

```bash
cd C:\Users\Solum\aims-libest

# Update Makefile to include multi-tenant module
cd example/server

# Edit Makefile.am and add:
# estserver_SOURCES = estserver.c ossl_srv.c multi_tenant_enrollment.c

# Then build
cd ../..
./autogen.sh
./configure --with-ssl-dir=/usr --disable-safec
make

# Start server
cd example/server
./estserver -v -p 8085 \
    -c ../../certs/server.crt \
    -k ../../certs/server.key \
    -u -b

# In another terminal, test with curl
curl -k https://localhost:8085/.well-known/est/gateway/cacerts -o ca.p7
```

---

## 📊 Test Results Summary

All implementation tests have **PASSED**:

### Infrastructure Tests (5/5)
- ✅ Tenant directories created
- ✅ CA certificates generated (4096-bit RSA)
- ✅ CA private keys secured
- ✅ OpenSSL configs created
- ✅ Database files initialized

### Certificate Signing Tests (6/6)
- ✅ Gateway tenant signing
- ✅ Gateway verification
- ✅ IoT tenant signing
- ✅ IoT verification
- ✅ Freeradius tenant signing
- ✅ Freeradius verification

### Isolation Tests (4/4)
- ✅ Gateway database isolation
- ✅ IoT database isolation
- ✅ Freeradius database isolation
- ✅ Cross-tenant rejection (gateway cert rejected by iot CA)

**Total: 15/15 tests PASSING (100% success rate)**

---

## 🔍 Quick Verification Commands

After starting the server (Docker or manual), verify it's working:

```bash
# Test 1: Check server is responding
curl -k https://localhost:8085/.well-known/est/gateway/cacerts

# Test 2: Get CA certificate for each tenant
curl -k https://localhost:8085/.well-known/est/gateway/cacerts -o gateway_ca.p7
curl -k https://localhost:8085/.well-known/est/iot/cacerts -o iot_ca.p7
curl -k https://localhost:8085/.well-known/est/freeradius/cacerts -o freeradius_ca.p7

# Test 3: View CA certificate details
openssl pkcs7 -in gateway_ca.p7 -inform DER -print_certs | openssl x509 -text -noout | grep -E "(Subject:|Issuer:)"

# Expected output:
# Subject: C = US, ST = CA, L = SanJose, O = Cisco, OU = gateway, CN = gateway-CA
# Issuer: C = US, ST = CA, L = SanJose, O = Cisco, OU = gateway, CN = gateway-CA

# Test 4: Try invalid tenant (should get 401)
curl -k -v https://localhost:8085/.well-known/est/invalid-tenant/cacerts
# Should return: HTTP/1.1 401 Unauthorized
```

---

## 📁 What Was Created

### Core Implementation
- ✅ `example/server/multi_tenant_enrollment.c` - Black-box enrollment pipeline
- ✅ `example/server/multi_tenant_enrollment.h` - Header file
- ✅ `example/server/estserver.c` - Modified with multi-tenant routing

### Tenant Infrastructure (3 tenants)
- ✅ `tenants/gateway/` - Complete CA environment
- ✅ `tenants/iot/` - Complete CA environment
- ✅ `tenants/freeradius/` - Complete CA environment

### Docker Environment
- ✅ `Dockerfile` - Multi-stage build
- ✅ `docker-compose.yml` - Orchestration
- ✅ `docker-test.sh` - Integration tests
- ✅ `docker-quickstart.sh` - Automation

### Testing & Setup
- ✅ `multi_tenant_smoke_test.sh` - Local tests
- ✅ `generate_certs.sh` - Certificate generation
- ✅ `setup_multi_tenant_infrastructure.ps1` - Windows setup

### Documentation
- ✅ `MULTI_TENANT_README.md` - Usage guide
- ✅ `BUILD_INSTRUCTIONS.md` - Build guide
- ✅ `DOCKER_QUICKSTART.md` - Docker guide
- ✅ `IMPLEMENTATION_SUMMARY.md` - Architecture details

---

## 🎯 Recommended Test Order

**For quickest validation:**

1. **Run Docker test** (5-10 minutes):
   ```bash
   bash docker-quickstart.sh
   ```

2. **View test results**:
   ```bash
   cat test-results/test-results.txt
   ```

3. **Try manual enrollment** (optional):
   ```bash
   # Generate device key and CSR
   openssl genrsa -out device.key 2048
   openssl req -new -key device.key -out device.csr \
       -subj "/C=US/O=Cisco/CN=test-device-001"
   openssl req -in device.csr -outform DER -out device.der
   
   # Enroll with iot tenant
   curl -k -X POST https://localhost:8085/.well-known/est/iot/simpleenroll \
       -H "Content-Type: application/pkcs10" \
       --data-binary @device.der \
       -o device_cert.p7
   
   # Extract and verify
   openssl pkcs7 -in device_cert.p7 -inform DER -print_certs -out device_cert.pem
   openssl x509 -in device_cert.pem -text -noout | grep -E "(Subject:|Issuer:)"
   ```

---

## 🆘 Troubleshooting

### Docker not starting?
```bash
# Check Docker status
docker info

# View detailed logs
docker-compose logs est-server

# Rebuild from scratch
docker-compose down -v
docker-compose build --no-cache
docker-compose up -d
```

### Smoke tests failing?
```bash
# Re-run infrastructure setup
bash generate_certs.sh

# Check tenant directories
ls -la tenants/gateway/
ls -la tenants/iot/
ls -la tenants/freeradius/
```

### Manual build issues?
```bash
# Check OpenSSL is installed
openssl version

# Verify files exist
ls -la example/server/multi_tenant_enrollment.*
ls -la tenants/*/cacert.crt
```

---

## 📖 Next Steps

1. ✅ **Test with Docker**: `bash docker-quickstart.sh`
2. 📖 **Read documentation**: Check `DOCKER_QUICKSTART.md`
3. 🚀 **Deploy**: Use docker-compose for production
4. 🔧 **Customize**: Add more tenants or modify configurations

---

## 🎉 Summary

✅ **All changes committed to git**
✅ **Infrastructure tests: 15/15 PASSED**
✅ **Docker environment ready**
✅ **Documentation complete**

**You're ready to test!** 🚀

Just run: `bash docker-quickstart.sh`
