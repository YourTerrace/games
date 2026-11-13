package com.example.securitycam

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.camera.core.CameraSelector
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FallbackStrategy
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.concurrent.futures.await
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * 前面サービスとして常駐し、n分ごとにクリップを録画する。
 * 録画の合間はカメラを解放して消費電力を抑える。
 * 音声は録音しない(withAudioEnabled を呼ばない)。通知も無音チャンネル。
 */
class RecorderService : LifecycleService() {

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        if (running) return START_STICKY
        running = true
        startInForeground()
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "securitycam:rec").apply { acquire() }
        lifecycleScope.launch { loop() }
        return START_STICKY
    }

    override fun onBind(intent: Intent): IBinder? = super.onBind(intent)

    override fun onDestroy() {
        running = false
        wakeLock?.takeIf { it.isHeld }?.release()
        super.onDestroy() // lifecycleScope をキャンセル → loop の finally でカメラ解放
    }

    private suspend fun loop() {
        val provider = ProcessCameraProvider.getInstance(this).await()
        val store = ClipStore(this)
        try {
            while (lifecycleScope.isActive) {
                val cfg = Prefs.load(this)
                val t0 = SystemClock.elapsedRealtime()
                try {
                    recordOne(provider, store, cfg)
                } catch (e: kotlinx.coroutines.CancellationException) {
                    throw e
                } catch (e: Exception) {
                    Log.e(TAG, "record failed", e)
                }
                val wait = cfg.intervalMin * 60_000L - (SystemClock.elapsedRealtime() - t0)
                delay(wait.coerceAtLeast(1_000L))
            }
        } finally {
            provider.unbindAll()
        }
    }

    private suspend fun recordOne(provider: ProcessCameraProvider, store: ClipStore, cfg: Config) {
        // 録画前に、直前のクリップ1本分の空きを確保しておく
        store.trim(cfg.maxBytes - store.lastClipBytes())

        val q = cfg.quality
        val recorder = Recorder.Builder()
            .setQualitySelector(QualitySelector.from(q, FallbackStrategy.lowerQualityOrHigherThan(q)))
            .build()
        val capture = VideoCapture.withOutput(recorder)
        val selector =
            if (cfg.useFront) CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA

        provider.unbindAll()
        provider.bindToLifecycle(this, selector, capture)

        val file = store.newFile()
        val finalized = CompletableDeferred<VideoRecordEvent.Finalize>()
        val rec = capture.output
            .prepareRecording(this, FileOutputOptions.Builder(file).build()) // 音声なし
            .start(ContextCompat.getMainExecutor(this)) { ev ->
                if (ev is VideoRecordEvent.Finalize) finalized.complete(ev)
            }
        try {
            delay(cfg.clipSec * 1_000L)
        } finally {
            rec.stop()
            withContext(NonCancellable) {
                val ev = withTimeoutOrNull(10_000L) { finalized.await() }
                if (ev != null && ev.hasError() && file.exists() && file.length() == 0L) file.delete()
                provider.unbindAll()
            }
        }
        store.trim(cfg.maxBytes)
    }

    private fun startInForeground() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(CHANNEL, "録画中", NotificationManager.IMPORTANCE_LOW).apply {
                setSound(null, null)
                enableVibration(false)
            }
            nm.createNotificationChannel(ch)
        }
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(this)
        val n = builder
            .setContentTitle("SecurityCam")
            .setContentText("定期録画中")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA)
        } else {
            startForeground(NOTIF_ID, n)
        }
    }

    companion object {
        private const val TAG = "SecurityCam"
        private const val CHANNEL = "rec"
        private const val NOTIF_ID = 1

        @Volatile
        var running = false
            private set
    }
}
