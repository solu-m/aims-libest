#!/bin/bash
#
# Quick Fix and Build Script
# Handles the Docker build issue and starts testing
#

set -e

echo "========================================="
echo " Fixing and Building Multi-Tenant EST"
echo "========================================="
echo ""

# Check if we're in the right directory
if [ ! -f "Dockerfile" ]; then
    echo "ERROR: Run this from the aims-libest directory"
    exit 1
fi

echo "[1/4] Verifying tenant config files exist..."
for tenant in gateway iot freeradius; do
    if [ -f "tenants/$tenant/${tenant}.cnf" ]; then
        echo "  ✓ tenants/$tenant/${tenant}.cnf"
    else
        echo "  ✗ tenants/$tenant/${tenant}.cnf MISSING!"
        exit 1
    fi
done
echo ""

echo "[2/4] Checking Docker..."
if ! docker info > /dev/null 2>&1; then
    echo "ERROR: Docker is not running"
    echo "Please start Docker and try again"
    exit 1
fi
echo "  ✓ Docker is running"
echo ""

echo "[3/4] Building Docker image (this may take 5-10 minutes)..."
echo ""

if docker-compose build; then
    echo ""
    echo "  ✓ Docker image built successfully!"
else
    echo ""
    echo "  ✗ Docker build failed"
    echo ""
    echo "If you see errors about COPY commands, the tenant configs may be missing."
    echo "Run: bash multi_tenant_smoke_test.sh"
    echo "This will regenerate the tenant infrastructure."
    exit 1
fi
echo ""

echo "[4/4] Starting EST server..."
docker-compose up -d est-server

echo ""
echo "Waiting for server to be healthy..."
for i in {1..30}; do
    if docker inspect multi-tenant-est-server --format='{{.State.Health.Status}}' 2>/dev/null | grep -q "healthy"; then
        echo "  ✓ EST server is healthy and ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "  ✗ Server failed to become healthy"
        echo ""
        echo "Check logs with: docker-compose logs est-server"
        exit 1
    fi
    echo -ne "  Waiting... ($i/30)\r"
    sleep 2
done

echo ""
echo "========================================="
echo " ✓ Multi-Tenant EST Server is Running!"
echo "========================================="
echo ""
echo "Server: https://localhost:8085"
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
echo "Stop server:"
echo "  docker-compose down"
echo ""
