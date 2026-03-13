
#include "mkcert.h"

#include <stdio.h>
#include <stdlib.h>

#include <openssl/evp.h>
#include <openssl/pem.h>
#include <OpenSSL/provider.h>
#include <OpenSSL/rsa.h>
#include <openssl/x509.h>
#include <OpenSSL/rand.h>

static const int NUM_BITS = 2048;
static const int SERIAL = 0;
static const int NUM_YEARS = 20;

void mkcert(X509 **x509p, EVP_PKEY **pkeyp, int bits, int serial, int years) {
    if (x509p) {
        *x509p = NULL;
    }
    if (pkeyp) {
        *pkeyp = NULL;
    }
    if (x509p == NULL || pkeyp == NULL) {
        return;
    }

    X509* cert = X509_new();
    if (cert == NULL) {
        return;
    }

    EVP_PKEY_CTX* ctx = EVP_PKEY_CTX_new_id(EVP_PKEY_RSA, NULL);
    if (ctx == NULL) {
        X509_free(cert);
        return;
    }

    if (EVP_PKEY_keygen_init(ctx) <= 0) {
        EVP_PKEY_CTX_free(ctx);
        X509_free(cert);
        return;
    }
    if (EVP_PKEY_CTX_set_rsa_keygen_bits(ctx, bits) <= 0) {
        EVP_PKEY_CTX_free(ctx);
        X509_free(cert);
        return;
    }

    // pk must be initialized on input
    EVP_PKEY* pk = NULL;
    if (EVP_PKEY_keygen(ctx, &pk) <= 0 || pk == NULL) {
        EVP_PKEY_CTX_free(ctx);
        X509_free(cert);
        return;
    }

    EVP_PKEY_CTX_free(ctx);

    if (X509_set_version(cert, 2) != 1) {
        EVP_PKEY_free(pk);
        X509_free(cert);
        return;
    }
    if (ASN1_INTEGER_set(X509_get_serialNumber(cert), serial) != 1) {
        EVP_PKEY_free(pk);
        X509_free(cert);
        return;
    }
#if OPENSSL_VERSION_NUMBER < 0x10100000L
    X509_gmtime_adj(X509_get_notBefore(cert), 0);
    X509_gmtime_adj(X509_get_notAfter(cert), 60 * 60 * 24 * 365 * years);
#else
    ASN1_TIME* before = ASN1_STRING_dup(X509_get0_notBefore(cert));
    ASN1_TIME* after = ASN1_STRING_dup(X509_get0_notAfter(cert));

    if (before == NULL || after == NULL) {
        ASN1_STRING_free(before);
        ASN1_STRING_free(after);
        EVP_PKEY_free(pk);
        X509_free(cert);
        return;
    }

    X509_gmtime_adj(before, 0);
    X509_gmtime_adj(after, 60 * 60 * 24 * 365 * years);

    X509_set1_notBefore(cert, before);
    X509_set1_notAfter(cert, after);

    ASN1_STRING_free(before);
    ASN1_STRING_free(after);
#endif

    if (X509_set_pubkey(cert, pk) != 1) {
        EVP_PKEY_free(pk);
        X509_free(cert);
        return;
    }

    X509_NAME* name = X509_get_subject_name(cert);
    if (name == NULL) {
        EVP_PKEY_free(pk);
        X509_free(cert);
        return;
    }
    X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC,
                               (const unsigned char*)"NVIDIA GameStream Client",
                               -1, -1, 0);
    X509_set_issuer_name(cert, name);

    if (X509_sign(cert, pk, EVP_sha256()) <= 0) {
        EVP_PKEY_free(pk);
        X509_free(cert);
        return;
    }
    
    *x509p = cert;
    *pkeyp = pk;
}

struct CertKeyPair generateCertKeyPair(void) {
    X509 *x509 = NULL;
    EVP_PKEY *pkey = NULL;
    PKCS12 *p12 = NULL;
    
    mkcert(&x509, &pkey, NUM_BITS, SERIAL, NUM_YEARS);

    if (x509 == NULL || pkey == NULL) {
        printf("Error generating X509 certificate / private key.\n");
        return (CertKeyPair){x509, pkey, NULL};
    }
    
    char* pass = "limelight";
    p12 = PKCS12_create(pass,
                        "GameStream",
                        pkey,
                        x509,
                        NULL,
                        NID_pbe_WithSHA1And3_Key_TripleDES_CBC,
                        -1, // disable certificate encryption
                        2048,
                        -1, // disable the automatic MAC
                        0);
    if (p12 == NULL) {
        printf("Error generating a valid PKCS12 certificate.\n");
        return (CertKeyPair){x509, pkey, NULL};
    }

    // MAC it ourselves with SHA1 since iOS refuses to load anything else.
    if (PKCS12_set_mac(p12, pass, -1, NULL, 0, 1, EVP_sha1()) != 1) {
        printf("Error setting PKCS12 MAC.\n");
        PKCS12_free(p12);
        p12 = NULL;
    }
    
    return (CertKeyPair){x509, pkey, p12};
}

void freeCertKeyPair(struct CertKeyPair certKeyPair) {
    if (certKeyPair.x509 != NULL) {
        X509_free(certKeyPair.x509);
    }
    if (certKeyPair.pkey != NULL) {
        EVP_PKEY_free(certKeyPair.pkey);
    }
    if (certKeyPair.p12 != NULL) {
        PKCS12_free(certKeyPair.p12);
    }
}
