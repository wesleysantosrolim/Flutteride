package com.flutteride.flutteride

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName =
        "com.flutteride.flutteride/native_path"

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                "getNativeLibDir" -> {
                    val nativeLibDir =
                        applicationInfo.nativeLibraryDir

                    result.success(nativeLibDir)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}