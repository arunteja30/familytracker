package com.mat.familytrack

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.media.AudioManager
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Telephony
import android.telephony.SmsManager
import android.telephony.SmsMessage
import android.util.Log
import androidx.core.content.ContextCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * ============================================================================
 * SECURITY SMS TRIGGER RECEIVER (LOUD ALARM & LOCATION DISPATCH ON "Find" SMS)
 * ============================================================================
 * Listens for incoming SMS messages.
 * When an SMS with body "Find" (case-insensitive, trimmed) is received:
 * 1. Acquires a WakeLock and wakes up CPU/Screen.
 * 2. Overrides Silent/DND modes and sets maximum Alarm volume.
 * 3. Plays a loud, continuous alarm siren via AlarmPlayer.startAlarm() for 60 seconds.
 * 4. Fetches the current GPS coordinates of the device immediately.
 * 5. Sends an SMS reply with Google Maps link & battery level to the sender/admin phone number.
 * 6. Sends a formatted location alert email with Google Maps link to the configured alert email.
 * 7. Updates Sticky Notification to show device locating status.
 */
class SmsSecurityReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SmsSecurityReceiver"
        private val TRIGGER_KEYWORDS = listOf("find", "audious")
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

                // Case-insensitive match for "find" or "audious" (e.g. "Find", "FIND", "audious", "Audious")
                if (TRIGGER_KEYWORDS.any { it.equals(body, ignoreCase = true) }) {
                    Log.i(TAG, "🚨 Security SMS trigger matched ('$body') from $sender! Triggering siren, GPS location, SMS reply & Email with backups...")
                    triggerFindPhoneSecurity(context.applicationContext, sender)
                    break
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing incoming SMS for security trigger: ${e.message}", e)
        }
    }

    private fun triggerFindPhoneSecurity(context: Context, senderPhone: String) {
        // 1. Acquire Partial WakeLock to keep device awake while alarm & GPS run
        try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            val wakeLock = powerManager?.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "FamilyTracker:FindPhoneWakeLock"
            )
            wakeLock?.acquire(90 * 1000L) // 90s timeout
        } catch (e: Exception) {
            Log.w(TAG, "WakeLock acquisition warning: ${e.message}")
        }

        // 2. Override Silent / Do-Not-Disturb and maximize audio volume
        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            audioManager?.let { am ->
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

        // 5. Fetch current GPS location and dispatch Location via SMS and Email
        fetchAndDispatchLocation(context, senderPhone)
    }

    private fun fetchAndDispatchLocation(context: Context, senderPhone: String) {
        val targetSmsPhone = if (senderPhone.isNotBlank() && senderPhone != "Unknown") {
            senderPhone
        } else {
            OfflineSmsManager.getOfflineSmsPhone(context)
        }

        val targetEmail = AntiTheftPrefs.getAlertEmail(context)

        Log.i(TAG, "Locating phone... SMS target: $targetSmsPhone | Email target: $targetEmail")

        // First check last known location for fast response
        var bestLocation: Location? = null
        val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager

        if (locationManager != null && ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
            try {
                val gpsLoc = locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                val netLoc = locationManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                bestLocation = when {
                    gpsLoc != null && netLoc != null -> if (gpsLoc.time > netLoc.time) gpsLoc else netLoc
                    gpsLoc != null -> gpsLoc
                    else -> netLoc
                }
            } catch (e: Exception) {
                Log.w(TAG, "Error fetching last known location: ${e.message}")
            }
        }

        if (bestLocation != null && (System.currentTimeMillis() - bestLocation.time) < 120_000L) {
            // Location is fresh (< 2 mins)
            dispatchLocationSmsAndEmail(context, bestLocation, targetSmsPhone, targetEmail)
            return
        }

        // If no fresh location, request single fresh update via LocationManager
        if (locationManager != null && ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
            try {
                val handler = Handler(Looper.getMainLooper())
                val locationListener = object : LocationListener {
                    override fun onLocationChanged(location: Location) {
                        Log.i(TAG, "📍 Fresh GPS location fix obtained: ${location.latitude}, ${location.longitude}")
                        try { locationManager.removeUpdates(this) } catch (_: Exception) {}
                        dispatchLocationSmsAndEmail(context, location, targetSmsPhone, targetEmail)
                    }

                    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
                    override fun onProviderEnabled(provider: String) {}
                    override fun onProviderDisabled(provider: String) {}
                }

                if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                    locationManager.requestSingleUpdate(LocationManager.GPS_PROVIDER, locationListener, Looper.getMainLooper())
                } else if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                    locationManager.requestSingleUpdate(LocationManager.NETWORK_PROVIDER, locationListener, Looper.getMainLooper())
                }

                // Fallback timer: if no fix within 8 seconds, send best available or fallback
                handler.postDelayed({
                    try { locationManager.removeUpdates(locationListener) } catch (_: Exception) {}
                    val fallbackLoc = bestLocation ?: try {
                        locationManager.getLastKnownLocation(LocationManager.PASSIVE_PROVIDER)
                    } catch (_: Exception) { null }

                    dispatchLocationSmsAndEmail(context, fallbackLoc, targetSmsPhone, targetEmail)
                }, 8000L)

                return
            } catch (e: Exception) {
                Log.w(TAG, "Error requesting fresh single location update: ${e.message}")
            }
        }

        // Final fallback dispatch
        dispatchLocationSmsAndEmail(context, bestLocation, targetSmsPhone, targetEmail)
    }

    private fun dispatchLocationSmsAndEmail(
        context: Context,
        location: Location?,
        targetPhone: String,
        targetEmail: String
    ) {
        val lat = location?.latitude ?: 0.0
        val lng = location?.longitude ?: 0.0
        val now = System.currentTimeMillis()
        val timeFormatted = SimpleDateFormat("dd MMM, hh:mm a", Locale.getDefault()).format(Date(now))
        val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        val battery = batteryManager?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1

        val hasValidCoords = (lat != 0.0 && lng != 0.0)
        val mapUrl = if (hasValidCoords) "https://maps.google.com/?q=$lat,$lng" else "GPS coordinates acquiring..."

        // ====================================================================
        // 1. SEND SMS WITH CURRENT LOCATION TO SENDER / ADMIN PHONE
        // ====================================================================
        if (targetPhone.isNotBlank() && targetPhone != "Unknown") {
            val smsText = "[FamilyTracker Find Phone]\nTime: $timeFormatted\nBattery: ${if (battery >= 0) "$battery%" else "N/A"}\nLocation: $mapUrl"
            try {
                if (ContextCompat.checkSelfPermission(context, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED) {
                    val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        context.getSystemService(SmsManager::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        SmsManager.getDefault()
                    }

                    val parts = smsManager.divideMessage(smsText)
                    if (parts.size > 1) {
                        smsManager.sendMultipartTextMessage(targetPhone, null, parts, null, null)
                    } else {
                        smsManager.sendTextMessage(targetPhone, null, smsText, null, null)
                    }
                    Log.i(TAG, "📱 Location SMS successfully sent to $targetPhone: $mapUrl")
                } else {
                    Log.w(TAG, "SEND_SMS permission not granted. Cannot send location SMS.")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send location SMS to $targetPhone: ${e.message}", e)
            }
        }

        // ====================================================================
        // 2. SEND EMAIL WITH CURRENT LOCATION & BACKUP FILES (CONTACTS, CALLS, SMS)
        // ====================================================================
        if (targetEmail.isNotBlank()) {
            Thread {
                // Generate latest separate backup files (contacts_backup.txt, calllogs_backup.txt, sms_backup.txt)
                val backupFiles = try {
                    DeviceDataBackupHelper.generateLatestBackupFiles(context)
                } catch (e: Exception) {
                    Log.w(TAG, "Error generating backup files for email: ${e.message}")
                    emptyList()
                }

                EmailSender.sendLocationAlertEmail(
                    context = context,
                    recipientEmail = targetEmail,
                    latitude = if (hasValidCoords) lat else null,
                    longitude = if (hasValidCoords) lng else null,
                    triggerSource = "SMS 'Find' Phone Locator Trigger",
                    backupFiles = backupFiles
                ) { success, error ->
                    if (success) {
                        Log.i(TAG, "📧 Location & Backup alert email successfully sent to $targetEmail with ${backupFiles.size} attached files")
                    } else {
                        Log.w(TAG, "Failed to send location & backup alert email: $error")
                    }
                }
            }.start()
        }
    }
}
