#!/bin/bash
echo "Checking build.log for uriparser detection..."
echo ""
echo "=== Searching for 'uriparser' in build.log ==="
grep -i "uriparser" build.log | head -30
echo ""
echo "=== Searching for 'checking for' lines around uriparser ==="
grep -B2 -A2 "checking for.*uri" build.log | head -40
echo ""
echo "=== Looking for HAVE_URIPARSER definition ==="
grep "HAVE_URIPARSER" build.log | head -10
echo ""
echo "=== Configure summary (if available) ==="
grep -A20 "^configure: creating" build.log | head -30
