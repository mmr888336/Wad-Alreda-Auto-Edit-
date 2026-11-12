package com.omer.filament_renderer

import android.content.Context
import android.graphics.Color
import android.view.Choreographer
import android.view.Gravity
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
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Android plugin for Wad Alreda AutoEdit's Filament renderer.
 *
 * The method channel retains the phase-one lifecycle diagnostics. The
 * PlatformView hosts a real Filament ModelViewer and loads a bundled GLB
 * sample so the first test can confirm native rendering on a physical device.
 */
class FilamentRendererPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    companion object {
        private const val CHANNEL_NAME = "com.omer.filament_renderer/methods"
        private const val VIEW_TYPE = "com.omer.filament_renderer/model_view"
        private const val FILAMENT_VERSION = "1.56.0"
    }

    private var channel: MethodChannel? = null
    private var diagnosticEngine: Engine? = null
    private val engineLock = Any()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
        binding.platformViewRegistry.registerViewFactory(
            VIEW_TYPE,
            FilamentModelViewFactory()
        )
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initializeEngine(result)
            "isInitialized" -> result.success(isEngineInitialized())
            "getNativeVersion" -> result.success(FILAMENT_VERSION)
            "dispose" -> disposeEngine(result)
            else -> result.notImplemented()
        }
    }

    private fun initializeEngine(result: MethodChannel.Result) {
        try {
            synchronized(engineLock) {
                if (diagnosticEngine == null) {
                    diagnosticEngine = Engine.create()
                }
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
        synchronized(engineLock) {
            return diagnosticEngine != null
        }
    }

    private fun disposeEngine(result: MethodChannel.Result) {
        try {
            releaseDiagnosticEngine()
            result.success(null)
        } catch (error: Throwable) {
            result.error(
                "FILAMENT_ENGINE_DISPOSE_FAILED",
                error.message ?: error.javaClass.simpleName,
                null
            )
        }
    }

    private fun releaseDiagnosticEngine() {
        synchronized(engineLock) {
            val current = diagnosticEngine
            diagnosticEngine = null
            current?.destroy()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        try {
            releaseDiagnosticEngine()
        } catch (_: Throwable) {
            // Best-effort cleanup during Flutter engine detachment.
        }
    }
}

private class FilamentModelViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return FilamentModelPlatformView(context)
    }
}

/**
 * A real Android SurfaceView backed by Filament's ModelViewer.
 * A simple bundled cube GLB is used to validate GLB loading and GPU rendering.
 */
private class FilamentModelPlatformView(context: Context) : PlatformView {
    private val root = FrameLayout(context)
    private val surfaceView = SurfaceView(context)
    private val choreographer = Choreographer.getInstance()
    private var modelViewer: ModelViewer? = null
    private var disposed = false

    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (disposed) return
            try {
                modelViewer?.render(frameTimeNanos)
            } catch (error: Throwable) {
                showError(error)
                return
            }
            if (!disposed && modelViewer != null) {
                choreographer.postFrameCallback(this)
            }
        }
    }

    init {
        root.addView(
            surfaceView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )

        try {
            // Loads Filament's JNI libraries before creating the renderer.
            Utils.init()
            val viewer = ModelViewer(surfaceView)
            modelViewer = viewer
            viewer.loadModelGlb(readBundledModel(context))
            viewer.transformToUnitCube()
            surfaceView.setOnTouchListener { _: View, event ->
                viewer.onTouchEvent(event)
            }
            choreographer.postFrameCallback(frameCallback)
        } catch (error: Throwable) {
            showError(error)
        }
    }

    private fun readBundledModel(context: Context): ByteBuffer {
        val bytes = context.assets.open("models/filament_sample.glb").use { input ->
            input.readBytes()
        }
        if (bytes.size < 20 || bytes[0] != 0x67.toByte() ||
            bytes[1] != 0x6C.toByte() || bytes[2] != 0x54.toByte() ||
            bytes[3] != 0x46.toByte()) {
            throw IllegalStateException("Bundled GLB asset is missing or invalid.")
        }
        return ByteBuffer.allocateDirect(bytes.size)
            .order(ByteOrder.nativeOrder())
            .apply {
                put(bytes)
                flip()
            }
    }

    private fun showError(error: Throwable) {
        choreographer.removeFrameCallback(frameCallback)
        try {
            modelViewer?.destroy()
        } catch (_: Throwable) {
            // Ignore cleanup failure while presenting the original error.
        }
        modelViewer = null
        root.removeView(surfaceView)
        val message = TextView(root.context).apply {
            text = "Filament / GLB load failed\n\n${error.javaClass.simpleName}: ${error.message ?: "Unknown error"}"
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
        choreographer.removeFrameCallback(frameCallback)
        try {
            modelViewer?.destroy()
        } catch (_: Throwable) {
            // Best-effort release of GPU resources.
        }
        modelViewer = null
    }
}
