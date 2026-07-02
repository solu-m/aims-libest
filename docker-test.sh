#!/bin/bash
#
# Docker-based Multi-Tenant EST Server Test Suite
# Runs comprehensive tests against dockerized EST server
#

set -e

# Configuration
EST_SERVER="https://est-server:8085"
TENANTS=("gateway" "iot" "freeradius")
TEST_DIR="/test-results"
RESULTS_FILE="$TEST_DIR/test-results.txt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Create test results directory
mkdir -p "$TEST_DIR"
rm -f "$RESULTS_FILE"

echo -e "${BLUE}=================================================================${NC}" | tee -a "$RESULTS_FILE"
echo -e "${BLUE}    Multi-Tenant EST Server - Docker Integration Tests${NC}" | tee -a "$RESULTS_FILE"
echo -e "${BLUE}=================================================================${NC}" | tee -a "$RESULTS_FILE"
echo "" | tee -a "$RESULTS_FILE"

# Wait for server to be fully ready
echo -e "${YELLOW}Waiting for EST server to be ready...${NC}"
for i in {1..30}; do
    if curl -k -s "$EST_SERVER/.well-known/est/gateway/cacerts" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ EST server is ready${NC}" | tee -a "$RESULTS_FILE"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RED}✗ EST server failed to start${NC}" | tee -a "$RESULTS_FILE"
        exit 1
    fi
    sleep 1
done
echo "" | tee -a "$RESULTS_FILE"

# Test function
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -ne "${YELLOW}[TEST $TESTS_RUN]${NC} $test_name ... " | tee -a "$RESULTS_FILE"
    
    if eval "$test_command" > "$TEST_DIR/test_${TESTS_RUN}.log" 2>&1; then
        echo -e "${GREEN}PASS${NC}" | tee -a "$RESULTS_FILE"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}FAIL${NC}" | tee -a "$RESULTS_FILE"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  Error details:" | tee -a "$RESULTS_FILE"
        tail -3 "$TEST_DIR/test_${TESTS_RUN}.log" | sed 's/^/    /' | tee -a "$RESULTS_FILE"
        return 1
    fi
}

echo -e "${BLUE}Phase 1: Server Connectivity Tests${NC}" | tee -a "$RESULTS_FILE"
echo "" | tee -a "$RESULTS_FILE"

# Test 1: Server responds to HTTPS
run_test "EST server HTTPS connectivity" \
    "curl -k -s -o /dev/null -w '%{http_code}' $EST_SERVER/.well-known/est/gateway/cacerts | grep -q 200"

echo "" | tee -a "$RESULTS_FILE"
echo -e "${BLUE}Phase 2: CA Certificate Retrieval Tests${NC}" | tee -a "$RESULTS_FILE"
echo "" | tee -a "$RESULTS_FILE"

for TENANT in "${TENANTS[@]}"; do
    echo -e "${YELLOW}Testing tenant: $TENANT${NC}" | tee -a "$RESULTS_FILE"
    
    # Test: Retrieve CA certificate
    run_test "  Retrieve $TENANT CA certificate" \
        "curl -k -s $EST_SERVER/.well-known/est/$TENANT/cacerts -o $TEST_DIR/${TENANT}_ca.p7 && test -s $TEST_DIR/${TENANT}_ca.p7"
    
    # Test: Verify PKCS7 format
    if [ -f "$TEST_DIR/${TENANT}_ca.p7" ]; then
        run_test "  Verify $TENANT PKCS7 format" \
            "openssl pkcs7 -in $TEST_DIR/${TENANT}_ca.p7 -inform DER -print_certs -out $TEST_DIR/${TENANT}_ca.pem"
        
        # Extract and display CA info
        if [ -f "$TEST_DIR/${TENANT}_ca.pem" ]; then
            CA_SUBJECT=$(openssl x509 -in "$TEST_DIR/${TENANT}_ca.pem" -noout -subject 2>/dev/null)
            echo "    CA Subject: $CA_SUBJECT" | tee -a "$RESULTS_FILE"
        fi
    fi
    
    echo "" | tee -a "$RESULTS_FILE"
done

echo -e "${BLUE}Phase 3: Certificate Enrollment Tests${NC}" | tee -a "$RESULTS_FILE"
echo "" | tee -a "$RESULTS_FILE"

for TENANT in "${TENANTS[@]}"; do
    echo -e "${YELLOW}Enrollment test for tenant: $TENANT${NC}" | tee -a "$RESULTS_FILE"
    
    # Generate device key and CSR
    DEVICE_KEY="$TEST_DIR/${TENANT}_device.key"
    DEVICE_CSR="$TEST_DIR/${TENANT}_device.csr"
    DEVICE_DER="$TEST_DIR/${TENANT}_device.der"
    DEVICE_CERT="$TEST_DIR/${TENANT}_device_cert.p7"
    DEVICE_CERT_PEM="$TEST_DIR/${TENANT}_device_cert.pem"
    
    openssl genrsa -out "$DEVICE_KEY" 2048 2>/dev/null
    openssl req -new -key "$DEVICE_KEY" -out "$DEVICE_CSR" \
        -subj "/C=US/ST=CA/L=SanJose/O=Cisco/OU=Testing/CN=docker-test-${TENANT}-device" 2>/dev/null
    openssl req -in "$DEVICE_CSR" -outform DER -out "$DEVICE_DER"
    
    # Test: Simple enrollment (with HTTP Basic Auth)
    run_test "  Enroll device with $TENANT tenant" \
        "curl -k -s -X POST $EST_SERVER/.well-known/est/$TENANT/simpleenroll \
              -H 'Content-Type: application/pkcs10' \
              -u estuser:estpwd \
              --data-binary @$DEVICE_DER \
              -o $DEVICE_CERT && test -s $DEVICE_CERT"
    
    # Test: Verify enrolled certificate
    if [ -f "$DEVICE_CERT" ]; then
        run_test "  Extract $TENANT enrolled certificate" \
            "openssl pkcs7 -in $DEVICE_CERT -inform DER -print_certs -out $DEVICE_CERT_PEM && test -s $DEVICE_CERT_PEM"
        
        if [ -f "$DEVICE_CERT_PEM" ] && [ -f "$TEST_DIR/${TENANT}_ca.pem" ]; then
            # Test: Verify certificate chain
            run_test "  Verify $TENANT certificate chain" \
                "openssl verify -CAfile $TEST_DIR/${TENANT}_ca.pem $DEVICE_CERT_PEM"
            
            # Extract and display cert info
            CERT_CN=$(openssl x509 -in "$DEVICE_CERT_PEM" -noout -subject 2>/dev/null | grep -oP 'CN\s*=\s*\K[^,]+')
            ISSUER_CN=$(openssl x509 -in "$DEVICE_CERT_PEM" -noout -issuer 2>/dev/null | grep -oP 'CN\s*=\s*\K[^,]+')
            echo "    Certificate CN: $CERT_CN" | tee -a "$RESULTS_FILE"
            echo "    Issuer CN: $ISSUER_CN" | tee -a "$RESULTS_FILE"
            
            # Verify issuer matches tenant
            if [[ "$ISSUER_CN" == *"$TENANT"* ]]; then
                echo -e "    ${GREEN}✓${NC} Issuer matches tenant CA" | tee -a "$RESULTS_FILE"
                TESTS_PASSED=$((TESTS_PASSED + 1))
            else
                echo -e "    ${RED}✗${NC} Issuer mismatch!" | tee -a "$RESULTS_FILE"
                TESTS_FAILED=$((TESTS_FAILED + 1))
            fi
            TESTS_RUN=$((TESTS_RUN + 1))
        fi
    fi
    
    echo "" | tee -a "$RESULTS_FILE"
done

echo -e "${BLUE}Phase 4: Tenant Isolation Verification${NC}" | tee -a "$RESULTS_FILE"
echo "" | tee -a "$RESULTS_FILE"

# Test: Cross-tenant certificate rejection
if [ -f "$TEST_DIR/gateway_device_cert.pem" ] && [ -f "$TEST_DIR/iot_ca.pem" ]; then
    echo -e "${YELLOW}Cross-tenant contamination check:${NC}" | tee -a "$RESULTS_FILE"
    
    if openssl verify -CAfile "$TEST_DIR/iot_ca.pem" "$TEST_DIR/gateway_device_cert.pem" 2>&1 | grep -q "verification failed"; then
        echo -e "  ${GREEN}✓${NC} gateway cert correctly rejected by iot CA (isolation confirmed)" | tee -a "$RESULTS_FILE"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  ${RED}✗${NC} gateway cert accepted by iot CA (ISOLATION BREACH!)" | tee -a "$RESULTS_FILE"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
fi

# Test: Invalid tenant ID
echo "" | tee -a "$RESULTS_FILE"
run_test "Reject invalid tenant ID" \
    "curl -k -s -o /dev/null -w '%{http_code}' $EST_SERVER/.well-known/est/invalid-tenant/cacerts | grep -q 401"

echo "" | tee -a "$RESULTS_FILE"
echo -e "${BLUE}=================================================================${NC}" | tee -a "$RESULTS_FILE"
echo -e "${BLUE}                          Test Summary${NC}" | tee -a "$RESULTS_FILE"
echo -e "${BLUE}=================================================================${NC}" | tee -a "$RESULTS_FILE"
echo "" | tee -a "$RESULTS_FILE"
echo -e "  Total Tests:   $TESTS_RUN" | tee -a "$RESULTS_FILE"
echo -e "  ${GREEN}Passed:        $TESTS_PASSED${NC}" | tee -a "$RESULTS_FILE"
echo -e "  ${RED}Failed:        $TESTS_FAILED${NC}" | tee -a "$RESULTS_FILE"
echo "" | tee -a "$RESULTS_FILE"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}============================================${NC}" | tee -a "$RESULTS_FILE"
    echo -e "${GREEN}  ✓ ALL DOCKER TESTS PASSED${NC}" | tee -a "$RESULTS_FILE"
    echo -e "${GREEN}  Multi-Tenant CA Engine is OPERATIONAL${NC}" | tee -a "$RESULTS_FILE"
    echo -e "${GREEN}============================================${NC}" | tee -a "$RESULTS_FILE"
    echo "" | tee -a "$RESULTS_FILE"
    exit 0
else
    echo -e "${RED}============================================${NC}" | tee -a "$RESULTS_FILE"
    echo -e "${RED}  ✗ TESTS FAILED${NC}" | tee -a "$RESULTS_FILE"
    echo -e "${RED}  Please review the errors above${NC}" | tee -a "$RESULTS_FILE"
    echo -e "${RED}============================================${NC}" | tee -a "$RESULTS_FILE"
    echo "" | tee -a "$RESULTS_FILE"
    exit 1
fi
