/*------------------------------------------------------------------
 * multi_tenant_enrollment.c - Multi-tenant black-box enrollment pipeline
 *                              Replaces legacy ossl_simple_enroll with 
 *                              tenant-isolated OpenSSL CA execution
 *
 * July, 2026
 *
 * Copyright (c) 2026 by Cisco Systems, Inc.
 * All rights reserved.
 *------------------------------------------------------------------
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <openssl/bio.h>
#include <openssl/pem.h>
#include <openssl/err.h>
#include <openssl/x509.h>

#define MAX_PATH_LEN 512
#define MAX_CMD_LEN 2048
#define REPO_ROOT "/mnt/c/Users/Solum/aims-libest"

/*
 * Multi-Tenant Black-Box Enrollment Pipeline
 * 
 * This function provides complete tenant isolation by:
 * 1. Writing DER CSR to tenant-specific directory
 * 2. Converting DER→PEM format
 * 3. Executing 'openssl ca' with tenant-specific config
 * 4. Creating PKCS7 bundle with tenant CA chain
 * 5. Reading result back into memory
 * 6. Cleaning up all temporary files
 *
 * Parameters:
 *   p10buf    - Binary DER-encoded PKCS#10 CSR from client
 *   p10len    - Length of CSR buffer
 *   tenant_id - Tenant identifier (gateway, iot, freeradius)
 *
 * Returns:
 *   BIO containing PKCS7 signed certificate, or NULL on error
 */
BIO * multi_tenant_enroll(const unsigned char *p10buf, int p10len, const char *tenant_id) {
    char tenant_dir[MAX_PATH_LEN];
    char der_file[MAX_PATH_LEN];
    char pem_file[MAX_PATH_LEN];
    char cert_file[MAX_PATH_LEN];
    char pkcs7_file[MAX_PATH_LEN];
    char config_file[MAX_PATH_LEN];
    char cmd[MAX_CMD_LEN];
    FILE *fp = NULL;
    BIO *bio_out = NULL;
    BIO *bio_mem = NULL;
    char *pkcs7_data = NULL;
    long pkcs7_len = 0;
    int rc = 0;
    
    // Validate tenant ID
    if (!tenant_id || strlen(tenant_id) == 0) {
        fprintf(stderr, "[ERROR] Tenant ID is NULL or empty\n");
        return NULL;
    }
    
    // [1] Build tenant-specific paths
    snprintf(tenant_dir, MAX_PATH_LEN, "%s/tenants/%s", REPO_ROOT, tenant_id);
    
    // Check if tenant directory exists (dynamic tenant validation)
    struct stat st;
    if (stat(tenant_dir, &st) != 0 || !S_ISDIR(st.st_mode)) {
        fprintf(stderr, "[ERROR] Tenant '%s' not found or not a directory: %s\n", tenant_id, tenant_dir);
        return NULL;
    }
    
    fprintf(stderr, "[INFO] Multi-tenant enrollment started for tenant: %s\n", tenant_id);
    snprintf(der_file, MAX_PATH_LEN, "%s/tmp_client.der", tenant_dir);
    snprintf(pem_file, MAX_PATH_LEN, "%s/tmp_client.pem", tenant_dir);
    snprintf(cert_file, MAX_PATH_LEN, "%s/tmp_client_cert.pem", tenant_dir);
    snprintf(pkcs7_file, MAX_PATH_LEN, "%s/tmp_client.p7", tenant_dir);
    snprintf(config_file, MAX_PATH_LEN, "%s/%s.cnf", tenant_dir, tenant_id);
    
    // [2] Write base64-encoded CSR to disk, then decode to DER
    // EST protocol sends base64-encoded PKCS#10, we need binary DER for OpenSSL
    char b64_file[MAX_PATH_LEN];
    snprintf(b64_file, MAX_PATH_LEN, "%s/tmp_client.b64", tenant_dir);
    
    fp = fopen(b64_file, "wb");
    if (!fp) {
        fprintf(stderr, "[ERROR] Failed to open %s for writing\n", b64_file);
        goto cleanup;
    }
    
    if (fwrite(p10buf, 1, p10len, fp) != (size_t)p10len) {
        fprintf(stderr, "[ERROR] Failed to write complete base64 data to %s\n", b64_file);
        fclose(fp);
        goto cleanup;
    }
    fclose(fp);
    fp = NULL;
    fprintf(stderr, "[INFO] [Step 1/7] Wrote base64 CSR to %s (%d bytes)\n", b64_file, p10len);
    
    // Decode base64 to DER
    snprintf(cmd, MAX_CMD_LEN, "base64 -d < %s > %s 2>&1", b64_file, der_file);
    rc = system(cmd);
    if (rc != 0) {
        fprintf(stderr, "[ERROR] [Step 2/7] Base64 decode failed (rc=%d)\n", rc);
        unlink(b64_file);
        goto cleanup;
    }
    fprintf(stderr, "[INFO] [Step 2/7] Decoded base64→DER successfully\n");
    unlink(b64_file);
    
    // [3] Convert DER→PEM (openssl req -inform DER -outform PEM)
    snprintf(cmd, MAX_CMD_LEN, 
        "openssl req -inform DER -in %s -outform PEM -out %s 2>&1",
        der_file, pem_file);
    
    rc = system(cmd);
    if (rc != 0) {
        fprintf(stderr, "[ERROR] [Step 3/7] DER to PEM conversion failed (rc=%d)\n", rc);
        goto cleanup;
    }
    fprintf(stderr, "[INFO] [Step 3/7] Converted DER→PEM successfully\n");
    
    // [4] Execute 'openssl ca' with tenant-specific config
    snprintf(cmd, MAX_CMD_LEN,
        "openssl ca -batch -config %s -in %s -out %s 2>&1",
        config_file, pem_file, cert_file);
    
    rc = system(cmd);
    if (rc != 0) {
        fprintf(stderr, "[ERROR] [Step 4/7] OpenSSL CA signing failed (rc=%d)\n", rc);
        fprintf(stderr, "[ERROR] Command: %s\n", cmd);
        goto cleanup;
    }
    fprintf(stderr, "[INFO] [Step 3/6] Certificate signed by %s CA\n", tenant_id);
    
    // [5] Create PKCS7 bundle (signed cert + CA cert chain)
    snprintf(cmd, MAX_CMD_LEN,
        "openssl crl2pkcs7 -nocrl -certfile %s/cacert.crt -certfile %s -out %s 2>&1",
        tenant_dir, cert_file, pkcs7_file);
    
    rc = system(cmd);
    if (rc != 0) {
        fprintf(stderr, "[ERROR] [Step 5/7] PKCS7 bundle creation failed (rc=%d)\n", rc);
        goto cleanup;
    }
    fprintf(stderr, "[INFO] [Step 5/7] Created PKCS7 bundle\n");
    
    // [6] Read PKCS7 file into memory (DER format for network transmission)
    snprintf(cmd, MAX_CMD_LEN,
        "openssl pkcs7 -in %s -outform DER -out %s.der 2>&1",
        pkcs7_file, pkcs7_file);
    
    rc = system(cmd);
    if (rc != 0) {
        fprintf(stderr, "[ERROR] [Step 6/7] PKCS7 DER conversion failed (rc=%d)\n", rc);
        goto cleanup;
    }
    
    // Read DER-encoded PKCS7 into BIO
    snprintf(cmd, MAX_CMD_LEN, "%s.der", pkcs7_file);
    fp = fopen(cmd, "rb");
    if (!fp) {
        fprintf(stderr, "[ERROR] Failed to open PKCS7 DER file: %s\n", cmd);
        goto cleanup;
    }
    
    // Get file size
    fseek(fp, 0, SEEK_END);
    pkcs7_len = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    
    // Allocate buffer and read
    pkcs7_data = malloc(pkcs7_len);
    if (!pkcs7_data) {
        fprintf(stderr, "[ERROR] Failed to allocate %ld bytes for PKCS7 data\n", pkcs7_len);
        fclose(fp);
        goto cleanup;
    }
    
    if (fread(pkcs7_data, 1, pkcs7_len, fp) != (size_t)pkcs7_len) {
        fprintf(stderr, "[ERROR] Failed to read complete PKCS7 data\n");
        fclose(fp);
        free(pkcs7_data);
        goto cleanup;
    }
    fclose(fp);
    fp = NULL;
    
    // Create memory BIO and transfer ownership
    bio_mem = BIO_new(BIO_s_mem());
    if (!bio_mem) {
        fprintf(stderr, "[ERROR] Failed to create memory BIO\n");
        free(pkcs7_data);
        goto cleanup;
    }
    
    BIO_write(bio_mem, pkcs7_data, pkcs7_len);
    free(pkcs7_data);
    pkcs7_data = NULL;
    
    fprintf(stderr, "[INFO] [Step 7/7] Loaded PKCS7 into memory (%ld bytes)\n", pkcs7_len);
    
    // [7] Cleanup all temporary files
    unlink(der_file);
    unlink(pem_file);
    unlink(cert_file);
    unlink(pkcs7_file);
    snprintf(cmd, MAX_CMD_LEN, "%s.der", pkcs7_file);
    unlink(cmd);
    
    fprintf(stderr, "[INFO] [Cleanup] Purged all temporary files\n");
    fprintf(stderr, "[SUCCESS] Multi-tenant enrollment complete for tenant: %s\n", tenant_id);
    
    return bio_mem;

cleanup:
    // Cleanup on error
    if (fp) fclose(fp);
    if (pkcs7_data) free(pkcs7_data);
    if (bio_mem) BIO_free(bio_mem);
    
    // Best-effort cleanup of temp files
    unlink(der_file);
    unlink(pem_file);
    unlink(cert_file);
    unlink(pkcs7_file);
    snprintf(cmd, MAX_CMD_LEN, "%s.der", pkcs7_file);
    unlink(cmd);
    
    fprintf(stderr, "[ERROR] Multi-tenant enrollment failed for tenant: %s\n", tenant_id);
    return NULL;
}

/*
 * Multi-Tenant CA Certs Callback
 * 
 * Returns the CA certificate(s) for a tenant in PKCS7 DER format.
 * Called by libest when a client requests /.well-known/est/<tenant>/cacerts
 *
 * Parameters:
 *   cacerts_len - Output: length of returned buffer
 *   path_seg    - Tenant ID extracted from URL path (e.g., "gateway")
 *   ex_data     - Application context (unused)
 *
 * Returns:
 *   Pointer to PKCS7 DER-encoded CA cert(s), or NULL on error
 */
unsigned char *multi_tenant_cacerts(int *cacerts_len, char *path_seg, void *ex_data)
{
    char tenant_id[64] = {0};
    char ca_cert_path[MAX_PATH_LEN];
    char pkcs7_path[MAX_PATH_LEN];
    char cmd[MAX_CMD_LEN];
    FILE *fp;
    unsigned char *pkcs7_buf = NULL;
    long file_size;
    size_t bytes_read;
    int rc;
    
    (void)ex_data;  // Unused
    
    // Step 1: Extract and validate tenant ID
    if (path_seg && strlen(path_seg) > 0 && strlen(path_seg) < sizeof(tenant_id)) {
        strncpy(tenant_id, path_seg, sizeof(tenant_id) - 1);
    } else {
        // Default to gateway if no path segment
        strncpy(tenant_id, "gateway", sizeof(tenant_id) - 1);
    }
    
    fprintf(stderr, "[INFO] CA certs request for tenant: %s\n", tenant_id);
    
    // Step 2: Construct paths
    snprintf(ca_cert_path, sizeof(ca_cert_path), 
             "%s/tenants/%s/cacert.crt", REPO_ROOT, tenant_id);
    snprintf(pkcs7_path, sizeof(pkcs7_path),
             "%s/tenants/%s/cacerts_response.pkcs7", REPO_ROOT, tenant_id);
    
    // Step 3: Check if CA cert exists
    if (access(ca_cert_path, R_OK) != 0) {
        fprintf(stderr, "[ERROR] CA cert not found for tenant %s: %s\n", 
                tenant_id, ca_cert_path);
        *cacerts_len = 0;
        return NULL;
    }
    
    // Step 4: Create PKCS7 bundle from CA cert
    // Convert PEM CA cert to PKCS7 DER format
    snprintf(cmd, sizeof(cmd),
             "openssl crl2pkcs7 -nocrl -certfile '%s' -outform DER -out '%s' 2>/dev/null",
             ca_cert_path, pkcs7_path);
    
    rc = system(cmd);
    if (rc != 0) {
        fprintf(stderr, "[ERROR] Failed to create PKCS7 bundle for tenant %s (rc=%d)\n",
                tenant_id, rc);
        *cacerts_len = 0;
        return NULL;
    }
    
    // Step 5: Read PKCS7 DER file into memory
    fp = fopen(pkcs7_path, "rb");
    if (!fp) {
        fprintf(stderr, "[ERROR] Failed to open PKCS7 file for tenant %s: %s\n",
                tenant_id, pkcs7_path);
        unlink(pkcs7_path);
        *cacerts_len = 0;
        return NULL;
    }
    
    // Get file size
    fseek(fp, 0, SEEK_END);
    file_size = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    
    if (file_size <= 0 || file_size > 1048576) {  // Max 1MB
        fprintf(stderr, "[ERROR] Invalid PKCS7 file size for tenant %s: %ld bytes\n",
                tenant_id, file_size);
        fclose(fp);
        unlink(pkcs7_path);
        *cacerts_len = 0;
        return NULL;
    }
    
    // Allocate buffer
    pkcs7_buf = (unsigned char *)malloc(file_size);
    if (!pkcs7_buf) {
        fprintf(stderr, "[ERROR] Memory allocation failed for tenant %s\n", tenant_id);
        fclose(fp);
        unlink(pkcs7_path);
        *cacerts_len = 0;
        return NULL;
    }
    
    // Read file
    bytes_read = fread(pkcs7_buf, 1, file_size, fp);
    fclose(fp);
    
    if (bytes_read != (size_t)file_size) {
        fprintf(stderr, "[ERROR] Failed to read PKCS7 file for tenant %s\n", tenant_id);
        free(pkcs7_buf);
        unlink(pkcs7_path);
        *cacerts_len = 0;
        return NULL;
    }
    
    // Cleanup temp file
    unlink(pkcs7_path);
    
    *cacerts_len = (int)file_size;
    fprintf(stderr, "[SUCCESS] Returning %d bytes of CA certs for tenant %s\n",
            *cacerts_len, tenant_id);
    
    return pkcs7_buf;
}
