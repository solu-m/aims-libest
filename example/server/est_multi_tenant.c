/*------------------------------------------------------------------
 * est_multi_tenant.c - Multi-tenant EST server implementation
 *
 * Implements tenant management, JSON configuration parsing, and
 * per-tenant EST context initialization.
 *
 * June, 2026
 **------------------------------------------------------------------
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <openssl/bio.h>
#include <openssl/pem.h>
#include <est.h>
#include "est_multi_tenant.h"
#include "../util/utils.h"
#include "../util/jsmn.h"

/* Forward declarations */
static int jsoneq(const char *json, jsmntok_t *tok, const char *s);

/*
 * Initialize the tenant registry
 */
TENANT_REGISTRY* tenant_registry_init(int max_tenants)
{
    TENANT_REGISTRY *registry = malloc(sizeof(TENANT_REGISTRY));
    if (!registry) {
        printf("Failed to allocate tenant registry\n");
        return NULL;
    }
    
    registry->tenants = calloc(max_tenants, sizeof(TENANT_CONFIG));
    if (!registry->tenants) {
        printf("Failed to allocate tenant array\n");
        free(registry);
        return NULL;
    }
    
    registry->max_tenants = max_tenants;
    registry->tenant_count = 0;
    pthread_mutex_init(&registry->registry_lock, NULL);
    
    printf("Tenant registry initialized (max: %d)\n", max_tenants);
    return registry;
}

/*
 * Helper function: Compare JSON token with string
 * Returns 0 if match, -1 otherwise
 */
static int jsoneq(const char *json, jsmntok_t *tok, const char *s)
{
    if (tok->type == JSMN_STRING && 
        (int)strlen(s) == tok->end - tok->start &&
        strncmp(json + tok->start, s, tok->end - tok->start) == 0) {
        return 0;
    }
    return -1;
}

/*
 * Extract string value from JSON token
 */
static void json_extract_string(const char *json, jsmntok_t *tok, 
                                 char *buffer, int buffer_size)
{
    int len = tok->end - tok->start;
    if (len >= buffer_size) {
        len = buffer_size - 1;
    }
    strncpy(buffer, json + tok->start, len);
    buffer[len] = '\0';
}

/*
 * Parse tenant configuration from JSON and populate registry
 */
int tenant_config_load_from_file(const char *config_file, 
                                  TENANT_REGISTRY *registry)
{
    unsigned char *config_data = NULL;
    int config_len;
    jsmn_parser parser;
    jsmntok_t *tokens = NULL;
    int token_count = 1000;
    int parse_result;
    int i, j, k;
    int tenant_idx = 0;
    TENANT_CONFIG *current_tenant = NULL;
    
    if (!registry) {
        printf("Invalid registry\n");
        return -1;
    }
    
    /* Read configuration file */
    printf("Loading tenant config from: %s\n", config_file);
    config_len = read_binary_file(config_file, &config_data);
    if (config_len <= 0) {
        printf("Failed to read config file: %s\n", config_file);
        return -1;
    }
    
    /* Allocate tokens for JSON parsing */
    tokens = calloc(token_count, sizeof(jsmntok_t));
    if (!tokens) {
        printf("Failed to allocate token buffer\n");
        free(config_data);
        return -1;
    }
    
    /* Parse JSON */
    jsmn_init(&parser);
    parse_result = jsmn_parse(&parser, (char *)config_data, config_len, 
                              tokens, token_count);
    
    if (parse_result < 0) {
        printf("Failed to parse JSON: error=%d\n", parse_result);
        free(tokens);
        free(config_data);
        return -1;
    }
    
    printf("JSON parsed successfully: %d tokens\n", parse_result);
    
    /* Traverse tokens and extract tenant configuration */
    for (i = 1; i < parse_result; i++) {
        
        /* Look for "tenants" array */
        if (jsoneq((char *)config_data, &tokens[i], "tenants") == 0) {
            jsmntok_t *tenants_array = &tokens[i + 1];
            int tenant_count = tenants_array->size;
            int token_offset = i + 2;
            
            printf("Found 'tenants' array with %d items\n", tenant_count);
            
            /* Iterate through each tenant in the array */
            for (j = 0; j < tenant_count && tenant_idx < registry->max_tenants; j++) {
                
                current_tenant = &registry->tenants[tenant_idx];
                memset(current_tenant, 0, sizeof(TENANT_CONFIG));
                pthread_mutex_init(&current_tenant->lock, NULL);
                current_tenant->active = 0;
                current_tenant->initialized = 0;
                
                /* Parse tenant object */
                int tenant_size = tokens[token_offset].size;
                int offset = token_offset + 1;
                int client_idx = 0;
                
                printf("\n--- Parsing Tenant %d ---\n", j + 1);
                
                for (k = 0; k < tenant_size * 2 && offset < parse_result; k += 2, offset++) {
                    
                    /* tenant_id */
                    if (jsoneq((char *)config_data, &tokens[offset], "tenant_id") == 0) {
                        json_extract_string((char *)config_data, &tokens[offset + 1],
                                          current_tenant->tenant_id, MAX_TENANT_ID_LEN);
                        printf("  tenant_id: %s\n", current_tenant->tenant_id);
                    }
                    
                    /* tenant_name */
                    else if (jsoneq((char *)config_data, &tokens[offset], "tenant_name") == 0) {
                        json_extract_string((char *)config_data, &tokens[offset + 1],
                                          current_tenant->tenant_name, MAX_TENANT_NAME_LEN);
                        printf("  tenant_name: %s\n", current_tenant->tenant_name);
                    }
                    
                    /* ca_cert_file */
                    else if (jsoneq((char *)config_data, &tokens[offset], "ca_cert_file") == 0) {
                        json_extract_string((char *)config_data, &tokens[offset + 1],
                                          current_tenant->ca_cert_file, MAX_FILE_PATH_LEN);
                        printf("  ca_cert_file: %s\n", current_tenant->ca_cert_file);
                    }
                    
                    /* ca_key_file */
                    else if (jsoneq((char *)config_data, &tokens[offset], "ca_key_file") == 0) {
                        json_extract_string((char *)config_data, &tokens[offset + 1],
                                          current_tenant->ca_key_file, MAX_FILE_PATH_LEN);
                        printf("  ca_key_file: %s\n", current_tenant->ca_key_file);
                    }
                    
                    /* truststore_file */
                    else if (jsoneq((char *)config_data, &tokens[offset], "truststore_file") == 0) {
                        json_extract_string((char *)config_data, &tokens[offset + 1],
                                          current_tenant->truststore_file, MAX_FILE_PATH_LEN);
                        printf("  truststore_file: %s\n", current_tenant->truststore_file);
                    }
                    
                    /* clients array */
                    else if (jsoneq((char *)config_data, &tokens[offset], "clients") == 0) {
                        jsmntok_t *clients_array = &tokens[offset + 1];
                        int client_count = clients_array->size;
                        int client_token_offset = offset + 2;
                        
                        printf("  Found %d clients\n", client_count);
                        
                        current_tenant->clients = calloc(client_count, sizeof(TENANT_CLIENT));
                        if (!current_tenant->clients) {
                            printf("Failed to allocate client array\n");
                            continue;
                        }
                        current_tenant->client_count = client_count;
                        
                        /* Parse each client */
                        for (int c = 0; c < client_count; c++) {
                            int client_obj_size = tokens[client_token_offset].size;
                            int client_off = client_token_offset + 1;
                            
                            for (int cp = 0; cp < client_obj_size * 2; cp += 2) {
                                
                                if (jsoneq((char *)config_data, &tokens[client_off], 
                                          "client_id") == 0) {
                                    json_extract_string((char *)config_data, 
                                                      &tokens[client_off + 1],
                                                      current_tenant->clients[c].client_id,
                                                      MAX_CLIENT_ID_LEN);
                                    printf("    client_id: %s\n", 
                                           current_tenant->clients[c].client_id);
                                }
                                
                                else if (jsoneq((char *)config_data, &tokens[client_off], 
                                               "password") == 0) {
                                    json_extract_string((char *)config_data, 
                                                      &tokens[client_off + 1],
                                                      current_tenant->clients[c].password,
                                                      MAX_PASSWORD_LEN);
                                    printf("    password: %s\n", 
                                           current_tenant->clients[c].password);
                                }
                                
                                else if (jsoneq((char *)config_data, &tokens[client_off], 
                                               "server_id") == 0) {
                                    json_extract_string((char *)config_data, 
                                                      &tokens[client_off + 1],
                                                      current_tenant->clients[c].server_id,
                                                      MAX_TENANT_ID_LEN);
                                    printf("    server_id: %s\n", 
                                           current_tenant->clients[c].server_id);
                                }
                                
                                client_off += 2;
                            }
                            
                            client_token_offset += tokens[client_token_offset].size + 1;
                        }
                        
                        offset = client_token_offset - 1;
                    }
                }
                
                tenant_idx++;
                token_offset += tokens[token_offset].size + 1;
            }
            
            break;  /* Done processing tenants array */
        }
    }
    
    registry->tenant_count = tenant_idx;
    printf("\nLoaded %d tenants successfully\n", tenant_idx);
    
    free(tokens);
    free(config_data);
    
    return tenant_idx > 0 ? 0 : -1;
}

/*
 * Find tenant by ID
 */
TENANT_CONFIG* tenant_find_by_id(TENANT_REGISTRY *registry, 
                                  const char *tenant_id)
{
    int i;
    
    if (!registry || !tenant_id) {
        return NULL;
    }
    
    pthread_mutex_lock(&registry->registry_lock);
    
    for (i = 0; i < registry->tenant_count; i++) {
        if (!strcmp(registry->tenants[i].tenant_id, tenant_id)) {
            pthread_mutex_unlock(&registry->registry_lock);
            return &registry->tenants[i];
        }
    }
    
    pthread_mutex_unlock(&registry->registry_lock);
    return NULL;
}

/*
 * Validate client credentials for a tenant
 */
int tenant_validate_client(TENANT_CONFIG *tenant, 
                           const char *client_id, 
                           const char *password)
{
    int i;
    
    if (!tenant || !client_id || !password) {
        return 0;
    }
    
    pthread_mutex_lock(&tenant->lock);
    
    for (i = 0; i < tenant->client_count; i++) {
        if (!strcmp(tenant->clients[i].client_id, client_id) &&
            !strcmp(tenant->clients[i].password, password) &&
            !strcmp(tenant->clients[i].server_id, tenant->tenant_id)) {
            
            pthread_mutex_unlock(&tenant->lock);
            return 1;  /* Valid */
        }
    }
    
    pthread_mutex_unlock(&tenant->lock);
    return 0;  /* Invalid */
}

/*
 * Parse Bearer token format: "tenant_id:client_id:password"
 */
int tenant_parse_bearer_token(const char *token,
                               char *tenant_id,
                               char *client_id,
                               char *password)
{
    int result;
    
    if (!token || !tenant_id || !client_id || !password) {
        return 0;
    }
    
    /* Parse token format: tenant_id:client_id:password */
    result = sscanf(token, "%63[^:]:%63[^:]:%255s",
                   tenant_id, client_id, password);
    
    if (result != 3) {
        printf("Invalid token format. Expected: tenant_id:client_id:password\n");
        return 0;
    }
    
    return 1;
}

/*
 * Load tenant's CA certificates from file
 */
static EST_ERROR tenant_load_ca_certs(TENANT_CONFIG *tenant)
{
    BIO *in = NULL;
    BIO *cacerts_bio = NULL;
    unsigned char *retval = NULL;
    
    if (!tenant->ca_cert_file[0]) {
        printf("Tenant %s: CA cert file not configured\n", tenant->tenant_id);
        return EST_ERR_INVALID_PARAMETERS;
    }
    
    /* Read CA certificate file */
    in = BIO_new(BIO_s_file());
    if (!in) {
        printf("Failed to create BIO for CA cert\n");
        return EST_ERR_LOAD_CACERTS;
    }
    
    if (BIO_read_filename(in, tenant->ca_cert_file) <= 0) {
        printf("Tenant %s: Failed to read CA cert file: %s\n",
               tenant->tenant_id, tenant->ca_cert_file);
        BIO_free(in);
        return EST_ERR_LOAD_CACERTS;
    }
    
    /* Load certificates into memory */
    tenant->ca_certs_len = read_binary_file(tenant->ca_cert_file, 
                                             &tenant->ca_certs);
    if (tenant->ca_certs_len <= 0) {
        printf("Tenant %s: Failed to load CA certs\n", tenant->tenant_id);
        BIO_free(in);
        return EST_ERR_LOAD_CACERTS;
    }
    
    BIO_free(in);
    printf("Tenant %s: Loaded %d bytes of CA certificates\n",
           tenant->tenant_id, tenant->ca_certs_len);
    
    return EST_ERR_NONE;
}

/*
 * Load tenant's trust store from file
 */
static EST_ERROR tenant_load_truststore(TENANT_CONFIG *tenant)
{
    if (!tenant->truststore_file[0]) {
        printf("Tenant %s: Truststore file not configured\n", tenant->tenant_id);
        return EST_ERR_INVALID_PARAMETERS;
    }
    
    tenant->trustcerts_len = read_binary_file(tenant->truststore_file,
                                               &tenant->trustcerts);
    if (tenant->trustcerts_len <= 0) {
        printf("Tenant %s: Failed to load truststore\n", tenant->tenant_id);
        return EST_ERR_LOAD_CACERTS;
    }
    
    printf("Tenant %s: Loaded %d bytes of trust certificates\n",
           tenant->tenant_id, tenant->trustcerts_len);
    
    return EST_ERR_NONE;
}

/*
 * Initialize EST context for a tenant
 */
EST_ERROR tenant_init_est_context(TENANT_CONFIG *tenant)
{
    EST_ERROR rv = EST_ERR_NONE;
    
    if (!tenant) {
        return EST_ERR_INVALID_PARAMETERS;
    }
    
    printf("\nInitializing EST context for tenant: %s\n", tenant->tenant_id);
    
    /* Load CA certificates */
    rv = tenant_load_ca_certs(tenant);
    if (rv != EST_ERR_NONE) {
        printf("Failed to load CA certs for tenant %s\n", tenant->tenant_id);
        return rv;
    }
    
    /* Load trust store */
    rv = tenant_load_truststore(tenant);
    if (rv != EST_ERR_NONE) {
        printf("Failed to load truststore for tenant %s\n", tenant->tenant_id);
        return rv;
    }
    
    /* TODO: Create EST context per tenant
     * This would require modifications to est_server_init() to accept
     * tenant-specific CA certificates and keys.
     * For now, we prepare the data; actual EST_CTX creation happens in main().
     */
    
    tenant->initialized = 1;
    printf("Tenant %s: Initialization complete\n", tenant->tenant_id);
    
    return EST_ERR_NONE;
}

/*
 * Cleanup single tenant
 */
void tenant_cleanup(TENANT_CONFIG *tenant)
{
    if (!tenant) {
        return;
    }
    
    if (tenant->ectx) {
        est_destroy(tenant->ectx);
        tenant->ectx = NULL;
    }
    
    if (tenant->ca_certs) {
        free(tenant->ca_certs);
        tenant->ca_certs = NULL;
    }
    
    if (tenant->trustcerts) {
        free(tenant->trustcerts);
        tenant->trustcerts = NULL;
    }
    
    if (tenant->server_cert) {
        X509_free(tenant->server_cert);
        tenant->server_cert = NULL;
    }
    
    if (tenant->server_key) {
        EVP_PKEY_free(tenant->server_key);
        tenant->server_key = NULL;
    }
    
    if (tenant->clients) {
        free(tenant->clients);
        tenant->clients = NULL;
    }
    
    pthread_mutex_destroy(&tenant->lock);
    tenant->active = 0;
}

/*
 * Cleanup and destroy entire tenant registry
 */
void tenant_registry_cleanup(TENANT_REGISTRY *registry)
{
    int i;
    
    if (!registry) {
        return;
    }
    
    pthread_mutex_lock(&registry->registry_lock);
    
    for (i = 0; i < registry->tenant_count; i++) {
        tenant_cleanup(&registry->tenants[i]);
    }
    
    pthread_mutex_unlock(&registry->registry_lock);
    pthread_mutex_destroy(&registry->registry_lock);
    
    if (registry->tenants) {
        free(registry->tenants);
        registry->tenants = NULL;
    }
    
    free(registry);
}
