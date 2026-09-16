package com.mat.familytrack

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import kotlin.concurrent.thread
import kotlin.math.PI
import kotlin.math.sin

object AlarmPlayer {
    private const val TAG = "AlarmPlayer"
    private val handler = Handler(Looper.getMainLooper())
    private var stopRunnable: Runnable? = null

    @Volatile
    private var isAlarmActive = false
    private var audioTrack: AudioTrack? = null
    private var ringtone: Ringtone? = null
    private var sirenThread: Thread? = null

    @Synchronized
    fun startAlarm(context: Context, durationSeconds: Int = 30) {
        stopAlarm()
        isAlarmActive = true

        try {
            // 1. Maximize Alarm and Music Audio Stream Volume
            val audioManager = context.applicationContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
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

            // 2. Play System Alarm Ringtone via RingtoneManager
            try {
                var alarmUri = RingtoneManager.getActualDefaultRingtoneUri(context, RingtoneManager.TYPE_ALARM)
                if (alarmUri == null) {
                    alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                }
                if (alarmUri == null) {
                    alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                }

                if (alarmUri != null) {
                    val r = RingtoneManager.getRingtone(context.applicationContext, alarmUri)
                    r?.let {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                            it.audioAttributes = AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_ALARM)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .build()
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            it.isLooping = true
                        }
                        it.play()
                        ringtone = it
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "RingtoneManager playback note: ${e.message}")
            }

            // 3. Guaranteed High-Decibel Wailing Siren Generator (AudioTrack Hardware Stream)
            sirenThread = thread(start = true, name = "IntruderSirenEngine") {
                playWailingSiren()
            }

            Log.i(TAG, "🚨 Intruder alarm siren started (duration: ${durationSeconds}s)")

            // 4. Auto-stop after durationSeconds
            stopRunnable = Runnable {
                stopAlarm()
            }
            handler.postDelayed(stopRunnable!!, durationSeconds * 1000L)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start intruder alarm", e)
        }
    }

    private fun playWailingSiren() {
        val sampleRate = 44100
        val minBufferSize = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        val bufferSize = maxOf(minBufferSize, sampleRate / 4)

        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val format = AudioFormat.Builder()
            .setSampleRate(sampleRate)
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
            .build()

        try {
            val track = AudioTrack(
                attributes,
                format,
                bufferSize,
                AudioTrack.MODE_STREAM,
                AudioManager.AUDIO_SESSION_ID_GENERATE
            )
            audioTrack = track
            track.play()

            val samples = ShortArray(bufferSize)
            var phase = 0.0
            var sirenProgress = 0.0
            val sirenCyclePeriod = sampleRate * 1.2 // 1.2s per wail cycle

            while (isAlarmActive) {
                for (i in 0 until bufferSize) {
                    // Oscillate frequency between 700 Hz (low wail) and 1600 Hz (high scream)
                    val mod = (sin(2.0 * PI * sirenProgress / sirenCyclePeriod) + 1.0) / 2.0
                    val currentFreq = 700.0 + (900.0 * mod)

                    val sampleValue = sin(2.0 * PI * phase) * Short.MAX_VALUE * 0.95
                    samples[i] = sampleValue.toInt().toShort()

                    phase += currentFreq / sampleRate
                    if (phase > 1.0) phase -= 1.0

                    sirenProgress += 1.0
                    if (sirenProgress >= sirenCyclePeriod) sirenProgress = 0.0
                }
                track.write(samples, 0, bufferSize)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Siren AudioTrack loop ended: ${e.message}")
        } finally {
            try {
                audioTrack?.stop()
                audioTrack?.release()
            } catch (_) {}
            audioTrack = null
        }
    }

    @Synchronized
    fun stopAlarm() {
        try {
            isAlarmActive = false
            stopRunnable?.let { handler.removeCallbacks(it) }
            stopRunnable = null

            // Stop Ringtone
            try {
                ringtone?.let {
                    if (it.isPlaying) {
                        it.stop()
                    }
                }
            } catch (_) {}
            ringtone = null

            // Stop AudioTrack
            try {
                audioTrack?.let {
                    it.pause()
                    it.flush()
                    it.stop()
                    it.release()
                }
            } catch (_) {}
            audioTrack = null

            sirenThread = null
            Log.i(TAG, "Intruder alarm siren stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping alarm", e)
        }
    }

    val isPlaying: Boolean
        get() = isAlarmActive
}
