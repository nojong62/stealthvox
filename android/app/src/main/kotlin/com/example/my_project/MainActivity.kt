package com.aienglishpractice.stealthvox

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.os.Build
import android.media.AudioTrack
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

// 🔊 재생기가 오디오 세션을 어디까지 건드리는가. 셋을 **이름으로** 갈라 둔다 —
//   예전에는 `voiceCall: Boolean` 하나였고, 통역을 끼우려면 그 의미를 바꿔야
//   해서 Direct까지 같이 흔들렸다.
//
//   media                 기존 무인자 호출. USAGE_MEDIA 그대로.
//   voiceCallManaged      Duo 직접 대화. 통화 모드·포커스·스피커폰을 **직접 잡고**
//                         끝날 때 되돌린다. AEC가 재생 신호를 참조로 받으려면
//                         이 모드가 필요하다.
//   voiceCommTrackOnly    Duo 만능 통역. **트랙 usage만** 통화용으로 연다.
//                         mode·focus·speakerphone·communicationDevice를 일절
//                         건드리지 않는다 — 통역 중에는 WebRTC가 이미 그것들을
//                         쥐고 있고, 발화마다 뺏었다 돌려주면 통화가 흔들린다.
private const val PLAYBACK_MEDIA = "media"
private const val PLAYBACK_VOICE_CALL_MANAGED = "voiceCallManaged"
private const val PLAYBACK_VOICE_COMM_TRACK_ONLY = "voiceCommTrackOnly"

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

    // 어느 모드로 열렸는가. 진단과 해제 분기가 이 값을 본다.
    private var pcmPlaybackMode = PLAYBACK_MEDIA

    // 🎚️ 앱 안쪽 음량(화자별 상대 게인). 물리 볼륨키가 잡는 시스템 음량과는
    //   **다른 축**이다 — 둘이 곱해져서 최종 크기가 된다.
    private var pcmVolume = 1.0f
    private var savedAudioMode = AudioManager.MODE_NORMAL
    private var savedSpeakerphoneOn = false

    @Volatile
    private var pcmAudioFocusResult = AudioManager.AUDIOFOCUS_REQUEST_FAILED
    // 🎙️ [DUO-MIC-TAP] WebRTC가 잡은 마이크 PCM을 전사 갈래로 흘리는 통로.
    //   마이크를 두 번 열지 않기 위한 자리다 — 자세한 내용은 그 파일에 있다.
    private var duoMicTap: DuoWebrtcMicTap? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        duoMicTap = DuoWebrtcMicTap(flutterEngine.dartExecutor.binaryMessenger)
            .also { it.register() }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            installReferrerChannel
        ).setMethodCallHandler { call, result ->
            if (call.method != "getInstallReferrer") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val client = InstallReferrerClient.newBuilder(this).build()
            val replied = AtomicBoolean(false)
            fun completeSuccess(value: String?) {
                if (replied.compareAndSet(false, true)) result.success(value)
            }
            fun completeError(code: String, message: String?) {
                if (replied.compareAndSet(false, true)) result.error(code, message, null)
            }
            client.startConnection(object : InstallReferrerStateListener {
                override fun onInstallReferrerSetupFinished(responseCode: Int) {
                    if (responseCode == InstallReferrerClient.InstallReferrerResponse.OK) {
                        try {
                            completeSuccess(client.installReferrer.installReferrer)
                        } catch (error: Exception) {
                            completeError("INSTALL_REFERRER_READ", error.message)
                        } finally {
                            client.endConnection()
                        }
                    } else {
                        client.endConnection()
                        completeSuccess(null)
                    }
                }

                override fun onInstallReferrerServiceDisconnected() {
                    // Dart의 Future를 끝내지 않으면 최초 진입이 무한 대기한다.
                    // 이후 setup 콜백이 와도 AtomicBoolean이 중복 응답을 막는다.
                    try {
                        client.endConnection()
                    } finally {
                        completeSuccess(null)
                    }
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
                    // 인자를 안 보내는 기존 호출(첫 턴 Realtime 음성)은 media —
                    // 그리고 `voiceCall: true`를 보내던 Direct는 voiceCallManaged로
                    // 그대로 간다. 기존 호출부는 한 글자도 안 바뀐다.
                    @Suppress("DEPRECATION")
                    val legacyVoiceCall = call.argument<Boolean>("voiceCall") ?: false
                    val mode = call.argument<String>("playbackMode")
                        ?: if (legacyVoiceCall) {
                            PLAYBACK_VOICE_CALL_MANAGED
                        } else {
                            PLAYBACK_MEDIA
                        }
                    val volume = (call.argument<Double>("volume") ?: 1.0).toFloat()
                    startPcmStream(sampleRate, mode, volume, result)
                }
                // 🚰 [BACKPRESSURE] `append`와 **의미가 다르다.** 이쪽은 실제
                //   AudioTrack.write가 끝난 뒤에만 결과를 돌려준다. 그래야 Dart
                //   쪽 공급이 재생 속도를 앞지르지 않는다.
                //
                //   ⚠️ `append`는 손대지 않는다 — Direct가 그 즉시 반환에 기대
                //   자체 프리버퍼를 돌리고 있다.
                "appendBlocking" -> {
                    val bytes = call.arguments as? ByteArray
                    if (bytes == null || bytes.isEmpty()) {
                        result.success(null)
                    } else {
                        appendPcmBlocking(bytes, result)
                    }
                }
                "setVolume" -> {
                    val volume = (call.argument<Double>("volume") ?: 1.0).toFloat()
                    setPcmVolume(volume)
                    result.success(null)
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
                "diagnostics" -> {
                    val manager =
                        getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    @Suppress("DEPRECATION")
                    val speakerphone = manager.isSpeakerphoneOn
                    val communicationDevice = if (Build.VERSION.SDK_INT >= 31) {
                        manager.communicationDevice?.type
                    } else {
                        null
                    }
                    result.success(mapOf(
                        "mode" to manager.mode,
                        "speakerphoneOn" to speakerphone,
                        "communicationDevice" to communicationDevice,
                        "audioFocusResult" to pcmAudioFocusResult,
                        "pcmTrackAlive" to (pcmTrack != null),
                        "pcmVoiceCall" to pcmVoiceCall,
                        "pcmPlaybackMode" to pcmPlaybackMode,
                        "pcmPlaying" to pcmPlaying
                    ))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startPcmStream(
        sampleRate: Int,
        mode: String,
        volume: Float,
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
                                if (mode == PLAYBACK_MEDIA) {
                                    AudioAttributes.USAGE_MEDIA
                                } else {
                                    AudioAttributes.USAGE_VOICE_COMMUNICATION
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
                pcmPlaybackMode = mode
                pcmVoiceCall = (mode == PLAYBACK_VOICE_CALL_MANAGED)
                pcmVolume = volume.coerceIn(0f, 1f)
                track.setVolume(pcmVolume)

                // 🚫 [voiceCommTrackOnly] 세션은 **손대지 않는다.**
                //   통역 중에는 WebRTC가 MODE_IN_COMMUNICATION·오디오 포커스·
                //   라우팅(스피커/유선/블루투스)을 모두 쥐고 있다. 발화마다
                //   여기서 다시 잡았다 놓으면 그 상태가 흔들린다. 트랙 usage만
                //   통화용이면 물리 볼륨키(STREAM_VOICE_CALL)가 닿는다.
                //
                //   `audioManager`를 비워 두는 것이 곧 해제 분기의 표식이다 —
                //   [releasePcmTrack]이 null을 보고 아무것도 되돌리지 않는다.
                if (mode == PLAYBACK_VOICE_CALL_MANAGED) {
                    val manager =
                        getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    audioManager = manager
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
                    @Suppress("DEPRECATION")
                    pcmAudioFocusResult = manager.requestAudioFocus(
                        null,
                        AudioManager.STREAM_VOICE_CALL,
                        AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
                    )
                } else if (mode == PLAYBACK_MEDIA) {
                    val manager =
                        getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    audioManager = manager
                    @Suppress("DEPRECATION")
                    pcmAudioFocusResult = manager.requestAudioFocus(
                        null,
                        AudioManager.STREAM_MUSIC,
                        AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
                    )
                }
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

    /// 🚰 [BACKPRESSURE] 실제로 다 쓰고 나서 돌아온다.
    ///
    /// `append`와 달리 `result.success`를 **write 완료 뒤에** 부른다. 그래야
    /// Dart의 `await feed(...)`가 재생 속도를 따라가고, 어댑터가 버퍼를 무한히
    /// 앞질러 채우지 않는다(flutter_sound `feedUint8FromStream`과 같은 의미).
    ///
    /// ⚠️ **플랫폼 스레드는 막지 않는다.** 블로킹 write는 전부 [pcmExecutor]
    ///   위에서 돌고, 이 함수 자체는 작업만 걸고 즉시 반환한다. 결과는 일이
    ///   끝난 뒤 UI 스레드에서 돌려준다.
    ///
    /// ⚠️ 조각을 **잘라서** 쓴다. 한 번에 통째로 쓰면 그 write가 끝날 때까지
    ///   generation 검사를 못 해 abort가 그만큼 늦는다. 100ms씩 끊으면 중단
    ///   요청이 그 안에 반영된다.
    private fun appendPcmBlocking(bytes: ByteArray, result: MethodChannel.Result) {
        val generation = pcmGeneration
        pcmExecutor.execute {
            val track = pcmTrack
            if (track == null || generation != pcmGeneration) {
                runOnUiThread { result.success(null) }
                return@execute
            }
            // 16-bit mono 기준 대략 100ms.
            val slice = maxOf(2, (pcmSampleRate / 5) and 1.inv())
            var offset = 0
            try {
                if (!pcmPlaying) {
                    val primeSize = minOf(bytes.size, pcmBufferSize / 2)
                    val primed = track.write(
                        bytes, 0, primeSize, AudioTrack.WRITE_BLOCKING
                    )
                    if (primed > 0) {
                        offset = primed
                        pcmFramesWritten += primed / 2L
                    }
                    track.play()
                    pcmPlaying = true
                }
                while (offset < bytes.size && generation == pcmGeneration) {
                    val chunk = minOf(slice, bytes.size - offset)
                    val written = track.write(
                        bytes, offset, chunk, AudioTrack.WRITE_BLOCKING
                    )
                    if (written <= 0) break
                    offset += written
                    pcmFramesWritten += written / 2L
                }
            } catch (_: Exception) {
                // 트랙이 중간에 풀렸다. 남은 조각은 버린다 — 다음 begin이 새로 연다.
            }
            runOnUiThread { result.success(null) }
        }
    }

    /// 🎚️ 화자별 상대 게인. 시스템 음량(물리 볼륨키)과는 다른 축이라 둘 다
    ///   살아 있어야 한다 — 여기서 0.5를 걸어도 사용자는 볼륨키로 더 올릴 수 있다.
    private fun setPcmVolume(volume: Float) {
        val clamped = volume.coerceIn(0f, 1f)
        pcmVolume = clamped
        pcmExecutor.execute {
            try {
                pcmTrack?.setVolume(clamped)
            } catch (_: Exception) {
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
        pcmAudioFocusResult = AudioManager.AUDIOFOCUS_REQUEST_FAILED
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
        pcmPlaybackMode = PLAYBACK_MEDIA
        pcmVolume = 1.0f
        audioManager = null
    }

    override fun onDestroy() {
        stopPcmStream()
        duoMicTap?.stop()
        duoMicTap = null
        pcmExecutor.shutdown()
        super.onDestroy()
    }
}
