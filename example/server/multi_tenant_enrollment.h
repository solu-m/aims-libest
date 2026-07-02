/*------------------------------------------------------------------
 * multi_tenant_enrollment.h - Multi-tenant enrollment header
 *
 * July, 2026
 *
 * Copyright (c) 2026 by Cisco Systems, Inc.
 * All rights reserved.
 *------------------------------------------------------------------
 */
#ifndef HEADER_MULTI_TENANT_ENROLLMENT_H
#define HEADER_MULTI_TENANT_ENROLLMENT_H

#include <openssl/bio.h>

/*
 * Multi-Tenant Black-Box Enrollment Function
 *
 * Performs isolated certificate enrollment for a specific tenant
 * using external OpenSSL CA execution.
 *
 * Parameters:
 *   p10buf    - Binary DER-encoded PKCS#10 CSR
 *   p10len    - Length of CSR buffer
 *   tenant_id - Tenant identifier (gateway, iot, or freeradius)
 *
 * Returns:
 *   BIO containing DER-encoded PKCS7 signed certificate, or NULL on error
 */
BIO * multi_tenant_enroll(const unsigned char *p10buf, int p10len, const char *tenant_id);

/*
 * Multi-Tenant CA Certs Callback
 *
 * Returns the CA certificate(s) for a tenant in PKCS7 DER format.
 *
 * Parameters:
 *   cacerts_len - Output: length of returned buffer
 *   path_seg    - Tenant ID extracted from URL path
 *   ex_data     - Application context (unused)
 *
 * Returns:
 *   Pointer to PKCS7 DER-encoded CA cert(s), or NULL on error
 */
unsigned char *multi_tenant_cacerts(int *cacerts_len, char *path_seg, void *ex_data);

#endif /* HEADER_MULTI_TENANT_ENROLLMENT_H */
