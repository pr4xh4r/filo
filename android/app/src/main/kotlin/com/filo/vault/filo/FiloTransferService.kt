package com.filo.vault.filo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Native Android foreground service for data sync.
 * Guarantees that chunk encryption and file transfers continue seamlessly
 * without being throttled or killed when the app is minimized or the screen is locked.
 */
class FiloTransferService : Service() {
    companion object {
        const val CHANNEL_ID = "filo_transfer_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "com.filo.vault.filo.START_TRANSFER"
        const val ACTION_STOP = "com.filo.vault.filo.STOP_TRANSFER"
        const val EXTRA_TITLE = "extra_title"
        const val EXTRA_CONTENT = "extra_content"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Filo Secure Sync"
        val content = intent?.getStringExtra(EXTRA_CONTENT) ?: "Transferring encrypted files..."

        val notification = buildNotification(title, content)
        startForeground(NOTIFICATION_ID, notification)

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(title: String, content: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(content)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Filo File Transfers",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Background file encryption, upload, and download transfers"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }
}
