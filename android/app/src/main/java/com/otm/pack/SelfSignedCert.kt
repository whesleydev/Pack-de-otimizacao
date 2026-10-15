package com.otm.pack

import org.bouncycastle.asn1.x500.X500Name
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder
import java.math.BigInteger
import java.security.KeyPair
import java.security.cert.X509Certificate
import java.util.Date

/** Gera um certificado autoassinado para o cliente ADB (BouncyCastle). */
object SelfSignedCert {

    fun generate(subject: String, kp: KeyPair): X509Certificate {
        val now = System.currentTimeMillis()
        val name = X500Name(subject)
        val serial = BigInteger.valueOf(now)
        val builder = JcaX509v3CertificateBuilder(
            name,
            serial,
            Date(now - 24L * 3600 * 1000),
            Date(now + 3650L * 24 * 3600 * 1000),
            name,
            kp.public,
        )
        val signer = JcaContentSignerBuilder("SHA256withRSA").build(kp.private)
        return JcaX509CertificateConverter().getCertificate(builder.build(signer))
    }
}
