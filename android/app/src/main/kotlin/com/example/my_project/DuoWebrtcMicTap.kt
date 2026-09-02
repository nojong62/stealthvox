package com.aienglishpractice.stealthvox

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.audio.LocalAudioTrack
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.webrtc.AudioTrackSink
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.sin

// ============================================================================
// 🎙️ [DUO-MIC-TAP] 마이크 하나를 통화와 전사 두 갈래로 나누는 자리
// ----------------------------------------------------------------------------
// 예전 구조는 마이크를 **두 번** 열었다.
//
//   record 패키지     → AudioRecord(DEFAULT, 24kHz)   → STT
//   flutter_webrtc    → AudioRecord(VOICE_COMM, 48kHz) → 통화
//
// 같은 앱에서 AudioRecord 두 개가 경합하면 안드로이드는 오류 없이 한쪽에
// 무음만 내보내고, 하드웨어 AEC도 한쪽 세션에만 붙는다. 제조사마다 다르다.
//
// 그래서 마이크는 **WebRTC 것 하나만** 열고, WebRTC가 잡은 바로 그 PCM을
// 여기서 받아 STT로 흘린다.
//
//   flutter_webrtc AudioRecord (1개)
//        ├─→ WebRTC 통화 (네이티브 파이프라인 그대로)
//        └─→ 이 탭 → 48k→24k 변환 → Dart → DuoMicPcmFanout → STT/RMS
//
// 🔌 **플러그인을 고치지 않는다.** flutter_webrtc가 이미 캡처한 조각을 모든
//   LocalAudioTrack에 넘겨 주고 있고(`MethodCallHandlerImpl`), `addSink`가
//   public이다. 우리는 거기에 귀 하나를 더 붙일 뿐이다.
//
// 🎧 **탭 위치가 중요하다.** 이 콜백은 AudioRecord에서 읽은 직후에 불린다.
//   즉 **하드웨어 AEC는 이미 적용됐고, WebRTC 소프트웨어 APM(AEC3/NS/AGC)은
//   아직 걸리지 않은** 소리다. 기존 STT 설정(echoCancel:true /
//   noiseSuppress:false)과 성질이 같아지는 자리가 정확히 여기다.
//   (하드웨어 NS는 Dart 쪽에서 따로 끈다)
//
// 🚫 PCM을 파일이나 DB에 남기지 않는다. 흘려보내고 버린다.
// ============================================================================

class DuoWebrtcMicTap(messenger: BinaryMessenger) {

    companion object {
        private const val TAG = "DuoMicTap"

        /// 전사 갈래가 요구하는 규격. 앱 전체 STT 샘플레이트와 같아야 한다.
        const val TARGET_SAMPLE_RATE = 24000

        /// Dart로 넘기기 전에 모으는 양. 10ms 조각을 그대로 넘기면 초당 100번
        /// 채널을 두드린다 — 40ms로 묶어 1/4로 줄인다.
        const val BATCH_MS = 40

        /// 반대역 저역통과 필터 탭 수. 홀수여야 선형 위상이 된다.
        ///
        /// ⚠️ **이 필터를 빼고 샘플만 버리면 안 된다.** 12~24kHz 성분이
        ///   0~12kHz로 접혀 들어오고(에일리어싱), 하필 그 대역에 ㅅ·ㅊ·ㅎ
        ///   마찰음의 에너지가 있다. 이 프로젝트가 NS를 끈 이유와 같은 이유로
        ///   여기서도 고역을 함부로 망가뜨리면 안 된다.
        private const val FIR_TAPS = 31
    }

    private val methodChannel =
        MethodChannel(messenger, "stealthvox/duo_mic_tap")
    private val eventChannel =
        EventChannel(messenger, "stealthvox/duo_mic_tap/pcm")

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    private var attachedTrack: LocalAudioTrack? = null
    private var sink: AudioTrackSink? = null

    /// 리샘플러 상태. 트랙마다 새로 만든다.
    private var resampler: Resampler? = null

    /// Dart로 넘길 24k 조각을 모으는 자리.
    private val batch = ArrayList<Short>(TARGET_SAMPLE_RATE * BATCH_MS / 1000 * 2)
    private val batchTarget = TARGET_SAMPLE_RATE * BATCH_MS / 1000

    /// 진단용 셈. 오디오 내용은 남기지 않는다.
    @Volatile private var framesIn = 0L
    @Volatile private var samplesOut = 0L
    @Volatile private var loggedFormat = false

    fun register() {
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val trackId = call.argument<String>("trackId")
                    if (trackId.isNullOrEmpty()) {
                        result.error("BAD_ARGS", "trackId is required", null)
                    } else {
                        result.success(start(trackId))
                    }
                }
                "stop" -> {
                    stop()
                    result.success(null)
                }
                // 하드웨어 잡음 억제를 끈다. 기존 STT 정책
                // (echoCancel:true / noiseSuppress:false)을 지키기 위해서다 —
                // flutter_webrtc는 기본으로 이걸 켜는데, NS는 마찰음과 문장 끝을
                // 같이 깎아 전사를 망친다. 통화 쪽 NS는 소프트웨어 APM이
                // 우리 탭 **뒤에서** 계속 해 주므로 통화 품질은 잃지 않는다.
                "setHardwareNoiseSuppressor" -> {
                    val on = call.argument<Boolean>("enabled") ?: false
                    result.success(setHardwareNoiseSuppressor(on))
                }
                "stats" -> result.success(
                    mapOf("framesIn" to framesIn, "samplesOut" to samplesOut)
                )
                else -> result.notImplemented()
            }
        }

        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    private fun setHardwareNoiseSuppressor(enabled: Boolean): Boolean {
        return try {
            val adm = FlutterWebRTCPlugin.sharedSingleton?.audioDeviceModule
            if (adm == null) {
                Log.w(TAG, "audioDeviceModule unavailable")
                false
            } else {
                adm.setNoiseSuppressorEnabled(enabled)
                Log.i(TAG, "hardware noise suppressor enabled=$enabled")
                true
            }
        } catch (e: Exception) {
            Log.w(TAG, "setNoiseSuppressorEnabled failed: ${e.message}")
            false
        }
    }

    /// WebRTC가 만든 로컬 오디오 트랙에 귀를 붙인다.
    private fun start(trackId: String): Boolean {
        stop()
        val plugin = FlutterWebRTCPlugin.sharedSingleton
        if (plugin == null) {
            Log.w(TAG, "FlutterWebRTCPlugin not initialised")
            return false
        }
        val local = plugin.getLocalTrack(trackId)
        if (local !is LocalAudioTrack) {
            Log.w(TAG, "track $trackId is not a LocalAudioTrack (got $local)")
            return false
        }

        framesIn = 0
        samplesOut = 0
        loggedFormat = false
        batch.clear()
        resampler = null

        val newSink = object : AudioTrackSink {
            override fun onData(
                audioData: ByteBuffer,
                bitsPerSample: Int,
                sampleRate: Int,
                numberOfChannels: Int,
                numberOfFrames: Int,
                absoluteCaptureTimestampMs: Long
            ) {
                // ⚠️ WebRTC 오디오 스레드다. 막으면 통화가 밀린다.
                //   변환은 싸고, Dart 전달만 메인 스레드로 넘긴다.
                if (bitsPerSample != 16) {
                    if (!loggedFormat) {
                        loggedFormat = true
                        Log.w(TAG, "unsupported bitsPerSample=$bitsPerSample")
                    }
                    return
                }
                handleFrame(audioData, sampleRate, numberOfChannels, numberOfFrames)
            }
        }
        local.addSink(newSink)
        attachedTrack = local
        sink = newSink
        Log.i(TAG, "attached to track=$trackId")
        return true
    }

    private fun handleFrame(
        audioData: ByteBuffer,
        sampleRate: Int,
        channels: Int,
        frames: Int
    ) {
        framesIn++
        if (!loggedFormat) {
            loggedFormat = true
            Log.i(
                TAG,
                "capture format rate=$sampleRate channels=$channels " +
                    "frames=$frames -> target=$TARGET_SAMPLE_RATE mono"
            )
        }

        val buf = audioData.duplicate().order(ByteOrder.LITTLE_ENDIAN)
        val shorts = buf.asShortBuffer()
        val total = shorts.remaining()
        if (total <= 0 || channels <= 0) return

        // ① 모노로 합친다. WebRTC가 스테레오를 줄 수도 있다.
        val frameCount = total / channels
        val mono = ShortArray(frameCount)
        if (channels == 1) {
            shorts.get(mono, 0, frameCount)
        } else {
            var idx = 0
            for (i in 0 until frameCount) {
                var acc = 0
                for (c in 0 until channels) acc += shorts.get(idx++).toInt()
                mono[i] = (acc / channels).toShort()
            }
        }

        // ② 저역통과 후 24kHz로 다시 뽑는다.
        val rs = resampler ?: Resampler(sampleRate, TARGET_SAMPLE_RATE).also {
            resampler = it
        }
        if (rs.inputRate != sampleRate) {
            // 통화 도중 레이트가 바뀌면 필터 상태를 새로 잡는다.
            resampler = Resampler(sampleRate, TARGET_SAMPLE_RATE)
        }
        val out = resampler!!.process(mono)
        if (out.isEmpty()) return

        // ③ 40ms로 묶어 Dart로 넘긴다.
        synchronized(batch) {
            for (s in out) batch.add(s)
            while (batch.size >= batchTarget) {
                val chunk = ShortArray(batchTarget)
                for (i in 0 until batchTarget) chunk[i] = batch[i]
                repeat(batchTarget) { batch.removeAt(0) }
                emit(chunk)
            }
        }
    }

    private fun emit(pcm: ShortArray) {
        samplesOut += pcm.size
        val bytes = ByteArray(pcm.size * 2)
        val bb = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        for (s in pcm) bb.putShort(s)
        mainHandler.post {
            eventSink?.success(bytes)
        }
    }

    fun stop() {
        val track = attachedTrack
        val s = sink
        attachedTrack = null
        sink = null
        if (track != null && s != null) {
            try {
                track.removeSink(s)
            } catch (e: Exception) {
                Log.w(TAG, "removeSink failed: ${e.message}")
            }
        }
        synchronized(batch) { batch.clear() }
        resampler = null
        if (track != null) {
            Log.i(TAG, "detached framesIn=$framesIn samplesOut=$samplesOut")
        }
    }

    // ========================================================================
    // 🔻 저역통과 + 리샘플
    // ------------------------------------------------------------------------
    // 48k → 24k는 정확히 2:1이라 "한 샘플 걸러 버리기"로도 숫자는 맞는다.
    // 하지만 그러면 12~24kHz가 통과 대역으로 접혀 들어온다. 그래서 먼저
    // 12kHz에서 자르고 그다음에 다시 뽑는다.
    //
    // 기기가 48k가 아닌 값을 줄 수도 있으므로(44.1k 등) 2:1을 가정하지 않고
    // 분수 위치로 뽑는다. 필터가 이미 걸린 뒤라 선형 보간으로 충분하다.
    // ========================================================================
    private class Resampler(val inputRate: Int, private val outputRate: Int) {
        private val coeffs: DoubleArray = designLowPass(inputRate, outputRate)
        private val history = ShortArray(FIR_TAPS)
        private var historyFilled = 0
        private var position = 0.0
        private val step = inputRate.toDouble() / outputRate.toDouble()

        /// 필터를 통과시킨 뒤 24kHz 격자 위의 값을 뽑는다.
        fun process(input: ShortArray): ShortArray {
            if (input.isEmpty()) return ShortArray(0)
            if (inputRate == outputRate) return input

            // 필터를 먹인 결과를 잠깐 담아 둔다(조각 하나 분량뿐이다).
            val filtered = DoubleArray(input.size)
            for (i in input.indices) {
                // 이동 평균창을 갱신한다.
                System.arraycopy(history, 1, history, 0, FIR_TAPS - 1)
                history[FIR_TAPS - 1] = input[i]
                if (historyFilled < FIR_TAPS) historyFilled++
                var acc = 0.0
                for (t in 0 until FIR_TAPS) acc += coeffs[t] * history[t]
                filtered[i] = acc
            }

            val out = ArrayList<Short>(input.size * outputRate / inputRate + 2)
            while (position < filtered.size - 1) {
                val i = position.toInt()
                val frac = position - i
                val v = filtered[i] * (1.0 - frac) + filtered[i + 1] * frac
                out.add(v.roundToInt().coerceIn(-32768, 32767).toShort())
                position += step
            }
            // 다음 조각으로 위치를 이어 간다.
            position -= filtered.size
            if (position < 0) position = 0.0

            val arr = ShortArray(out.size)
            for (i in out.indices) arr[i] = out[i]
            return arr
        }

        companion object {
            /// 창 함수를 씌운 sinc 저역통과. 차단 주파수는 출력 나이퀴스트다.
            fun designLowPass(inputRate: Int, outputRate: Int): DoubleArray {
                val cutoff = (outputRate / 2.0) / inputRate // 정규화 (cycles/sample)
                val m = FIR_TAPS - 1
                val h = DoubleArray(FIR_TAPS)
                var sum = 0.0
                for (n in 0 until FIR_TAPS) {
                    val x = n - m / 2.0
                    val sinc = if (abs(x) < 1e-9) {
                        2.0 * cutoff
                    } else {
                        sin(2.0 * PI * cutoff * x) / (PI * x)
                    }
                    // 해밍 창 — 사이드로브를 눌러 고역이 접혀 오는 것을 막는다.
                    val w = 0.54 - 0.46 * kotlin.math.cos(2.0 * PI * n / m)
                    h[n] = sinc * w
                    sum += h[n]
                }
                // 이득을 1로 맞춘다. 안 맞추면 전사 세기가 통째로 틀어진다.
                if (sum != 0.0) for (n in 0 until FIR_TAPS) h[n] /= sum
                return h
            }
        }
    }
}
