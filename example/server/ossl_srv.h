/*------------------------------------------------------------------
 * ossl_srv.h - Entry point definitions into the OpenSSL
 *              interface for EST server operations. 
 *
 * November, 2012
 *
 * Copyright (c) 2012 by cisco Systems, Inc.
 * All rights reserved.
 *------------------------------------------------------------------
 */
#ifndef HEADER_OSSL_SRV_H 
#define HEADER_OSSL_SRV_H 

#include <openssl/x509.h>
#include <openssl/evp.h>
#include <openssl/bio.h>

BIO * ossl_simple_enroll(unsigned char *p10buf, int p10len);

/* Role-based certificate enrollment functions */
X509* ossl_role_based_enroll(unsigned char *pkcs10_data,
                             int pkcs10_len,
                             X509 *ca_cert,
                             EVP_PKEY *ca_key,
                             const char *role,
                             long serial,
                             int days);

BIO* ossl_role_based_enroll_pkcs7(unsigned char *pkcs10_data,
                                  int pkcs10_len,
                                  X509 *ca_cert,
                                  EVP_PKEY *ca_key,
                                  const char *role,
                                  long serial,
                                  int days);

#endif
