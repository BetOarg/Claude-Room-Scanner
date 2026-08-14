package com.tuempresa.room_scanner_ar

import android.os.Bundle

import com.google.ar.core.ArCoreApk

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {

        private const val DEVICE_CAPABILITIES_CHANNEL =
            "com.betOarg.room_scanner_ar/device_capabilities"
    }

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEVICE_CAPABILITIES_CHANNEL
        )

        channel.setMethodCallHandler { call, result ->

            when (call.method) {

                "isARCoreSupported" -> {
                    checkARCoreAvailability(result)
                }

                "isARKitSupported" -> {
                    // ARKit no existe en Android.
                    result.success(false)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    /**
     * Comprueba si el dispositivo Android es compatible con ARCore.
     *
     * IMPORTANTE:
     *
     * - No instala ARCore.
     * - No inicia una sesión AR.
     * - No obliga a utilizar ARCore.
     *
     * Solamente determina si el dispositivo puede utilizar
     * las funcionalidades AR.
     *
     * Si devuelve false, Flutter podrá utilizar el Basic Scanner.
     */
    private fun checkARCoreAvailability(
        result: MethodChannel.Result
    ) {

        try {

            ArCoreApk.getInstance()
                .checkAvailabilityAsync(
                    applicationContext
                ) { availability ->

                    val supported =
                        availability ==
                                ArCoreApk.Availability.SUPPORTED_INSTALLED ||
                        availability ==
                                ArCoreApk.Availability.SUPPORTED_APK_TOO_OLD ||
                        availability ==
                                ArCoreApk.Availability.SUPPORTED_NOT_INSTALLED

                    result.success(supported)
                }

        } catch (exception: Exception) {

            result.error(
                "ARCORE_CHECK_FAILED",
                exception.message
                    ?: "No se pudo comprobar ARCore.",
                null
            )
        }
    }
}