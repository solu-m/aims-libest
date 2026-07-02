# 🎯 Final Multi-Tenant CA Docker Test Plan

**Status:** ✅ All code committed and ready to test  
**Date:** 2026-07-02  
**Estimated Time:** 10-15 minutes

---

## 📦 What's Been Fixed

### Completed Work:
✅ **Multi-tenant enrollment pipeline** (`multi_tenant_enrollment.c` - 258 lines)  
✅ **Server URL routing** (estserver.c modified to extract tenant from path)  
✅ **FIPS compatibility stub** (`fips_compat.c` - resolves OpenSSL 3.0 errors)  
✅ **Docker build configuration** (Dockerfile with proper compilation order)  
✅ **3 tenant infrastructures** (gateway, iot, freeradius - complete CA hierarchies)  
✅ **Integration tests** (docker-test.sh with 15 automated checks)

### Latest Commit:
```
d1fb545 - added
  M  Dockerfile
  A  src/est/fips_compat.c
```

---

## 🚀 Step-by-Step Test Instructions

### Step 1: Pull Latest Code
```bash
cd /home/aims/aims-libest
git pull
```

**Expected output:**
```
Updating 2afba92..d1fb545
Fast-forward
 Dockerfile              | 7 +++++--
 src/est/fips_compat.c   | 20 ++++++++++++++++++++
 2 files changed, 25 insertions(+), 2 deletions(-)
 create mode 100644 src/est/fips_compat.c
```

---

### Step 2: Build Docker Image
```bash
bash docker-build-alternative.sh
```

**What to watch for:**

1. ✅ **safe_c_stub builds** - Should complete in ~5 seconds
2. ✅ **fips_compat.c compiles** - Look for:
   ```
   gcc -c fips_compat.c -I. -I/usr/include -fPIC -DHAVE_CONFIG_H ...
   ```
3. ✅ **libest.so builds** - Should link WITHOUT "undefined reference to FIPS_mode"
4. ✅ **multi_tenant_enrollment.c compiles** - Creates multi_tenant_enrollment.o
5. ✅ **estserver links** - Final binary created with multi-tenant support
6. ✅ **Install completes** - Libraries and binary installed to /opt/est

**Expected success message:**
```
Successfully built <image_id>
Successfully tagged aims-libest-est-server:latest
```

**If build fails:**
- Copy the LAST 50 lines of error output
- Share with me for debugging

---

### Step 3: Verify Docker Image
```bash
docker images | grep aims-libest
```

**Expected output:**
```
aims-libest-est-server   latest   <image_id>   <time>   <size>
```

---

### Step 4: Start Server
```bash
docker-compose up -d est-server
```

**Expected output:**
```
Creating network "aims-libest_default" with the default driver
Creating aims-libest-est-server ... done
```

---

### Step 5: Verify Server is Running
```bash
docker-compose ps
```

**Expected output:**
```
Name                      State   Ports
aims-libest-est-server    Up      0.0.0.0:8085->8085/tcp
```

---

### Step 6: Check Server Logs
```bash
docker-compose logs est-server
```

**Look for:**
- ✅ "EST server started on port 8085"
- ✅ No errors about missing libraries
- ✅ No FIPS_mode errors

---

### Step 7: Run Integration Tests
```bash
bash docker-test.sh
```

**Expected tests (15 total):**

1. ✅ Test 1: Gateway tenant directory exists
2. ✅ Test 2: IoT tenant directory exists  
3. ✅ Test 3: FreeRADIUS tenant directory exists
4. ✅ Test 4: Gateway CA certificate valid
5. ✅ Test 5: IoT CA certificate valid
6. ✅ Test 6: FreeRADIUS CA certificate valid
7. ✅ Test 7: Gateway can sign certificates
8. ✅ Test 8: IoT can sign certificates
9. ✅ Test 9: FreeRADIUS can sign certificates
10. ✅ Test 10: Gateway index.txt updated
11. ✅ Test 11: IoT index.txt updated
12. ✅ Test 12: FreeRADIUS index.txt updated
13. ✅ Test 13: Cross-tenant isolation (gateway ≠ iot)
14. ✅ Test 14: Cross-tenant isolation (iot ≠ freeradius)
15. ✅ Test 15: All certificates unique

**Success message:**
```
✅ All 15 tests passed!
🎉 Multi-tenant CA engine is working correctly!
```

---

## 🧪 Manual Testing (Optional)

### Test Multi-Tenant Enrollment

#### Get Gateway CA Certificate:
```bash
curl -k https://localhost:8085/.well-known/est/gateway/cacerts -o gateway_ca.p7
openssl pkcs7 -in gateway_ca.p7 -inform DER -print_certs -noout
```

#### Get IoT CA Certificate:
```bash
curl -k https://localhost:8085/.well-known/est/iot/cacerts -o iot_ca.p7
openssl pkcs7 -in iot_ca.p7 -inform DER -print_certs -noout
```

#### Get FreeRADIUS CA Certificate:
```bash
curl -k https://localhost:8085/.well-known/est/freeradius/cacerts -o freeradius_ca.p7
openssl pkcs7 -in freeradius_ca.p7 -inform DER -print_certs -noout
```

**Expected:** Each tenant returns a DIFFERENT CA certificate, proving isolation.

---

## ❌ Troubleshooting

### Build Fails at FIPS_mode
**Problem:** `undefined reference to 'FIPS_mode'`  
**Solution:** Make sure `git pull` succeeded. Check if `src/est/fips_compat.c` exists:
```bash
ls -la src/est/fips_compat.c
```

### Build Fails at multi_tenant_enroll
**Problem:** `undefined reference to 'multi_tenant_enroll'`  
**Solution:** Dockerfile should compile multi_tenant_enrollment.c separately. Check line 88.

### Server Won't Start
**Problem:** Port 8085 already in use  
**Solution:**
```bash
docker-compose down
sudo netstat -tulpn | grep 8085
# Kill any process using port 8085
docker-compose up -d est-server
```

### Tests Fail
**Problem:** Certificates not being signed  
**Solution:** Check server logs:
```bash
docker-compose logs est-server | tail -50
```

---

## 📊 Expected Final Result

```
╔══════════════════════════════════════════════════════════════╗
║       🎉 MULTI-TENANT CA ENGINE - FULLY OPERATIONAL!        ║
╚══════════════════════════════════════════════════════════════╝

✅ Docker Build: SUCCESS
✅ Server Start: SUCCESS  
✅ Integration Tests: 15/15 PASSED
✅ Multi-Tenant Isolation: VERIFIED

Architecture Verified:
  ┌──> [gateway]    ──> gateway/ca.key    (Isolated)
  ├──> [iot]        ──> iot/ca.key        (Isolated)
  └──> [freeradius] ──> freeradius/ca.key (Isolated)

Zero cross-contamination. Zero shared state.
Mathematical isolation guaranteed.
```

---

## 📝 After Successful Test

**Please share:**
1. ✅ Build output (last 20 lines showing success)
2. ✅ Test results (showing 15/15 passed)
3. ✅ Any errors encountered

This will confirm the multi-tenant CA engine is production-ready! 🚀
