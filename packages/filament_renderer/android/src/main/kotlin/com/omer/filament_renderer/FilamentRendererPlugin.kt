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

/** Filament preview, diagnostics and frame-capture bridge. */
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
                } else {
                    result.success(view.diagnostics())
                }
            }
            "captureFrames" -> {
                val id = call.argument<Int>("viewId")
                val duration = call.argument<Double>("durationSeconds") ?: 3.0
                val fps = call.argument<Int>("frameRate") ?: 24
                val view = id?.let { synchronized(viewLock) { modelViews[it] } }
                if (view == null) {
                    result.error("FILAMENT_VIEW_NOT_FOUND", "The 3D preview is not attached.", null)
                } else {
                    view.captureFrames(duration, fps, result)
                }
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
            result.error(
                "FILAMENT_ENGINE_INIT_FAILED",
                error.message ?: error.javaClass.simpleName,
                null
            )
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
            result.error(
                "FILAMENT_ENGINE_DISPOSE_FAILED",
                error.message ?: error.javaClass.simpleName,
                null
            )
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

/**
 * ModelViewer registers its internal SurfaceHolder callbacks before this
 * view is attached. Our callback then starts the render loop only after the
 * Android surface is genuinely ready.
 */
private class FilamentModelPlatformView(
    private val appContext: Context
) : PlatformView {
    private val root = FrameLayout(appContext)
    private val surfaceView = SurfaceView(appContext)
    private val choreographer = Choreographer.getInstance()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor = Executors.newSingleThreadExecutor()

    private var modelViewer: ModelViewer? = null
    private var surfaceReady = false
    private var modelLoaded = false
    private var framesRendered = 0L
    private var lastError: String? = null
    private var disposed = false
    private var frameScheduled = false
    private var captureInProgress = false
    private var captureGeneration = 0

    private val holderCallback = object : SurfaceHolder.Callback {
        override fun surfaceCreated(holder: SurfaceHolder) {
            surfaceReady = holder.surface.isValid
            scheduleFrame()
        }

        override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            surfaceReady = holder.surface.isValid && width > 0 && height > 0
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
            val viewer = ModelViewer(surfaceView)
            modelViewer = viewer
            viewer.loadModelGlb(readBundledModel(appContext))
            viewer.transformToUnitCube()
            modelLoaded = true
            lastError = null
            surfaceView.setOnTouchListener { _, event ->
                viewer.onTouchEvent(event)
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
        if (bytes.size < 20 ||
            bytes[0] != 0x67.toByte() ||
            bytes[1] != 0x6C.toByte() ||
            bytes[2] != 0x54.toByte() ||
            bytes[3] != 0x46.toByte()
        ) {
            throw IllegalStateException("Bundled GLB asset is missing or invalid.")
        }
        val header = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        header.position(4)
        val version = header.int
        val declaredLength = header.int
        if (version != 2 || declaredLength != bytes.size) {
            throw IllegalStateException(
                "Invalid GLB header: version=" + version +
                    ", declaredLength=" + declaredLength + ", actual=" + bytes.size
            )
        }
        return ByteBuffer.allocateDirect(bytes.size)
            .order(ByteOrder.nativeOrder())
            .apply {
                put(bytes)
                flip()
            }
    }

    private fun scheduleFrame() {
        if (disposed || frameScheduled || modelViewer == null || !surfaceReady) return
        frameScheduled = true
        choreographer.postFrameCallback(frameCallback)
    }

    fun diagnostics(): Map<String, Any?> = mapOf(
        "surfaceReady" to (surfaceReady && surfaceView.holder.surface.isValid),
        "surfaceWidth" to surfaceView.width,
        "surfaceHeight" to surfaceView.height,
        "modelLoaded" to modelLoaded,
        "framesRendered" to framesRendered,
        "captureInProgress" to captureInProgress,
        "lastError" to lastError
    )

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
            result.error(
                "FILAMENT_NOT_RENDERING",
                "The GLB or Surface is not ready. Diagnostics: " + diagnostics(),
                null
            )
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
                        fail("FILAMENT_PIXEL_COPY_FAILED", "PixelCopy failed with code " + copyResult)
                    } else {
                        val currentIndex = frameIndex
                        ioExecutor.execute {
                            val saved = try {
                                val target = File(
                                    folder,
                                    "frame_" + currentIndex.toString().padStart(5, '0') + ".png"
                                )
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
                                if (!saved) {
                                    fail("FILAMENT_FRAME_WRITE_FAILED", "Could not save frame " + currentIndex)
                                } else {
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
        root.addView(
            message,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )
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
        try { modelViewer?.engine?.destroy() } catch (_: Throwable) {}
        modelViewer = null
        modelLoaded = false
        ioExecutor.shutdown()
    }
}
