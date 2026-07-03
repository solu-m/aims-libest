#!/usr/bin/env python3
"""
Multi-Tenant EST Server - Dynamic Tenant Management API
FastAPI-based microservice for runtime tenant provisioning
"""

from fastapi import FastAPI, HTTPException, Header, status, Depends
from fastapi.responses import JSONResponse, FileResponse
from pydantic import BaseModel, Field, validator
from typing import Optional, List, Dict
from datetime import datetime
import sqlite3
import subprocess
import os
import json
import shutil
from pathlib import Path

# Configuration
TENANT_DATA_DIR = os.getenv("TENANT_DATA_DIR", "/opt/est/tenants")
REGISTRY_DB = os.getenv("REGISTRY_DB", "/opt/est/data/tenant_registry.db")
ADMIN_API_KEY = os.getenv("ADMIN_API_KEY", "changeme-admin-key-here")

# Initialize FastAPI app
app = FastAPI(
    title="Multi-Tenant EST Admin API",
    description="Dynamic tenant provisioning and management API",
    version="1.0.0"
)

# ============================================================================
# Pydantic Models
# ============================================================================

class CAConfig(BaseModel):
    common_name: str = Field(..., min_length=1, max_length=64)
    country: str = Field(default="US", min_length=2, max_length=2)
    state: str = Field(default="CA", max_length=64)
    locality: str = Field(default="SanJose", max_length=64)
    organization: str = Field(default="Cisco", max_length=64)
    organizational_unit: Optional[str] = None
    key_size: int = Field(default=4096, ge=2048, le=8192)
    validity_days: int = Field(default=3650, ge=365, le=7300)
    digest: str = Field(default="sha256")

class CertPolicy(BaseModel):
    default_validity_days: int = Field(default=365, ge=1, le=3650)
    max_validity_days: int = Field(default=730, ge=1, le=3650)
    require_cn: bool = True
    unique_subject: bool = False

class AuthConfig(BaseModel):
    require_pop: bool = False
    allowed_users: List[str] = Field(default_factory=list)

class TenantCreateRequest(BaseModel):
    tenant_id: str = Field(..., min_length=1, max_length=32)
    display_name: str = Field(..., min_length=1, max_length=128)
    ca_config: CAConfig
    cert_policy: CertPolicy = Field(default_factory=CertPolicy)
    auth_config: AuthConfig = Field(default_factory=AuthConfig)

    @validator('tenant_id')
    def validate_tenant_id(cls, v):
        import re
        if not re.match(r'^[a-z0-9-]+$', v):
            raise ValueError('tenant_id must contain only lowercase letters, numbers, and hyphens')
        if v in ['admin', 'api', 'health', 'metrics']:
            raise ValueError(f'Reserved tenant ID: {v}')
        return v

# ============================================================================
# Database Functions
# ============================================================================

def init_database():
    """Initialize the tenant registry database"""
    os.makedirs(os.path.dirname(REGISTRY_DB), exist_ok=True)
    
    conn = sqlite3.connect(REGISTRY_DB)
    cursor = conn.cursor()
    
    cursor.executescript("""
        CREATE TABLE IF NOT EXISTS tenants (
            tenant_id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            status TEXT CHECK(status IN ('active', 'suspended', 'deleted')) DEFAULT 'active',
            ca_subject TEXT NOT NULL,
            ca_config TEXT NOT NULL,
            cert_policy TEXT NOT NULL,
            auth_config TEXT NOT NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        );
        
        CREATE TABLE IF NOT EXISTS tenant_stats (
            tenant_id TEXT PRIMARY KEY,
            certificates_issued INTEGER DEFAULT 0,
            certificates_revoked INTEGER DEFAULT 0,
            last_enrollment TEXT,
            last_revocation TEXT,
            FOREIGN KEY (tenant_id) REFERENCES tenants(tenant_id) ON DELETE CASCADE
        );
    """)
    
    conn.commit()
    conn.close()

def get_db():
    """Get database connection"""
    conn = sqlite3.connect(REGISTRY_DB)
    conn.row_factory = sqlite3.Row
    return conn

# ============================================================================
# Authentication
# ============================================================================

async def verify_admin_token(authorization: str = Header(None)):
    """Verify admin API key"""
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing authorization header")
    
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid authorization format")
    
    token = authorization.replace("Bearer ", "")
    if token != ADMIN_API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")
    
    return token

# ============================================================================
# Tenant Provisioning Functions
# ============================================================================

def provision_tenant(tenant_id: str, config: TenantCreateRequest) -> Dict:
    """Provision a new tenant with CA infrastructure"""
    
    tenant_dir = Path(TENANT_DATA_DIR) / tenant_id
    
    # Create directory structure
    tenant_dir.mkdir(parents=True, exist_ok=True)
    (tenant_dir / "newcerts").mkdir(exist_ok=True)
    (tenant_dir / "private").mkdir(mode=0o700, exist_ok=True)
    
    ca_key_path = tenant_dir / "private" / "cakey.pem"
    ca_cert_path = tenant_dir / "cacert.crt"
    config_path = tenant_dir / f"{tenant_id}.cnf"
    
    # Generate CA private key
    result = subprocess.run([
        "openssl", "genrsa",
        "-out", str(ca_key_path),
        str(config.ca_config.key_size)
    ], capture_output=True, text=True)
    
    if result.returncode != 0:
        raise Exception(f"Failed to generate CA key: {result.stderr}")
    
    # Set restrictive permissions on private key
    os.chmod(ca_key_path, 0o600)
    
    # Build CA subject
    subject = f"/C={config.ca_config.country}/ST={config.ca_config.state}" \
              f"/L={config.ca_config.locality}/O={config.ca_config.organization}"
    
    if config.ca_config.organizational_unit:
        subject += f"/OU={config.ca_config.organizational_unit}"
    
    subject += f"/CN={config.ca_config.common_name}"
    
    # Generate self-signed CA certificate
    result = subprocess.run([
        "openssl", "req",
        "-new", "-x509",
        "-key", str(ca_key_path),
        "-out", str(ca_cert_path),
        "-days", str(config.ca_config.validity_days),
        "-subj", subject,
        f"-{config.ca_config.digest}"
    ], capture_output=True, text=True)
    
    if result.returncode != 0:
        raise Exception(f"Failed to generate CA cert: {result.stderr}")
    
    # Generate OpenSSL config file
    openssl_config = f"""[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = {tenant_dir}
certs             = $dir
new_certs_dir     = $dir/newcerts
database          = $dir/index.txt
serial            = $dir/serial
private_key       = $dir/private/cakey.pem
certificate       = $dir/cacert.crt
default_md        = {config.ca_config.digest}
default_days      = {config.cert_policy.default_validity_days}
preserve          = no
policy            = policy_loose
unique_subject    = {'yes' if config.cert_policy.unique_subject else 'no'}

[ policy_loose ]
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional
"""
    
    with open(config_path, 'w') as f:
        f.write(openssl_config)
    
    # Initialize database files
    (tenant_dir / "index.txt").touch()
    with open(tenant_dir / "serial", 'w') as f:
        f.write("01\n")
    
    with open(tenant_dir / "index.txt.attr", 'w') as f:
        f.write("unique_subject = no\n")
    
    # Fix ownership for EST server (runs as estuser uid=1000)
    # This ensures the EST server can write temporary files during enrollment
    try:
        import pwd
        estuser_uid = pwd.getpwnam("estuser").pw_uid
        estuser_gid = pwd.getpwnam("estuser").pw_gid
    except (KeyError, ImportError):
        # Fallback to uid=1000 if estuser doesn't exist or pwd module unavailable
        estuser_uid = 1000
        estuser_gid = 1000
    
    # Recursively change ownership of all tenant files
    for root, dirs, files in os.walk(tenant_dir):
        os.chown(root, estuser_uid, estuser_gid)
        for dir_name in dirs:
            os.chown(os.path.join(root, dir_name), estuser_uid, estuser_gid)
        for file_name in files:
            os.chown(os.path.join(root, file_name), estuser_uid, estuser_gid)
    
    # Read CA certificate for response
    with open(ca_cert_path, 'r') as f:
        ca_certificate = f.read()
    
    return {
        "ca_subject": subject,
        "ca_certificate": ca_certificate,
        "tenant_dir": str(tenant_dir)
    }

# ============================================================================
# API Endpoints
# ============================================================================

@app.on_event("startup")
async def startup_event():
    """Initialize database on startup"""
    init_database()

@app.get("/admin/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}

@app.post("/admin/tenants", status_code=status.HTTP_201_CREATED)
async def create_tenant(
    request: TenantCreateRequest,
    token: str = Depends(verify_admin_token)
):
    """Create a new tenant with CA infrastructure"""
    
    conn = get_db()
    cursor = conn.cursor()
    
    # Check if tenant already exists
    existing = cursor.execute(
        "SELECT tenant_id FROM tenants WHERE tenant_id = ?",
        (request.tenant_id,)
    ).fetchone()
    
    if existing:
        conn.close()
        raise HTTPException(
            status_code=409,
            detail=f"Tenant '{request.tenant_id}' already exists"
        )
    
    try:
        # Provision tenant infrastructure
        provision_result = provision_tenant(request.tenant_id, request)
        
        # Store in database
        cursor.execute("""
            INSERT INTO tenants (
                tenant_id, display_name, ca_subject,
                ca_config, cert_policy, auth_config
            ) VALUES (?, ?, ?, ?, ?, ?)
        """, (
            request.tenant_id,
            request.display_name,
            provision_result["ca_subject"],
            json.dumps(request.ca_config.dict()),
            json.dumps(request.cert_policy.dict()),
            json.dumps(request.auth_config.dict())
        ))
        
        cursor.execute("""
            INSERT INTO tenant_stats (tenant_id)
            VALUES (?)
        """, (request.tenant_id,))
        
        conn.commit()
        
        return {
            "status": "success",
            "tenant_id": request.tenant_id,
            "message": "Tenant created successfully",
            "ca_certificate": provision_result["ca_certificate"],
            "endpoints": {
                "cacerts": f"https://localhost:8085/.well-known/est/{request.tenant_id}/cacerts",
                "simpleenroll": f"https://localhost:8085/.well-known/est/{request.tenant_id}/simpleenroll"
            },
            "created_at": datetime.now().isoformat()
        }
        
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        conn.close()

@app.get("/admin/tenants")
async def list_tenants(token: str = Depends(verify_admin_token)):
    """List all tenants"""
    
    conn = get_db()
    cursor = conn.cursor()
    
    rows = cursor.execute("""
        SELECT 
            t.tenant_id, t.display_name, t.status, t.ca_subject,
            t.created_at, s.certificates_issued, s.last_enrollment
        FROM tenants t
        LEFT JOIN tenant_stats s ON t.tenant_id = s.tenant_id
        ORDER BY t.created_at DESC
    """).fetchall()
    
    conn.close()
    
    tenants = []
    for row in rows:
        tenants.append({
            "tenant_id": row["tenant_id"],
            "display_name": row["display_name"],
            "status": row["status"],
            "ca_subject": row["ca_subject"],
            "certificates_issued": row["certificates_issued"] or 0,
            "created_at": row["created_at"],
            "last_enrollment": row["last_enrollment"]
        })
    
    return {
        "status": "success",
        "count": len(tenants),
        "tenants": tenants
    }

@app.get("/admin/tenants/{tenant_id}")
async def get_tenant(
    tenant_id: str,
    token: str = Depends(verify_admin_token)
):
    """Get detailed information about a tenant"""
    
    conn = get_db()
    cursor = conn.cursor()
    
    row = cursor.execute("""
        SELECT 
            t.*, s.certificates_issued, s.certificates_revoked,
            s.last_enrollment, s.last_revocation
        FROM tenants t
        LEFT JOIN tenant_stats s ON t.tenant_id = s.tenant_id
        WHERE t.tenant_id = ?
    """, (tenant_id,)).fetchone()
    
    conn.close()
    
    if not row:
        raise HTTPException(status_code=404, detail="Tenant not found")
    
    # Read current serial number
    tenant_dir = Path(TENANT_DATA_DIR) / tenant_id
    current_serial = "01"
    if (tenant_dir / "serial").exists():
        with open(tenant_dir / "serial", 'r') as f:
            current_serial = f.read().strip()
    
    return {
        "status": "success",
        "tenant": {
            "tenant_id": row["tenant_id"],
            "display_name": row["display_name"],
            "status": row["status"],
            "ca_subject": row["ca_subject"],
            "ca_config": json.loads(row["ca_config"]),
            "cert_policy": json.loads(row["cert_policy"]),
            "statistics": {
                "certificates_issued": row["certificates_issued"] or 0,
                "current_serial": current_serial
            },
            "created_at": row["created_at"]
        }
    }

@app.delete("/admin/tenants/{tenant_id}")
async def delete_tenant(
    tenant_id: str,
    archive: bool = False,
    token: str = Depends(verify_admin_token)
):
    """Delete a tenant"""
    
    conn = get_db()
    cursor = conn.cursor()
    
    row = cursor.execute(
        "SELECT tenant_id FROM tenants WHERE tenant_id = ?",
        (tenant_id,)
    ).fetchone()
    
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Tenant not found")
    
    try:
        # Delete files
        tenant_dir = Path(TENANT_DATA_DIR) / tenant_id
        if tenant_dir.exists():
            shutil.rmtree(tenant_dir)
        
        # Delete from database
        cursor.execute("DELETE FROM tenants WHERE tenant_id = ?", (tenant_id,))
        conn.commit()
        
        return {
            "status": "success",
            "message": "Tenant deleted successfully"
        }
        
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        conn.close()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8087)
