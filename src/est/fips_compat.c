/*
 * OpenSSL 3.0 FIPS compatibility stub
 * 
 * FIPS_mode() and FIPS_mode_set() were removed in OpenSSL 3.0.
 * This provides stub implementations for backward compatibility.
 * 
 * For production FIPS mode with OpenSSL 3.0, configure the FIPS provider
 * in openssl.cnf instead of using these deprecated functions.
 */

int FIPS_mode(void) {
    /* Return 0 (not in FIPS mode) for OpenSSL 3.0+ */
    return 0;
}

int FIPS_mode_set(int onoff) {
    /* No-op for OpenSSL 3.0+ - configure via provider instead */
    (void)onoff;  /* Suppress unused parameter warning */
    return 1;     /* Return success */
}
