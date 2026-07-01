#!/bin/bash
#
# Alternative Dockerfile Build Script
# Bypasses autotools issues by using configure directly
#

set -e

echo "=========================================="
echo " Alternative Docker Build Method"
echo "=========================================="
echo ""

# Check if we're in the right directory
if [ ! -f "Dockerfile" ]; then
    echo "ERROR: Run this from the aims-libest directory"
    exit 1
fi

echo "[1/3] Checking prerequisites..."
echo ""

# Check if configure exists
if [ ! -f "configure" ]; then
    echo "ERROR: configure script not found!"
    echo "The repository should include a pre-generated configure script."
    echo ""
    echo "Try running: git pull origin main"
    exit 1
fi
echo "  ✓ configure script exists"

# Check tenant configs
for tenant in gateway iot freeradius; do
    if [ ! -f "tenants/$tenant/${tenant}.cnf" ]; then
        echo "  ✗ tenants/$tenant/${tenant}.cnf missing"
        echo ""
        echo "Run: bash multi_tenant_smoke_test.sh"
        exit 1
    fi
done
echo "  ✓ Tenant configs exist"

# Check Docker
if ! docker info > /dev/null 2>&1; then
    echo "  ✗ Docker is not running"
    exit 1
fi
echo "  ✓ Docker is running"
echo ""

echo "[2/3] Building Docker image..."
echo "(This uses the existing configure script to avoid autotools issues)"
echo ""

if docker-compose build --progress=plain 2>&1 | tee docker-build.log; then
    echo ""
    echo "  ✓ Docker build completed successfully!"
else
    echo ""
    echo "  ✗ Docker build failed"
    echo ""
    echo "Check docker-build.log for details"
    echo ""
    echo "Common issues:"
    echo "  1. Compiler errors - check multi_tenant_enrollment.c syntax"
    echo "  2. Missing dependencies - check Dockerfile packages"
    echo "  3. OpenSSL compatibility - ensure OpenSSL 1.0.2+ or 1.1.x"
    exit 1
fi
echo ""

echo "[3/3] Starting EST server..."
docker-compose up -d est-server

echo ""
echo "Waiting for server to become healthy..."
for i in {1..30}; do
    status=$(docker inspect multi-tenant-est-server --format='{{.State.Health.Status}}' 2>/dev/null || echo "starting")
    
    if [ "$status" = "healthy" ]; then
        echo "  ✓ EST server is healthy!"
        break
    fi
    
    if [ $i -eq 30 ]; then
        echo "  ✗ Server failed to become healthy"
        echo ""
        echo "Check logs: docker-compose logs est-server"
        exit 1
    fi
    
    echo -ne "  Status: $status (attempt $i/30)\r"
    sleep 2
done

echo ""
echo "=========================================="
echo " ✓ Build Complete!"
echo "=========================================="
echo ""
echo "Server URL: https://localhost:8085"
echo ""
echo "Quick test:"
echo "  curl -k https://localhost:8085/.well-known/est/gateway/cacerts -o ca.p7"
echo ""
echo "Run full tests:"
echo "  docker-compose run --rm test-client"
echo ""
echo "View logs:"
echo "  docker-compose logs -f est-server"
echo ""
