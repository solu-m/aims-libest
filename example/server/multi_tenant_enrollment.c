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
    
    if (strcmp(tenant_id, "gateway") != 0 && 
        strcmp(tenant_id, "iot") != 0 && 
        strcmp(tenant_id, "freeradius") != 0) {
        fprintf(stderr, "[ERROR] Invalid tenant ID: %s (must be gateway, iot, or freeradius)\n", tenant_id);
        return NULL;
    }
    
    fprintf(stderr, "[INFO] Multi-tenant enrollment started for tenant: %s\n", tenant_id);
    
    // [1] Build tenant-specific paths
    snprintf(tenant_dir, MAX_PATH_LEN, "%s/tenants/%s", REPO_ROOT, tenant_id);
    snprintf(der_file, MAX_PATH_LEN, "%s/tmp_client.der", tenant_dir);
    snprintf(pem_file, MAX_PATH_LEN, "%s/tmp_client.pem", tenant_dir);
    snprintf(cert_file, MAX_PATH_LEN, "%s/tmp_client_cert.pem", tenant_dir);
    snprintf(pkcs7_file, MAX_PATH_LEN, "%s/tmp_client.p7", tenant_dir);
    snprintf(config_file, MAX_PATH_LEN, "%s/%s.cnf", tenant_dir, tenant_id);
    
    // [2] Write binary DER CSR to disk
    fp = fopen(der_file, "wb");
    if (!fp) {
        fprintf(stderr, "[ERROR] Failed to open %s for writing\n", der_file);
        goto cleanup;
    }
    
    if (fwrite(p10buf, 1, p10len, fp) != (size_t)p10len) {
        fprintf(stderr, "[ERROR] Failed to write complete DER data to %s\n", der_file);
        fclose(fp);
        goto cleanup;
    }
    fclose(fp);
    fp = NULL;
    fprintf(stderr, "[INFO] [Step 1/6] Wrote DER CSR to %s (%d bytes)\n", der_file, p10len);
    
    // [3] Convert DER→PEM (openssl req -inform DER -outform PEM)
    snprintf(cmd, MAX_CMD_LEN, 
        "openssl req -inform DER -in %s -outform PEM -out %s 2>&1",
        der_file, pem_file);
    
    rc = system(cmd);
    if (rc != 0) {
        fprintf(stderr, "[ERROR] [Step 2/6] DER to PEM conversion failed (rc=%d)\n", rc);
        goto cleanup;
    }
    fprintf(stderr, "[INFO] [Step 2/6] Converted DER→PEM successfully\n");
    
    // [4] Execute 'openssl ca' with tenant-specific config
    snprintf(cmd, MAX_CMD_LEN,
        "openssl ca -batch -config %s -in %s -out %s 2>&1",
        config_file, pem_file, cert_file);
    
    rc = system(cmd);
    if (rc != 0) {
        fprintf(stderr, "[ERROR] [Step 3/6] OpenSSL CA signing failed (rc=%d)\n", rc);
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
        fprintf(stderr, "[ERROR] [Step 4/6] PKCS7 bundle creation failed (rc=%d)\n", rc);
        goto cleanup;
    }
    fprintf(stderr, "[INFO] [Step 4/6] Created PKCS7 bundle\n");
    
    // [6] Read PKCS7 file into memory (DER format for network transmission)
    snprintf(cmd, MAX_CMD_LEN,
        "openssl pkcs7 -in %s -outform DER -out %s.der 2>&1",
        pkcs7_file, pkcs7_file);
    
    rc = system(cmd);
    if (rc != 0) {
        fprintf(stderr, "[ERROR] [Step 5/6] PKCS7 DER conversion failed (rc=%d)\n", rc);
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
    
    fprintf(stderr, "[INFO] [Step 6/6] Loaded PKCS7 into memory (%ld bytes)\n", pkcs7_len);
    
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
