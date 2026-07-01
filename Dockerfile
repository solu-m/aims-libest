# Multi-Stage Dockerfile for Multi-Tenant EST Server
# Stage 1: Build environment
FROM ubuntu:22.04 AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    autoconf \
    automake \
    libtool \
    libssl-dev \
    git \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /build

# Copy source code
COPY . /build/

# Set up tenant infrastructure
RUN bash -c 'set -e; \
    TENANTS_DIR="/build/tenants"; \
    mkdir -p "$TENANTS_DIR"; \
    for tenant in gateway iot freeradius; do \
        echo "Setting up tenant: $tenant"; \
        mkdir -p "$TENANTS_DIR/$tenant/private"; \
        mkdir -p "$TENANTS_DIR/$tenant/newcerts"; \
        touch "$TENANTS_DIR/$tenant/index.txt"; \
        echo "01" > "$TENANTS_DIR/$tenant/serial"; \
        openssl genrsa -out "$TENANTS_DIR/$tenant/private/cakey.pem" 4096 2>/dev/null; \
        openssl req -new -x509 -days 3650 \
            -key "$TENANTS_DIR/$tenant/private/cakey.pem" \
            -out "$TENANTS_DIR/$tenant/cacert.crt" -sha256 \
            -subj "/C=US/ST=CA/L=SanJose/O=Cisco/OU=$tenant/CN=$tenant-CA" 2>/dev/null; \
        echo "Tenant $tenant setup complete"; \
    done; \
    echo "All tenants configured successfully"'

# Create OpenSSL configuration files for each tenant
COPY tenants/gateway/gateway.cnf /build/tenants/gateway/gateway.cnf
COPY tenants/iot/iot.cnf /build/tenants/iot/iot.cnf
COPY tenants/freeradius/freeradius.cnf /build/tenants/freeradius/freeradius.cnf

# Update config paths to Docker runtime paths
RUN sed -i 's|dir.*=.*|dir            = /opt/est/tenants/gateway|g' /build/tenants/gateway/gateway.cnf && \
    sed -i 's|dir.*=.*|dir            = /opt/est/tenants/iot|g' /build/tenants/iot/iot.cnf && \
    sed -i 's|dir.*=.*|dir            = /opt/est/tenants/freeradius|g' /build/tenants/freeradius/freeradius.cnf && \
    chmod 644 /build/tenants/*//*.cnf && \
    chmod 600 /build/tenants/*/private/*.pem

# Update multi_tenant_enrollment.c to use Docker paths
RUN sed -i 's|#define REPO_ROOT.*|#define REPO_ROOT "/opt/est"|g' \
    /build/example/server/multi_tenant_enrollment.c

# Update Makefile.am to include multi-tenant module
RUN cd /build/example/server && \
    if ! grep -q "multi_tenant_enrollment.c" Makefile.am; then \
        sed -i 's/estserver_SOURCES = estserver.c ossl_srv.c/estserver_SOURCES = estserver.c ossl_srv.c multi_tenant_enrollment.c/g' Makefile.am; \
        sed -i 's/noinst_HEADERS = ossl_srv.h/noinst_HEADERS = ossl_srv.h multi_tenant_enrollment.h/g' Makefile.am; \
    fi

# Generate server certificate and key for TLS
RUN mkdir -p /build/certs && \
    openssl genrsa -out /build/certs/server.key 2048 && \
    openssl req -new -x509 -days 365 -key /build/certs/server.key \
        -out /build/certs/server.crt \
        -subj "/C=US/ST=CA/L=SanJose/O=Cisco/CN=est-server"

# Build libest with multi-tenant support
# Use existing configure script (skip autogen.sh to avoid AM_INIT_AUTOMAKE duplication)
# Build only library and server (skip client to avoid FIPS_mode issues with OpenSSL 3.0)
# Add FIPS compatibility stub for OpenSSL 3.0
# Compile multi_tenant_enrollment.c directly and link with server
RUN cd /build && \
    ./configure --prefix=/opt/est \
                --with-ssl-dir=/usr \
                --disable-safec \
                CFLAGS="-Wno-error -DOPENSSL_API_COMPAT=0x10100000L" && \
    make -j$(nproc) -C safe_c_stub && \
    cd /build/src/est && \
    gcc -c fips_compat.c -I. -I/usr/include -fPIC -DHAVE_CONFIG_H -Wno-error -DOPENSSL_API_COMPAT=0x10100000L && \
    cd /build && \
    make -j$(nproc) -C src LDADD="fips_compat.o" && \
    cd /build/example/server && \
    gcc -c multi_tenant_enrollment.c -I../../src/est -I/usr/include -DHAVE_CONFIG_H -Wno-error -DOPENSSL_API_COMPAT=0x10100000L -Wall && \
    cd /build && \
    make -j$(nproc) -C example/server LDADD="multi_tenant_enrollment.o" && \
    make install -C safe_c_stub && \
    make install -C src && \
    make install -C example/server

# Stage 2: Runtime environment
FROM ubuntu:22.04

# Install runtime dependencies only
RUN apt-get update && apt-get install -y \
    libssl3 \
    openssl \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create application user
RUN useradd -m -u 1000 -s /bin/bash estuser

# Set up directory structure
RUN mkdir -p /opt/est/tenants && \
    chown -R estuser:estuser /opt/est

# Copy built artifacts from builder
COPY --from=builder /opt/est /opt/est
COPY --from=builder /build/tenants /opt/est/tenants
COPY --from=builder /build/certs /opt/est/certs
COPY --from=builder /build/example/server/estserver /opt/est/bin/estserver
COPY --from=builder /build/example/server/.libs/*.so* /opt/est/lib/ 2>/dev/null || true

# Set ownership
RUN chown -R estuser:estuser /opt/est && \
    chmod -R 755 /opt/est/tenants/*/newcerts && \
    chmod -R 700 /opt/est/tenants/*/private && \
    chmod 600 /opt/est/tenants/*/private/*.pem

# Set library path
ENV LD_LIBRARY_PATH=/opt/est/lib:/usr/local/lib:$LD_LIBRARY_PATH

# Switch to non-root user
USER estuser
WORKDIR /opt/est

# Expose EST server port
EXPOSE 8085

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -k https://localhost:8085/.well-known/est/gateway/cacerts || exit 1

# Start EST server with multi-tenant support
CMD ["/opt/est/bin/estserver", \
     "-v", \
     "-p", "8085", \
     "-c", "/opt/est/certs/server.crt", \
     "-k", "/opt/est/certs/server.key", \
     "-r", "/opt/est/tenants/gateway/cacert.crt", \
     "-u", \
     "-b"]

# Labels
LABEL maintainer="Multi-Tenant EST Server"
LABEL description="Highly secure, multi-tenant Certificate Authority engine based on libest"
LABEL version="1.0.0"
