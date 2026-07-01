#!/bin/bash
#
# Multi-Tenant CA Smoke Test
# Validates complete tenant isolation for gateway, iot, and freeradius
#
# Test scenarios:
# 1. Simple enrollment for each tenant
# 2. Verify unique certificates issued per tenant
# 3. Confirm no cross-tenant contamination
# 4. Validate index.txt isolation
#

set -e

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
TENANTS_DIR="$REPO_ROOT/tenants"
TEST_DIR="$REPO_ROOT/smoke_test_temp"
TENANTS=("gateway" "iot" "freeradius")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}===================================================================${NC}"
echo -e "${BLUE}       Multi-Tenant CA Engine Smoke Test${NC}"
echo -e "${BLUE}===================================================================${NC}"
echo ""

# Clean up any previous test artifacts
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -ne "${YELLOW}[TEST $TESTS_RUN]${NC} $test_name ... "
    
    if eval "$test_command" > "$TEST_DIR/test_${TESTS_RUN}.log" 2>&1; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  Error details:"
        tail -5 "$TEST_DIR/test_${TESTS_RUN}.log" | sed 's/^/    /'
        return 1
    fi
}

echo -e "${BLUE}Phase 1: Infrastructure Validation${NC}"
echo ""

# Test 1: Verify tenant directories exist
run_test "Tenant directories exist" \
    "test -d $TENANTS_DIR/gateway && test -d $TENANTS_DIR/iot && test -d $TENANTS_DIR/freeradius"

# Test 2: Verify CA certificates exist
run_test "CA certificates generated" \
    "test -f $TENANTS_DIR/gateway/cacert.crt && test -f $TENANTS_DIR/iot/cacert.crt && test -f $TENANTS_DIR/freeradius/cacert.crt"

# Test 3: Verify CA private keys exist
run_test "CA private keys generated" \
    "test -f $TENANTS_DIR/gateway/private/cakey.pem && test -f $TENANTS_DIR/iot/private/cakey.pem && test -f $TENANTS_DIR/freeradius/private/cakey.pem"

# Test 4: Verify OpenSSL configs exist
run_test "OpenSSL configs created" \
    "test -f $TENANTS_DIR/gateway/gateway.cnf && test -f $TENANTS_DIR/iot/iot.cnf && test -f $TENANTS_DIR/freeradius/freeradius.cnf"

# Test 5: Verify index.txt files exist
run_test "Index files initialized" \
    "test -f $TENANTS_DIR/gateway/index.txt && test -f $TENANTS_DIR/iot/index.txt && test -f $TENANTS_DIR/freeradius/index.txt"

echo ""
echo -e "${BLUE}Phase 2: Certificate Signing Test${NC}"
echo ""

for TENANT in "${TENANTS[@]}"; do
    echo -e "${YELLOW}Testing tenant: $TENANT${NC}"
    
    # Generate a test CSR for this tenant
    TEST_CSR="$TEST_DIR/${TENANT}_test.csr"
    TEST_KEY="$TEST_DIR/${TENANT}_test.key"
    TEST_CERT="$TEST_DIR/${TENANT}_test.crt"
    
    # Generate private key
    openssl genrsa -out "$TEST_KEY" 2048 2>/dev/null
    
    # Generate CSR
    openssl req -new -key "$TEST_KEY" -out "$TEST_CSR" \
        -subj "/C=US/ST=CA/L=SanJose/O=Cisco/OU=Testing/CN=test-${TENANT}-device" 2>/dev/null
    
    # Sign certificate using tenant-specific config
    run_test "  Sign certificate for $TENANT" \
        "openssl ca -batch -config $TENANTS_DIR/$TENANT/${TENANT}.cnf -in $TEST_CSR -out $TEST_CERT"
    
    if [ -f "$TEST_CERT" ]; then
        # Verify certificate was issued
        run_test "  Verify $TENANT certificate" \
            "openssl verify -CAfile $TENANTS_DIR/$TENANT/cacert.crt $TEST_CERT"
        
        # Extract certificate details
        CERT_CN=$(openssl x509 -in "$TEST_CERT" -noout -subject | grep -oP 'CN\s*=\s*\K[^,]+')
        ISSUER_CN=$(openssl x509 -in "$TEST_CERT" -noout -issuer | grep -oP 'CN\s*=\s*\K[^,]+')
        
        echo "    Certificate CN: $CERT_CN"
        echo "    Issuer CN: $ISSUER_CN"
        
        # Verify issuer matches tenant CA
        if [[ "$ISSUER_CN" == *"$TENANT"* ]]; then
            echo -e "    ${GREEN}?${NC} Issuer matches tenant CA"
        else
            echo -e "    ${RED}?${NC} Issuer mismatch!"
        fi
    fi
    
    echo ""
done

echo -e "${BLUE}Phase 3: Tenant Isolation Verification${NC}"
echo ""

# Test: Verify each tenant's index.txt has exactly 1 entry
for TENANT in "${TENANTS[@]}"; do
    ENTRY_COUNT=$(wc -l < "$TENANTS_DIR/$TENANT/index.txt")
    run_test "  $TENANT index.txt has exactly 1 entry" \
        "test $ENTRY_COUNT -eq 1"
done

# Test: Verify certificates are NOT cross-signed
echo -e "${YELLOW}Cross-tenant contamination check:${NC}"
GATEWAY_CERT="$TEST_DIR/gateway_test.crt"
IOT_CA="$TENANTS_DIR/iot/cacert.crt"

if [ -f "$GATEWAY_CERT" ] && [ -f "$IOT_CA" ]; then
    if openssl verify -CAfile "$IOT_CA" "$GATEWAY_CERT" 2>&1 | grep -q "verification failed"; then
        echo -e "  ${GREEN}?${NC} gateway cert correctly rejected by iot CA (isolation confirmed)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  ${RED}?${NC} gateway cert accepted by iot CA (ISOLATION BREACH!)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
fi

echo ""
echo -e "${BLUE}Phase 4: CA Certificate Inspection${NC}"
echo ""

for TENANT in "${TENANTS[@]}"; do
    echo -e "${YELLOW}$TENANT CA Certificate:${NC}"
    openssl x509 -in "$TENANTS_DIR/$TENANT/cacert.crt" -noout -subject -issuer -dates | sed 's/^/  /'
    echo ""
done

echo ""
echo -e "${BLUE}===================================================================${NC}"
echo -e "${BLUE}                      Test Summary${NC}"
echo -e "${BLUE}===================================================================${NC}"
echo ""
echo -e "  Total Tests:   $TESTS_RUN"
echo -e "  ${GREEN}Passed:        $TESTS_PASSED${NC}"
echo -e "  ${RED}Failed:        $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  ? ALL TESTS PASSED${NC}"
    echo -e "${GREEN}  Multi-Tenant CA Engine is OPERATIONAL${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Build the estserver with multi_tenant_enrollment.c"
    echo "  2. Start the server with: ./estserver -v -c <server_cert> -k <server_key>"
    echo "  3. Test EST enrollment with: curl https://localhost:8085/.well-known/est/<tenant>/cacerts"
    exit 0
else
    echo -e "${RED}============================================${NC}"
    echo -e "${RED}  ? TESTS FAILED${NC}"
    echo -e "${RED}  Please review the errors above${NC}"
    echo -e "${RED}============================================${NC}"
    echo ""
    echo "Check log files in: $TEST_DIR/"
    exit 1
fi