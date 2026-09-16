package com.mat.familytrack

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.os.PowerManager
import android.provider.Telephony
import android.telephony.SmsMessage
import android.util.Log

/**
 * ============================================================================
 * SECURITY SMS TRIGGER RECEIVER (LOUD ALARM ON "Find" SMS)
 * ============================================================================
 * Listens for incoming SMS messages.
 * When an SMS with body "Find" (case-insensitive, trimmed) is received:
 * 1. Acquires a WakeLock and wakes up CPU/Screen.
 * 2. Overrides Silent/DND modes and sets maximum Alarm volume.
 * 3. Plays a loud, continuous alarm siren via AlarmPlayer.startAlarm() for 60 seconds.
 * 4. Updates Sticky Notification to show device locating status.
 */
class SmsSecurityReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SmsSecurityReceiver"
        private const val FIND_TRIGGER_KEYWORD = "find"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            return
        }

        try {
            val messages: Array<SmsMessage>? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                Telephony.Sms.Intents.getMessagesFromIntent(intent)
            } else {
                val bundle = intent.extras ?: return
                val pdus = bundle.get("pdus") as? Array<*> ?: return
                pdus.mapNotNull { pdu ->
                    @Suppress("DEPRECATION")
                    (pdu as? ByteArray)?.let { SmsMessage.createFromPdu(it) }
                }.toTypedArray()
            }

            if (messages.isNullOrEmpty()) {
                return
            }

            for (sms in messages) {
                val body = sms.displayMessageBody?.trim() ?: ""
                val sender = sms.displayOriginatingAddress ?: "Unknown"

                Log.d(TAG, "SMS Received from: $sender | Content: $body")

                // Case-insensitive match for "find" (e.g. "Find", "FIND", "find", " find ")
                if (body.equals(FIND_TRIGGER_KEYWORD, ignoreCase = true)) {
                    Log.i(TAG, "🚨 'Find' SMS triggered from $sender! Triggering maximum volume siren to locate phone...")
                    triggerFindPhoneAlarm(context.applicationContext, sender)
                    break
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing incoming SMS for security trigger: ${e.message}", e)
        }
    }

    private fun triggerFindPhoneAlarm(context: Context, senderPhone: String) {
        // 1. Acquire Partial WakeLock to keep device awake while alarm plays
        try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            val wakeLock = powerManager?.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "FamilyTracker:FindPhoneWakeLock"
            )
            wakeLock?.acquire(60 * 1000L) // 60s timeout
        } catch (e: Exception) {
            Log.w(TAG, "WakeLock acquisition warning: ${e.message}")
        }

        // 2. Override Silent / Do-Not-Disturb and maximize audio volume
        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            audioManager?.let { am ->
                // Ensure ringer mode is normal (unmute)
                am.ringerMode = AudioManager.RINGER_MODE_NORMAL

                val maxAlarmVol = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                am.setStreamVolume(AudioManager.STREAM_ALARM, maxAlarmVol, AudioManager.FLAG_SHOW_UI)

                val maxMusicVol = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                am.setStreamVolume(AudioManager.STREAM_MUSIC, maxMusicVol, 0)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Audio volume adjustment warning: ${e.message}")
        }

        // 3. Play loud alarm siren for 60 seconds (even in silent mode)
        AlarmPlayer.startAlarm(context, durationSeconds = 60)

        // 4. Update Sticky Notification with prominent alert
        try {
            StickyTrackerService.updateStickyNotificationFromFlutter(
                context = context,
                title = "🚨 PHONE LOCATOR ACTIVE",
                text = "Loud alarm triggered by 'Find' SMS from $senderPhone",
                isSosActive = true
            )
        } catch (e: Exception) {
            Log.w(TAG, "Sticky notification update warning: ${e.message}")
        }
    }
}
