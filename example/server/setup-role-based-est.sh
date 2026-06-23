#!/bin/bash

################################################################################
# setup-role-based-est.sh - Complete setup for role-based EST server
#
# This script automates the setup of:
# 1. EST Server with role-based certificate enrollment
# 2. FreeRADIUS for 802.1X authentication
# 3. Certificate generation and enrollment
#
################################################################################

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[*]${NC} $1"
}

success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

error() {
    echo -e "${RED}[✗]${NC} $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

################################################################################
# Phase 1: Check Prerequisites
################################################################################

phase_prerequisites() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "Phase 1: Checking Prerequisites"
    echo "═══════════════════════════════════════════════════════════════"
    
    log "Checking required commands..."
    
    for cmd in openssl curl make gcc; do
        if command -v $cmd &> /dev/null; then
            success "$cmd found"
        else
            error "$cmd not found. Please install it first."
        fi
    done
    
    log "Checking libest headers..."
    if [ -d "/usr/include/est" ] || [ -d "/usr/local/include/est" ]; then
        success "libest headers found"
    else
        warning "libest headers may not be installed"
        warning "Run: sudo apt-get install libest-dev"
    fi
}

################################################################################
# Phase 2: Build EST Server
################################################################################

phase_build() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "Phase 2: Building EST Server"
    echo "═══════════════════════════════════════════════════════════════"
    
    log "Running autogen..."
    cd "$SCRIPT_DIR/../.."
    ./autogen.sh > /dev/null 2>&1 || warning "autogen may have issues"
    
    log "Configuring..."
    ./configure --enable-est-server > /dev/null 2>&1
    success "Configuration done"
    
    log "Building..."
    make clean > /dev/null 2>&1
    make > /dev/null 2>&1
    success "Build completed"
    
    cd "$SCRIPT_DIR"
}

################################################################################
# Phase 3: Generate CA
################################################################################

phase_ca() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "Phase 3: Generating CA Infrastructure"
    echo "═══════════════════════════════════════════════════════════════"
    
    if [ -d "estCA" ]; then
        warning "estCA directory already exists"
        log "Skipping CA generation (remove estCA to regenerate)"
        return
    fi
    
    log "Creating CA..."
    if [ -f "createCA.sh" ]; then
        bash createCA.sh > /dev/null 2>&1
        success "CA created"
    else
        error "createCA.sh not found"
    fi
    
    log "CA structure:"
    ls -la estCA/ | sed 's/^/  /'
}

################################################################################
# Phase 4: Verify OpenSSL Configs
################################################################################

phase_openssl_configs() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "Phase 4: Verifying OpenSSL Configuration Files"
    echo "═══════════════════════════════════════════════════════════════"
    
    for config in client-auth.cnf server-auth.cnf; do
        if [ -f "$config" ]; then
            success "$config exists"
            log "Verifying syntax..."
            if openssl conf -in "$config" -text > /dev/null 2>&1; then
                success "$config syntax is valid"
            else
                warning "$config may have syntax issues"
            fi
        else
            error "$config not found"
        fi
    done
}

################################################################################
# Phase 5: Verify tenants.json
################################################################################

phase_tenants() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "Phase 5: Verifying tenants.json"
    echo "═══════════════════════════════════════════════════════════════"
    
    if [ ! -f "tenants.json" ]; then
        error "tenants.json not found"
    fi
    
    log "Checking JSON syntax..."
    if python3 -m json.tool tenants.json > /dev/null 2>&1; then
        success "tenants.json is valid JSON"
    else
        error "tenants.json has syntax errors"
    fi
    
    log "Checking tenant configuration..."
    local tenant_count=$(grep -c '"tenant_id"' tenants.json)
    success "Found $tenant_count tenants"
    
    log "Checking client roles..."
    grep -o '"role": "[^"]*"' tenants.json | sort | uniq | sed 's/^/  /'
}

################################################################################
# Phase 6: Generate Test Certificates
################################################################################

phase_test_certs() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "Phase 6: Generating Test Certificates"
    echo "═══════════════════════════════════════════════════════════════"
    
    log "Generating Gateway CSR..."
    openssl req -new \
        -keyout test-gateway-key.pem \
        -out test-gateway.csr \
        -subj "/CN=gateway-1/O=company-a/C=US" > /dev/null 2>&1
    success "Gateway CSR generated"
    
    log "Generating FreeRADIUS CSR..."
    openssl req -new \
        -keyout test-radius-key.pem \
        -out test-radius.csr \
        -subj "/CN=freeradius-1/O=company-a/C=US" > /dev/null 2>&1
    success "FreeRADIUS CSR generated"
    
    log "Generated certificates:"
    ls -la test-*.pem test-*.csr 2>/dev/null | sed 's/^/  /' || true
}

################################################################################
# Phase 7: Start EST Server
################################################################################

phase_start_server() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "Phase 7: Starting EST Server"
    echo "═══════════════════════════════════════════════════════════════"
    
    if [ ! -f "./estserver" ]; then
        error "estserver binary not found. Did build complete successfully?"
    fi
    
    log "Setting environment variables..."
    export EST_OPENSSL_CACONFIG=$(pwd)/estExampleCA.cnf
    export EST_OPENSSL_CADIR=$(pwd)/estCA
    success "Environment configured"
    
    log ""
    log "To start the EST server, run:"
    echo ""
    echo -e "${BLUE}cd $SCRIPT_DIR${NC}"
    echo "export EST_OPENSSL_CACONFIG=\$(pwd)/estExampleCA.cnf"
    echo "export EST_OPENSSL_CADIR=\$(pwd)/estCA"
    echo "./estserver -p 8085 -v"
    echo ""
}

################################################################################
# Phase 8: Test Enrollment
################################################################################

phase_test_enrollment() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "Phase 8: Testing Certificate Enrollment"
    echo "═══════════════════════════════════════════════════════════════"
    
    warning "EST server must be running for this test"
    
    read -p "Is the EST server running on https://localhost:8085? (y/n) " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Testing enrollment..."
        if bash test-role-based-enrollment.sh; then
            success "All enrollment tests passed!"
        else
            warning "Some tests failed. Check EST server logs."
        fi
    else
        log "To run tests later:"
        echo "cd $SCRIPT_DIR"
        echo "./test-role-based-enrollment.sh"
    fi
}

################################################################################
# Main Setup
################################################################################

main() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║   Role-Based EST Server Setup                                ║"
    echo "║   Multi-Tenant EST with clientAuth/serverAuth Support        ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    
    phase_prerequisites
    
    read -p "Build EST server from source? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        phase_build
    else
        log "Skipping build. Make sure estserver binary exists."
    fi
    
    phase_ca
    phase_openssl_configs
    phase_tenants
    phase_test_certs
    phase_start_server
    phase_test_enrollment
    
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║   Setup Complete!                                            ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Read the documentation:"
    echo "   cat IMPLEMENTATION_GUIDE.md"
    echo "   cat ROLE_BASED_ENROLLMENT.md"
    echo ""
    echo "2. Start the EST server:"
    echo "   cd $SCRIPT_DIR"
    echo "   export EST_OPENSSL_CACONFIG=\$(pwd)/estExampleCA.cnf"
    echo "   export EST_OPENSSL_CADIR=\$(pwd)/estCA"
    echo "   ./estserver -p 8085 -v"
    echo ""
    echo "3. In another terminal, test enrollment:"
    echo "   cd $SCRIPT_DIR"
    echo "   ./test-role-based-enrollment.sh"
    echo ""
    echo "4. Integrate with FreeRADIUS and Hostapd for 802.1X authentication"
    echo ""
}

main "$@"
