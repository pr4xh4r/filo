package com.filo.vault.filo

import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val TAG = "FiloMainActivity"

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
}

