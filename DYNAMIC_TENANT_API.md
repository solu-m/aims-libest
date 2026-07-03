# Dynamic Tenant Management API Design

## Overview

Enable runtime registration and management of EST tenants without container restarts.

---

## API Endpoints

### 1. Register New Tenant

**POST** `/admin/tenants`

Register a new tenant and automatically provision CA infrastructure.

**Request Headers:**
```
Authorization: Bearer <admin-api-key>
Content-Type: application/json
```

**Request Body:**
```json
{
  "tenant_id": "manufacturing",
  "display_name": "Manufacturing Division",
  "ca_config": {
    "common_name": "manufacturing-CA",
    "country": "US",
    "state": "CA",
    "locality": "SanJose",
    "organization": "Cisco",
    "organizational_unit": "Manufacturing",
    "key_size": 4096,
    "validity_days": 3650,
    "digest": "sha256"
  },
  "cert_policy": {
    "default_validity_days": 365,
    "max_validity_days": 730,
    "require_cn": true,
    "allowed_key_usages": ["digitalSignature", "keyEncipherment"],
    "unique_subject": false
  },
  "auth_config": {
    "require_pop": false,
    "allowed_users": ["mfguser1", "mfguser2"],
    "client_cert_auth": false
  }
}
```

**Response (201 Created):**
```json
{
  "status": "success",
  "tenant_id": "manufacturing",
  "message": "Tenant created successfully",
  "ca_certificate": "-----BEGIN CERTIFICATE-----\n...",
  "endpoints": {
    "cacerts": "https://est-server:8085/.well-known/est/manufacturing/cacerts",
    "csrattrs": "https://est-server:8085/.well-known/est/manufacturing/csrattrs",
    "simpleenroll": "https://est-server:8085/.well-known/est/manufacturing/simpleenroll",
    "simplereenroll": "https://est-server:8085/.well-known/est/manufacturing/simplereenroll"
  },
  "created_at": "2026-07-03T15:40:00Z"
}
```

**Error Responses:**
- `400 Bad Request` - Invalid tenant configuration
- `409 Conflict` - Tenant ID already exists
- `500 Internal Server Error` - CA provisioning failed

---

### 2. List All Tenants

**GET** `/admin/tenants`

List all registered tenants.

**Response (200 OK):**
```json
{
  "status": "success",
  "count": 4,
  "tenants": [
    {
      "tenant_id": "gateway",
      "display_name": "Gateway Division",
      "status": "active",
      "ca_subject": "CN=gateway-CA, OU=gateway, O=Cisco",
      "certificates_issued": 127,
      "created_at": "2026-07-01T08:00:00Z",
      "last_enrollment": "2026-07-03T15:30:00Z"
    },
    {
      "tenant_id": "iot",
      "display_name": "IoT Division",
      "status": "active",
      "ca_subject": "CN=iot-CA, OU=iot, O=Cisco",
      "certificates_issued": 453,
      "created_at": "2026-07-01T08:00:00Z",
      "last_enrollment": "2026-07-03T15:25:00Z"
    }
  ]
}
```

---

### 3. Get Tenant Details

**GET** `/admin/tenants/{tenant_id}`

Get detailed information about a specific tenant.

**Response (200 OK):**
```json
{
  "status": "success",
  "tenant": {
    "tenant_id": "manufacturing",
    "display_name": "Manufacturing Division",
    "status": "active",
    "ca_config": {
      "common_name": "manufacturing-CA",
      "country": "US",
      "state": "CA",
      "locality": "SanJose",
      "organization": "Cisco",
      "organizational_unit": "Manufacturing",
      "key_size": 4096,
      "validity_days": 3650,
      "serial_start": "01",
      "current_serial": "3F"
    },
    "statistics": {
      "certificates_issued": 62,
      "certificates_revoked": 3,
      "last_enrollment": "2026-07-03T14:22:15Z",
      "last_revocation": "2026-07-02T10:15:00Z"
    },
    "storage": {
      "ca_cert_path": "/opt/est/tenants/manufacturing/cacert.crt",
      "database_path": "/opt/est/tenants/manufacturing/index.txt",
      "config_path": "/opt/est/tenants/manufacturing/manufacturing.cnf"
    },
    "created_at": "2026-07-03T15:40:00Z",
    "updated_at": "2026-07-03T15:40:00Z"
  }
}
```

---

### 4. Update Tenant Configuration

**PATCH** `/admin/tenants/{tenant_id}`

Update tenant policies (non-CA settings only).

**Request Body:**
```json
{
  "display_name": "Manufacturing & Quality Control",
  "cert_policy": {
    "default_validity_days": 730,
    "max_validity_days": 1095
  },
  "auth_config": {
    "allowed_users": ["mfguser1", "mfguser2", "mfguser3"]
  }
}
```

**Response (200 OK):**
```json
{
  "status": "success",
  "message": "Tenant updated successfully",
  "updated_fields": ["display_name", "cert_policy", "auth_config"]
}
```

---

### 5. Delete Tenant

**DELETE** `/admin/tenants/{tenant_id}`

Delete a tenant and optionally archive its data.

**Query Parameters:**
- `archive=true` - Archive tenant data before deletion (default: false)
- `force=true` - Force deletion even if active certificates exist

**Response (200 OK):**
```json
{
  "status": "success",
  "message": "Tenant deleted successfully",
  "archive_path": "/opt/est/archives/manufacturing_20260703_154000.tar.gz",
  "certificates_archived": 62
}
```

---

### 6. Get Tenant Statistics

**GET** `/admin/tenants/{tenant_id}/stats`

Get detailed statistics for a tenant.

**Response (200 OK):**
```json
{
  "status": "success",
  "tenant_id": "manufacturing",
  "statistics": {
    "certificates": {
      "total_issued": 62,
      "active": 59,
      "expired": 0,
      "revoked": 3
    },
    "enrollments": {
      "total": 62,
      "last_24h": 5,
      "last_7d": 18,
      "last_30d": 42
    },
    "current_serial": "3F",
    "database_size": "4.2 KB",
    "storage_usage": "156 KB"
  }
}
```

---

### 7. Export Tenant CA Certificate

**GET** `/admin/tenants/{tenant_id}/ca-cert`

Export the tenant's CA certificate.

**Query Parameters:**
- `format=pem|der|pkcs7` (default: pem)

**Response (200 OK):**
```
Content-Type: application/x-pem-file

-----BEGIN CERTIFICATE-----
MIIFXjCCA0agAwIBAgIUXJZ...
-----END CERTIFICATE-----
```

---

### 8. Revoke Certificate

**POST** `/admin/tenants/{tenant_id}/revoke`

Revoke a certificate issued by this tenant's CA.

**Request Body:**
```json
{
  "serial": "3E",
  "reason": "keyCompromise",
  "revocation_date": "2026-07-03T15:40:00Z"
}
```

**Response (200 OK):**
```json
{
  "status": "success",
  "message": "Certificate revoked successfully",
  "serial": "3E",
  "revocation_date": "2026-07-03T15:40:00Z"
}
```

---

## Implementation Architecture

### Component 1: Tenant Registry (SQLite Database)

**Schema:**
```sql
CREATE TABLE tenants (
    tenant_id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    status TEXT DEFAULT 'active',  -- active, suspended, deleted
    ca_subject TEXT NOT NULL,
    ca_config JSON NOT NULL,
    cert_policy JSON NOT NULL,
    auth_config JSON NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE tenant_stats (
    tenant_id TEXT PRIMARY KEY,
    certificates_issued INTEGER DEFAULT 0,
    certificates_revoked INTEGER DEFAULT 0,
    last_enrollment TIMESTAMP,
    last_revocation TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(tenant_id)
);

CREATE TABLE tenant_users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tenant_id TEXT NOT NULL,
    username TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(tenant_id),
    UNIQUE(tenant_id, username)
);
```

### Component 2: Dynamic Provisioning Engine

**File:** `example/server/tenant_provisioner.c`

```c
// Core provisioning function
int provision_tenant(const char *tenant_id, const tenant_config_t *config) {
    char tenant_dir[MAX_PATH_LEN];
    char cmd[MAX_CMD_LEN];
    
    // 1. Create tenant directory structure
    snprintf(tenant_dir, sizeof(tenant_dir), "%s/tenants/%s", REPO_ROOT, tenant_id);
    mkdir_p(tenant_dir);
    mkdir_p(tenant_dir, "newcerts");
    mkdir_p(tenant_dir, "private");
    
    // 2. Generate CA private key
    generate_ca_key(tenant_id, config->key_size);
    
    // 3. Create self-signed CA certificate
    create_ca_cert(tenant_id, config);
    
    // 4. Generate OpenSSL config file
    generate_openssl_config(tenant_id, config);
    
    // 5. Initialize database files
    initialize_ca_database(tenant_id);
    
    // 6. Register in tenant registry
    register_tenant_in_db(tenant_id, config);
    
    return 0;
}
```

### Component 3: HTTP Admin API Handler

**File:** `example/server/admin_api.c`

```c
// Main admin API request handler
void handle_admin_request(struct mg_connection *conn, const char *uri, const char *method) {
    
    // Authentication check
    if (!validate_admin_token(conn)) {
        send_json_response(conn, 401, "{\"error\":\"Unauthorized\"}");
        return;
    }
    
    // Route to appropriate handler
    if (strcmp(uri, "/admin/tenants") == 0) {
        if (strcmp(method, "POST") == 0) {
            handle_create_tenant(conn);
        } else if (strcmp(method, "GET") == 0) {
            handle_list_tenants(conn);
        }
    } else if (strncmp(uri, "/admin/tenants/", 15) == 0) {
        const char *tenant_id = uri + 15;
        
        if (strcmp(method, "GET") == 0) {
            handle_get_tenant(conn, tenant_id);
        } else if (strcmp(method, "PATCH") == 0) {
            handle_update_tenant(conn, tenant_id);
        } else if (strcmp(method, "DELETE") == 0) {
            handle_delete_tenant(conn, tenant_id);
        }
    }
}
```

### Component 4: Modified Enrollment Callback

**Update:** `multi_tenant_enrollment.c`

```c
BIO *multi_tenant_enroll(unsigned char *p10buf, int p10len, const char *tenant_id) {
    
    // Check if tenant exists in registry
    if (!tenant_exists(tenant_id)) {
        fprintf(stderr, "[ERROR] Tenant '%s' not found in registry\n", tenant_id);
        return NULL;
    }
    
    // Load tenant configuration from database
    tenant_config_t *config = load_tenant_config(tenant_id);
    if (!config) {
        fprintf(stderr, "[ERROR] Failed to load config for tenant '%s'\n", tenant_id);
        return NULL;
    }
    
    // Apply tenant-specific policies
    apply_cert_policy(config->cert_policy);
    
    // Continue with existing enrollment logic...
    // (existing 7-step pipeline)
    
    // Update statistics
    increment_tenant_stats(tenant_id, "certificates_issued");
    update_last_enrollment(tenant_id);
    
    free(config);
    return result;
}
```

---

## Usage Examples

### Example 1: Register New Tenant via curl

```bash
curl -X POST https://localhost:8085/admin/tenants \
  -H "Authorization: Bearer your-admin-api-key-here" \
  -H "Content-Type: application/json" \
  -d '{
    "tenant_id": "manufacturing",
    "display_name": "Manufacturing Division",
    "ca_config": {
      "common_name": "manufacturing-CA",
      "country": "US",
      "state": "CA",
      "locality": "SanJose",
      "organization": "Cisco",
      "organizational_unit": "Manufacturing",
      "key_size": 4096,
      "validity_days": 3650
    },
    "cert_policy": {
      "default_validity_days": 365,
      "unique_subject": false
    },
    "auth_config": {
      "allowed_users": ["mfguser"]
    }
  }'
```

### Example 2: List All Tenants

```bash
curl -X GET https://localhost:8085/admin/tenants \
  -H "Authorization: Bearer your-admin-api-key-here"
```

### Example 3: Immediately Use New Tenant

```bash
# 1. Register tenant
curl -X POST https://localhost:8085/admin/tenants \
  -H "Authorization: Bearer admin-key" \
  -H "Content-Type: application/json" \
  -d '{"tenant_id": "manufacturing", ...}'

# 2. Get CA cert (no restart needed!)
curl -k https://localhost:8085/.well-known/est/manufacturing/cacerts \
  -o manufacturing-ca.p7

# 3. Enroll device immediately
openssl req -new -key device.key -outform DER | base64 > device.b64
curl -k -u mfguser:password \
  -H "Content-Type: application/pkcs10" \
  --data-binary @device.b64 \
  https://localhost:8085/.well-known/est/manufacturing/simpleenroll \
  -o device-cert.p7
```

---

## Security Considerations

1. **Admin API Authentication**
   - Use strong API keys (JWT tokens recommended)
   - Store API keys in environment variables or secrets manager
   - Implement rate limiting on admin endpoints

2. **Tenant Isolation**
   - Each tenant's CA key must be stored with restricted permissions (0600)
   - Separate database files prevent cross-tenant data leakage

3. **Audit Logging**
   - Log all admin API operations
   - Track who created/modified/deleted tenants
   - Store audit trail in separate log file

4. **Input Validation**
   - Validate tenant_id format (alphanumeric, hyphens only)
   - Sanitize all configuration inputs
   - Enforce maximum key sizes and validity periods

---

## Database Schema for Tenant Registry

**File:** `example/server/tenant_registry_schema.sql`

```sql
-- Main tenant registry
CREATE TABLE IF NOT EXISTS tenants (
    tenant_id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    status TEXT CHECK(status IN ('active', 'suspended', 'deleted')) DEFAULT 'active',
    ca_subject TEXT NOT NULL,
    ca_config TEXT NOT NULL,  -- JSON
    cert_policy TEXT NOT NULL,  -- JSON
    auth_config TEXT NOT NULL,  -- JSON
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Tenant statistics
CREATE TABLE IF NOT EXISTS tenant_stats (
    tenant_id TEXT PRIMARY KEY,
    certificates_issued INTEGER DEFAULT 0,
    certificates_revoked INTEGER DEFAULT 0,
    last_enrollment TEXT,
    last_revocation TEXT,
    FOREIGN KEY (tenant_id) REFERENCES tenants(tenant_id) ON DELETE CASCADE
);

-- Tenant-specific users
CREATE TABLE IF NOT EXISTS tenant_users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tenant_id TEXT NOT NULL,
    username TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    UNIQUE(tenant_id, username)
);

-- Admin API keys
CREATE TABLE IF NOT EXISTS admin_api_keys (
    key_id TEXT PRIMARY KEY,
    key_hash TEXT NOT NULL,
    description TEXT,
    created_by TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    expires_at TEXT,
    last_used TEXT
);

-- Audit log
CREATE TABLE IF NOT EXISTS audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT DEFAULT CURRENT_TIMESTAMP,
    operation TEXT NOT NULL,
    tenant_id TEXT,
    user TEXT,
    ip_address TEXT,
    request_data TEXT,
    response_status INTEGER
);

-- Indexes for performance
CREATE INDEX idx_tenants_status ON tenants(status);
CREATE INDEX idx_audit_tenant ON audit_log(tenant_id);
CREATE INDEX idx_audit_timestamp ON audit_log(timestamp);
```

---

## Configuration File

**File:** `admin_api_config.json`

```json
{
  "admin_api": {
    "enabled": true,
    "bind_address": "0.0.0.0",
    "port": 8086,
    "tls": {
      "enabled": true,
      "cert_file": "/opt/est/certs/admin-server.crt",
      "key_file": "/opt/est/certs/admin-server.key"
    },
    "authentication": {
      "method": "bearer_token",
      "token_header": "Authorization"
    },
    "rate_limiting": {
      "enabled": true,
      "max_requests_per_minute": 60
    }
  },
  "tenant_defaults": {
    "ca_key_size": 4096,
    "ca_validity_days": 3650,
    "cert_default_validity_days": 365,
    "digest_algorithm": "sha256"
  },
  "storage": {
    "tenant_registry_db": "/opt/est/data/tenant_registry.db",
    "tenant_data_dir": "/opt/est/tenants",
    "archive_dir": "/opt/est/archives"
  }
}
```

---

## Implementation Phases

### Phase 1: Core Infrastructure (Week 1)
- [ ] Create tenant registry SQLite database
- [ ] Implement tenant provisioning engine
- [ ] Add tenant existence check in enrollment callback
- [ ] Basic CRUD operations for tenants

### Phase 2: HTTP Admin API (Week 2)
- [ ] Implement admin API HTTP server (separate port 8086)
- [ ] Add authentication/authorization
- [ ] Create tenant registration endpoint
- [ ] List/get tenant endpoints

### Phase 3: Advanced Features (Week 3)
- [ ] Update/delete tenant endpoints
- [ ] Statistics and monitoring
- [ ] Audit logging
- [ ] Certificate revocation API

### Phase 4: Testing & Documentation (Week 4)
- [ ] Integration tests for admin API
- [ ] Performance testing
- [ ] API documentation
- [ ] User guide for tenant management

---

## Benefits

✅ **Zero Downtime** - Add tenants without restarting  
✅ **Self-Service** - Customers can register their own tenants  
✅ **Scalability** - Support hundreds of tenants dynamically  
✅ **Flexibility** - Each tenant has custom policies  
✅ **Audit Trail** - Track all tenant operations  
✅ **RESTful API** - Easy integration with management systems  

---

## Next Steps

1. Review and approve this design
2. Choose implementation approach:
   - Option A: Build admin API in C (integrated with estserver)
   - Option B: Build admin API in Python/Go (separate microservice)
3. Set up development environment
4. Begin Phase 1 implementation
