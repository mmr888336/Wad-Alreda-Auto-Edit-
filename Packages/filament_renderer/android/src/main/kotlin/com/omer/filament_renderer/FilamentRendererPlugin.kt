package com.omer.filament_renderer

import com.google.android.filament.Engine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * First-stage Android bridge for Filament.
 *
 * This plugin deliberately does not create a Surface, SwapChain, Renderer,
 * View, or Scene yet. Its responsibility in this phase is to prove that the
 * Filament native libraries load and that an Engine can be created/destroyed
 * safely on the Android device before adding GLB loading and offscreen render.
 */
class FilamentRendererPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    companion object {
        private const val CHANNEL_NAME = "com.omer.filament_renderer/methods"
        private const val FILAMENT_VERSION = "1.56.0"
    }

    private var channel: MethodChannel? = null
    private var engine: Engine? = null
    private val engineLock = Any()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
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
                if (engine == null) {
                    engine = Engine.create()
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
            return engine != null
        }
    }

    private fun disposeEngine(result: MethodChannel.Result) {
        try {
            releaseEngine()
            result.success(null)
        } catch (error: Throwable) {
            result.error(
                "FILAMENT_ENGINE_DISPOSE_FAILED",
                error.message ?: error.javaClass.simpleName,
                null
            )
        }
    }

    private fun releaseEngine() {
        synchronized(engineLock) {
            val current = engine
            engine = null
            current?.destroy()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        // Do not let a teardown exception prevent Flutter engine detachment.
        try {
            releaseEngine()
        } catch (_: Throwable) {
            // Native resources are best-effort released during host teardown.
        }
    }
}
