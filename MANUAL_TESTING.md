# Multi-Tenant EST Server - Manual Testing Guide

This guide provides simple copy-paste commands to test the multi-tenant EST server.

## Prerequisites

Ensure the Docker container is running:
```bash
docker compose up -d
docker ps  # Should show multi-tenant-est-server running
```

---

## Test 1: Server Connectivity

Check if the HTTPS server is responding:

```bash
curl -k -I https://localhost:8085/.well-known/est/gateway/cacerts
```

**Expected:** HTTP status line showing `200 OK` or `HTTP/1.1 200`

---

## Test 2: Retrieve CA Certificates for Each Tenant

### Gateway Tenant
```bash
curl -k -o gateway-ca.p7 https://localhost:8085/.well-known/est/gateway/cacerts
openssl pkcs7 -inform DER -in gateway-ca.p7 -print_certs -text | grep "Subject:"
```

**Expected:** Should show `CN = gateway-CA`

### IoT Tenant
```bash
curl -k -o iot-ca.p7 https://localhost:8085/.well-known/est/iot/cacerts
openssl pkcs7 -inform DER -in iot-ca.p7 -print_certs -text | grep "Subject:"
```

**Expected:** Should show `CN = iot-CA`

### FreeRADIUS Tenant
```bash
curl -k -o freeradius-ca.p7 https://localhost:8085/.well-known/est/freeradius/cacerts
openssl pkcs7 -inform DER -in freeradius-ca.p7 -print_certs -text | grep "Subject:"
```

**Expected:** Should show `CN = freeradius-CA`

---

## Test 3: Enroll a Device Certificate

### Step 1: Generate a Private Key and CSR
```bash
# Generate private key
openssl genrsa -out device.key 2048

# Generate Certificate Signing Request (CSR)
openssl req -new -key device.key -out device.csr \
  -subj "/CN=my-test-device/C=US/ST=CA/L=SanJose/O=Cisco/OU=Testing"
```

### Step 2: Enroll with Gateway Tenant
```bash
# Convert CSR to base64-encoded DER format (required by EST protocol)
openssl req -in device.csr -outform DER | base64 > device.b64

# Send enrollment request (requires authentication: estuser/estpwd)
curl -k -v -u estuser:estpwd \
  -H "Content-Type: application/pkcs10" \
  -H "Content-Transfer-Encoding: base64" \
  --data-binary @device.b64 \
  https://localhost:8085/.well-known/est/gateway/simpleenroll \
  -o device-cert.p7
```

**Expected:** Server returns a PKCS7 file containing the signed certificate

### Step 3: Extract and Verify the Certificate
```bash
# Extract certificate from PKCS7 response
openssl pkcs7 -inform DER -in device-cert.p7 -print_certs -out device-cert.pem

# View certificate details
openssl x509 -in device-cert.pem -text -noout | grep -A2 "Subject:"

# Verify it was signed by gateway CA
openssl pkcs7 -inform DER -in gateway-ca.p7 -print_certs -out gateway-ca.pem
openssl verify -CAfile gateway-ca.pem device-cert.pem
```

**Expected:** 
- Subject should show `CN = my-test-device`
- Issuer should show `CN = gateway-CA`
- Verification should show `device-cert.pem: OK`

---

## Test 4: Enroll with Different Tenants

### Enroll with IoT Tenant
```bash
# Generate new CSR for IoT device
openssl req -new -key device.key -out iot-device.csr \
  -subj "/CN=iot-sensor-001/C=US/ST=CA/L=SanJose/O=Cisco/OU=IoT"

# Convert and enroll
openssl req -in iot-device.csr -outform DER | base64 > iot-device.b64

curl -k -u estuser:estpwd \
  -H "Content-Type: application/pkcs10" \
  -H "Content-Transfer-Encoding: base64" \
  --data-binary @iot-device.b64 \
  https://localhost:8085/.well-known/est/iot/simpleenroll \
  -o iot-device-cert.p7

# Extract and verify
openssl pkcs7 -inform DER -in iot-device-cert.p7 -print_certs -out iot-device-cert.pem
openssl pkcs7 -inform DER -in iot-ca.p7 -print_certs -out iot-ca.pem
openssl verify -CAfile iot-ca.pem iot-device-cert.pem
```

**Expected:** Certificate issued by `iot-CA`

### Enroll with FreeRADIUS Tenant
```bash
# Generate new CSR for FreeRADIUS client
openssl req -new -key device.key -out radius-device.csr \
  -subj "/CN=radius-client-001/C=US/ST=CA/L=SanJose/O=Cisco/OU=FreeRADIUS"

# Convert and enroll
openssl req -in radius-device.csr -outform DER | base64 > radius-device.b64

curl -k -u estuser:estpwd \
  -H "Content-Type: application/pkcs10" \
  -H "Content-Transfer-Encoding: base64" \
  --data-binary @radius-device.b64 \
  https://localhost:8085/.well-known/est/freeradius/simpleenroll \
  -o radius-device-cert.p7

# Extract and verify
openssl pkcs7 -inform DER -in radius-device-cert.p7 -print_certs -out radius-device-cert.pem
openssl pkcs7 -inform DER -in freeradius-ca.p7 -print_certs -out freeradius-ca.pem
openssl verify -CAfile freeradius-ca.pem radius-device-cert.pem
```

**Expected:** Certificate issued by `freeradius-CA`

---

## Test 5: Tenant Isolation (Cross-Validation Should Fail)

Verify that a certificate from one tenant **cannot** be validated by another tenant's CA:

```bash
# Try to verify gateway device cert with iot CA (should FAIL)
openssl verify -CAfile iot-ca.pem device-cert.pem
```

**Expected:** `device-cert.pem: verification failed` - This proves tenant isolation!

```bash
# Try to verify iot device cert with gateway CA (should FAIL)
openssl verify -CAfile gateway-ca.pem iot-device-cert.pem
```

**Expected:** `iot-device-cert.pem: verification failed`

---

## Test 6: Invalid Tenant Rejection

Test that invalid/non-existent tenants return proper error:

```bash
curl -k -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  https://localhost:8085/.well-known/est/invalid-tenant/cacerts
```

**Expected:** `HTTP Status: 204` (No Content - tenant doesn't exist)

---

## Test 7: Check Server Logs

View what's happening on the server side:

```bash
# View last 50 log lines
docker logs multi-tenant-est-server --tail 50

# Follow logs in real-time
docker logs multi-tenant-est-server -f

# Search for enrollment activity
docker logs multi-tenant-est-server 2>&1 | grep "Multi-tenant enrollment"
```

---

## Test 8: Inspect Tenant Data

Check the tenant directories and certificate databases:

```bash
# View gateway tenant database
docker exec multi-tenant-est-server cat /opt/est/tenants/gateway/index.txt

# View gateway serial number
docker exec multi-tenant-est-server cat /opt/est/tenants/gateway/serial

# List all issued certificates
docker exec multi-tenant-est-server ls -lh /opt/est/tenants/gateway/newcerts/

# View CA certificate
docker exec multi-tenant-est-server openssl x509 -in /opt/est/tenants/gateway/cacert.crt -text -noout
```

---

## Cleanup

Remove test files:
```bash
rm -f *.key *.csr *.b64 *.p7 *.pem
```

Stop and remove containers:
```bash
docker compose down
```

Remove volumes (resets all tenant data):
```bash
docker compose down -v
```

---

## Quick Test Summary

**One-liner to test all three tenants:**
```bash
for tenant in gateway iot freeradius; do
  echo "=== Testing $tenant ==="
  curl -k -s https://localhost:8085/.well-known/est/$tenant/cacerts | \
    openssl pkcs7 -inform DER -print_certs -text | grep "Subject:" | head -1
done
```

**Expected Output:**
```
=== Testing gateway ===
        Subject: C = US, ST = CA, L = SanJose, O = Cisco, OU = gateway, CN = gateway-CA
=== Testing iot ===
        Subject: C = US, ST = CA, L = SanJose, O = Cisco, OU = iot, CN = iot-CA
=== Testing freeradius ===
        Subject: C = US, ST = CA, L = SanJose, O = Cisco, OU = freeradius, CN = freeradius-CA
```

---

## Common Issues

### Issue: "curl: (7) Failed to connect"
**Solution:** Ensure server is running: `docker compose up -d`

### Issue: "unable to load PKCS7 object"
**Solution:** The enrollment failed. Check server logs: `docker logs multi-tenant-est-server --tail 30`

### Issue: "Serial number XX has already been issued"
**Solution:** Reset tenant database:
```bash
docker exec multi-tenant-est-server bash -c "
  echo '02' > /opt/est/tenants/gateway/serial
  truncate -s 0 /opt/est/tenants/gateway/index.txt
"
```

### Issue: "HTTP 401 Unauthorized"
**Solution:** Add authentication: `-u estuser:estpwd` to curl command

---

## Success Criteria

✅ All three tenants return their CA certificates  
✅ All three tenants successfully enroll device certificates  
✅ Each certificate is signed by the correct tenant CA  
✅ Cross-tenant verification fails (isolation confirmed)  
✅ Invalid tenants return HTTP 204 No Content  

**If all tests pass, your multi-tenant EST server is working perfectly!** 🎉
