package com.aienglishpractice.stealthvox

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity: FlutterActivity() {
    private val installReferrerChannel = "stealthvox/install_referrer"
    private val realtimePcmChannel = "stealthvox/realtime_pcm"
    private val pcmExecutor = Executors.newSingleThreadExecutor()

    @Volatile
    private var pcmGeneration = 0
    private var pcmTrack: AudioTrack? = null
    private var pcmSampleRate = 24000
    private var pcmBufferSize = 0
    private var pcmFramesWritten = 0L
    private var pcmPlaying = false
    private var audioManager: AudioManager? = null

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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            realtimePcmChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val sampleRate = call.argument<Int>("sampleRate") ?: 24000
                    startPcmStream(sampleRate, result)
                }
                "append" -> {
                    val bytes = call.arguments as? ByteArray
                    if (bytes == null || bytes.isEmpty()) {
                        result.success(null)
                    } else {
                        appendPcm(bytes)
                        result.success(null)
                    }
                }
                "finish" -> finishPcmStream(result)
                "stop" -> {
                    stopPcmStream()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startPcmStream(sampleRate: Int, result: MethodChannel.Result) {
        val generation = ++pcmGeneration
        pcmExecutor.execute {
            releasePcmTrack()
            try {
                val minBuffer = AudioTrack.getMinBufferSize(
                    sampleRate,
                    AudioFormat.CHANNEL_OUT_MONO,
                    AudioFormat.ENCODING_PCM_16BIT
                )
                pcmBufferSize = maxOf(minBuffer, sampleRate)
                val track = AudioTrack.Builder()
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build()
                    )
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(sampleRate)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                            .build()
                    )
                    .setBufferSizeInBytes(pcmBufferSize)
                    .setTransferMode(AudioTrack.MODE_STREAM)
                    .build()
                if (generation != pcmGeneration ||
                    track.state != AudioTrack.STATE_INITIALIZED) {
                    track.release()
                    runOnUiThread { result.success(false) }
                    return@execute
                }
                pcmTrack = track
                pcmSampleRate = sampleRate
                pcmFramesWritten = 0L
                pcmPlaying = false
                audioManager =
                    getSystemService(Context.AUDIO_SERVICE) as AudioManager
                @Suppress("DEPRECATION")
                audioManager?.requestAudioFocus(
                    null,
                    AudioManager.STREAM_MUSIC,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
                )
                runOnUiThread { result.success(true) }
            } catch (error: Exception) {
                releasePcmTrack()
                runOnUiThread {
                    result.error("PCM_START", error.message, null)
                }
            }
        }
    }

    private fun appendPcm(bytes: ByteArray) {
        val generation = pcmGeneration
        pcmExecutor.execute {
            val track = pcmTrack ?: return@execute
            if (generation != pcmGeneration) return@execute
            var offset = 0
            if (!pcmPlaying) {
                // 재생 전에 약간 prime해 첫 샘플 underrun을 줄인다.
                val primeSize = minOf(bytes.size, pcmBufferSize / 2)
                val primed = track.write(
                    bytes,
                    0,
                    primeSize,
                    AudioTrack.WRITE_BLOCKING
                )
                if (primed > 0) {
                    offset = primed
                    pcmFramesWritten += primed / 2L
                }
                track.play()
                pcmPlaying = true
            }
            while (offset < bytes.size && generation == pcmGeneration) {
                val written = track.write(
                    bytes,
                    offset,
                    bytes.size - offset,
                    AudioTrack.WRITE_BLOCKING
                )
                if (written <= 0) break
                offset += written
                pcmFramesWritten += written / 2L
            }
        }
    }

    private fun finishPcmStream(result: MethodChannel.Result) {
        val generation = pcmGeneration
        pcmExecutor.execute {
            val track = pcmTrack
            if (track != null && generation == pcmGeneration && pcmPlaying) {
                val deadlineMs = System.currentTimeMillis() +
                    ((pcmFramesWritten * 1000L / pcmSampleRate) + 2000L)
                while (generation == pcmGeneration &&
                    track.playbackHeadPosition.toLong() < pcmFramesWritten &&
                    System.currentTimeMillis() < deadlineMs) {
                    try {
                        Thread.sleep(10)
                    } catch (_: InterruptedException) {
                        break
                    }
                }
            }
            if (generation == pcmGeneration) releasePcmTrack()
            runOnUiThread { result.success(null) }
        }
    }

    private fun stopPcmStream() {
        ++pcmGeneration
        pcmExecutor.execute { releasePcmTrack() }
    }

    private fun releasePcmTrack() {
        val track = pcmTrack
        pcmTrack = null
        pcmPlaying = false
        pcmFramesWritten = 0L
        if (track != null) {
            try {
                track.pause()
                track.flush()
                track.stop()
            } catch (_: Exception) {
            }
            try {
                track.release()
            } catch (_: Exception) {
            }
        }
        @Suppress("DEPRECATION")
        audioManager?.abandonAudioFocus(null)
        audioManager = null
    }

    override fun onDestroy() {
        stopPcmStream()
        pcmExecutor.shutdown()
        super.onDestroy()
    }
}
