# Dynamic Tenant Management - Quick Start Guide

This guide shows how to use the new dynamic tenant management API.

## Architecture

```
Port 8085 (Single Entry Point)
    ├── Nginx Gateway
    │   ├── /.well-known/est/* → EST Server (backend port 8086)
    │   └── /admin/*           → Admin API (backend port 8087)
```

## Quick Start

### 1. Start the Services

```bash
# Set admin API key (change this!)
export ADMIN_API_KEY="your-super-secret-admin-key-here"

# Start all services
docker compose -f docker-compose.dynamic.yml up -d

# Check status
docker compose -f docker-compose.dynamic.yml ps
```

### 2. Register a New Tenant

```bash
# Create a new tenant called "manufacturing"
curl -k -X POST https://localhost:8085/admin/tenants \
  -H "Authorization: Bearer your-super-secret-admin-key-here" \
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
      "default_validity_days": 365
    },
    "auth_config": {
      "allowed_users": ["mfguser"]
    }
  }'
```

**Expected Response:**
```json
{
  "status": "success",
  "tenant_id": "manufacturing",
  "message": "Tenant created successfully",
  "ca_certificate": "-----BEGIN CERTIFICATE-----\n...",
  "endpoints": {
    "cacerts": "https://localhost:8085/.well-known/est/manufacturing/cacerts",
    "simpleenroll": "https://localhost:8085/.well-known/est/manufacturing/simpleenroll"
  },
  "created_at": "2026-07-03T15:40:00Z"
}
```

### 3. Use the New Tenant Immediately (No Restart!)

```bash
# Get CA certificate
curl -k https://localhost:8085/.well-known/est/manufacturing/cacerts \
  -o manufacturing-ca.p7

# Enroll a device
openssl genrsa -out mfg-device.key 2048
openssl req -new -key mfg-device.key -out mfg-device.csr \
  -subj "/CN=mfg-robot-001/C=US/ST=CA/O=Cisco/OU=Manufacturing"

openssl req -in mfg-device.csr -outform DER | base64 > mfg-device.b64

curl -k -u estuser:estpwd \
  -H "Content-Type: application/pkcs10" \
  -H "Content-Transfer-Encoding: base64" \
  --data-binary @mfg-device.b64 \
  https://localhost:8085/.well-known/est/manufacturing/simpleenroll \
  -o mfg-device-cert.p7
```

### 4. List All Tenants

```bash
curl -k https://localhost:8085/admin/tenants \
  -H "Authorization: Bearer your-super-secret-admin-key-here" | jq
```

**Expected Response:**
```json
{
  "status": "success",
  "count": 4,
  "tenants": [
    {
      "tenant_id": "manufacturing",
      "display_name": "Manufacturing Division",
      "status": "active",
      "ca_subject": "/C=US/ST=CA/L=SanJose/O=Cisco/OU=Manufacturing/CN=manufacturing-CA",
      "certificates_issued": 0,
      "created_at": "2026-07-03T15:40:00",
      "last_enrollment": null
    },
    {
      "tenant_id": "gateway",
      "display_name": "Gateway Division",
      "status": "active",
      "ca_subject": "/C=US/ST=CA/L=SanJose/O=Cisco/OU=gateway/CN=gateway-CA",
      "certificates_issued": 5,
      "created_at": "2026-07-01T08:00:00",
      "last_enrollment": "2026-07-03T15:30:00"
    }
  ]
}
```

### 5. Get Tenant Details

```bash
curl -k https://localhost:8085/admin/tenants/manufacturing \
  -H "Authorization: Bearer your-super-secret-admin-key-here" | jq
```

### 6. Delete a Tenant

```bash
curl -k -X DELETE https://localhost:8085/admin/tenants/manufacturing \
  -H "Authorization: Bearer your-super-secret-admin-key-here"
```

## Complete API Reference

### Admin Endpoints

All admin endpoints require authentication:
```
Authorization: Bearer <your-admin-api-key>
```

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/admin/tenants` | Create new tenant |
| GET | `/admin/tenants` | List all tenants |
| GET | `/admin/tenants/{id}` | Get tenant details |
| DELETE | `/admin/tenants/{id}` | Delete tenant |
| GET | `/admin/tenants/{id}/ca-cert` | Download CA certificate |
| GET | `/admin/health` | Health check (no auth required) |

### EST Endpoints

Standard EST protocol endpoints (no changes):

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/.well-known/est/{tenant}/cacerts` | Get CA certificates |
| POST | `/.well-known/est/{tenant}/simpleenroll` | Enroll device certificate |

## Environment Variables

```bash
# Admin API key (CHANGE THIS!)
ADMIN_API_KEY=your-super-secret-admin-key-here

# Tenant data directory (default: /opt/est/tenants)
TENANT_DATA_DIR=/opt/est/tenants

# Registry database path (default: /opt/est/data/tenant_registry.db)
REGISTRY_DB=/opt/est/data/tenant_registry.db
```

## Testing

### Test Admin API

```bash
# Health check
curl -k https://localhost:8085/admin/health

# List tenants
curl -k https://localhost:8085/admin/tenants \
  -H "Authorization: Bearer your-super-secret-admin-key-here"
```

### Test Dynamic Tenant Creation

```bash
# Create tenant
curl -k -X POST https://localhost:8085/admin/tenants \
  -H "Authorization: Bearer your-super-secret-admin-key-here" \
  -H "Content-Type: application/json" \
  -d '{
    "tenant_id": "test-auto",
    "display_name": "Auto-Created Tenant",
    "ca_config": {
      "common_name": "test-auto-CA"
    }
  }'

# Immediately get CA cert (no restart!)
curl -k https://localhost:8085/.well-known/est/test-auto/cacerts | \
  openssl pkcs7 -inform DER -print_certs -text | grep "Subject:"

# Clean up
curl -k -X DELETE https://localhost:8085/admin/tenants/test-auto \
  -H "Authorization: Bearer your-super-secret-admin-key-here"
```

## Logs

```bash
# Gateway logs
docker logs est-gateway

# EST server logs
docker logs est-server-backend

# Admin API logs
docker logs admin-api
```

## Troubleshooting

### Issue: "401 Unauthorized" on admin endpoints

**Solution:** Check your API key:
```bash
export ADMIN_API_KEY="your-super-secret-admin-key-here"
docker compose -f docker-compose.dynamic.yml restart admin-api
```

### Issue: Tenant not found after creation

**Solution:** Check admin API logs:
```bash
docker logs admin-api --tail 50
```

### Issue: EST enrollment fails for new tenant

**Solution:** Check if tenant files were created:
```bash
docker exec admin-api ls -la /opt/est/tenants/your-tenant-id/
```

## Migration from Static Tenants

If you have existing tenants (gateway, iot, freeradius), they will continue to work. You can:

1. Keep using them as-is
2. Register them in the registry for tracking:
```bash
curl -k -X POST https://localhost:8085/admin/tenants \
  -H "Authorization: Bearer key" \
  -H "Content-Type: application/json" \
  -d '{"tenant_id": "gateway", "display_name": "Gateway Division", ...}'
```

## Benefits

✅ **Zero Downtime** - Add tenants without restarting containers  
✅ **Self-Service** - Tenants can be registered via API calls  
✅ **Scalability** - Support unlimited tenants dynamically  
✅ **Single Port** - All access through port 8085  
✅ **Clean Architecture** - Nginx gateway separates concerns  

## Next Steps

1. Secure your admin API key
2. Set up authentication/authorization for tenant users
3. Implement tenant quotas and rate limiting
4. Add monitoring and alerting
5. Backup tenant registry database regularly
