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

    // 🎧 [DUO-DIRECT] 통화 모드로 연 트랙인지. Duo 직접 대화만 true다.
    //   true면 재생이 USAGE_VOICE_COMMUNICATION으로 나가고 AudioManager를
    //   MODE_IN_COMMUNICATION으로 돌린다. 안드로이드 AEC는 이 모드일 때만
    //   재생 신호를 참조로 받아 마이크에서 지울 수 있다 — 녹음 쪽 echoCancel만
    //   켜면 지울 대상을 몰라 효과가 없다.
    private var pcmVoiceCall = false
    private var savedAudioMode = AudioManager.MODE_NORMAL
    private var savedSpeakerphoneOn = false

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
                    // 인자를 안 보내는 기존 호출(첫 턴 Realtime 음성)은 false —
                    // 미디어 재생 그대로 두고 Duo 직접 대화만 통화 모드로 연다.
                    val voiceCall = call.argument<Boolean>("voiceCall") ?: false
                    startPcmStream(sampleRate, voiceCall, result)
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

    private fun startPcmStream(
        sampleRate: Int,
        voiceCall: Boolean,
        result: MethodChannel.Result
    ) {
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
                            .setUsage(
                                if (voiceCall) {
                                    AudioAttributes.USAGE_VOICE_COMMUNICATION
                                } else {
                                    AudioAttributes.USAGE_MEDIA
                                }
                            )
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
                val manager =
                    getSystemService(Context.AUDIO_SERVICE) as AudioManager
                audioManager = manager
                pcmVoiceCall = voiceCall
                if (voiceCall) {
                    // 되돌릴 값을 먼저 저장한다. 통화가 끝나면 원래대로 돌린다.
                    savedAudioMode = manager.mode
                    @Suppress("DEPRECATION")
                    savedSpeakerphoneOn = manager.isSpeakerphoneOn
                    manager.mode = AudioManager.MODE_IN_COMMUNICATION
                    // 통화 모드는 기본이 수화부다. Duo는 폰을 놓고 쓰는 화면이라
                    // 스피커폰을 켜 지금 들리던 방식을 유지한다. AEC는 스피커폰
                    // 상태에서도 동작한다(핸즈프리 통화와 같은 경로).
                    @Suppress("DEPRECATION")
                    manager.isSpeakerphoneOn = true
                }
                @Suppress("DEPRECATION")
                manager.requestAudioFocus(
                    null,
                    if (voiceCall) {
                        AudioManager.STREAM_VOICE_CALL
                    } else {
                        AudioManager.STREAM_MUSIC
                    },
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
        val manager = audioManager
        @Suppress("DEPRECATION")
        manager?.abandonAudioFocus(null)
        if (manager != null && pcmVoiceCall) {
            // 통화 모드를 남겨 두면 앱의 다른 소리(TTS·효과음)까지 통화 경로로
            // 나가고 볼륨 키도 통화 볼륨을 잡는다. 반드시 되돌린다.
            try {
                @Suppress("DEPRECATION")
                manager.isSpeakerphoneOn = savedSpeakerphoneOn
                manager.mode = savedAudioMode
            } catch (_: Exception) {
            }
        }
        pcmVoiceCall = false
        audioManager = null
    }

    override fun onDestroy() {
        stopPcmStream()
        pcmExecutor.shutdown()
        super.onDestroy()
    }
}
