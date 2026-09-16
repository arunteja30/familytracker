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
    private var imageReader: ImageReader? = null
    private var backgroundThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null
    private var wakeLock: PowerManager.WakeLock? = null

    private val cameraQueue: Queue<String> = LinkedList()
    private val capturedFiles: MutableList<File> = mutableListOf()
    private var recipientEmail: String = ""
    private var captureDual: Boolean = true
    private var latitude: Double = 0.0
    private var longitude: Double = 0.0
    private var isCapturing = false
    private var cameraTimeoutRunnable: Runnable? = null
    private var isCameraClosing = false

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
            wakeLock?.acquire(25000L) // Max 25s hold
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
        recipientEmail = intent?.getStringExtra(EXTRA_ALERT_EMAIL) ?: AntiTheftPrefs.getAlertEmail(this)
        captureDual = intent?.getBooleanExtra(EXTRA_CAPTURE_DUAL, AntiTheftPrefs.isDualCamEnabled(this)) ?: true
        latitude = intent?.getDoubleExtra(EXTRA_LATITUDE, 0.0) ?: 0.0
        longitude = intent?.getDoubleExtra(EXTRA_LONGITUDE, 0.0) ?: 0.0

        // If coordinates not supplied, attempt to fetch last known location from GPS / Network
        if (latitude == 0.0 && longitude == 0.0) {
            fetchLastKnownLocation()
        }

        if (!isCapturing) {
            isCapturing = true
            initCameraCapture()
        }

        // Master safety timeout to ensure service finishes and dispatches email even if HAL stalls
        Handler(Looper.getMainLooper()).postDelayed({
            if (isCapturing) {
                Log.w(TAG, "Master timeout reached. Finalizing capture session.")
                finishAndSendEmail()
            }
        }, 15000L)

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

            var frontCamId: String? = null
            var backCamId: String? = null

            for (id in cameraIds) {
                val chars = cm.getCameraCharacteristics(id)
                val facing = chars.get(CameraCharacteristics.LENS_FACING)
                if (facing == CameraCharacteristics.LENS_FACING_FRONT && frontCamId == null) {
                    frontCamId = id
                } else if (facing == CameraCharacteristics.LENS_FACING_BACK && backCamId == null) {
                    backCamId = id
                }
            }

            // Priority: Front camera first (captures intruder face), then Back camera
            if (frontCamId != null) {
                cameraQueue.add(frontCamId)
            }
            if (captureDual && backCamId != null && backCamId != frontCamId) {
                cameraQueue.add(backCamId)
            }

            Log.i(TAG, "Queued cameras for intruder capture: ${cameraQueue.toList()}")

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
        val nextCamId = cameraQueue.poll()
        if (nextCamId == null) {
            // All queued cameras have finished capturing
            Log.i(TAG, "All camera captures processed. Total saved: ${capturedFiles.size}")
            finishAndSendEmail()
            return
        }

        Log.i(TAG, "Starting capture sequence for camera: $nextCamId")
        openAndCapture(nextCamId)
    }

    @SuppressLint("MissingPermission")
    private fun openAndCapture(cameraId: String) {
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

        // Setup 4-second safety timeout per camera in case camera HAL drops callbacks
        cameraTimeoutRunnable = Runnable {
            Log.w(TAG, "Camera $cameraId capture timed out after 4000ms. Moving to next camera.")
            closeCurrentCamera()
            bgHandler.postDelayed({ captureNextCamera() }, 300L)
        }
        bgHandler.postDelayed(cameraTimeoutRunnable!!, 4000L)

        try {
            val chars = cm.getCameraCharacteristics(cameraId)
            val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            val jpegSizes: Array<Size>? = map?.getOutputSizes(ImageFormat.JPEG)

            // Select an optimal image resolution (<= 1280 wide to ensure fast processing and avoid OOM)
            var chosenSize = Size(640, 480)
            if (!jpegSizes.isNullOrEmpty()) {
                val candidate = jpegSizes.firstOrNull { it.width <= 1280 && it.width >= 480 }
                chosenSize = candidate ?: jpegSizes[0]
            }

            val width = chosenSize.width
            val height = chosenSize.height
            Log.d(TAG, "Configuring ImageReader for camera $cameraId with resolution: ${width}x${height}")

            imageReader = ImageReader.newInstance(width, height, ImageFormat.JPEG, 2)
            imageReader?.setOnImageAvailableListener({ reader ->
                Log.d(TAG, "OnImageAvailable triggered for camera $cameraId")
                try {
                    val image = reader.acquireLatestImage() ?: reader.acquireNextImage()
                    if (image != null) {
                        try {
                            val planes = image.planes
                            val buffer: ByteBuffer = planes[0].buffer
                            val bytes = ByteArray(buffer.remaining())
                            buffer.get(bytes)
                            savePhotoBytes(bytes, cameraId)
                        } finally {
                            image.close()
                        }

                        // Success! Cancel safety timeout and gracefully close camera before moving to next
                        cameraTimeoutRunnable?.let { bgHandler.removeCallbacks(it) }
                        bgHandler.postDelayed({
                            closeCurrentCamera()
                            bgHandler.postDelayed({ captureNextCamera() }, 300L)
                        }, 200L)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error acquiring image from reader on camera $cameraId", e)
                }
            }, bgHandler)

            cm.openCamera(cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    Log.i(TAG, "Camera $cameraId opened successfully. Waiting 500ms for sensor warm-up.")
                    cameraDevice = camera
                    isCameraClosing = false
                    // Sensor warm-up delay (500ms) matches native reference to avoid black frames or AE crash
                    bgHandler.postDelayed({
                        takeStillPicture(camera, cameraId, chars)
                    }, 500L)
                }

                override fun onDisconnected(camera: CameraDevice) {
                    Log.w(TAG, "Camera $cameraId disconnected.")
                    cameraTimeoutRunnable?.let { bgHandler.removeCallbacks(it) }
                    closeCurrentCamera()
                    bgHandler.postDelayed({ captureNextCamera() }, 300L)
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    Log.e(TAG, "Camera $cameraId encountered error: $error")
                    cameraTimeoutRunnable?.let { bgHandler.removeCallbacks(it) }
                    closeCurrentCamera()
                    bgHandler.postDelayed({ captureNextCamera() }, 300L)
                }
            }, bgHandler)

        } catch (e: Exception) {
            Log.e(TAG, "Failed to open camera $cameraId", e)
            cameraTimeoutRunnable?.let { bgHandler.removeCallbacks(it) }
            closeCurrentCamera()
            bgHandler.postDelayed({ captureNextCamera() }, 300L)
        }
    }

    private fun takeStillPicture(camera: CameraDevice, cameraId: String, chars: CameraCharacteristics) {
        val reader = imageReader ?: run {
            Log.e(TAG, "Cannot take picture: ImageReader is null")
            closeCurrentCamera()
            captureNextCamera()
            return
        }
        val bgHandler = backgroundHandler ?: return

        try {
            val facing = chars.get(CameraCharacteristics.LENS_FACING)
            val captureBuilder = camera.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE).apply {
                addTarget(reader.surface)
                set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO)
                set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
                set(CaptureRequest.CONTROL_AE_LOCK, false)

                // Set orientation: Front = 270, Back = 90 (matches native reference)
                val orientation = if (facing == CameraCharacteristics.LENS_FACING_FRONT) 270 else 90
                set(CaptureRequest.JPEG_ORIENTATION, orientation)
            }

            camera.createCaptureSession(listOf(reader.surface), object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    try {
                        Log.i(TAG, "Capture session configured for camera $cameraId. Dispatching still capture request.")
                        session.capture(captureBuilder.build(), object : CameraCaptureSession.CaptureCallback() {
                            override fun onCaptureCompleted(
                                session: CameraCaptureSession,
                                request: CaptureRequest,
                                result: TotalCaptureResult
                            ) {
                                super.onCaptureCompleted(session, request, result)
                                Log.i(TAG, "Hardware still capture completed for camera $cameraId. Awaiting ImageReader frame...")
                                // Note: Camera is NOT closed here. It is closed in OnImageAvailableListener when bytes are written!
                            }

                            override fun onCaptureFailed(
                                session: CameraCaptureSession,
                                request: CaptureRequest,
                                failure: CaptureFailure
                            ) {
                                super.onCaptureFailed(session, request, failure)
                                Log.w(TAG, "Hardware capture failed for camera $cameraId: reason=${failure.reason}")
                            }
                        }, bgHandler)
                    } catch (e: Exception) {
                        Log.e(TAG, "Capture session execution error", e)
                    }
                }

                override fun onConfigureFailed(session: CameraCaptureSession) {
                    Log.e(TAG, "Camera capture session configuration failed for camera $cameraId")
                    closeCurrentCamera()
                    bgHandler.postDelayed({ captureNextCamera() }, 300L)
                }
            }, bgHandler)

        } catch (e: Exception) {
            Log.e(TAG, "Error configuring still picture capture", e)
            closeCurrentCamera()
            bgHandler.postDelayed({ captureNextCamera() }, 300L)
        }
    }

    private fun savePhotoBytes(bytes: ByteArray, cameraId: String) {
        try {
            val timeStamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
            val filename = "INTRUDER_${cameraId}_$timeStamp.jpg"
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
            Log.i(TAG, "✅ Successfully saved intruder photo: ${file.absolutePath} (${file.length()} bytes)")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to write photo file", e)
        }
    }

    private fun closeCurrentCamera() {
        if (isCameraClosing) return
        isCameraClosing = true
        try {
            cameraDevice?.close()
            cameraDevice = null
        } catch (e: Exception) {
            Log.e(TAG, "Error closing cameraDevice", e)
        }
        try {
            imageReader?.close()
            imageReader = null
        } catch (e: Exception) {
            Log.e(TAG, "Error closing imageReader", e)
        }
    }

    private fun finishAndSendEmail() {
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
        isCapturing = false
        closeCurrentCamera()
        stopBackgroundThread()
        releaseWakeLock()
        Log.d(TAG, "IntruderCaptureService destroyed")
    }
}

