package com.example.magnetnodebrowser

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.magnetnodebrowser/magnet"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getMagnetLink" -> {
                    val magnetLink = extractMagnetLink()
                    result.success(magnetLink)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    private fun extractMagnetLink(): String? {
        val intent = intent
        return when {
            intent?.action == Intent.ACTION_VIEW -> {
                intent.dataString ?: intent.data?.toString()
            }
            else -> null
        }
    }
}
