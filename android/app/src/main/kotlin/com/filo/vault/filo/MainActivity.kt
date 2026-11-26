package com.filo.vault.filo

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val TAG = "FiloMainActivity"
        private const val CHANNEL = "com.filo.vault.filo/transfers"

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
                "openUrl" -> {
                    val url = call.argument<String>("url") ?: ""
                    try {
                        val uri = android.net.Uri.parse(url)
                        val scheme = uri.scheme?.lowercase()
                        if (scheme != "http" && scheme != "https") {
                            result.error("INVALID_SCHEME", "Only HTTP and HTTPS URLs are permitted", null)
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.filo.vault.filo/security").setMethodCallHandler { call, result ->
            when (call.method) {
                "getSecureCredentials" -> {
                    try {
                        val creds = FiloSecurityManager.getCredentials(applicationContext)
                        result.success(creds)
                    } catch (e: Exception) {
                        result.error("SECURITY_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}


