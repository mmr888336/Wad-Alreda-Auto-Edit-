package com.omer.filament_renderer

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.Choreographer
import android.view.Gravity
import android.view.PixelCopy
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import com.google.android.filament.Engine
import com.google.android.filament.gltfio.Animator
import com.google.android.filament.utils.Manipulator
import com.google.android.filament.utils.ModelViewer
import com.google.android.filament.utils.Utils
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.cos
import kotlin.math.sin

/** Native Filament preview, dynamic GLB loading, animation and camera bridge. */
class FilamentRendererPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    companion object {
        private const val CHANNEL_NAME = "com.omer.filament_renderer/methods"
        private const val VIEW_TYPE = "com.omer.filament_renderer/model_view"
        private const val FILAMENT_VERSION = "1.56.0"
    }

    private var channel: MethodChannel? = null
    private var diagnosticEngine: Engine? = null
    private val engineLock = Any()
    private val viewLock = Any()
    private val modelViews = HashMap<Int, FilamentModelPlatformView>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
        binding.platformViewRegistry.registerViewFactory(
            VIEW_TYPE,
            FilamentModelViewFactory(
                onCreated = { id, view -> synchronized(viewLock) { modelViews[id] = view } },
                onDisposed = { id -> synchronized(viewLock) { modelViews.remove(id) } }
            )
        )
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initializeEngine(result)
            "isInitialized" -> result.success(isEngineInitialized())
            "getNativeVersion" -> result.success(FILAMENT_VERSION)
            "dispose" -> disposeEngine(result)
            "getViewDiagnostics" -> {
                val id = call.argument<Int>("viewId")
                val view = id?.let { synchronized(viewLock) { modelViews[it] } }
                if (view == null) {
                    result.error("FILAMENT_VIEW_NOT_FOUND", "The 3D preview is not attached.", null)
                } else result.success(view.diagnostics())
            }
            "loadModelFromFile" -> {
                val id = call.argument<Int>("viewId")
                val path = call.argument<String>("filePath")
                val view = id?.let { synchronized(viewLock) { modelViews[it] } }
                if (view == null) {
                    result.error("FILAMENT_VIEW_NOT_FOUND", "The 3D preview is not attached.", null)
                } else if (path.isNullOrBlank()) {
                    result.error("FILAMENT_MODEL_PATH", "A local GLB file path is required.", null)
                } else view.loadModelFromFile(path, result)
            }
            "setCameraMotion" -> {
                val id = call.argument<Int>("viewId")
                val mode = call.argument<String>("mode") ?: "manual"
                val view = id?.let { synchronized(viewLock) { modelViews[it] } }
                if (view == null) {
                    result.error("FILAMENT_VIEW_NOT_FOUND", "The 3D preview is not attached.", null)
                } else {
                    try {
                        view.setCameraMotion(mode)
                        result.success(null)
                    } catch (error: Throwable) {
                        result.error("FILAMENT_CAMERA_MODE", error.message ?: "Invalid camera mode.", null)
                    }
                }
            }
            "captureFrames" -> {
                val id = call.argument<Int>("viewId")
                val duration = call.argument<Double>("durationSeconds") ?: 3.0
                val fps = call.argument<Int>("frameRate") ?: 24
                val view = id?.let { synchronized(viewLock) { modelViews[it] } }
                if (view == null) {
                    result.error("FILAMENT_VIEW_NOT_FOUND", "The 3D preview is not attached.", null)
                } else view.captureFrames(duration, fps, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun initializeEngine(result: MethodChannel.Result) {
        try {
            synchronized(engineLock) {
                if (diagnosticEngine == null) diagnosticEngine = Engine.create()
            }
            result.success(true)
        } catch (error: Throwable) {
            result.error("FILAMENT_ENGINE_INIT_FAILED", error.message ?: error.javaClass.simpleName, null)
        }
    }

    private fun isEngineInitialized(): Boolean {
        synchronized(engineLock) { return diagnosticEngine != null }
    }

    private fun disposeEngine(result: MethodChannel.Result) {
        try {
            synchronized(engineLock) {
                diagnosticEngine?.destroy()
                diagnosticEngine = null
            }
            result.success(null)
        } catch (error: Throwable) {
            result.error("FILAMENT_ENGINE_DISPOSE_FAILED", error.message ?: error.javaClass.simpleName, null)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        val views = synchronized(viewLock) {
            val copy = modelViews.values.toList()
            modelViews.clear()
            copy
        }
        views.forEach { try { it.dispose() } catch (_: Throwable) {} }
        try {
            synchronized(engineLock) {
                diagnosticEngine?.destroy()
                diagnosticEngine = null
            }
        } catch (_: Throwable) {}
    }
}

private class FilamentModelViewFactory(
    private val onCreated: (Int, FilamentModelPlatformView) -> Unit,
    private val onDisposed: (Int) -> Unit
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val renderer = FilamentModelPlatformView(context)
        onCreated(viewId, renderer)
        return object : PlatformView {
            override fun getView(): View = renderer.getView()
            override fun dispose() {
                renderer.dispose()
                onDisposed(viewId)
            }
        }
    }
}

private class FilamentModelPlatformView(
    private val appContext: Context
) : PlatformView {
    private val root = FrameLayout(appContext)
    private val surfaceView = SurfaceView(appContext)
    private val choreographer = Choreographer.getInstance()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor = Executors.newSingleThreadExecutor()

    private val cameraManipulator: Manipulator = Manipulator.Builder()
        .targetPosition(0.0f, 0.0f, -4.0f)
        .orbitHomePosition(0.0f, 0.0f, 1.0f)
        .viewport(1, 1)
        .build(Manipulator.Mode.ORBIT)

    private var modelViewer: ModelViewer? = null
    private var surfaceReady = false
    private var modelLoaded = false
    private var framesRendered = 0L
    private var lastError: String? = null
    private var disposed = false
    private var frameScheduled = false
    private var captureInProgress = false
    private var captureGeneration = 0
    private var activeModelPath: String? = null
    private var cameraMode = "orbit"
    private var cameraGestureStarted = false
    private var cameraGestureStrafe = false
    private var cameraElapsed = 0.0
    private var lastFrameTimeNanos = 0L
    private var cameraBaseX = 0
    private var cameraBaseY = 0

    private val holderCallback = object : SurfaceHolder.Callback {
        override fun surfaceCreated(holder: SurfaceHolder) {
            surfaceReady = holder.surface.isValid
            scheduleFrame()
        }

        override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            surfaceReady = holder.surface.isValid && width > 0 && height > 0
            cameraManipulator.setViewport(width.coerceAtLeast(1), height.coerceAtLeast(1))
            scheduleFrame()
        }

        override fun surfaceDestroyed(holder: SurfaceHolder) {
            surfaceReady = false
            frameScheduled = false
            choreographer.removeFrameCallback(frameCallback)
        }
    }

    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            frameScheduled = false
            if (disposed) return
            val viewer = modelViewer
            if (viewer != null && surfaceReady && surfaceView.holder.surface.isValid) {
                try {
                    updateCamera(frameTimeNanos)
                    updateModelAnimation(viewer)
                    viewer.render(frameTimeNanos)
                    framesRendered++
                } catch (error: Throwable) {
                    showError(error)
                    return
                }
            }
            scheduleFrame()
        }
    }

    init {
        root.setBackgroundColor(Color.rgb(13, 16, 25))
        surfaceView.setBackgroundColor(Color.rgb(13, 16, 25))
        try {
            Utils.init()
            modelViewer = ModelViewer(surfaceView, manipulator = cameraManipulator)
            val initial = readBundledModel(appContext)
            modelViewer?.loadModelGlb(initial)
            modelViewer?.transformToUnitCube()
            modelLoaded = true
            activeModelPath = "bundled:filament_sample.glb"
            lastError = null
            surfaceView.setOnTouchListener { _, event ->
                // Manual touch always takes control from the scripted camera.
                cameraMode = "manual"
                endCameraGesture()
                modelViewer?.onTouchEvent(event)
                true
            }
        } catch (error: Throwable) {
            lastError = error.javaClass.simpleName + ": " + (error.message ?: "Unknown error")
        }

        // Register before attaching to the root so surfaceCreated is not missed.
        surfaceView.holder.addCallback(holderCallback)
        root.addView(
            surfaceView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )
        if (lastError != null) showError(IllegalStateException(lastError))
    }

    private fun readBundledModel(context: Context): ByteBuffer {
        val bytes = context.assets.open("models/filament_sample.glb").use { it.readBytes() }
        return toGlbBuffer(bytes, "Bundled GLB")
    }

    private fun toGlbBuffer(bytes: ByteArray, label: String): ByteBuffer {
        if (bytes.size < 20 ||
            bytes[0] != 0x67.toByte() || bytes[1] != 0x6c.toByte() ||
            bytes[2] != 0x54.toByte() || bytes[3] != 0x46.toByte()
        ) throw IllegalStateException("$label is not a GLB v2 file.")
        val header = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        header.position(4)
        val version = header.int
        val declaredLength = header.int
        if (version != 2 || declaredLength != bytes.size) {
            throw IllegalStateException("Invalid $label header: version=$version, declared=$declaredLength, actual=${bytes.size}")
        }
        return ByteBuffer.allocateDirect(bytes.size)
            .order(ByteOrder.nativeOrder())
            .apply { put(bytes); flip() }
    }

    fun loadModelFromFile(path: String, result: MethodChannel.Result) {
        if (disposed) {
            result.error("FILAMENT_VIEW_DISPOSED", "The 3D preview is closed.", null)
            return
        }
        ioExecutor.execute {
            try {
                val file = File(path)
                if (!file.isFile || !file.canRead()) throw IllegalStateException("GLB file cannot be read.")
                if (file.length() > 80L * 1024L * 1024L) throw IllegalStateException("GLB exceeds the 80 MB safety limit.")
                val bytes = file.readBytes()
                val buffer = toGlbBuffer(bytes, "Downloaded model")
                mainHandler.post {
                    if (disposed) {
                        result.error("FILAMENT_VIEW_DISPOSED", "The 3D preview closed while loading.", null)
                        return@post
                    }
                    try {
                        val viewer = modelViewer ?: throw IllegalStateException("Filament viewer is unavailable.")
                        viewer.loadModelGlb(buffer)
                        if (viewer.asset == null) throw IllegalStateException("Filament could not parse this GLB asset.")
                        viewer.transformToUnitCube()
                        modelLoaded = true
                        activeModelPath = file.absolutePath
                        lastError = null
                        cameraElapsed = 0.0
                        endCameraGesture()
                        scheduleFrame()
                        result.success(true)
                    } catch (error: Throwable) {
                        modelLoaded = false
                        lastError = error.javaClass.simpleName + ": " + (error.message ?: "Model load failed")
                        result.error("FILAMENT_MODEL_LOAD", lastError ?: "Model load failed.", diagnostics())
                    }
                }
            } catch (error: Throwable) {
                mainHandler.post {
                    lastError = error.javaClass.simpleName + ": " + (error.message ?: "Model download failed")
                    result.error("FILAMENT_MODEL_FILE", lastError ?: "Model file load failed.", diagnostics())
                }
            }
        }
    }

    fun setCameraMotion(mode: String) {
        val allowed = setOf("manual", "orbit", "orbit_fast", "push_in", "pull_out", "follow")
        if (mode !in allowed) throw IllegalArgumentException("Unsupported camera mode: $mode")
        endCameraGesture()
        cameraMode = mode
        cameraElapsed = 0.0
        lastFrameTimeNanos = 0L
        cameraBaseX = (surfaceView.width / 2).coerceAtLeast(1)
        cameraBaseY = (surfaceView.height / 2).coerceAtLeast(1)
    }

    private fun endCameraGesture() {
        if (cameraGestureStarted) {
            try { cameraManipulator.grabEnd() } catch (_: Throwable) {}
        }
        cameraGestureStarted = false
    }

    private fun updateCamera(frameTimeNanos: Long) {
        val dt = if (lastFrameTimeNanos == 0L) 1.0 / 60.0
            else ((frameTimeNanos - lastFrameTimeNanos).toDouble() / 1_000_000_000.0).coerceIn(0.001, 0.05)
        lastFrameTimeNanos = frameTimeNanos
        cameraElapsed += dt

        val width = surfaceView.width.coerceAtLeast(2)
        val height = surfaceView.height.coerceAtLeast(2)
        val centerX = width / 2
        val centerY = height / 2
        if (cameraMode != "manual") {
            when (cameraMode) {
                "orbit", "orbit_fast" -> {
                    if (!cameraGestureStarted) {
                        cameraManipulator.grabBegin(centerX, centerY, false)
                        cameraGestureStarted = true
                        cameraGestureStrafe = false
                    }
                    val pixelsPerSecond = if (cameraMode == "orbit_fast") 88.0 else 42.0
                    val x = centerX + (cameraElapsed * pixelsPerSecond).toInt()
                    val y = centerY + (sin(cameraElapsed * 0.55) * height * 0.035).toInt()
                    cameraManipulator.grabUpdate(x, y)
                }
                "push_in" -> cameraManipulator.scroll(centerX, centerY, (-48.0 * dt).toFloat())
                "pull_out" -> cameraManipulator.scroll(centerX, centerY, (48.0 * dt).toFloat())
                "follow" -> {
                    if (!cameraGestureStarted) {
                        cameraManipulator.grabBegin(centerX, centerY, true)
                        cameraGestureStarted = true
                        cameraGestureStrafe = true
                    }
                    val x = centerX + (sin(cameraElapsed * 0.78) * width * 0.13).toInt()
                    val y = centerY + (cos(cameraElapsed * 0.91) * height * 0.045).toInt()
                    cameraManipulator.grabUpdate(x, y)
                }
            }
        }
        cameraManipulator.update(dt.toFloat())
    }

    private fun updateModelAnimation(viewer: ModelViewer) {
        val animator: Animator = viewer.animator ?: return
        val count = animator.animationCount
        if (count <= 0) return
        val duration = animator.getAnimationDuration(0)
        if (duration <= 0.001f) return
        val time = (cameraElapsed % duration.toDouble()).toFloat()
        animator.applyAnimation(0, time)
        animator.updateBoneMatrices()
    }

    fun diagnostics(): Map<String, Any?> {
        val animationCount = try { modelViewer?.animator?.animationCount ?: 0 } catch (_: Throwable) { 0 }
        return mapOf(
            "surfaceReady" to (surfaceReady && surfaceView.holder.surface.isValid),
            "surfaceWidth" to surfaceView.width,
            "surfaceHeight" to surfaceView.height,
            "modelLoaded" to modelLoaded,
            "activeModelPath" to activeModelPath,
            "animationCount" to animationCount,
            "cameraMotion" to cameraMode,
            "framesRendered" to framesRendered,
            "captureInProgress" to captureInProgress,
            "lastError" to lastError
        )
    }

    fun captureFrames(durationSeconds: Double, frameRate: Int, result: MethodChannel.Result) {
        if (disposed) {
            result.error("FILAMENT_VIEW_DISPOSED", "The 3D preview is closed.", null)
            return
        }
        if (durationSeconds < 0.5 || durationSeconds > 8.0 || frameRate !in 12..30) {
            result.error("FILAMENT_CAPTURE_ARGUMENTS", "Use 0.5–8 seconds and 12–30 FPS.", null)
            return
        }
        if (!modelLoaded || !surfaceReady || !surfaceView.holder.surface.isValid ||
            surfaceView.width <= 0 || surfaceView.height <= 0 || framesRendered < 2
        ) {
            result.error("FILAMENT_NOT_RENDERING", "The GLB or Surface is not ready. Diagnostics: ${diagnostics()}", null)
            return
        }
        if (captureInProgress) {
            result.error("FILAMENT_CAPTURE_BUSY", "A 3D capture is already running.", null)
            return
        }

        captureInProgress = true
        captureGeneration++
        val generation = captureGeneration
        val resultSent = AtomicBoolean(false)
        val folder = File(appContext.cacheDir, "filament_frames_" + System.currentTimeMillis())
        if (!folder.mkdirs()) {
            captureInProgress = false
            result.error("FILAMENT_CAPTURE_STORAGE", "Could not create the frame folder.", null)
            return
        }

        val frameCount = (durationSeconds * frameRate).toInt().coerceIn(6, 240)
        val frameDelayMs = (1000L / frameRate).coerceAtLeast(1L)
        var frameIndex = 0

        fun fail(code: String, message: String) {
            if (resultSent.compareAndSet(false, true)) {
                captureInProgress = false
                folder.deleteRecursively()
                result.error(code, message, diagnostics())
            }
        }

        fun captureNext() {
            if (resultSent.get()) return
            if (disposed || generation != captureGeneration) {
                fail("FILAMENT_CAPTURE_CANCELLED", "The preview closed during capture.")
                return
            }
            if (frameIndex >= frameCount) {
                if (resultSent.compareAndSet(false, true)) {
                    captureInProgress = false
                    result.success(folder.absolutePath)
                }
                return
            }
            if (!surfaceView.holder.surface.isValid) {
                fail("FILAMENT_SURFACE_LOST", "The render Surface was detached.")
                return
            }

            val bitmap = try {
                Bitmap.createBitmap(surfaceView.width, surfaceView.height, Bitmap.Config.ARGB_8888)
            } catch (error: Throwable) {
                fail("FILAMENT_BITMAP_FAILED", error.message ?: "Could not allocate a frame.")
                return
            }

            try {
                PixelCopy.request(surfaceView, bitmap, { copyResult ->
                    if (copyResult != PixelCopy.SUCCESS) {
                        bitmap.recycle()
                        fail("FILAMENT_PIXEL_COPY_FAILED", "PixelCopy failed with code $copyResult")
                    } else {
                        val currentIndex = frameIndex
                        ioExecutor.execute {
                            val saved = try {
                                val target = File(folder, "frame_" + currentIndex.toString().padStart(5, '0') + ".png")
                                FileOutputStream(target).use { output ->
                                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
                                }
                            } catch (_: Throwable) {
                                false
                            } finally {
                                bitmap.recycle()
                            }
                            mainHandler.post {
                                if (resultSent.get()) return@post
                                if (!saved) fail("FILAMENT_FRAME_WRITE_FAILED", "Could not save frame $currentIndex")
                                else {
                                    frameIndex++
                                    mainHandler.postDelayed({ captureNext() }, frameDelayMs)
                                }
                            }
                        }
                    }
                }, mainHandler)
            } catch (error: Throwable) {
                bitmap.recycle()
                fail("FILAMENT_PIXEL_COPY_FAILED", error.message ?: "Could not copy the Surface.")
            }
        }

        captureNext()
    }

    private fun scheduleFrame() {
        if (disposed || frameScheduled || modelViewer == null || !surfaceReady) return
        frameScheduled = true
        choreographer.postFrameCallback(frameCallback)
    }

    private fun showError(error: Throwable) {
        lastError = error.javaClass.simpleName + ": " + (error.message ?: "Unknown error")
        choreographer.removeFrameCallback(frameCallback)
        frameScheduled = false
        root.removeView(surfaceView)
        val message = TextView(root.context).apply {
            text = "Filament / GLB load failed\n\n" + (lastError ?: "Unknown error")
            setTextColor(Color.WHITE)
            textSize = 13f
            gravity = Gravity.CENTER
            setPadding(24, 24, 24, 24)
            setBackgroundColor(Color.rgb(44, 24, 32))
        }
        root.addView(message, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        ))
    }

    override fun getView(): View = root

    override fun dispose() {
        if (disposed) return
        disposed = true
        captureGeneration++
        captureInProgress = false
        choreographer.removeFrameCallback(frameCallback)
        surfaceView.holder.removeCallback(holderCallback)
        surfaceView.setOnTouchListener(null)
        endCameraGesture()
        try { modelViewer?.destroyModel() } catch (_: Throwable) {}
        try { modelViewer?.engine?.destroy() } catch (_: Throwable) {}
        modelViewer = null
        modelLoaded = false
        ioExecutor.shutdown()
    }
}
