package com.filo.vault.filo

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
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
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            System.loadLibrary("sqlite3")
            Log.i(TAG, "Loaded libsqlite3.so in onCreate")
        } catch (t: Throwable) {
            Log.w(TAG, "onCreate loadLibrary('sqlite3') note: ${t.message}")
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
                        val intent = Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url))
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("URL_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}


