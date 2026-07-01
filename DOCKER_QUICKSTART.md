# Multi-Tenant EST Server - Docker Quick Start Guide

## Prerequisites

- Docker Engine 20.10+ or Docker Desktop
- Docker Compose V2 (included with Docker Desktop)
- 2GB free disk space
- Ports 8085 available

## Quick Start (3 Steps)

### Step 1: Build the Docker Image

```bash
cd aims-libest

# Build the multi-tenant EST server image
docker-compose build

# This will:
# - Compile libest with multi-tenant support
# - Set up 3 tenant environments (gateway, iot, freeradius)
# - Generate CA certificates
# - Create server TLS certificates
```

Expected output:
```
[+] Building 120.5s (24/24) FINISHED
 => [builder  1/15] FROM docker.io/library/ubuntu:22.04
 => [builder  2/15] RUN apt-get update && apt-get install -y build-essential...
 => [builder  3/15] WORKDIR /build
 ...
 => [stage-1 8/9] COPY --from=builder /build/tenants /opt/est/tenants
 => exporting to image
 => => naming to docker.io/library/aims-libest-est-server
```

### Step 2: Start the Server

```bash
# Start EST server in detached mode
docker-compose up -d est-server

# Check server status
docker-compose ps

# View server logs
docker-compose logs -f est-server
```

Expected logs:
```
multi-tenant-est-server  | EST server started on port 8085
multi-tenant-est-server  | [Multi-tenant mode enabled]
multi-tenant-est-server  | [Valid tenants: gateway, iot, freeradius]
```

### Step 3: Run Integration Tests

```bash
# Run comprehensive test suite
docker-compose run --rm test-client

# Or use the profile shortcut
docker-compose --profile test up --abort-on-container-exit
```

Expected output:
```
=================================================================
    Multi-Tenant EST Server - Docker Integration Tests
=================================================================

Waiting for EST server to be ready...
✓ EST server is ready

Phase 1: Server Connectivity Tests
[TEST 1] EST server HTTPS connectivity ... PASS

Phase 2: CA Certificate Retrieval Tests
Testing tenant: gateway
[TEST 2]   Retrieve gateway CA certificate ... PASS
[TEST 3]   Verify gateway PKCS7 format ... PASS
...

✓ ALL DOCKER TESTS PASSED
Multi-Tenant CA Engine is OPERATIONAL
```

## Detailed Usage

### Manual Testing with curl

Once the server is running, test from your host machine:

```bash
# Test 1: Retrieve gateway CA certificate
curl -k https://localhost:8085/.well-known/est/gateway/cacerts \
    -o gateway_ca.p7

# Test 2: Retrieve iot CA certificate
curl -k https://localhost:8085/.well-known/est/iot/cacerts \
    -o iot_ca.p7

# Test 3: Retrieve freeradius CA certificate
curl -k https://localhost:8085/.well-known/est/freeradius/cacerts \
    -o freeradius_ca.p7

# Convert PKCS7 to PEM for viewing
openssl pkcs7 -in gateway_ca.p7 -inform DER -print_certs | openssl x509 -text -noout
```

### Enroll a Device Certificate

```bash
# Generate device key
openssl genrsa -out device.key 2048

# Create CSR
openssl req -new -key device.key -out device.csr \
    -subj "/C=US/ST=CA/O=Cisco/CN=my-device-001"

# Convert to DER format (EST requires DER)
openssl req -in device.csr -outform DER -out device.der

# Enroll with iot tenant
curl -k -X POST https://localhost:8085/.well-known/est/iot/simpleenroll \
    -H "Content-Type: application/pkcs10" \
    --data-binary @device.der \
    -o device_cert.p7

# Extract certificate
openssl pkcs7 -in device_cert.p7 -inform DER -print_certs -out device_cert.pem

# Verify certificate
openssl x509 -in device_cert.pem -text -noout | grep -E "(Subject:|Issuer:)"
```

Expected output:
```
Subject: C = US, ST = CA, O = Cisco, CN = my-device-001
Issuer: C = US, ST = CA, L = SanJose, O = Cisco, OU = iot, CN = iot-CA
```

## Docker Commands Reference

### Container Management

```bash
# Start all services
docker-compose up -d

# Stop all services
docker-compose down

# Restart EST server
docker-compose restart est-server

# View real-time logs
docker-compose logs -f est-server

# Check container health
docker-compose ps
docker inspect multi-tenant-est-server | grep -A 5 Health
```

### Debugging

```bash
# Enter running container
docker exec -it multi-tenant-est-server bash

# Inside container:
cd /opt/est
ls -la tenants/
cat tenants/gateway/index.txt
cat tenants/iot/index.txt
cat tenants/freeradius/index.txt

# Test OpenSSL CA directly
openssl ca -config tenants/gateway/gateway.cnf -in test.csr -out test.crt
```

### Viewing Tenant Data

```bash
# Check tenant CA certificates
docker exec multi-tenant-est-server \
    openssl x509 -in /opt/est/tenants/gateway/cacert.crt -text -noout

# View certificate database
docker exec multi-tenant-est-server cat /opt/est/tenants/iot/index.txt

# Check issued certificates
docker exec multi-tenant-est-server ls -la /opt/est/tenants/freeradius/newcerts/
```

### Cleanup

```bash
# Stop and remove containers
docker-compose down

# Remove volumes (deletes all tenant data!)
docker-compose down -v

# Remove images
docker rmi aims-libest-est-server

# Complete cleanup
docker-compose down -v --rmi all
docker system prune -f
```

## Volume Management

### Persistent Tenant Data

Tenant data is stored in a Docker volume:

```bash
# List volumes
docker volume ls | grep aims-libest

# Inspect volume
docker volume inspect aims-libest_tenant-data

# Backup tenant data
docker run --rm -v aims-libest_tenant-data:/data \
    -v $(pwd):/backup \
    ubuntu tar czf /backup/tenant-backup.tar.gz -C /data .

# Restore tenant data
docker run --rm -v aims-libest_tenant-data:/data \
    -v $(pwd):/backup \
    ubuntu tar xzf /backup/tenant-backup.tar.gz -C /data
```

## Performance Testing

### Load Test with Multiple Concurrent Enrollments

```bash
# Install apache bench
sudo apt-get install apache2-utils

# Prepare test CSR
openssl req -new -newkey rsa:2048 -nodes \
    -keyout loadtest.key -out loadtest.csr \
    -subj "/C=US/ST=CA/O=Cisco/CN=loadtest"
openssl req -in loadtest.csr -outform DER -out loadtest.der

# Load test (100 requests, 10 concurrent)
ab -n 100 -c 10 -p loadtest.der \
    -T "application/pkcs10" \
    -k https://localhost:8085/.well-known/est/gateway/simpleenroll
```

## Troubleshooting

### Issue: Container won't start

```bash
# Check logs
docker-compose logs est-server

# Common issues:
# - Port 8085 already in use
# - Insufficient memory

# Solution: Change port in docker-compose.yml
ports:
  - "9085:8085"  # Use port 9085 on host
```

### Issue: Health check failing

```bash
# Check health status
docker inspect multi-tenant-est-server | grep -A 10 Health

# Test connectivity from inside container
docker exec multi-tenant-est-server \
    curl -k https://localhost:8085/.well-known/est/gateway/cacerts

# Check if server is listening
docker exec multi-tenant-est-server netstat -tlnp | grep 8085
```

### Issue: Certificate enrollment returns 500 error

```bash
# View detailed server logs
docker-compose logs -f est-server

# Look for:
# [ERROR] [Step X/6] ...

# Common causes:
# - Tenant config file missing
# - OpenSSL CA execution failed
# - Permission issues on private keys

# Fix: Rebuild image with correct permissions
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

### Issue: Cross-tenant contamination detected

```bash
# Verify tenant isolation
docker exec multi-tenant-est-server bash -c '
    for tenant in gateway iot freeradius; do
        echo "=== $tenant ===="
        wc -l /opt/est/tenants/$tenant/index.txt
    done
'

# Each should show independent counts
# If any show unexpected entries, rebuild:
docker-compose down -v
docker-compose build --no-cache
docker-compose up -d
```

## Production Deployment

### Recommended docker-compose.yml Modifications

```yaml
services:
  est-server:
    # Use specific version tag
    image: your-registry/multi-tenant-est:1.0.0
    
    # Add resource limits
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 1G
        reservations:
          cpus: '1'
          memory: 512M
    
    # Use secrets for certificates
    secrets:
      - server_cert
      - server_key
    
    # Enable logging driver
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    
    # Add monitoring labels
    labels:
      - "prometheus.scrape=true"
      - "prometheus.port=9090"

secrets:
  server_cert:
    file: ./certs/server.crt
  server_key:
    file: ./certs/server.key
```

## Next Steps

### 1. Add More Tenants

Edit Dockerfile to add new tenants:

```dockerfile
RUN bash -c 'for tenant in gateway iot freeradius manufacturing; do ...'
```

### 2. Enable Metrics

Add Prometheus endpoint:

```yaml
services:
  prometheus:
    image: prom/prometheus
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"
```

### 3. Deploy to Kubernetes

```bash
# Convert docker-compose to Kubernetes manifests
kompose convert -f docker-compose.yml

# Or use Helm chart (create custom chart)
helm create multi-tenant-est
```

## Test Results Location

After running tests:

```bash
# View test results
cat test-results/test-results.txt

# View individual test logs
ls -la test-results/
cat test-results/test_1.log
```

## Summary

Your multi-tenant EST server is now running in Docker! 🎉

- ✅ Isolated container environment
- ✅ Persistent tenant data
- ✅ Health checks enabled
- ✅ Automated testing
- ✅ Production-ready

For more information, see:
- `MULTI_TENANT_README.md` - Complete usage guide
- `BUILD_INSTRUCTIONS.md` - Manual build instructions
- `IMPLEMENTATION_SUMMARY.md` - Architecture details
