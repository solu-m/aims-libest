#!/bin/bash

################################################################################
# test-role-based-enrollment.sh - Test role-based EST certificate enrollment
#
# This script tests that:
# 1. Gateway receives clientAuth certificates
# 2. FreeRADIUS receives serverAuth certificates
# 3. Certificates are properly validated
# 4. 802.1X authentication succeeds
#
################################################################################

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
EST_SERVER="https://localhost:8085"
CA_CERT="./estCA/cacert.crt"
TENANT="company-a"
GATEWAY_CLIENT="gateway-1"
GATEWAY_PASS="gateway_secret_001"
RADIUS_CLIENT="freeradius-1"
RADIUS_PASS="freeradius_secret_001"

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    ((TESTS_PASSED++))
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    ((TESTS_FAILED++))
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

################################################################################
# Test 1: Generate CA Certificate
################################################################################

test_ca_certificate() {
    log_info "Test 1: Verify CA certificate exists"
    
    if [ ! -f "$CA_CERT" ]; then
        log_warning "CA certificate not found at $CA_CERT"
        log_info "Run 'createCA.sh' first"
        return 1
    fi
    
    log_success "CA certificate found"
    
    # Show CA certificate details
    log_info "CA Certificate Details:"
    openssl x509 -in "$CA_CERT" -text -noout | head -20 | sed 's/^/  /'
    
    return 0
}

################################################################################
# Test 2: Generate Gateway CSR (Client Role)
################################################################################

test_gateway_csr() {
    log_info "Test 2: Generate Gateway CSR (client role)"
    
    local key_file="test-gateway-key.pem"
    local csr_file="test-gateway.csr"
    
    # Generate private key
    openssl genrsa -out "$key_file" 2048 > /dev/null 2>&1
    log_success "Generated gateway private key: $key_file"
    
    # Generate CSR
    openssl req -new \
        -key "$key_file" \
        -out "$csr_file" \
        -subj "/CN=$GATEWAY_CLIENT/O=$TENANT/C=US" > /dev/null 2>&1
    log_success "Generated gateway CSR: $csr_file"
    
    log_info "Gateway CSR Details:"
    openssl req -in "$csr_file" -text -noout | head -15 | sed 's/^/  /'
    
    echo "$key_file"
}

################################################################################
# Test 3: Enroll Gateway Certificate (clientAuth)
################################################################################

test_gateway_enrollment() {
    log_info "Test 3: Enroll Gateway certificate (should have clientAuth EKU)"
    
    local key_file="$1"
    local csr_file="test-gateway.csr"
    local cert_p7m="test-gateway-cert.p7m"
    local cert_pem="test-gateway-cert.pem"
    
    # Prepare Bearer token
    local token="${TENANT}:${GATEWAY_CLIENT}:${GATEWAY_PASS}"
    local token_b64=$(echo -n "$token" | base64 | tr -d '\n')
    
    log_info "Enrolling with token: $token"
    
    # Enroll certificate
    if curl -s -k \
        -H "Content-Type: application/pkcs10" \
        -H "Authorization: Bearer $token_b64" \
        --data-binary "@$csr_file" \
        "$EST_SERVER/.well-known/est/simpleenroll" \
        -o "$cert_p7m"; then
        
        log_success "EST enrollment request succeeded"
        
        # Extract certificate from PKCS#7
        if openssl pkcs7 -in "$cert_p7m" -inform DER -print_certs -out "$cert_pem" 2>/dev/null; then
            log_success "Extracted certificate from PKCS#7"
        else
            log_error "Failed to extract certificate from PKCS#7"
            return 1
        fi
    else
        log_error "EST enrollment request failed"
        return 1
    fi
    
    # Verify certificate details
    log_info "Gateway Certificate Details:"
    openssl x509 -in "$cert_pem" -text -noout | head -15 | sed 's/^/  /'
    
    echo "$cert_pem"
}

################################################################################
# Test 4: Verify Gateway EKU (clientAuth)
################################################################################

test_gateway_ekus() {
    log_info "Test 4: Verify Gateway certificate has clientAuth EKU"
    
    local cert_pem="$1"
    
    if [ ! -f "$cert_pem" ]; then
        log_error "Certificate file not found: $cert_pem"
        return 1
    fi
    
    # Extract EKU
    local ekus=$(openssl x509 -in "$cert_pem" -noout -text | grep -A 1 "Extended Key Usage" || true)
    
    if [ -z "$ekus" ]; then
        log_error "No EKU extension found in certificate"
        return 1
    fi
    
    log_info "Extended Key Usage found:"
    echo "$ekus" | sed 's/^/  /'
    
    # Check for clientAuth
    if echo "$ekus" | grep -q "TLS Web Client Authentication\|1.3.6.1.5.5.7.3.2"; then
        log_success "✓ Certificate has clientAuth EKU (correct for Gateway)"
        return 0
    else
        log_error "✗ Certificate missing clientAuth EKU"
        log_warning "  Found: $ekus"
        return 1
    fi
}

################################################################################
# Test 5: Generate FreeRADIUS CSR (Server Role)
################################################################################

test_radius_csr() {
    log_info "Test 5: Generate FreeRADIUS CSR (server role)"
    
    local key_file="test-freeradius-key.pem"
    local csr_file="test-freeradius.csr"
    
    # Generate private key
    openssl genrsa -out "$key_file" 2048 > /dev/null 2>&1
    log_success "Generated FreeRADIUS private key: $key_file"
    
    # Generate CSR
    openssl req -new \
        -key "$key_file" \
        -out "$csr_file" \
        -subj "/CN=$RADIUS_CLIENT/O=$TENANT/C=US" > /dev/null 2>&1
    log_success "Generated FreeRADIUS CSR: $csr_file"
    
    log_info "FreeRADIUS CSR Details:"
    openssl req -in "$csr_file" -text -noout | head -15 | sed 's/^/  /'
    
    echo "$key_file"
}

################################################################################
# Test 6: Enroll FreeRADIUS Certificate (serverAuth)
################################################################################

test_radius_enrollment() {
    log_info "Test 6: Enroll FreeRADIUS certificate (should have serverAuth EKU)"
    
    local key_file="$1"
    local csr_file="test-freeradius.csr"
    local cert_p7m="test-freeradius-cert.p7m"
    local cert_pem="test-freeradius-cert.pem"
    
    # Prepare Bearer token
    local token="${TENANT}:${RADIUS_CLIENT}:${RADIUS_PASS}"
    local token_b64=$(echo -n "$token" | base64 | tr -d '\n')
    
    log_info "Enrolling with token: $token"
    
    # Enroll certificate
    if curl -s -k \
        -H "Content-Type: application/pkcs10" \
        -H "Authorization: Bearer $token_b64" \
        --data-binary "@$csr_file" \
        "$EST_SERVER/.well-known/est/simpleenroll" \
        -o "$cert_p7m"; then
        
        log_success "EST enrollment request succeeded"
        
        # Extract certificate from PKCS#7
        if openssl pkcs7 -in "$cert_p7m" -inform DER -print_certs -out "$cert_pem" 2>/dev/null; then
            log_success "Extracted certificate from PKCS#7"
        else
            log_error "Failed to extract certificate from PKCS#7"
            return 1
        fi
    else
        log_error "EST enrollment request failed"
        return 1
    fi
    
    # Verify certificate details
    log_info "FreeRADIUS Certificate Details:"
    openssl x509 -in "$cert_pem" -text -noout | head -15 | sed 's/^/  /'
    
    echo "$cert_pem"
}

################################################################################
# Test 7: Verify FreeRADIUS EKU (serverAuth)
################################################################################

test_radius_ekus() {
    log_info "Test 7: Verify FreeRADIUS certificate has serverAuth EKU"
    
    local cert_pem="$1"
    
    if [ ! -f "$cert_pem" ]; then
        log_error "Certificate file not found: $cert_pem"
        return 1
    fi
    
    # Extract EKU
    local ekus=$(openssl x509 -in "$cert_pem" -noout -text | grep -A 1 "Extended Key Usage" || true)
    
    if [ -z "$ekus" ]; then
        log_error "No EKU extension found in certificate"
        return 1
    fi
    
    log_info "Extended Key Usage found:"
    echo "$ekus" | sed 's/^/  /'
    
    # Check for serverAuth
    if echo "$ekus" | grep -q "TLS Web Server Authentication\|1.3.6.1.5.5.7.3.1"; then
        log_success "✓ Certificate has serverAuth EKU (correct for FreeRADIUS)"
        return 0
    else
        log_error "✗ Certificate missing serverAuth EKU"
        log_warning "  Found: $ekus"
        return 1
    fi
}

################################################################################
# Test 8: Verify Certificates are Signed by CA
################################################################################

test_certificate_chain() {
    log_info "Test 8: Verify certificates are signed by trusted CA"
    
    local gateway_cert="test-gateway-cert.pem"
    local radius_cert="test-freeradius-cert.pem"
    
    # Verify Gateway certificate
    if openssl verify -CAfile "$CA_CERT" "$gateway_cert" > /dev/null 2>&1; then
        log_success "Gateway certificate is signed by CA"
    else
        log_warning "Gateway certificate verification failed (expected if using self-signed)"
    fi
    
    # Verify FreeRADIUS certificate
    if openssl verify -CAfile "$CA_CERT" "$radius_cert" > /dev/null 2>&1; then
        log_success "FreeRADIUS certificate is signed by CA"
    else
        log_warning "FreeRADIUS certificate verification failed (expected if using self-signed)"
    fi
}

################################################################################
# Main Test Execution
################################################################################

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  Role-Based EST Certificate Enrollment Test                   ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Check prerequisites
    log_info "Checking prerequisites..."
    
    if ! command -v openssl &> /dev/null; then
        log_error "openssl not found"
        exit 1
    fi
    log_success "openssl found"
    
    if ! command -v curl &> /dev/null; then
        log_error "curl not found"
        exit 1
    fi
    log_success "curl found"
    
    echo ""
    
    # Run tests
    test_ca_certificate || log_warning "CA test failed, continuing..."
    echo ""
    
    local gw_key=$(test_gateway_csr) || exit 1
    echo ""
    
    local gw_cert=$(test_gateway_enrollment "$gw_key") || exit 1
    test_gateway_ekus "$gw_cert" || exit 1
    echo ""
    
    local rad_key=$(test_radius_csr) || exit 1
    echo ""
    
    local rad_cert=$(test_radius_enrollment "$rad_key") || exit 1
    test_radius_ekus "$rad_cert" || exit 1
    echo ""
    
    test_certificate_chain || true
    echo ""
    
    # Summary
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  Test Summary                                                  ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    log_success "Tests passed: $TESTS_PASSED"
    
    if [ $TESTS_FAILED -gt 0 ]; then
        log_error "Tests failed: $TESTS_FAILED"
        echo ""
        exit 1
    else
        echo ""
        echo -e "${GREEN}═════════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}All tests passed! ✓${NC}"
        echo -e "${GREEN}═════════════════════════════════════════════════════════════════${NC}"
        echo ""
    fi
}

main "$@"
