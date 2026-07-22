package com.aienglishpractice.stealthvox

import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val installReferrerChannel = "stealthvox/install_referrer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            installReferrerChannel
        ).setMethodCallHandler { call, result ->
            if (call.method != "getInstallReferrer") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val client = InstallReferrerClient.newBuilder(this).build()
            client.startConnection(object : InstallReferrerStateListener {
                override fun onInstallReferrerSetupFinished(responseCode: Int) {
                    if (responseCode == InstallReferrerClient.InstallReferrerResponse.OK) {
                        try {
                            result.success(client.installReferrer.installReferrer)
                        } catch (error: Exception) {
                            result.error("INSTALL_REFERRER_READ", error.message, null)
                        } finally {
                            client.endConnection()
                        }
                    } else {
                        client.endConnection()
                        result.success(null)
                    }
                }

                override fun onInstallReferrerServiceDisconnected() {
                    // A later app launch retries; do not fail startup for this.
                }
            })
        }
    }
}
