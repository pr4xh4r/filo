package com.filo.vault.filo

import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.StatFs
import android.provider.MediaStore
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.util.Base64
import android.util.Log
import android.view.WindowManager
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.GeneralSecurityException
import java.security.InvalidKeyException
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val TAG = "FiloMainActivity"
        private const val CHANNEL = "com.filo.vault.filo/transfers"
        private const val SECURITY_CHANNEL = "com.filo.vault.filo/security"
        private const val HW_BIOMETRIC_PREFIX = "v2_hw:"
        private val ALLOWED_URL_HOSTS = setOf("github.com", "raw.githubusercontent.com")

        init {
            try {
                System.loadLibrary("sqlite3")
                Log.i(TAG, "Preloaded libsqlite3.so successfully via System.loadLibrary")
            } catch (t: Throwable) {
                Log.w(TAG, "Initial loadLibrary('sqlite3') failed or deferred: ${t.message}")
            }
            try {
                System.loadLibrary("tdjson")
                Log.i(TAG, "Preloaded libtdjson.so successfully via System.loadLibrary")
            } catch (t: Throwable) {
                Log.w(TAG, "Initial loadLibrary('tdjson') note: ${t.message}")
            }
        }
    }

    private val biometricPromptActive = AtomicBoolean(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Security: Prevent screen captures, task switcher previews, and screen recording leaks in release builds
        val isDebuggable = (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (!isDebuggable) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE
            )
        }
        try {
            System.loadLibrary("sqlite3")
            Log.i(TAG, "Loaded libsqlite3.so in onCreate")
        } catch (t: Throwable) {
            Log.w(TAG, "onCreate loadLibrary('sqlite3') note: ${t.message}")
        }
        try {
            System.loadLibrary("tdjson")
            Log.i(TAG, "Loaded libtdjson.so in onCreate")
        } catch (t: Throwable) {
            Log.w(TAG, "onCreate loadLibrary('tdjson') note: ${t.message}")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundTransfer" -> {
                    val title = call.argument<String>("title") ?: "Filo Transfer"
                    val content = call.argument<String>("content") ?: "Transferring files in background..."
                    val intent = Intent(this, FiloTransferService::class.java).apply {
                        action = FiloTransferService.ACTION_START
                        putExtra(FiloTransferService.EXTRA_TITLE, title)
                        putExtra(FiloTransferService.EXTRA_CONTENT, content)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        ContextCompat.startForegroundService(this, intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "stopForegroundTransfer" -> {
                    val intent = Intent(this, FiloTransferService::class.java).apply {
                        action = FiloTransferService.ACTION_STOP
                    }
                    startService(intent)
                    result.success(true)
                }
                "getAvailableStorageBytes" -> {
                    val path = call.argument<String>("path") ?: filesDir.absolutePath
                    try {
                        val stat = StatFs(path)
                        result.success(stat.availableBytes)
                    } catch (e: Exception) {
                        result.error("STAT_FAILED", e.message, null)
                    }
                }
                "saveExportToDownloads" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    val fileName = call.argument<String>("fileName")
                    val mimeType = call.argument<String>("mimeType") ?: "application/zip"
                    val deleteSource = call.argument<Boolean>("deleteSource") ?: true
                    if (sourcePath.isNullOrBlank() || fileName.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "sourcePath and fileName are required", null)
                        return@setMethodCallHandler
                    }
                    handleSaveExportToDownloads(sourcePath, fileName, mimeType, deleteSource, result)
                }
                "openUrl" -> {
                    val url = call.argument<String>("url")?.trim() ?: ""
                    try {
                        val uri = android.net.Uri.parse(url)
                        val scheme = uri.scheme?.lowercase(Locale.US)
                        val host = uri.host?.lowercase(Locale.US)
                        val path = uri.path ?: ""
                        val isPathAllowed = (path == "/pr4xh4r/filo" || path.startsWith("/pr4xh4r/filo/")) &&
                            !path.contains("..")
                        if (scheme != "https" ||
                            uri.userInfo != null ||
                            host == null ||
                            host !in ALLOWED_URL_HOSTS ||
                            !isPathAllowed
                        ) {
                            result.error("UNTRUSTED_URL", "Only trusted HTTPS Filo repository URLs are permitted", null)
                            return@setMethodCallHandler
                        }
                        val intent = Intent(Intent.ACTION_VIEW, uri)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("URL_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURITY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSecureCredentials" -> {
                    try {
                        val creds = FiloSecurityManager.getCredentials(applicationContext)
                        result.success(creds)
                    } catch (e: Exception) {
                        result.error("SECURITY_ERROR", e.message, null)
                    }
                }
                "canUseHardwareBiometric" -> {
                    result.success(FiloSecurityManager.isHardwareBiometricAvailable(this))
                }
                "enrollBiometricKey" -> {
                    val masterKeyBase64 = call.argument<String>("masterKeyBase64")
                    val reason = call.argument<String>("reason")
                        ?: "Authenticate to enable biometric unlock for Filo"
                    handleEnrollBiometricKey(masterKeyBase64, reason, result)
                }
                "unsealBiometricKey" -> {
                    val wrappedBlob = call.argument<String>("wrappedBlob")
                    val reason = call.argument<String>("reason")
                        ?: "Scan fingerprint to unlock Filo vault"
                    handleUnsealBiometricKey(wrappedBlob, reason, result)
                }
                "deleteBiometricKey" -> {
                    FiloSecurityManager.deleteBiometricKey()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun handleEnrollBiometricKey(
        masterKeyBase64: String?,
        reason: String,
        result: MethodChannel.Result
    ) {
        if (masterKeyBase64.isNullOrBlank()) {
            result.error("INVALID_ARGS", "Master key payload is required", null)
            return
        }
        val rawBytes = try {
            Base64.decode(masterKeyBase64, Base64.DEFAULT)
        } catch (_: IllegalArgumentException) {
            result.error("INVALID_ARGS", "Invalid base64 master key payload", null)
            return
        }
        if (rawBytes.isEmpty()) {
            result.error("INVALID_ARGS", "Empty master key payload", null)
            return
        }

        if (!FiloSecurityManager.isHardwareBiometricAvailable(this)) {
            rawBytes.fill(0)
            result.error("BIOMETRIC_UNAVAILABLE", "Strong hardware biometrics are not available or enrolled", null)
            return
        }

        if (!biometricPromptActive.compareAndSet(false, true)) {
            rawBytes.fill(0)
            result.error("BIOMETRIC_IN_PROGRESS", "A biometric prompt is already active", null)
            return
        }

        runOnUiThread {
            val replied = AtomicBoolean(false)
            try {
                val cipher = FiloSecurityManager.createEncryptCipher()
                val promptInfo = BiometricPrompt.PromptInfo.Builder()
                    .setTitle("Filo Vault")
                    .setSubtitle(reason)
                    .setNegativeButtonText("Cancel")
                    .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
                    .build()

                val callback = object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(authResult: BiometricPrompt.AuthenticationResult) {
                        if (!replied.compareAndSet(false, true)) return
                        biometricPromptActive.set(false)
                        var combined: ByteArray? = null
                        try {
                            val authCipher = authResult.cryptoObject?.cipher
                            if (authCipher == null) {
                                result.error("CRYPTO_ERROR", "Missing hardware cipher in biometric result", null)
                                return
                            }
                            val iv = authCipher.iv
                            if (iv == null || iv.size != 12) {
                                result.error("CRYPTO_ERROR", "Invalid AES-GCM IV length from Keystore", null)
                                return
                            }
                            val ciphertext = authCipher.doFinal(rawBytes)
                            combined = ByteArray(iv.size + ciphertext.size)
                            System.arraycopy(iv, 0, combined, 0, iv.size)
                            System.arraycopy(ciphertext, 0, combined, iv.size, ciphertext.size)
                            val wrappedBlob = HW_BIOMETRIC_PREFIX + Base64.encodeToString(combined, Base64.NO_WRAP)
                            result.success(wrappedBlob)
                        } catch (e: Exception) {
                            result.error("CRYPTO_ERROR", e.message ?: "Failed to encrypt biometric key", null)
                        } finally {
                            rawBytes.fill(0)
                            combined?.fill(0)
                        }
                    }

                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                        if (!replied.compareAndSet(false, true)) return
                        biometricPromptActive.set(false)
                        rawBytes.fill(0)
                        result.error(mapBiometricErrorCode(errorCode), errString.toString(), errorCode)
                    }
                }

                val prompt = BiometricPrompt(this, ContextCompat.getMainExecutor(this), callback)
                prompt.authenticate(promptInfo, BiometricPrompt.CryptoObject(cipher))
            } catch (e: Exception) {
                if (replied.compareAndSet(false, true)) {
                    biometricPromptActive.set(false)
                    rawBytes.fill(0)
                    result.error("BIOMETRIC_ERROR", e.message ?: "Biometric enrollment failed", null)
                }
            }
        }
    }

    private fun handleUnsealBiometricKey(
        wrappedBlob: String?,
        reason: String,
        result: MethodChannel.Result
    ) {
        if (wrappedBlob.isNullOrBlank() || !wrappedBlob.startsWith(HW_BIOMETRIC_PREFIX)) {
            result.error("BIOMETRIC_REENROLL_REQUIRED", "Legacy biometric credential requires re-enrollment", null)
            return
        }

        val combined = try {
            Base64.decode(wrappedBlob.removePrefix(HW_BIOMETRIC_PREFIX), Base64.DEFAULT)
        } catch (_: IllegalArgumentException) {
            result.error("BIOMETRIC_REENROLL_REQUIRED", "Malformed biometric key payload", null)
            return
        }

        // Minimum: 12-byte IV + 16-byte GCM authentication tag
        if (combined.size < 28) {
            combined.fill(0)
            result.error("BIOMETRIC_REENROLL_REQUIRED", "Corrupted biometric key payload", null)
            return
        }

        val iv = combined.copyOfRange(0, 12)
        val ciphertext = combined.copyOfRange(12, combined.size)
        combined.fill(0)

        if (!biometricPromptActive.compareAndSet(false, true)) {
            iv.fill(0)
            ciphertext.fill(0)
            result.error("BIOMETRIC_IN_PROGRESS", "A biometric prompt is already active", null)
            return
        }

        runOnUiThread {
            val replied = AtomicBoolean(false)
            try {
                val cipher = FiloSecurityManager.createDecryptCipher(iv)
                val promptInfo = BiometricPrompt.PromptInfo.Builder()
                    .setTitle("Filo Vault")
                    .setSubtitle(reason)
                    .setNegativeButtonText("Cancel")
                    .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
                    .build()

                val callback = object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(authResult: BiometricPrompt.AuthenticationResult) {
                        if (!replied.compareAndSet(false, true)) return
                        biometricPromptActive.set(false)
                        var rawKey: ByteArray? = null
                        try {
                            val authCipher = authResult.cryptoObject?.cipher
                            if (authCipher == null) {
                                result.error("CRYPTO_ERROR", "Missing hardware cipher in biometric result", null)
                                return
                            }
                            rawKey = authCipher.doFinal(ciphertext)
                            val rawKeyBase64 = Base64.encodeToString(rawKey, Base64.NO_WRAP)
                            result.success(rawKeyBase64)
                        } catch (e: GeneralSecurityException) {
                            FiloSecurityManager.deleteBiometricKey()
                            result.error(
                                "BIOMETRIC_REENROLL_REQUIRED",
                                "Biometric unseal failed; please unlock with passphrase and re-enable biometric unlock",
                                null
                            )
                        } catch (e: Exception) {
                            result.error("CRYPTO_ERROR", e.message ?: "Biometric decryption failed", null)
                        } finally {
                            rawKey?.fill(0)
                            iv.fill(0)
                            ciphertext.fill(0)
                        }
                    }

                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                        if (!replied.compareAndSet(false, true)) return
                        biometricPromptActive.set(false)
                        iv.fill(0)
                        ciphertext.fill(0)
                        result.error(mapBiometricErrorCode(errorCode), errString.toString(), errorCode)
                    }
                }

                val prompt = BiometricPrompt(this, ContextCompat.getMainExecutor(this), callback)
                prompt.authenticate(promptInfo, BiometricPrompt.CryptoObject(cipher))
            } catch (e: KeyPermanentlyInvalidatedException) {
                if (replied.compareAndSet(false, true)) {
                    biometricPromptActive.set(false)
                    iv.fill(0)
                    ciphertext.fill(0)
                    FiloSecurityManager.deleteBiometricKey()
                    result.error(
                        "BIOMETRIC_REENROLL_REQUIRED",
                        "Device biometrics changed; please unlock with passphrase and re-enable biometric unlock",
                        null
                    )
                }
            } catch (e: Exception) {
                if (replied.compareAndSet(false, true)) {
                    biometricPromptActive.set(false)
                    iv.fill(0)
                    ciphertext.fill(0)
                    val code = if (e is InvalidKeyException || e is IllegalStateException) {
                        FiloSecurityManager.deleteBiometricKey()
                        "BIOMETRIC_REENROLL_REQUIRED"
                    } else {
                        "BIOMETRIC_ERROR"
                    }
                    result.error(code, e.message ?: "Biometric authentication failed", null)
                }
            }
        }
    }

    private fun handleSaveExportToDownloads(
        sourcePath: String,
        fileName: String,
        mimeType: String,
        deleteSource: Boolean,
        result: MethodChannel.Result
    ) {
        Thread {
            val srcFile = File(sourcePath)
            if (!srcFile.exists()) {
                runOnUiThread {
                    result.error("SOURCE_MISSING", "Export archive does not exist: $sourcePath", null)
                }
                return@Thread
            }

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val resolver = applicationContext.contentResolver
                    val values = ContentValues().apply {
                        put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                        put(MediaStore.Downloads.MIME_TYPE, mimeType)
                        put(
                            MediaStore.Downloads.RELATIVE_PATH,
                            Environment.DIRECTORY_DOWNLOADS + File.separator + "Filo"
                        )
                        put(MediaStore.Downloads.IS_PENDING, 1)
                    }
                    val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                        ?: throw IllegalStateException("MediaStore failed to allocate Download entry")

                    try {
                        val outStream = resolver.openOutputStream(uri)
                            ?: throw IllegalStateException("Unable to open MediaStore output stream")
                        outStream.use { out ->
                            FileInputStream(srcFile).use { input ->
                                val buffer = ByteArray(1024 * 1024)
                                while (true) {
                                    val read = input.read(buffer)
                                    if (read <= 0) break
                                    out.write(buffer, 0, read)
                                }
                                out.flush()
                            }
                        }

                        val readyValues = ContentValues().apply {
                            put(MediaStore.Downloads.IS_PENDING, 0)
                        }
                        resolver.update(uri, readyValues, null, null)
                        if (deleteSource) {
                            srcFile.delete()
                        }

                        runOnUiThread {
                            result.success(
                                mapOf(
                                    "savedPath" to "Downloads/Filo/$fileName",
                                    "uri" to uri.toString()
                                )
                            )
                        }
                    } catch (e: Exception) {
                        try {
                            resolver.delete(uri, null, null)
                        } catch (_: Exception) {}
                        throw e
                    }
                } else {
                    val publicDownloads = Environment.getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_DOWNLOADS
                    )
                    val targetDir = File(publicDownloads, "Filo")
                    var destFile = File(targetDir, fileName)
                    val canWritePublic = try {
                        if (!targetDir.exists()) targetDir.mkdirs()
                        targetDir.exists() && targetDir.canWrite()
                    } catch (_: SecurityException) {
                        false
                    }

                    if (!canWritePublic) {
                        val fallbackDir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: filesDir
                        if (!fallbackDir.exists()) fallbackDir.mkdirs()
                        destFile = File(fallbackDir, fileName)
                    }

                    FileInputStream(srcFile).use { input ->
                        FileOutputStream(destFile).use { out ->
                            val buffer = ByteArray(1024 * 1024)
                            while (true) {
                                val read = input.read(buffer)
                                if (read <= 0) break
                                out.write(buffer, 0, read)
                            }
                            out.flush()
                        }
                    }

                    if (deleteSource) {
                        srcFile.delete()
                    }

                    MediaScannerConnection.scanFile(
                        applicationContext,
                        arrayOf(destFile.absolutePath),
                        arrayOf(mimeType),
                        null
                    )

                    runOnUiThread {
                        result.success(
                            mapOf(
                                "savedPath" to destFile.absolutePath,
                                "uri" to null
                            )
                        )
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to save export to Downloads", e)
                runOnUiThread {
                    result.error("EXPORT_SAVE_FAILED", e.message ?: "Failed to save export archive", null)
                }
            }
        }.start()
    }

    private fun mapBiometricErrorCode(errorCode: Int): String {
        return when (errorCode) {
            BiometricPrompt.ERROR_USER_CANCELED,
            BiometricPrompt.ERROR_NEGATIVE_BUTTON,
            BiometricPrompt.ERROR_CANCELED -> "BIOMETRIC_CANCELED"
            else -> "BIOMETRIC_AUTH_FAILED"
        }
    }
}


