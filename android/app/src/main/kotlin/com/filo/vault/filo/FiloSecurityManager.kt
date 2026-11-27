package com.filo.vault.filo

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Build
import android.os.Debug
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import androidx.biometric.BiometricManager
import java.io.File
import java.security.InvalidKeyException
import java.security.KeyStore
import java.util.Locale
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Native Android Security Manager for Filo.
 *
 * Implements anti-tampering, runtime debugger detection, Android Keystore
 * hardware-bound biometric cryptographic key management, and
 * dynamic multi-part bitwise XOR credential unmasking.
 * Prevents plain-text API ID and API Hash exposure to decompilers (JADX, APKTool).
 */
object FiloSecurityManager {
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"
    private const val BIOMETRIC_KEY_ALIAS = "filo_biometric_hw_key_v1"
    private const val AES_GCM_TRANSFORMATION = "AES/GCM/NoPadding"
    private const val GCM_TAG_LENGTH_BITS = 128

    // Math-derived API ID (Never stored as literal integer or string)
    private const val PART_A = 0x02345678
    private const val PART_B = 0x03C79AFC

    // Multi-part XOR mask for 32-char hex API Hash (Never stored as string literal)
    private val HASH_MASK = byteArrayOf(
        0x02.toByte(), 0x57.toByte(), 0x53.toByte(), 0x07.toByte(),
        0x07.toByte(), 0x53.toByte(), 0x53.toByte(), 0x51.toByte(),
        0x04.toByte(), 0x02.toByte(), 0x05.toByte(), 0x03.toByte(),
        0x05.toByte(), 0x07.toByte(), 0x53.toByte(), 0x03.toByte(),
        0x55.toByte(), 0x5f.toByte(), 0x5e.toByte(), 0x5e.toByte(),
        0x5e.toByte(), 0x5e.toByte(), 0x02.toByte(), 0x03.toByte(),
        0x55.toByte(), 0x5e.toByte(), 0x50.toByte(), 0x03.toByte(),
        0x54.toByte(), 0x57.toByte(), 0x56.toByte(), 0x5f.toByte()
    )
    private const val HASH_XOR_KEY: Byte = 0x66

    fun isEnvironmentTampered(context: Context? = null): Boolean {
        val isDebuggable = context != null &&
            (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

        // Only check debugger/ptrace attachment in non-debuggable builds so dev runs work cleanly.
        if (!isDebuggable) {
            if (Debug.isDebuggerConnected() || Debug.waitingForDebugger()) {
                return true
            }

            try {
                val statusFile = File("/proc/self/status")
                if (statusFile.exists()) {
                    var tracerAttached = false
                    statusFile.useLines { lines ->
                        for (line in lines) {
                            if (line.startsWith("TracerPid:")) {
                                val tracerPid = line.substringAfter(":").trim().toIntOrNull() ?: 0
                                if (tracerPid != 0) {
                                    tracerAttached = true
                                }
                                break
                            }
                        }
                    }
                    if (tracerAttached) return true
                }
            } catch (_: Exception) {}
        }

        // Always detect Frida server binaries
        val suspiciousPaths = arrayOf(
            "/data/local/tmp/frida-server",
            "/data/local/tmp/re.frida.server",
            "/system/bin/frida-server"
        )
        for (path in suspiciousPaths) {
            try {
                if (File(path).exists()) return true
            } catch (_: Exception) {}
        }

        // Always inspect loaded memory mappings for instrumentation frameworks
        try {
            val mapsFile = File("/proc/self/maps")
            if (mapsFile.exists()) {
                var hookDetected = false
                mapsFile.useLines { lines ->
                    for (line in lines) {
                        val lower = line.lowercase(Locale.US)
                        if (lower.contains("frida") ||
                            lower.contains("xposed") ||
                            lower.contains("substrate")
                        ) {
                            hookDetected = true
                            break
                        }
                    }
                }
                if (hookDetected) return true
            }
        } catch (_: Exception) {}

        return false
    }

    fun getCredentials(context: Context): Map<String, Any> {
        if (isEnvironmentTampered(context)) {
            // Anti-tamper trigger: return dummy credentials to deny unauthorized dynamic extraction
            return mapOf(
                "apiId" to 0,
                "apiHash" to ""
            )
        }

        val unmaskedId = (PART_A xor PART_B) % 100000000
        val unmaskedBytes = ByteArray(HASH_MASK.size) { i ->
            (HASH_MASK[i].toInt() xor HASH_XOR_KEY.toInt()).toByte()
        }
        val unmaskedHash = String(unmaskedBytes, Charsets.UTF_8)
        unmaskedBytes.fill(0)

        return mapOf(
            "apiId" to unmaskedId,
            "apiHash" to unmaskedHash
        )
    }

    fun isHardwareBiometricAvailable(context: Context): Boolean {
        return try {
            val biometricManager = BiometricManager.from(context)
            biometricManager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG) ==
                BiometricManager.BIOMETRIC_SUCCESS
        } catch (_: Exception) {
            false
        }
    }

    fun getOrCreateBiometricKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        val existingKey = keyStore.getKey(BIOMETRIC_KEY_ALIAS, null) as? SecretKey
        if (existingKey != null) {
            return existingKey
        }

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            ANDROID_KEYSTORE
        )
        val specBuilder = KeyGenParameterSpec.Builder(
            BIOMETRIC_KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            specBuilder.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
        } else {
            @Suppress("DEPRECATION")
            specBuilder.setUserAuthenticationValidityDurationSeconds(-1)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            specBuilder.setInvalidatedByBiometricEnrollment(true)
        }

        keyGenerator.init(specBuilder.build())
        return keyGenerator.generateKey()
    }

    fun createEncryptCipher(): Cipher {
        return try {
            val key = getOrCreateBiometricKey()
            Cipher.getInstance(AES_GCM_TRANSFORMATION).apply {
                init(Cipher.ENCRYPT_MODE, key)
            }
        } catch (e: KeyPermanentlyInvalidatedException) {
            deleteBiometricKey()
            val freshKey = getOrCreateBiometricKey()
            Cipher.getInstance(AES_GCM_TRANSFORMATION).apply {
                init(Cipher.ENCRYPT_MODE, freshKey)
            }
        } catch (e: InvalidKeyException) {
            deleteBiometricKey()
            val freshKey = getOrCreateBiometricKey()
            Cipher.getInstance(AES_GCM_TRANSFORMATION).apply {
                init(Cipher.ENCRYPT_MODE, freshKey)
            }
        }
    }

    fun createDecryptCipher(iv: ByteArray): Cipher {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        val key = keyStore.getKey(BIOMETRIC_KEY_ALIAS, null) as? SecretKey
            ?: throw IllegalStateException("Biometric key not found in Android Keystore")

        return try {
            Cipher.getInstance(AES_GCM_TRANSFORMATION).apply {
                init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv))
            }
        } catch (e: KeyPermanentlyInvalidatedException) {
            deleteBiometricKey()
            throw e
        } catch (e: InvalidKeyException) {
            deleteBiometricKey()
            throw e
        }
    }

    fun deleteBiometricKey() {
        try {
            val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
            if (keyStore.containsAlias(BIOMETRIC_KEY_ALIAS)) {
                keyStore.deleteEntry(BIOMETRIC_KEY_ALIAS)
            }
        } catch (_: Exception) {}
    }
}
