package com.tuempresa.room_scanner_ar

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
     * Comprueba si ARCore está disponible y correctamente instalado
     * para poder utilizar el Scanner AR.
     *
     * Esta comprobación NO instala ARCore y NO inicia una sesión AR.
     *
     * El resultado se utiliza únicamente para seleccionar entre:
     *
     *   ARCore disponible e instalado
     *       -> ARScannerScreen
     *
     *   ARCore no disponible
     *       -> BasicScannerScreen
     *
     * Para considerar ARCore utilizable exigimos:
     *
     *   SUPPORTED_INSTALLED
     *
     * No consideramos como AR disponible:
     *
     *   SUPPORTED_NOT_INSTALLED
     *   SUPPORTED_APK_TOO_OLD
     *
     * En esos casos el usuario utilizará el Scanner Básico.
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
                                ArCoreApk.Availability.SUPPORTED_INSTALLED

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