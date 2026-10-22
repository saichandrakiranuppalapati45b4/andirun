package com.andirun.worker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class WorkerService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var isRunning = false

    companion object {
        const val CHANNEL_ID = "AndiRunWorkerChannel"
        const val NOTIFICATION_ID = 1001

        init {
            System.loadLibrary("andirun_native")
        }

        @JvmStatic
        external fun startTailServer(port: Int, modelPath: String): Int

        @JvmStatic
        external fun stopTailServer()

        @JvmStatic
        external fun getWorkerStatus(): String
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()

        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "AndiRun::WorkerWakeLock")
        wakeLock?.acquire()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val modelPath = intent?.getStringExtra("MODEL_PATH") ?: "/data/local/tmp/tail-L20.gguf"
        val port = intent?.getIntExtra("PORT", 8080) ?: 8080

        val notification = buildNotification("AndiRun Tail Worker listening on :$port")
        startForeground(NOTIFICATION_ID, notification)

        if (!isRunning) {
            isRunning = true
            Thread {
                startTailServer(port, modelPath)
            }.start()
        }

        return START_STICKY
    }

    override fun onDestroy() {
        stopTailServer()
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        isRunning = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "AndiRun Worker Background Service",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Keeps the Backburner LLM Co-Processor GPU/CPU server active"
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(text: String): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("AndiRun LLM Co-Processor")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }
}
