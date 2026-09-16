package com.mat.familytrack

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Handler
import android.os.Looper
import android.util.Log

object AlarmPlayer {
    private const val TAG = "AlarmPlayer"
    private var mediaPlayer: MediaPlayer? = null
    private val handler = Handler(Looper.getMainLooper())
    private var stopRunnable: Runnable? = null

    @Synchronized
    fun startAlarm(context: Context, durationSeconds: Int = 30) {
        stopAlarm()

        try {
            var alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            if (alarmUri == null) {
                alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            }
            if (alarmUri == null) {
                alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            }

            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            audioManager?.let { am ->
                val maxVol = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                am.setStreamVolume(AudioManager.STREAM_ALARM, maxVol, 0)
            }

            mediaPlayer = MediaPlayer().apply {
                setDataSource(context, alarmUri)
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                isLooping = true
                prepare()
                start()
            }
            Log.d(TAG, "Intruder alarm siren started")

            stopRunnable = Runnable {
                stopAlarm()
            }
            handler.postDelayed(stopRunnable!!, durationSeconds * 1000L)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start intruder alarm", e)
        }
    }

    @Synchronized
    fun stopAlarm() {
        try {
            stopRunnable?.let { handler.removeCallbacks(it) }
            stopRunnable = null
            mediaPlayer?.let {
                if (it.isPlaying) {
                    it.stop()
                }
                it.release()
            }
            mediaPlayer = null
            Log.d(TAG, "Intruder alarm siren stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping alarm", e)
        }
    }

    val isPlaying: Boolean
        get() = mediaPlayer?.isPlaying == true
}
