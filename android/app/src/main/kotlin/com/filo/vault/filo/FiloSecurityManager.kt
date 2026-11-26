package com.filo.vault.filo

import android.content.Context
import android.os.Debug
import java.io.File

/**
 * Native Android Security Manager for Filo.
 *
 * Implements anti-tampering, runtime debugger detection, and
 * dynamic multi-part bitwise XOR credential unmasking.
 * Prevents plain-text API ID and API Hash exposure to decompilers (JADX, APKTool).
 */
object FiloSecurityManager {
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

    fun isEnvironmentTampered(): Boolean {
        // Detect attached debugger in release
        if (Debug.isDebuggerConnected() || Debug.waitingForDebugger()) {
            return true
        }

        // Detect Frida server or common dynamic instrumentation hooks
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

        return false
    }

    fun getCredentials(context: Context): Map<String, Any> {
        if (isEnvironmentTampered()) {
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

        return mapOf(
            "apiId" to unmaskedId,
            "apiHash" to unmaskedHash
        )
    }
}
