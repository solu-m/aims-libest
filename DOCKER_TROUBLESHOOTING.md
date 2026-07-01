# Docker Build Troubleshooting Guide

## Issue: Dockerfile heredoc syntax error

### Problem
```
failed to solve: dockerfile parse error on line 40: unknown instruction: [
```

This error occurs because Dockerfile doesn't support heredoc (<<EOF) syntax within RUN commands.

### Solution ✅ FIXED

The Dockerfile has been updated to:
1. **Remove heredoc syntax** - No longer using `<<EOF` in RUN commands
2. **Use COPY instead** - Copies existing tenant config files from local filesystem
3. **Update paths at runtime** - Uses `sed` to adjust paths for Docker environment

### What Changed

**Before (Broken):**
```dockerfile
RUN bash -c 'cat > "$TENANTS_DIR/$tenant/$tenant.cnf" <<EOF
[ ca ]
default_ca = CA_default
...
EOF'
```

**After (Fixed):**
```dockerfile
# Copy existing config files
COPY tenants/gateway/gateway.cnf /build/tenants/gateway/gateway.cnf
COPY tenants/iot/iot.cnf /build/tenants/iot/iot.cnf
COPY tenants/freeradius/freeradius.cnf /build/tenants/freeradius/freeradius.cnf

# Update paths for Docker runtime
RUN sed -i 's|dir.*=.*|dir = /opt/est/tenants/gateway|g' /build/tenants/gateway/gateway.cnf
```

## Prerequisites

Before running Docker build, ensure tenant configs exist:

```bash
# Verify files exist
ls -la tenants/gateway/gateway.cnf
ls -la tenants/iot/iot.cnf
ls -la tenants/freeradius/freeradius.cnf
```

If missing, regenerate them:

```bash
bash multi_tenant_smoke_test.sh
```

## How to Build Now

### Option 1: Automated Script (Recommended)

```bash
bash docker-build-and-run.sh
```

This script:
- ✓ Verifies prerequisites
- ✓ Builds Docker image
- ✓ Starts EST server
- ✓ Checks health status
- ✓ Shows quick test commands

### Option 2: Manual Steps

```bash
# 1. Build image
docker-compose build

# 2. Start server
docker-compose up -d est-server

# 3. Check status
docker-compose ps

# 4. View logs
docker-compose logs -f est-server

# 5. Run tests
docker-compose run --rm test-client
```

## Common Issues

### Issue: "ERROR: Service 'est-server' failed to build"

**Cause:** Tenant config files don't exist

**Solution:**
```bash
# Regenerate tenant infrastructure
bash generate_certs.sh

# Or run full smoke test
bash multi_tenant_smoke_test.sh

# Then rebuild
docker-compose build
```

### Issue: "WARN[0000] version is obsolete"

**Cause:** docker-compose.yml had `version: '3.8'` which is deprecated

**Solution:** ✅ Already fixed - removed `version:` field

### Issue: Docker daemon not running

**Solution:**
```bash
# Linux
sudo systemctl start docker

# macOS/Windows
# Start Docker Desktop application
```

## Verification

After successful build, verify:

```bash
# Check image exists
docker images | grep aims-libest

# Should show:
# aims-libest-est-server   latest   ...   5-10 minutes ago   ...

# Check server is running
docker-compose ps

# Should show:
# multi-tenant-est-server   running (healthy)

# Test endpoint
curl -k https://localhost:8085/.well-known/est/gateway/cacerts
```

## Next Steps

Once Docker build succeeds:

1. **Run integration tests:**
   ```bash
   docker-compose run --rm test-client
   ```

2. **Test manually:**
   ```bash
   curl -k https://localhost:8085/.well-known/est/gateway/cacerts -o ca.p7
   openssl pkcs7 -in ca.p7 -inform DER -print_certs
   ```

3. **View server logs:**
   ```bash
   docker-compose logs -f est-server
   ```

## Changes Committed

All fixes have been committed to git:

```
fix: Resolve Dockerfile heredoc syntax and docker-compose version warning

- Removed heredoc (<<EOF) syntax from Dockerfile
- Changed to COPY existing tenant config files
- Removed obsolete 'version:' field from docker-compose.yml
- Added docker-build-and-run.sh helper script
```

## Summary

✅ **Dockerfile fixed** - No more heredoc syntax errors
✅ **docker-compose.yml updated** - No more version warnings
✅ **Helper script added** - Automated build and start
✅ **Changes committed** - Ready to pull and test

You can now successfully build and run the multi-tenant EST server in Docker! 🎉
