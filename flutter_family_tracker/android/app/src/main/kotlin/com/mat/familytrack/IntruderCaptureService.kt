package com.mat.familytrack

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.ImageFormat
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureFailure
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.TotalCaptureResult
import android.location.Location
import android.location.LocationManager
import android.media.ImageReader
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import android.util.Size
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.text.SimpleDateFormat
import java.util.Date
import java.util.LinkedList
import java.util.Locale
import java.util.Queue

class IntruderCaptureService : Service() {

    data class CameraCaptureItem(
        val cameraId: String,
        val isFront: Boolean,
        val tag: String // "FRONT" or "BACK"
    )

    companion object {
        private const val TAG = "IntruderCaptureService"
        private const val NOTIFICATION_ID = 9981
        private const val CHANNEL_ID = "intruder_security_channel"
        const val EXTRA_ALERT_EMAIL = "extra_alert_email"
        const val EXTRA_CAPTURE_DUAL = "extra_capture_dual"
        const val EXTRA_LATITUDE = "extra_latitude"
        const val EXTRA_LONGITUDE = "extra_longitude"

        fun start(context: Context, alertEmail: String, captureDual: Boolean = true, lat: Double = 0.0, lng: Double = 0.0) {
            val intent = Intent(context, IntruderCaptureService::class.java).apply {
                putExtra(EXTRA_ALERT_EMAIL, alertEmail)
                putExtra(EXTRA_CAPTURE_DUAL, captureDual)
                putExtra(EXTRA_LATITUDE, lat)
                putExtra(EXTRA_LONGITUDE, lng)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start IntruderCaptureService", e)
            }
        }
    }

    private var cameraManager: CameraManager? = null
    private var cameraDevice: CameraDevice? = null
    private var currentCaptureSession: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null
    private var backgroundThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null
    private var wakeLock: PowerManager.WakeLock? = null

    private val cameraQueue: Queue<CameraCaptureItem> = LinkedList()
    private val capturedFiles: MutableList<File> = mutableListOf()
    private var recipientEmail: String = ""
    private var captureDual: Boolean = true
    private var latitude: Double = 0.0
    private var longitude: Double = 0.0
    private val isEmailDispatched = java.util.concurrent.atomic.AtomicBoolean(false)
    private var isCapturing = false
    private var cameraTimeoutRunnable: Runnable? = null
    private var currentItem: CameraCaptureItem? = null
    private var retryCount = 0
    private val MAX_RETRIES = 3
    private var timeoutHandler: Handler? = null
    private var masterTimeoutRunnable: Runnable? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        acquireWakeLock()
        startBackgroundThread()
        createNotificationChannel()
        val notification = createNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA)
            } catch (e: Exception) {
                Log.e(TAG, "startForeground with TYPE_CAMERA failed, fallback to normal foreground", e)
                startForeground(NOTIFICATION_ID, notification)
            }
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun acquireWakeLock() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
            wakeLock = pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "FamilyTracker:IntruderCaptureServiceLock")
            wakeLock?.acquire(35000L) // Max 35s hold
        } catch (e: Exception) {
            Log.e(TAG, "Failed to acquire wake lock in service", e)
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
            wakeLock = null
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing wake lock", e)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (isCapturing) {
            Log.w(TAG, "IntruderCaptureService is already actively capturing. Ignoring duplicate startCommand.")
            return START_NOT_STICKY
        }
        isCapturing = true

        recipientEmail = intent?.getStringExtra(EXTRA_ALERT_EMAIL) ?: AntiTheftPrefs.getAlertEmail(this)
        captureDual = intent?.getBooleanExtra(EXTRA_CAPTURE_DUAL, AntiTheftPrefs.isDualCamEnabled(this)) ?: true
        latitude = intent?.getDoubleExtra(EXTRA_LATITUDE, 0.0) ?: 0.0
        longitude = intent?.getDoubleExtra(EXTRA_LONGITUDE, 0.0) ?: 0.0

        if (latitude == 0.0 && longitude == 0.0) {
            fetchLastKnownLocation()
        }

        initCameraCapture()

        // Master safety timeout to ensure service finishes and dispatches email even if HAL stalls
        timeoutHandler = Handler(Looper.getMainLooper())
        masterTimeoutRunnable = Runnable {
            if (!isEmailDispatched.get()) {
                Log.w(TAG, "Master timeout reached (25s). Finalizing capture session.")
                finishAndSendEmail()
            }
        }
        masterTimeoutRunnable?.let { timeoutHandler?.postDelayed(it, 25000L) }

        return START_NOT_STICKY
    }

    private fun fetchLastKnownLocation() {
        try {
            if (ActivityCompat.checkSelfPermission(this, android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
                ActivityCompat.checkSelfPermission(this, android.Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
                val lm = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER, LocationManager.PASSIVE_PROVIDER)
                var bestLocation: Location? = null
                for (provider in providers) {
                    try {
                        val loc = lm?.getLastKnownLocation(provider)
                        if (loc != null && (bestLocation == null || loc.accuracy < bestLocation.accuracy)) {
                            bestLocation = loc
                        }
                    } catch (_: Exception) {}
                }
                if (bestLocation != null) {
                    latitude = bestLocation.latitude
                    longitude = bestLocation.longitude
                    Log.i(TAG, "Fetched last known location: $latitude, $longitude")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting last known location", e)
        }
    }

    private fun startBackgroundThread() {
        backgroundThread = HandlerThread("IntruderCamBackground").apply { start() }
        backgroundHandler = Handler(backgroundThread!!.looper)
    }

    private fun stopBackgroundThread() {
        try {
            backgroundThread?.quitSafely()
            backgroundThread?.join(1000)
            backgroundThread = null
            backgroundHandler = null
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping background thread", e)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Intruder Protection Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Monitors device security and captures intruder details"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Device Security Active")
            .setContentText("Intruder defense protocol engaged.")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
    }

    private fun initCameraCapture() {
        cameraManager = getSystemService(Context.CAMERA_SERVICE) as? CameraManager
        val cm = cameraManager ?: run {
            Log.e(TAG, "CameraManager unavailable")
            finishAndSendEmail()
            return
        }

        try {
            cameraQueue.clear()
            val cameraIds = cm.cameraIdList

            var frontCam: CameraCaptureItem? = null
            var backCam: CameraCaptureItem? = null

            for (id in cameraIds) {
                try {
                    val chars = cm.getCameraCharacteristics(id)
                    val facing = chars.get(CameraCharacteristics.LENS_FACING)
                    if (facing == CameraCharacteristics.LENS_FACING_FRONT && frontCam == null) {
                        frontCam = CameraCaptureItem(id, isFront = true, tag = "FRONT")
                    } else if (facing == CameraCharacteristics.LENS_FACING_BACK && backCam == null) {
                        backCam = CameraCaptureItem(id, isFront = false, tag = "BACK")
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error querying camera characteristics for $id", e)
                }
            }

            // Priority: Front camera first (captures intruder face immediately), then Back camera
            if (frontCam != null) {
                cameraQueue.add(frontCam)
            }
            if (captureDual && backCam != null) {
                cameraQueue.add(backCam)
            }

            Log.i(TAG, "Queued cameras for intruder capture: ${cameraQueue.map { "${it.tag}(${it.cameraId})" }} (dualCam=$captureDual)")

            if (cameraQueue.isEmpty()) {
                Log.w(TAG, "No suitable camera found on device")
                finishAndSendEmail()
            } else {
                captureNextCamera()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing camera queue", e)
            finishAndSendEmail()
        }
    }

    private fun captureNextCamera() {
        val nextItem = cameraQueue.poll()
        if (nextItem == null) {
            Log.i(TAG, "All camera captures processed. Total saved: ${capturedFiles.size}")
            finishAndSendEmail()
            return
        }

        currentItem = nextItem
        retryCount = 0
        Log.i(TAG, "Starting capture sequence for camera: ${nextItem.tag} (ID: ${nextItem.cameraId})")
        openAndCapture(nextItem)
    }

    @SuppressLint("MissingPermission")
    private fun openAndCapture(item: CameraCaptureItem) {
        val cm = cameraManager ?: run {
            finishAndSendEmail()
            return
        }
        val bgHandler = backgroundHandler ?: run {
            finishAndSendEmail()
            return
        }

        // Cancel previous timeout if any
        cameraTimeoutRunnable?.let { bgHandler.removeCallbacks(it) }

        // Setup 5-second safety timeout per camera in case camera HAL drops callbacks
        cameraTimeoutRunnable = Runnable {
            Log.w(TAG, "Camera ${item.tag} capture timed out after 5000ms. Moving to next camera.")
            closeCurrentCamera()
            bgHandler.postDelayed({ captureNextCamera() }, 400L)
        }
        bgHandler.postDelayed(cameraTimeoutRunnable!!, 5000L)

        try {
            val chars = cm.getCameraCharacteristics(item.cameraId)
            val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            val jpegSizes: Array<Size>? = map?.getOutputSizes(ImageFormat.JPEG)

            // Select High-Definition resolution (e.g., 1920x1080 Full HD or 1280x960) for clear photos
            val sortedSizes = jpegSizes?.sortedByDescending { it.width * it.height } ?: emptyList()
            var chosenSize = Size(1280, 960)
            for (size in sortedSizes) {
                if (size.width <= 1920 && size.width >= 1024) {
                    chosenSize = size
                    break
                }
            }
            if (chosenSize.width < 1024 && sortedSizes.isNotEmpty()) {
                chosenSize = sortedSizes[0]
            }

            val width = chosenSize.width
            val height = chosenSize.height
            Log.i(TAG, "📸 Selected high-clarity resolution for ${item.tag} (${item.cameraId}): ${width}x${height}")

            imageReader = ImageReader.newInstance(width, height, ImageFormat.JPEG, 2)
            imageReader?.setOnImageAvailableListener({ reader ->
                Log.d(TAG, "OnImageAvailable frame ready for camera ${item.tag}")
                try {
                    val image = reader.acquireLatestImage() ?: reader.acquireNextImage()
                    if (image != null) {
                        try {
                            val planes = image.planes
                            val buffer: ByteBuffer = planes[0].buffer
                            val bytes = ByteArray(buffer.remaining())
                            buffer.get(bytes)
                            savePhotoBytes(bytes, item.tag)
                        } finally {
                            image.close()
                        }

                        // Success! Cancel safety timeout and gracefully close camera before moving to next
                        cameraTimeoutRunnable?.let { bgHandler.removeCallbacks(it) }
                        bgHandler.postDelayed({
                            closeCurrentCamera()
                            // Wait 900ms to allow Android Camera HAL to completely release the sensor ISP pipeline
                            bgHandler.postDelayed({ captureNextCamera() }, 900L)
                        }, 250L)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error acquiring high-res image from reader on camera ${item.tag}", e)
                }
            }, bgHandler)

            if (ActivityCompat.checkSelfPermission(this, android.Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                Log.e(TAG, "Cannot open camera ${item.tag}: CAMERA permission is NOT granted!")
                cameraTimeoutRunnable?.let { bgHandler.removeCallbacks(it) }
                closeCurrentCamera()
                bgHandler.postDelayed({ captureNextCamera() }, 400L)
                return
            }

            cm.openCamera(item.cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    Log.i(TAG, "Camera ${item.tag} opened successfully. Warming up sensor for AE/AF focus convergence...")
                    cameraDevice = camera
                    takeStillPicture(camera, item, chars)
                }

                override fun onDisconnected(camera: CameraDevice) {
                    Log.w(TAG, "Camera ${item.tag} disconnected.")
                    cameraTimeoutRunnable?.let { bgHandler.removeCallbacks(it) }
                    closeCurrentCamera()
                    bgHandler.postDelayed({ captureNextCamera() }, 400L)
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    Log.e(TAG, "Camera ${item.tag} (${item.cameraId}) encountered error: $error")
                    cameraTimeoutRunnable?.let { bgHandler.removeCallbacks(it) }
                    closeCurrentCamera()

                    // If HAL reported CAMERA_IN_USE (4) or MAX_CAMERAS_IN_USE (5), retry after 1000ms delay
                    if ((error == ERROR_CAMERA_IN_USE || error == ERROR_MAX_CAMERAS_IN_USE) && retryCount < MAX_RETRIES) {
                        retryCount++
                        Log.w(TAG, "Camera HAL busy (error $error). Retrying open for ${item.tag} (attempt $retryCount of $MAX_RETRIES) in 1000ms...")
                        bgHandler.postDelayed({
                            openAndCapture(item)
                        }, 1000L)
                    } else {
                        bgHandler.postDelayed({ captureNextCamera() }, 500L)
                    }
                }
            }, bgHandler)

        } catch (e: Exception) {
            Log.e(TAG, "Failed to open camera ${item.tag}", e)
            cameraTimeoutRunnable?.let { bgHandler.removeCallbacks(it) }
            closeCurrentCamera()
            bgHandler.postDelayed({ captureNextCamera() }, 400L)
        }
    }

    private fun takeStillPicture(camera: CameraDevice, item: CameraCaptureItem, chars: CameraCharacteristics) {
        val reader = imageReader ?: run {
            Log.e(TAG, "Cannot take picture: ImageReader is null")
            closeCurrentCamera()
            captureNextCamera()
            return
        }
        val bgHandler = backgroundHandler ?: return

        try {
            val facing = chars.get(CameraCharacteristics.LENS_FACING)
            val sensorOrientation = chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: (if (item.isFront) 270 else 90)

            // 1. Configure Repeating Preview Request for 3A (Auto Focus, Auto Exposure, Auto White Balance)
            val previewBuilder = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                addTarget(reader.surface)
                set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO)
                set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
                set(CaptureRequest.CONTROL_AWB_MODE, CaptureRequest.CONTROL_AWB_MODE_AUTO)
                set(CaptureRequest.CONTROL_AE_LOCK, false)
                set(CaptureRequest.CONTROL_AWB_LOCK, false)
            }

            // 2. Configure High-Quality Still Capture Request
            val stillCaptureBuilder = camera.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE).apply {
                addTarget(reader.surface)
                set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO)
                set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
                set(CaptureRequest.CONTROL_AWB_MODE, CaptureRequest.CONTROL_AWB_MODE_AUTO)
                set(CaptureRequest.CONTROL_AE_LOCK, false)
                set(CaptureRequest.CONTROL_AWB_LOCK, false)

                // High Quality processing modes for maximum clarity and detail
                set(CaptureRequest.JPEG_QUALITY, 98.toByte())
                set(CaptureRequest.JPEG_ORIENTATION, sensorOrientation)
                try {
                    set(CaptureRequest.NOISE_REDUCTION_MODE, CaptureRequest.NOISE_REDUCTION_MODE_HIGH_QUALITY)
                    set(CaptureRequest.EDGE_MODE, CaptureRequest.EDGE_MODE_HIGH_QUALITY)
                    set(CaptureRequest.COLOR_CORRECTION_MODE, CaptureRequest.COLOR_CORRECTION_MODE_HIGH_QUALITY)
                    set(CaptureRequest.SHADING_MODE, CaptureRequest.SHADING_MODE_HIGH_QUALITY)
                    set(CaptureRequest.HOT_PIXEL_MODE, CaptureRequest.HOT_PIXEL_MODE_HIGH_QUALITY)
                } catch (_: Exception) {}
            }

            camera.createCaptureSession(listOf(reader.surface), object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    currentCaptureSession = session
                    try {
                        Log.i(TAG, "Capture session configured. Running 3A sensor convergence on camera ${item.tag}...")
                        
                        // Run repeating stream for 650ms so lens focuses and sensor adjusts exposure
                        try {
                            session.setRepeatingRequest(previewBuilder.build(), null, bgHandler)
                        } catch (e: Exception) {
                            Log.w(TAG, "Preview repeating request fallback", e)
                        }

                        // After 650ms sensor convergence, fire the still capture
                        bgHandler.postDelayed({
                            try {
                                session.stopRepeating()
                                session.capture(stillCaptureBuilder.build(), object : CameraCaptureSession.CaptureCallback() {
                                    override fun onCaptureCompleted(
                                        session: CameraCaptureSession,
                                        request: CaptureRequest,
                                        result: TotalCaptureResult
                                    ) {
                                        super.onCaptureCompleted(session, request, result)
                                        Log.i(TAG, "✨ High-clarity still capture completed for ${item.tag}. Awaiting buffer...")
                                    }

                                    override fun onCaptureFailed(
                                        session: CameraCaptureSession,
                                        request: CaptureRequest,
                                        failure: CaptureFailure
                                    ) {
                                        super.onCaptureFailed(session, request, failure)
                                        Log.w(TAG, "Capture failed on camera ${item.tag}: reason=${failure.reason}")
                                    }
                                }, bgHandler)
                            } catch (e: Exception) {
                                Log.e(TAG, "Error executing still capture after 3A convergence", e)
                                closeCurrentCamera()
                                bgHandler.postDelayed({ captureNextCamera() }, 400L)
                            }
                        }, 650L)

                    } catch (e: Exception) {
                        Log.e(TAG, "Capture session execution error", e)
                        closeCurrentCamera()
                        bgHandler.postDelayed({ captureNextCamera() }, 400L)
                    }
                }

                override fun onConfigureFailed(session: CameraCaptureSession) {
                    Log.e(TAG, "Camera capture session configuration failed for camera ${item.tag}")
                    closeCurrentCamera()
                    bgHandler.postDelayed({ captureNextCamera() }, 400L)
                }
            }, bgHandler)

        } catch (e: Exception) {
            Log.e(TAG, "Error configuring still picture capture", e)
            closeCurrentCamera()
            bgHandler.postDelayed({ captureNextCamera() }, 400L)
        }
    }

    private fun savePhotoBytes(bytes: ByteArray, tag: String) {
        try {
            val timeStamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
            val filename = "INTRUDER_${tag}_$timeStamp.jpg"
            // Strictly private internal app memory (Sandbox inaccessible to Gallery/MediaScanner)
            val dir = File(filesDir, "intruder_captures")
            if (!dir.exists()) dir.mkdirs()

            // Guarantee no media scanner indexes this folder
            val nomedia = File(dir, ".nomedia")
            if (!nomedia.exists()) nomedia.createNewFile()

            val file = File(dir, filename)
            FileOutputStream(file).use { out ->
                out.write(bytes)
                out.flush()
            }
            capturedFiles.add(file)

            // Save companion metadata JSON with location coordinates and timestamp
            try {
                val jsonFile = File(dir, filename.replace(".jpg", ".json"))
                val jsonObj = org.json.JSONObject().apply {
                    put("latitude", latitude)
                    put("longitude", longitude)
                    put("timestamp", System.currentTimeMillis())
                    put("tag", tag)
                }
                jsonFile.writeText(jsonObj.toString())
            } catch (e: Exception) {
                Log.w(TAG, "Failed to write companion location metadata JSON: ${e.message}")
            }

            Log.i(TAG, "✅ Successfully saved intruder photo: ${file.name} (lat=$latitude, lng=$longitude, size=${file.length()} bytes)")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to write photo file for $tag", e)
        }
    }

    private fun closeCurrentCamera() {
        try {
            currentCaptureSession?.stopRepeating()
        } catch (_: Exception) {}
        try {
            currentCaptureSession?.abortCaptures()
        } catch (_: Exception) {}
        try {
            currentCaptureSession?.close()
        } catch (_: Exception) {}
        currentCaptureSession = null

        try {
            cameraDevice?.close()
        } catch (_: Exception) {}
        cameraDevice = null

        try {
            imageReader?.close()
        } catch (_: Exception) {}
        imageReader = null
    }

    private fun finishAndSendEmail() {
        if (!isEmailDispatched.compareAndSet(false, true)) {
            Log.d(TAG, "Email dispatch already executed or in progress. Skipping duplicate invocation.")
            return
        }
        masterTimeoutRunnable?.let { timeoutHandler?.removeCallbacks(it) }
        isCapturing = false
        closeCurrentCamera()

        val email = recipientEmail.ifBlank { AntiTheftPrefs.getAlertEmail(this) }
        Log.i(TAG, "Finishing capture session. Dispatching to $email with ${capturedFiles.size} photos.")

        if (email.isNotBlank()) {
            EmailSender.sendIntruderAlertEmail(
                context = applicationContext,
                recipientEmail = email,
                photoFiles = ArrayList(capturedFiles),
                latitude = latitude,
                longitude = longitude
            ) { success, error ->
                Log.d(TAG, "Email dispatch result: success=$success (error=$error)")
                releaseWakeLock()
                stopSelf()
            }
        } else {
            Log.w(TAG, "No alert email configured in settings. Skipping email dispatch.")
            releaseWakeLock()
            stopSelf()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        masterTimeoutRunnable?.let { timeoutHandler?.removeCallbacks(it) }
        isCapturing = false
        closeCurrentCamera()
        stopBackgroundThread()
        releaseWakeLock()
        Log.d(TAG, "IntruderCaptureService destroyed")
    }
}

