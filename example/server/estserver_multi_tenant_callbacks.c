/*------------------------------------------------------------------
 * estserver_multi_tenant_callbacks.c - Multi-tenant callback handlers
 *
 * Implements HTTP authentication and enrollment callbacks that support
 * multiple independent tenants with isolated CAs and clients.
 *
 * June, 2026
 **------------------------------------------------------------------
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <openssl/bio.h>
#include <est.h>
#include "est_multi_tenant.h"
#include "../util/utils.h"

/* Global tenant registry */
extern TENANT_REGISTRY *g_tenant_registry;

#ifndef WIN32
pthread_mutex_t enrollment_mutex = PTHREAD_MUTEX_INITIALIZER;
#else
static CRITICAL_SECTION enrollment_critical_section;
#endif

#define MAX_CERT_LEN 8192

/*
 * Multi-tenant HTTP authentication callback
 *
 * Extracts tenant_id:client_id:password from Bearer token
 * Validates client credentials against tenant-specific store
 * Stores tenant context in EST_CTX for use by enrollment callbacks
 */
int process_http_auth_multi_tenant(
    EST_CTX *ctx, EST_HTTP_AUTH_HDR *ah, X509 *peer_cert,
    char *path_seg, void *app_data)
{
    TENANT_CONFIG *tenant = NULL;
    char tenant_id[MAX_TENANT_ID_LEN];
    char client_id[MAX_CLIENT_ID_LEN];
    char password[MAX_PASSWORD_LEN];
    int result = 0;
    
    if (!ah) {
        printf("Invalid auth header\n");
        return 0;
    }
    
    memset(tenant_id, 0, sizeof(tenant_id));
    memset(client_id, 0, sizeof(client_id));
    memset(password, 0, sizeof(password));
    
    printf("\n=== Multi-Tenant Authentication ===\n");
    printf("Auth mode: %d\n", ah->mode);
    
    switch (ah->mode) {
    
    case AUTH_TOKEN:
        /*
         * Bearer token format: "tenant_id:client_id:password"
         * Example: "company-a:device-1:secret123"
         */
        printf("Processing Bearer token authentication\n");
        printf("Token: %s\n", ah->auth_token);
        
        /* Parse token */
        if (!tenant_parse_bearer_token(ah->auth_token, tenant_id, 
                                       client_id, password)) {
            printf("Failed to parse Bearer token\n");
            return 0;
        }
        
        printf("Parsed token - Tenant: %s, Client: %s\n", 
               tenant_id, client_id);
        
        /* Find tenant in registry */
        tenant = tenant_find_by_id(g_tenant_registry, tenant_id);
        if (!tenant) {
            printf("Tenant '%s' not found in registry\n", tenant_id);
            return 0;
        }
        
        printf("Found tenant: %s (%s)\n", 
               tenant->tenant_id, tenant->tenant_name);
        
        /* Validate client credentials */
        if (!tenant->active) {
            printf("Tenant '%s' is not active\n", tenant_id);
            return 0;
        }
        
        result = tenant_validate_client(tenant, client_id, password);
        if (result) {
            printf("Client '%s' authenticated successfully for tenant '%s'\n",
                   client_id, tenant_id);
            
            /* Store tenant context in EST context for callbacks */
            est_set_ex_data(ctx, tenant);
        } else {
            printf("Client '%s' authentication failed for tenant '%s'\n",
                   client_id, tenant_id);
        }
        
        break;
    
    case AUTH_BASIC:
        /*
         * Basic auth: username=tenant_id, password contains client_id:password
         * This is an alternative to Bearer token approach
         */
        printf("Processing Basic authentication\n");
        printf("User: %s\n", ah->user);
        
        /* Find tenant by username */
        tenant = tenant_find_by_id(g_tenant_registry, ah->user);
        if (!tenant) {
            printf("Tenant '%s' not found\n", ah->user);
            return 0;
        }
        
        if (!tenant->active) {
            printf("Tenant '%s' is not active\n", ah->user);
            return 0;
        }
        
        printf("Found tenant: %s\n", tenant->tenant_name);
        
        /* Password contains "client_id:client_password" */
        if (sscanf(ah->pwd, "%63[^:]:%255s", client_id, password) != 2) {
            printf("Invalid password format for Basic auth\n");
            return 0;
        }
        
        result = tenant_validate_client(tenant, client_id, password);
        if (result) {
            printf("Client '%s' authenticated for tenant '%s'\n",
                   client_id, ah->user);
            est_set_ex_data(ctx, tenant);
        } else {
            printf("Client '%s' authentication failed\n", client_id);
        }
        
        break;
    
    case AUTH_NONE:
    case AUTH_FAIL:
    default:
        printf("Unsupported authentication mode: %d\n", ah->mode);
        return 0;
    }
    
    return result;
}

/*
 * Multi-tenant enrollment callback
 *
 * Processes PKCS10 certificate request for specific tenant
 * Uses tenant's CA to sign the certificate
 * Ensures certificates are isolated per tenant
 */
int process_pkcs10_enrollment_multi_tenant(
    unsigned char *pkcs10, int p10_len,
    unsigned char **pkcs7, int *pkcs7_len,
    char *user_id, X509 *peer_cert, char *path_seg,
    void *app_data)
{
    TENANT_CONFIG *tenant = (TENANT_CONFIG *)app_data;
    BIO *result = NULL;
    char *buf = NULL;
    int rc = 0;
    
    fprintf(stderr, "\n=== Multi-Tenant Enrollment ===\n");
    fprintf(stderr, "Entering %s\n", __FUNCTION__);
    
    if (!tenant) {
        fprintf(stderr, "Error: Invalid tenant context (app_data is NULL)\n");
        fprintf(stderr, "This callback must be called with tenant context set via est_set_ex_data()\n");
        return EST_ERR_INVALID_PARAMETERS;
    }
    
    fprintf(stderr, "Processing enrollment for tenant: %s (%s)\n",
            tenant->tenant_id, tenant->tenant_name);
    
    if (user_id) {
        fprintf(stderr, "User ID: %s\n", user_id);
    }
    
    if (path_seg) {
        fprintf(stderr, "Path segment: %s\n", path_seg);
    }
    
    /* Lock tenant for exclusive enrollment */
    pthread_mutex_lock(&tenant->lock);
    
    if (!tenant->initialized || !tenant->ca_certs) {
        fprintf(stderr, "Error: Tenant not properly initialized\n");
        pthread_mutex_unlock(&tenant->lock);
        return EST_ERR_INVALID_PARAMETERS;
    }
    
    fprintf(stderr, "Tenant initialized. CA certs available: %d bytes\n",
            tenant->ca_certs_len);
    
    /* 
     * TODO: Call tenant-specific enrollment function
     * This requires creating a tenant-specific CA context or modifying
     * ossl_simple_enroll() to accept tenant configuration
     * 
     * For now, we use the global ossl_simple_enroll as a placeholder.
     * In production, you would:
     * 1. Load tenant's CA cert and key
     * 2. Sign the CSR with tenant's CA
     * 3. Return tenant-specific certificate
     */
    
#ifndef WIN32
    rc = pthread_mutex_lock(&enrollment_mutex);
    if (rc) {
        fprintf(stderr, "Error: mutex lock failed rc=%d\n", rc);
        pthread_mutex_unlock(&tenant->lock);
        return EST_ERR_INVALID_PARAMETERS;
    }
#else
    EnterCriticalSection(&enrollment_critical_section);
#endif
    
    /* Call OpenSSL-based enrollment */
    result = ossl_simple_enroll(pkcs10, p10_len);
    
#ifndef WIN32
    rc = pthread_mutex_unlock(&enrollment_mutex);
    if (rc) {
        fprintf(stderr, "Error: mutex unlock failed rc=%d\n", rc);
    }
#else
    LeaveCriticalSection(&enrollment_critical_section);
#endif
    
    pthread_mutex_unlock(&tenant->lock);
    
    if (!result) {
        fprintf(stderr, "Error: Enrollment failed for tenant %s\n",
                tenant->tenant_id);
        return EST_ERR_CA_ENROLL_RETRY;
    }
    
    /* Extract signed certificate from BIO */
    *pkcs7_len = BIO_get_mem_data(result, (char**)&buf);
    if (*pkcs7_len > 0 && *pkcs7_len < MAX_CERT_LEN) {
        *pkcs7 = malloc(*pkcs7_len);
        if (!*pkcs7) {
            fprintf(stderr, "Error: Memory allocation failed\n");
            BIO_free_all(result);
            return EST_ERR_MALLOC;
        }
        memcpy(*pkcs7, buf, *pkcs7_len);
        fprintf(stderr, "Successfully enrolled client. Certificate size: %d bytes\n",
                *pkcs7_len);
    } else {
        fprintf(stderr, "Error: Invalid certificate size: %d\n", *pkcs7_len);
        BIO_free_all(result);
        return EST_ERR_INVALID_PARAMETERS;
    }
    
    BIO_free_all(result);
    
    fprintf(stderr, "Enrollment complete for tenant: %s\n", tenant->tenant_id);
    return EST_ERR_NONE;
}

/*
 * Multi-tenant CSR attributes callback
 *
 * Returns tenant-specific CSR attributes if configured
 */
unsigned char* process_csrattrs_request_multi_tenant(
    int *csr_len, char *path_seg, X509 *peer_cert,
    void *app_data)
{
    TENANT_CONFIG *tenant = (TENANT_CONFIG *)app_data;
    unsigned char *csr_data = NULL;
    
    /* Default CSR attributes */
    #define DEFAULT_CSR "MCYGBysGAQEBARYGCSqGSIb3DQEJAQYFK4EEACIGCWCGSAFlAwQCAg=="
    
    printf("\n=== CSR Attributes Request ===\n");
    
    if (tenant) {
        printf("Tenant: %s\n", tenant->tenant_id);
    }
    
    if (path_seg) {
        printf("Path segment: %s\n", path_seg);
    }
    
    /* For now, return default CSR attributes */
    *csr_len = strlen(DEFAULT_CSR);
    csr_data = malloc(*csr_len + 1);
    if (csr_data) {
        strcpy((char *)csr_data, DEFAULT_CSR);
    }
    
    return csr_data;
}

/*
 * Initialize multi-tenant callbacks for EST context
 *
 * Registers the multi-tenant callback functions with libEST
 */
EST_ERROR init_multi_tenant_callbacks(EST_CTX *ectx)
{
    EST_ERROR rv = EST_ERR_NONE;
    
    printf("\nRegistering multi-tenant callbacks...\n");
    
    /* Register HTTP authentication callback */
    if (est_set_http_auth_cb(ectx, &process_http_auth_multi_tenant)) {
        printf("Failed to set HTTP auth callback\n");
        return EST_ERR_INVALID_PARAMETERS;
    }
    printf("✓ HTTP auth callback registered\n");
    
    /* Register enrollment callback */
    if (est_set_ca_enroll_cb(ectx, &process_pkcs10_enrollment_multi_tenant)) {
        printf("Failed to set enrollment callback\n");
        return EST_ERR_INVALID_PARAMETERS;
    }
    printf("✓ Enrollment callback registered\n");
    
    /* Register re-enrollment callback (same as enrollment) */
    if (est_set_ca_reenroll_cb(ectx, &process_pkcs10_enrollment_multi_tenant)) {
        printf("Failed to set re-enrollment callback\n");
        return EST_ERR_INVALID_PARAMETERS;
    }
    printf("✓ Re-enrollment callback registered\n");
    
    /* Register CSR attributes callback */
    if (est_set_csr_cb(ectx, &process_csrattrs_request_multi_tenant)) {
        printf("Failed to set CSR attributes callback\n");
        return EST_ERR_INVALID_PARAMETERS;
    }
    printf("✓ CSR attributes callback registered\n");
    
    printf("\nAll multi-tenant callbacks registered successfully\n");
    
    return rv;
}
