#!/bin/bash
#
# Quick Docker Build and Test Script
# Automates the complete Docker workflow
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}    Multi-Tenant EST Server - Docker Quick Start${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}✗ Docker is not running${NC}"
    echo "Please start Docker Desktop and try again."
    exit 1
fi
echo -e "${GREEN}✓ Docker is running${NC}"

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}✗ docker-compose not found${NC}"
    echo "Please install docker-compose and try again."
    exit 1
fi
echo -e "${GREEN}✓ docker-compose is available${NC}"
echo ""

# Parse command line arguments
SKIP_BUILD=false
SKIP_TEST=false
CLEANUP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --skip-test)
            SKIP_TEST=true
            shift
            ;;
        --cleanup)
            CLEANUP=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-build    Skip Docker image build step"
            echo "  --skip-test     Skip automated tests"
            echo "  --cleanup       Remove existing containers and volumes"
            echo "  --help          Show this help message"
            echo ""
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Cleanup if requested
if [ "$CLEANUP" = true ]; then
    echo -e "${YELLOW}Cleaning up existing containers and volumes...${NC}"
    docker-compose down -v 2>/dev/null || true
    echo -e "${GREEN}✓ Cleanup complete${NC}"
    echo ""
fi

# Step 1: Build Docker image
if [ "$SKIP_BUILD" = false ]; then
    echo -e "${BLUE}Step 1: Building Docker image${NC}"
    echo "This may take 5-10 minutes on first build..."
    echo ""
    
    if docker-compose build; then
        echo ""
        echo -e "${GREEN}✓ Docker image built successfully${NC}"
    else
        echo ""
        echo -e "${RED}✗ Docker build failed${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}Skipping Docker build (--skip-build specified)${NC}"
fi
echo ""

# Step 2: Start EST server
echo -e "${BLUE}Step 2: Starting EST server${NC}"
echo ""

docker-compose up -d est-server

# Wait for server to be healthy
echo -e "${YELLOW}Waiting for EST server to be ready...${NC}"
for i in {1..60}; do
    HEALTH=$(docker inspect multi-tenant-est-server --format='{{.State.Health.Status}}' 2>/dev/null || echo "starting")
    
    if [ "$HEALTH" = "healthy" ]; then
        echo -e "${GREEN}✓ EST server is healthy and ready${NC}"
        break
    fi
    
    if [ $i -eq 60 ]; then
        echo -e "${RED}✗ EST server failed to become healthy${NC}"
        echo ""
        echo "Server logs:"
        docker-compose logs est-server | tail -20
        exit 1
    fi
    
    echo -ne "  Health check: $HEALTH (attempt $i/60)\r"
    sleep 2
done
echo ""

# Show server info
echo -e "${BLUE}Server Information:${NC}"
docker-compose ps
echo ""

# Step 3: Run tests
if [ "$SKIP_TEST" = false ]; then
    echo -e "${BLUE}Step 3: Running integration tests${NC}"
    echo ""
    
    # Create test-results directory
    mkdir -p test-results
    
    # Run tests
    if docker-compose run --rm test-client; then
        echo ""
        echo -e "${GREEN}✓ All tests passed${NC}"
        TEST_SUCCESS=true
    else
        echo ""
        echo -e "${RED}✗ Some tests failed${NC}"
        TEST_SUCCESS=false
    fi
    
    # Show test results
    if [ -f "test-results/test-results.txt" ]; then
        echo ""
        echo -e "${BLUE}Test Results Summary:${NC}"
        tail -20 test-results/test-results.txt
    fi
else
    echo -e "${YELLOW}Skipping tests (--skip-test specified)${NC}"
    TEST_SUCCESS=true
fi
echo ""

# Step 4: Quick manual test
echo -e "${BLUE}Step 4: Quick manual connectivity test${NC}"
echo ""

echo "Testing CA certificate retrieval..."
if curl -k -s https://localhost:8085/.well-known/est/gateway/cacerts -o test-results/manual_gateway_ca.p7 2>/dev/null; then
    if [ -s test-results/manual_gateway_ca.p7 ]; then
        echo -e "${GREEN}✓ Gateway CA certificate retrieved successfully${NC}"
        echo ""
        echo "Certificate details:"
        openssl pkcs7 -in test-results/manual_gateway_ca.p7 -inform DER -print_certs 2>/dev/null | \
            openssl x509 -noout -subject -issuer -dates 2>/dev/null | sed 's/^/  /'
    else
        echo -e "${RED}✗ Failed to retrieve CA certificate (empty file)${NC}"
    fi
else
    echo -e "${RED}✗ Failed to connect to EST server${NC}"
fi
echo ""

# Final summary
echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}                        Summary${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""

if [ "$TEST_SUCCESS" = true ]; then
    echo -e "${GREEN}✓ Multi-Tenant EST Server is OPERATIONAL${NC}"
    echo ""
    echo "Server is running at: https://localhost:8085"
    echo ""
    echo "Available endpoints:"
    echo "  - https://localhost:8085/.well-known/est/gateway/cacerts"
    echo "  - https://localhost:8085/.well-known/est/iot/cacerts"
    echo "  - https://localhost:8085/.well-known/est/freeradius/cacerts"
    echo ""
    echo "Example commands:"
    echo "  # Retrieve CA certificate"
    echo "  curl -k https://localhost:8085/.well-known/est/gateway/cacerts -o ca.p7"
    echo ""
    echo "  # View server logs"
    echo "  docker-compose logs -f est-server"
    echo ""
    echo "  # Stop server"
    echo "  docker-compose down"
    echo ""
    echo "  # Full cleanup (including volumes)"
    echo "  docker-compose down -v"
    echo ""
    echo "For more information, see DOCKER_QUICKSTART.md"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Tests failed - please review errors above${NC}"
    echo ""
    echo "Debug commands:"
    echo "  docker-compose logs est-server"
    echo "  docker exec -it multi-tenant-est-server bash"
    echo "  cat test-results/test-results.txt"
    echo ""
    exit 1
fi
