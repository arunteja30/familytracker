package com.mat.familytrack

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.util.Log

object AlarmPlayer {
    private const val TAG = "AlarmPlayer"
    private val handler = Handler(Looper.getMainLooper())
    private var stopRunnable: Runnable? = null
    private var mediaPlayer: MediaPlayer? = null

    @Volatile
    private var isAlarmActive = false

    @Synchronized
    fun startAlarm(context: Context, durationSeconds: Int = 30) {
        stopAlarm()
        isAlarmActive = true

        try {
            val appContext = context.applicationContext

            // 1. Maximize Alarm and Music Audio Stream Volume
            val audioManager = appContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            audioManager?.let { am ->
                try {
                    val maxAlarmVol = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                    am.setStreamVolume(AudioManager.STREAM_ALARM, maxAlarmVol, 0)
                    val maxMusicVol = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                    am.setStreamVolume(AudioManager.STREAM_MUSIC, maxMusicVol, 0)
                } catch (e: Exception) {
                    Log.w(TAG, "Unable to adjust stream volume: ${e.message}")
                }
            }

            // 2. Play native alert sound from res/raw/alarm.wav
            val mp = MediaPlayer.create(appContext, R.raw.alarm)
            if (mp != null) {
                mp.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                mp.isLooping = true
                mp.start()
                mediaPlayer = mp
                Log.i(TAG, "🚨 Native intruder alarm sound (R.raw.alarm) started successfully (duration: ${durationSeconds}s)")
            } else {
                Log.e(TAG, "MediaPlayer.create(context, R.raw.alarm) returned null")
            }

            // 3. Auto-stop after durationSeconds
            stopRunnable = Runnable {
                stopAlarm()
            }
            handler.postDelayed(stopRunnable!!, durationSeconds * 1000L)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start intruder alarm sound", e)
        }
    }

    @Synchronized
    fun stopAlarm() {
        try {
            isAlarmActive = false
            stopRunnable?.let { handler.removeCallbacks(it) }
            stopRunnable = null

            mediaPlayer?.let { mp ->
                try {
                    if (mp.isPlaying) {
                        mp.stop()
                    }
                    mp.release()
                } catch (e: Exception) {
                    Log.w(TAG, "Error releasing MediaPlayer: ${e.message}")
                }
            }
            mediaPlayer = null
            Log.i(TAG, "Intruder alarm sound stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping alarm", e)
        }
    }

    val isPlaying: Boolean
        get() = isAlarmActive || (mediaPlayer?.isPlaying == true)
}
