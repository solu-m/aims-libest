/*------------------------------------------------------------------
 * est_multi_tenant.h - Multi-tenant EST server support
 *
 * Defines structures and functions for managing multiple independent
 * EST servers, each with unique CAs and client credentials.
 * Clients are isolated by tenant ID embedded in HTTP Bearer token.
 *
 * June, 2026
 **------------------------------------------------------------------
 */

#ifndef EST_MULTI_TENANT_H
#define EST_MULTI_TENANT_H

#include <pthread.h>
#include <openssl/x509.h>
#include <est.h>

#define MAX_TENANT_ID_LEN 64
#define MAX_TENANT_NAME_LEN 256
#define MAX_CLIENT_ID_LEN 64
#define MAX_PASSWORD_LEN 256
#define MAX_TENANTS 50
#define MAX_CLIENTS_PER_TENANT 100
#define MAX_FILE_PATH_LEN 512

/*
 * Represents a single client (device) within a tenant
 */
typedef struct {
    char client_id[MAX_CLIENT_ID_LEN];
    char password[MAX_PASSWORD_LEN];
    char server_id[MAX_TENANT_ID_LEN];     /* Which server/tenant can connect */
    int enrolled;                           /* Track if client has enrolled */
} TENANT_CLIENT;

/*
 * Represents a complete tenant (customer/organization)
 * Each tenant has its own CA, credentials, and EST context
 */
typedef struct {
    char tenant_id[MAX_TENANT_ID_LEN];
    char tenant_name[MAX_TENANT_NAME_LEN];
    
    /* CA Configuration per tenant */
    char ca_cert_file[MAX_FILE_PATH_LEN];
    char ca_key_file[MAX_FILE_PATH_LEN];
    char truststore_file[MAX_FILE_PATH_LEN];
    
    unsigned char *ca_certs;
    int ca_certs_len;
    unsigned char *trustcerts;
    int trustcerts_len;
    
    /* Server certificate and key for TLS */
    X509 *server_cert;
    EVP_PKEY *server_key;
    
    /* EST context unique to this tenant */
    EST_CTX *ectx;
    
    /* Client credentials for this tenant */
    TENANT_CLIENT *clients;
    int client_count;
    
    /* Synchronization and status */
    pthread_mutex_t lock;
    int active;
    int initialized;
} TENANT_CONFIG;

/*
 * Global tenant registry - manages all tenants
 */
typedef struct {
    TENANT_CONFIG *tenants;
    int tenant_count;
    int max_tenants;
    pthread_mutex_t registry_lock;
} TENANT_REGISTRY;

/* Function prototypes */

/*
 * Initialize the tenant registry
 */
TENANT_REGISTRY* tenant_registry_init(int max_tenants);

/*
 * Load tenant configuration from JSON file
 * File format:
 * {
 *   "tenants": [
 *     {
 *       "tenant_id": "company-a",
 *       "tenant_name": "Company A",
 *       "ca_cert_file": "/path/to/ca.pem",
 *       "ca_key_file": "/path/to/key.pem",
 *       "truststore_file": "/path/to/trust.pem",
 *       "clients": [
 *         {
 *           "client_id": "device-1",
 *           "password": "secret123",
 *           "server_id": "company-a"
 *         }
 *       ]
 *     }
 *   ]
 * }
 */
int tenant_config_load_from_file(const char *config_file, 
                                  TENANT_REGISTRY *registry);

/*
 * Find tenant by ID
 */
TENANT_CONFIG* tenant_find_by_id(TENANT_REGISTRY *registry, 
                                  const char *tenant_id);

/*
 * Validate client credentials for a tenant
 * Returns 1 if valid, 0 otherwise
 */
int tenant_validate_client(TENANT_CONFIG *tenant, 
                           const char *client_id, 
                           const char *password);

/*
 * Parse Bearer token in format: "tenant_id:client_id:password"
 * Returns 1 on success, 0 on failure
 */
int tenant_parse_bearer_token(const char *token,
                               char *tenant_id,
                               char *client_id,
                               char *password);

/*
 * Initialize EST context for a tenant
 */
EST_ERROR tenant_init_est_context(TENANT_CONFIG *tenant);

/*
 * Cleanup and destroy tenant registry
 */
void tenant_registry_cleanup(TENANT_REGISTRY *registry);

/*
 * Cleanup single tenant
 */
void tenant_cleanup(TENANT_CONFIG *tenant);

#endif /* EST_MULTI_TENANT_H */
