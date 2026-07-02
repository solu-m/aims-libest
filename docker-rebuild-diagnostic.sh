#!/bin/bash

#=================================================================
# Docker Rebuild with Diagnostic Output
# Purpose: Debug uriparser detection and HAVE_URIPARSER definition
#=================================================================

set -e

echo "========================================="
echo "  Multi-Tenant EST - Diagnostic Rebuild"
echo "========================================="
echo ""

# Step 1: Clean everything
echo "[STEP 1] Cleaning Docker environment..."
docker compose down -v 2>/dev/null || true
docker image rm aims-libest-est-server:latest 2>/dev/null || true
docker system prune -f
echo "✓ Clean complete"
echo ""

# Step 2: Rebuild with NO CACHE
echo "[STEP 2] Building with --no-cache (this will take ~3-5 minutes)..."
echo ""
docker compose build est-server --no-cache --progress=plain 2>&1 | tee build.log
echo ""
echo "✓ Build complete"
echo ""

# Step 3: Start server
echo "[STEP 3] Starting EST server..."
docker compose up -d est-server
sleep 5
echo "✓ Server started"
echo ""

# Step 4: Run diagnostics inside container
echo "[STEP 4] Running diagnostics inside container..."
echo ""

docker exec multi-tenant-est-server bash -c '
echo "=== Diagnostic Results ==="
echo ""

echo "1. Check if liburiparser package is installed:"
dpkg -l | grep uriparser || echo "   NOT FOUND"
echo ""

echo "2. Check if uriparser library files exist:"
ls -la /usr/lib/x86_64-linux-gnu/liburiparser* 2>/dev/null || echo "   NOT FOUND"
ls -la /usr/include/uriparser/ 2>/dev/null || echo "   NOT FOUND"
echo ""

echo "3. Check if pkg-config can find uriparser:"
pkg-config --exists liburiparser && echo "   ✓ pkg-config FOUND liburiparser" || echo "   ✗ pkg-config CANNOT find liburiparser"
if pkg-config --exists liburiparser; then
    echo "   Version: $(pkg-config --modversion liburiparser)"
    echo "   CFLAGS: $(pkg-config --cflags liburiparser)"
    echo "   LIBS: $(pkg-config --libs liburiparser)"
fi
echo ""

echo "4. Check if libest.so was compiled with uriparser symbols:"
strings /opt/est/lib/libest-3.2.0p.so | grep -i uri | head -20 || echo "   No URI symbols found"
echo ""

echo "5. Check if HAVE_URIPARSER is defined in config.h:"
if [ -f /build/src/est/config.h ]; then
    grep -i "HAVE_URIPARSER" /build/src/est/config.h || echo "   NOT DEFINED in config.h"
elif [ -f /opt/est/include/config.h ]; then
    grep -i "HAVE_URIPARSER" /opt/est/include/config.h || echo "   NOT DEFINED in config.h"
else
    echo "   config.h not found"
fi
echo ""

echo "6. Check configure.log for uriparser detection:"
if [ -f /build/config.log ]; then
    echo "   Checking config.log for uriparser..."
    grep -A5 -B5 "uriparser" /build/config.log | tail -30 || echo "   No uriparser references in config.log"
else
    echo "   config.log not found"
fi
echo ""

echo "7. Test EST path segment handling:"
curl -k -s "https://127.0.0.1:8085/.well-known/est/gateway/cacerts" -o /tmp/test_response.bin
RESPONSE_SIZE=$(stat -c%s /tmp/test_response.bin 2>/dev/null || echo "0")
if [ "$RESPONSE_SIZE" -gt 100 ]; then
    echo "   ✓ SUCCESS: Got $RESPONSE_SIZE bytes (certificate response)"
else
    echo "   ✗ FAILED: Got $RESPONSE_SIZE bytes (likely error page)"
    echo "   Response content:"
    head -c 200 /tmp/test_response.bin 2>/dev/null || echo "   (empty)"
fi
echo ""

echo "=== End Diagnostics ==="
'

echo ""
echo "========================================="
echo "  Diagnostic Complete"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Review the diagnostic output above"
echo "2. Check build.log file for configure output"
echo "3. Look for any ERROR or WARNING messages"
echo ""
echo "If uriparser is installed but HAVE_URIPARSER is not defined:"
echo "  → Configure script failed to detect it"
echo "  → Check config.log (step 6 above)"
echo ""
