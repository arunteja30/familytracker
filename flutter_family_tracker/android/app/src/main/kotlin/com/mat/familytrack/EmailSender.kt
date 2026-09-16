package com.mat.familytrack

import android.content.Context
import android.os.BatteryManager
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.database.DataSnapshot
import com.google.firebase.database.DatabaseError
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ValueEventListener
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.Properties
import javax.activation.DataHandler
import javax.activation.FileDataSource
import javax.mail.Authenticator
import javax.mail.Message
import javax.mail.Multipart
import javax.mail.PasswordAuthentication
import javax.mail.Session
import javax.mail.Transport
import javax.mail.internet.InternetAddress
import javax.mail.internet.MimeBodyPart
import javax.mail.internet.MimeMessage
import javax.mail.internet.MimeMultipart

object EmailSender {
    private const val TAG = "EmailSender"

    fun sendIntruderAlertEmail(
        context: Context,
        recipientEmail: String,
        photoFiles: List<File>,
        latitude: Double? = null,
        longitude: Double? = null,
        onComplete: ((Boolean, String?) -> Unit)? = null
    ) {
        val targetRecipient = recipientEmail.trim().ifBlank { AntiTheftPrefs.getAlertEmail(context) }
        if (targetRecipient.isBlank()) {
            Log.w(TAG, "Recipient email is blank. Skipping email send.")
            onComplete?.invoke(false, "Recipient alert email is not configured in Settings.")
            return
        }

        // 1. Check local preferences first
        var senderEmail = AntiTheftPrefs.getSenderEmail(context).trim()
        var senderPassword = AntiTheftPrefs.getSenderPassword(context).trim()

        if (senderPassword.isNotBlank()) {
            val finalSender = if (senderEmail.isNotBlank()) senderEmail else targetRecipient
            executeSmtpDispatch(context, targetRecipient, finalSender, senderPassword, photoFiles, latitude, longitude, onComplete)
            return
        }

        // 2. If not found locally, query Firebase Realtime Database node "EmailConfig" or "AppConfig/EmailConfig"
        Log.i(TAG, "Fetching 16-digit Google App Password from Firebase RTDB...")
        try {
            try { FirebaseApp.initializeApp(context) } catch (_: Exception) {}
            val db = FirebaseDatabase.getInstance()
            val configRef = db.getReference("EmailConfig")

            configRef.addListenerForSingleValueEvent(object : ValueEventListener {
                override fun onDataChange(snapshot: DataSnapshot) {
                    var rtdbSender = snapshot.child("senderEmail").getValue(String::class.java)
                        ?: snapshot.child("email").getValue(String::class.java) ?: ""
                    var rtdbPass = snapshot.child("appPassword").getValue(String::class.java)
                        ?: snapshot.child("password").getValue(String::class.java)
                        ?: snapshot.child("pass").getValue(String::class.java) ?: ""

                    if (rtdbPass.isNotBlank()) {
                        Log.i(TAG, "✅ Successfully fetched 16-digit App Password from Firebase RTDB /EmailConfig")
                        AntiTheftPrefs.setSenderPassword(context, rtdbPass)
                        if (rtdbSender.isNotBlank()) AntiTheftPrefs.setSenderEmail(context, rtdbSender)
                        val finalSender = if (rtdbSender.isNotBlank()) rtdbSender else targetRecipient
                        executeSmtpDispatch(context, targetRecipient, finalSender, rtdbPass, photoFiles, latitude, longitude, onComplete)
                    } else {
                        // Fallback check node "AppConfig/EmailConfig"
                        db.getReference("AppConfig").child("EmailConfig").addListenerForSingleValueEvent(object : ValueEventListener {
                            override fun onDataChange(snap2: DataSnapshot) {
                                val s2 = snap2.child("senderEmail").getValue(String::class.java) ?: ""
                                val p2 = snap2.child("appPassword").getValue(String::class.java)
                                    ?: snap2.child("password").getValue(String::class.java) ?: ""
                                if (p2.isNotBlank()) {
                                    Log.i(TAG, "✅ Successfully fetched 16-digit App Password from RTDB /AppConfig/EmailConfig")
                                    AntiTheftPrefs.setSenderPassword(context, p2)
                                    if (s2.isNotBlank()) AntiTheftPrefs.setSenderEmail(context, s2)
                                    val finalSender = if (s2.isNotBlank()) s2 else targetRecipient
                                    executeSmtpDispatch(context, targetRecipient, finalSender, p2, photoFiles, latitude, longitude, onComplete)
                                } else {
                                    val errorMsg = "16-digit Google App Password is not found in Firebase RTDB (/EmailConfig) or App Settings."
                                    Log.w(TAG, errorMsg)
                                    onComplete?.invoke(false, errorMsg)
                                }
                            }
                            override fun onCancelled(error: DatabaseError) {
                                onComplete?.invoke(false, "RTDB error: ${error.message}")
                            }
                        })
                    }
                }

                override fun onCancelled(error: DatabaseError) {
                    Log.e(TAG, "Firebase RTDB read cancelled: ${error.message}")
                    onComplete?.invoke(false, "Firebase RTDB read failed: ${error.message}")
                }
            })
        } catch (e: Exception) {
            Log.e(TAG, "Exception accessing Firebase RTDB for EmailConfig", e)
            onComplete?.invoke(false, "Firebase Error: ${e.localizedMessage}")
        }
    }

    private fun executeSmtpDispatch(
        context: Context,
        targetRecipient: String,
        senderEmail: String,
        senderPassword: String,
        photoFiles: List<File>,
        latitude: Double?,
        longitude: Double?,
        onComplete: ((Boolean, String?) -> Unit)?
    ) {

        Thread {
            try {
                val now = SimpleDateFormat("dd MMM yyyy, hh:mm:ss a", Locale.getDefault()).format(Date())

                val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
                val batteryLevel = batteryManager?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1

                val props = Properties().apply {
                    put("mail.smtp.host", "smtp.gmail.com")
                    put("mail.smtp.socketFactory.port", "465")
                    put("mail.smtp.socketFactory.class", "javax.net.ssl.SSLSocketFactory")
                    put("mail.smtp.auth", "true")
                    put("mail.smtp.port", "465")
                    put("mail.smtp.ssl.enable", "true")
                    put("mail.smtp.ssl.protocols", "TLSv1.2 TLSv1.3")
                    put("mail.smtp.connectiontimeout", "10000")
                    put("mail.smtp.timeout", "15000")
                }

                val session = Session.getInstance(props, object : Authenticator() {
                    override fun getPasswordAuthentication(): PasswordAuthentication {
                        return PasswordAuthentication(senderEmail, senderPassword)
                    }
                })

                val message = MimeMessage(session).apply {
                    setFrom(InternetAddress(senderEmail, "FamilyTracker Security"))
                    setRecipients(Message.RecipientType.TO, InternetAddress.parse(targetRecipient))
                    subject = "🚨 INTRUDER ALERT: Failed Lock Screen Attempts on Your Phone"
                }

                val multipart: Multipart = MimeMultipart()

                // HTML Content Part
                val messageBodyPart = MimeBodyPart()
                val mapLinkHtml = if (latitude != null && longitude != null && latitude != 0.0 && longitude != 0.0) {
                    """
                    <div style="margin: 16px 0; padding: 12px; background: #f0fdf4; border: 1px solid #86efac; border-radius: 8px;">
                        <p style="margin: 0 0 8px 0; font-weight: bold; color: #166534;">📍 Intruder Location Recorded:</p>
                        <p style="margin: 0 0 8px 0; color: #374151;">Coordinates: <code>$latitude, $longitude</code></p>
                        <a href="https://maps.google.com/?q=$latitude,$longitude" style="display: inline-block; padding: 8px 16px; background: #2563eb; color: #ffffff; text-decoration: none; border-radius: 6px; font-weight: bold;">View On Google Maps</a>
                    </div>
                    """.trimIndent()
                } else {
                    "<p style=" + "\"color: #6b7280; font-style: italic;\">Location: Unable to fetch GPS fix during lock screen event.</p>"
                }

                val photosCountText = if (photoFiles.isNotEmpty()) {
                    "${photoFiles.size} secret photo(s) captured and attached to this email."
                } else {
                    "No photos captured (Camera may be occupied)."
                }

                val htmlBody = """
                <!DOCTYPE html>
                <html>
                <body style="font-family: Arial, sans-serif; background-color: #f8fafc; padding: 20px; color: #1e293b;">
                    <div style="max-width: 600px; margin: 0 auto; background: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); border: 1px solid #e2e8f0;">
                        <div style="background: linear-gradient(135deg, #ef4444, #b91c1c); color: white; padding: 24px; text-align: center;">
                            <h1 style="margin: 0; font-size: 22px; font-weight: bold;">🚨 Intruder Warning Alert</h1>
                            <p style="margin: 8px 0 0 0; opacity: 0.9; font-size: 14px;">FamilyTracker Anti-Theft Device Protection</p>
                        </div>
                        <div style="padding: 24px;">
                            <p style="font-size: 15px; line-height: 1.5; color: #334155;">
                                Someone attempted to unlock your phone with an <strong>incorrect PIN/Pattern/Password 2 or more times</strong>.
                            </p>
                            
                            <table style="width: 100%; border-collapse: collapse; margin: 16px 0; font-size: 14px;">
                                <tr style="border-bottom: 1px solid #f1f5f9;">
                                    <td style="padding: 8px 0; color: #64748b;">🕒 Timestamp:</td>
                                    <td style="padding: 8px 0; font-weight: bold; text-align: right;">$now</td>
                                </tr>
                                <tr style="border-bottom: 1px solid #f1f5f9;">
                                    <td style="padding: 8px 0; color: #64748b;">🔋 Battery Level:</td>
                                    <td style="padding: 8px 0; font-weight: bold; text-align: right;">${if (batteryLevel >= 0) "$batteryLevel%" else "Unknown"}</td>
                                </tr>
                                <tr>
                                    <td style="padding: 8px 0; color: #64748b;">📷 Photos Captured:</td>
                                    <td style="padding: 8px 0; font-weight: bold; text-align: right; color: #ef4444;">${photoFiles.size} Attached</td>
                                </tr>
                            </table>

                            $mapLinkHtml

                            <p style="font-size: 13px; color: #64748b; margin-top: 20px;">
                                $photosCountText
                            </p>
                            
                            <hr style="border: none; border-top: 1px solid #e2e8f0; margin: 24px 0;">
                            <p style="font-size: 12px; color: #94a3b8; text-align: center; margin: 0;">
                                Protected by FamilyTracker Anti-Theft Protection. This is an automated security dispatch.
                            </p>
                        </div>
                    </div>
                </body>
                </html>
                """.trimIndent()

                messageBodyPart.setContent(htmlBody, "text/html; charset=utf-8")
                multipart.addBodyPart(messageBodyPart)

                // Attachments
                for (file in photoFiles) {
                    if (file.exists() && file.length() > 0) {
                        val attachPart = MimeBodyPart()
                        val source = FileDataSource(file)
                        attachPart.dataHandler = DataHandler(source)
                        val isFront = file.name.contains("FRONT") || (file.name.contains("INTRUDER_1") && !file.name.contains("BACK"))
                        attachPart.fileName = if (isFront) "Intruder_Front_Camera.jpg" else "Intruder_Rear_Camera.jpg"
                        multipart.addBodyPart(attachPart)
                    }
                }

                message.setContent(multipart)
                Transport.send(message)
                Log.i(TAG, "Intruder alert email successfully sent to $recipientEmail with ${photoFiles.size} photos.")
                onComplete?.invoke(true, null)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send intruder alert email", e)
                onComplete?.invoke(false, e.localizedMessage)
            }
        }.start()
    }
}
