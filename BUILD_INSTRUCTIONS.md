# Multi-Tenant CA Engine - Build Instructions

## Quick Start Guide

This guide walks you through building and running the multi-tenant EST server.

## Prerequisites

- **Operating System**: Linux/WSL, macOS, or Unix-like environment
- **Compiler**: GCC 4.8+ or Clang 3.5+
- **Libraries**:
  - OpenSSL 1.0.2+ or 1.1.x
  - pthread (usually included with gcc)
  - libc6-dev

### Installing Dependencies

#### Ubuntu/Debian:
```bash
sudo apt-get update
sudo apt-get install -y build-essential libssl-dev autoconf automake libtool
```

#### CentOS/RHEL:
```bash
sudo yum install -y gcc make openssl-devel autoconf automake libtool
```

#### macOS:
```bash
brew install openssl autoconf automake libtool
```

## Step-by-Step Build Process

### 1. Set Up Tenant Infrastructure

First, create the isolated tenant environments:

```bash
cd aims-libest

# If on Windows with WSL, generate certificates
bash generate_certs.sh

# If tenant configs not created, they should already exist in tenants/*/
# Verify with:
ls -la tenants/gateway/
ls -la tenants/iot/
ls -la tenants/freeradius/
```

### 2. Run Smoke Tests

Verify infrastructure is correctly set up:

```bash
bash multi_tenant_smoke_test.sh
```

Expected output:
```
===================================================================
       Multi-Tenant CA Engine Smoke Test
===================================================================

...
✓ ALL TESTS PASSED
Multi-Tenant CA Engine is OPERATIONAL
```

### 3. Modify Makefile to Include Multi-Tenant Module

Edit `example/server/Makefile.am`:

```makefile
# Add multi_tenant_enrollment.c to sources
estserver_SOURCES = estserver.c ossl_srv.c multi_tenant_enrollment.c \
                    ../util/utils.c ../util/simple_server.c ../util/jsmn.c

# Add header
noinst_HEADERS = ossl_srv.h multi_tenant_enrollment.h ../util/utils.h \
                 ../util/simple_server.h ../util/jsmn.h apps.h
```

### 4. Regenerate Build Configuration

```bash
cd aims-libest

# Clean previous build artifacts
make clean 2>/dev/null || true

# Regenerate autoconf files
./autogen.sh

# Configure with OpenSSL support
./configure --prefix=/usr/local \
            --with-ssl-dir=/usr \
            --enable-shared \
            --enable-static

# If configure fails to find OpenSSL on macOS:
./configure --prefix=/usr/local \
            --with-ssl-dir=/usr/local/opt/openssl@1.1 \
            --enable-shared \
            --enable-static
```

### 5. Build the Server

```bash
# Build with verbose output
make V=1

# Expected output should include:
# gcc ... -c multi_tenant_enrollment.c -o multi_tenant_enrollment.o
# gcc ... estserver.o ossl_srv.o multi_tenant_enrollment.o ... -o estserver
```

### 6. Verify Build Success

```bash
# Check if binary was created
ls -lh example/server/estserver

# Should show executable permissions and recent timestamp
# -rwxr-xr-x 1 user group 250K Jul  1 13:00 example/server/estserver
```

## Running the Multi-Tenant Server

### Option A: Quick Test (No TLS Client Auth)

For initial testing without client certificates:

```bash
cd example/server

# Start server with HTTP auth disabled
./estserver -v -p 8085 \
    -c ../../test/CA/estCA/private/secp256r1.cert.pem \
    -k ../../test/CA/estCA/private/secp256r1.key.pem \
    -u -b

# Server should start and display:
# [Multi-tenant CA server running on port 8085]
# [Valid tenants: gateway, iot, freeradius]
```

Flags explained:
- `-v`: Verbose logging
- `-p 8085`: Port number
- `-c`: Server TLS certificate
- `-k`: Server TLS private key
- `-u`: Disable HTTP Basic/Digest authentication
- `-b`: Disable Proof of Possession checks

### Option B: Production Mode (With Client Auth)

```bash
./estserver -v -p 8085 \
    -c /path/to/server.crt \
    -k /path/to/server.key \
    -r /path/to/trusted_root.pem \
    -h estuser:estpwd
```

Flags:
- `-r`: Trusted root CA for client certificate validation
- `-h`: HTTP Basic auth credentials (username:password)

## Testing the Server

### Test 1: Retrieve CA Certificates

```bash
# In a new terminal, test gateway tenant
curl -k https://localhost:8085/.well-known/est/gateway/cacerts -o gateway_ca.p7

# Verify it's valid PKCS7
openssl pkcs7 -in gateway_ca.p7 -inform DER -print_certs | grep "subject"

# Should show:
# subject=C = US, ST = CA, L = SanJose, O = Cisco, OU = gateway, CN = gateway-CA
```

### Test 2: Simple Enrollment

```bash
# Generate test device key and CSR
openssl genrsa -out test_device.key 2048
openssl req -new -key test_device.key -out test_device.csr \
    -subj "/C=US/ST=CA/O=Cisco/CN=test-device-001"

# Convert CSR to DER format (EST requires DER)
openssl req -in test_device.csr -outform DER -out test_device.der

# Enroll with iot tenant
curl -k -X POST \
    https://localhost:8085/.well-known/est/iot/simpleenroll \
    -H "Content-Type: application/pkcs10" \
    -H "Content-Transfer-Encoding: base64" \
    --data-binary @test_device.der \
    -o enrolled_cert.p7

# Extract certificate
openssl pkcs7 -in enrolled_cert.p7 -inform DER -print_certs -out enrolled_cert.pem

# Verify issuer is iot CA
openssl x509 -in enrolled_cert.pem -noout -issuer
# issuer=C = US, ST = CA, ..., CN = iot-CA
```

### Test 3: Check Server Logs

The server terminal should show detailed multi-tenant routing:

```
================================================
[MULTI-TENANT] Enrollment request received
================================================
[ROUTING] Tenant ID from path: 'iot'
[PIPELINE] Executing multi-tenant enrollment for: iot
[INFO] Multi-tenant enrollment started for tenant: iot
[INFO] [Step 1/6] Wrote DER CSR to /tenants/iot/tmp_client.der (522 bytes)
[INFO] [Step 2/6] Converted DER→PEM successfully
[INFO] [Step 3/6] Certificate signed by iot CA
[INFO] [Step 4/6] Created PKCS7 bundle
[INFO] [Step 5/6] Loaded PKCS7 into memory (1523 bytes)
[INFO] [Cleanup] Purged all temporary files
[SUCCESS] Multi-tenant enrollment complete for tenant: iot
[SUCCESS] Enrollment complete for tenant: iot (1523 bytes)
================================================
```

## Troubleshooting Build Issues

### Issue: "multi_tenant_enrollment.h: No such file or directory"

**Solution**: Ensure header file is in the same directory as .c file:
```bash
ls example/server/multi_tenant_enrollment.*
# Should show both .c and .h files
```

### Issue: "undefined reference to `multi_tenant_enroll`"

**Solution**: Verify multi_tenant_enrollment.c is in Makefile sources:
```bash
grep multi_tenant_enrollment example/server/Makefile.am
```

### Issue: "REPO_ROOT path incorrect" at runtime

**Solution**: Update the path in `multi_tenant_enrollment.c`:
```c
#define REPO_ROOT "/mnt/c/Users/Solum/aims-libest"
// Change to your actual repository path
```

You can make this dynamic by using environment variables:
```c
const char *repo_root = getenv("EST_REPO_ROOT");
if (!repo_root) {
    repo_root = "/mnt/c/Users/Solum/aims-libest";  // fallback
}
```

### Issue: Linker errors about OpenSSL functions

**Solution**: Add OpenSSL libraries explicitly:
```bash
./configure LDFLAGS="-L/usr/lib/x86_64-linux-gnu" \
            CPPFLAGS="-I/usr/include/openssl"
```

## Advanced Configuration

### Enable Additional Tenants

To add a new tenant (e.g., "manufacturing"):

1. Create tenant directory structure:
```bash
mkdir -p tenants/manufacturing/{private,newcerts}
touch tenants/manufacturing/index.txt
echo "01" > tenants/manufacturing/serial
```

2. Generate CA certificate:
```bash
openssl genrsa -out tenants/manufacturing/private/cakey.pem 4096
openssl req -new -x509 -days 3650 \
    -key tenants/manufacturing/private/cakey.pem \
    -out tenants/manufacturing/cacert.crt \
    -subj "/C=US/ST=CA/O=Cisco/OU=manufacturing/CN=manufacturing-CA"
```

3. Create OpenSSL config (copy from gateway and modify paths)

4. Update `multi_tenant_enroll` validation logic in `multi_tenant_enrollment.c`:
```c
if (strcmp(tenant_id, "gateway") != 0 && 
    strcmp(tenant_id, "iot") != 0 && 
    strcmp(tenant_id, "freeradius") != 0 &&
    strcmp(tenant_id, "manufacturing") != 0) {
    // invalid tenant
}
```

5. Rebuild and restart server

## Performance Tuning

### Increase Thread Pool Size

Edit `estserver.c` and increase worker threads for higher concurrency.

### Optimize File I/O

For high-volume enrollments, consider using tmpfs for temporary files:
```bash
sudo mount -t tmpfs -o size=100M tmpfs /tmp/est_temp
```

Then update temp file paths in `multi_tenant_enrollment.c`.

## Next Steps

After successful build and testing:

1. **Production Deployment**: Set up systemd service or Docker container
2. **Load Balancing**: Deploy multiple instances behind nginx/haproxy
3. **Monitoring**: Integrate with Prometheus/Grafana
4. **HSM Integration**: Move CA private keys to hardware security modules

## Summary

You now have a fully functional multi-tenant Certificate Authority engine! 🎉

- ✅ Infrastructure set up
- ✅ Smoke tests passing
- ✅ Server built and running
- ✅ Multi-tenant isolation verified

For usage examples and API documentation, see `MULTI_TENANT_README.md`.
