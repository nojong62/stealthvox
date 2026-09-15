// ====================================================================
// 💾 [ORIGIN-PCM] 발화별 음성을 **원문 복원이 끝날 때까지만** 들고 있는 창고
// --------------------------------------------------------------------
// 대화방은 발화마다 PCM을 gpt-transcribe에 올리고, 다 쓰면 곧바로 버린다
// (`_resetTurnPcmBuffer`). 그래서 대화가 끝난 뒤 "17번 발화의 '네가'가 정말
// 네가였나"를 물을 방법이 없었다. 되물을 소리가 남아 있지 않으니 남는 길은
// 문맥만 보고 고치는 것뿐이고, 그것은 **하지 않은 말을 지어내는 지름길이다.**
//
// 이 창고는 그 소리를 잠깐 남긴다. 전사에 올린 바로 그 바이트를 파일로도
// 써 두고, 복원이 끝나면 지운다.
//
//   대화방   put(roomId, seq, pcm)     전사와 같은 바이트. 기다리지 않는다.
//   복원     read(roomId, seq)         의심 가는 발화만 꺼내 다시 듣는다.
//   복원 끝  discard(roomId)           **Final Origin이 확정되면 즉시.**
//   앱 시작  cleanupOnce()             놓친 것을 나이로 회수한다.
//
// ⚠️ **Documents가 아니라 Temporary에 쓴다.** Documents는 iOS에서 iCloud
//    백업 대상이라, 사용자 음성 원본이 백업에 실린다. TTS 캐시가 Documents에
//    있다고 따라가면 안 되는 이유가 이것이다. Temporary는 OS가 압박을 받으면
//    임의로 비우는데, 그것은 이 설계에서 결함이 아니라 마지막 안전망이다 —
//    파일이 사라지면 그 의심점이 강등될 뿐 복원은 계속 돈다.
//
// 🚫 **서버로 나가지 않는다.** 업로드 경로를 만들지 않는 것이 이 파일이 지는
//    유일한 약속이다.
//
// ⚠️ **이 층에는 판정이 하나도 없다.** 받아서 쓰고, 달라면 주고, 끝나면
//    지운다. 무엇이 의심스러운지, 무엇을 고칠지는 복원 쪽 일이다.
// ====================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'pcm_audio_utils.dart';

/// 창고 뿌리 폴더 이름.
const String kOriginPcmDirName = 'origin_pcm';

/// 방이 아직 없을 때 쓰는 자리.
///
/// 첫 발화는 대개 이름·장소·주제처럼 **뒤따르는 모든 줄의 기준**이 되는
/// 내용이라, 방이 늦게 만들어진다는 이유로 버리기엔 아깝다.
const String kOriginPcmPendingDir = '_pending';

/// 한 방이 쓸 수 있는 최대 바이트. 10분 세션이 약 8.6MB이므로 정상 대화는
/// 닿지 않는다. **닿았다면 그것은 비정상 신호다** — 그래서 오래된 것을 버리고
/// 자리를 내주는 대신 **더 쓰지 않는다.** 이미 확보한 소리를 잃는 쪽이 나쁘다.
const int kOriginPcmSessionMaxBytes = 40 * 1024 * 1024;

/// 창고 전체 상한. 청소 뒤에도 넘치면 오래된 방부터 통째로 버린다.
const int kOriginPcmGlobalMaxBytes = 200 * 1024 * 1024;

/// 이만큼 지난 방 폴더는 주인이 없다고 본다.
const Duration kOriginPcmMaxAge = Duration(hours: 24);

/// 📌 [TRANSCRIBE-STATE] 방 하나의 전사가 어디까지 갔는가.
///
/// **아직 아무도 쓰지 않는다.** 통화 후 일괄 전사(다음 판)가 쓸 자리를 미리
/// 이름만 정해 두는 것이고, 지금 이 판에서 상태 기계를 세우지 않는다.
///
/// 이 값이 필요한 이유는 하나다 — 그 구조에서는 PCM이 **원본**이라, 전사가
/// 끝나기 전에 소리가 사라지면 그 발화의 글자가 영영 안 생긴다. 그때
/// "이 방은 아직 전사를 기다리는 중"이라고 말할 칸이 있어야 청소기도
/// 화면도 그 사실을 알 수 있다.
const String kRoomTranscriptionStateField = 'duo_transcription_state';

/// 소리는 모았고 글자는 아직이다. **이 방의 PCM을 지우면 안 된다.**
const String kRoomTranscriptionPending = 'pending';

/// 모든 발화가 글자를 가졌다. 이제 소리를 지워도 된다.
const String kRoomTranscriptionComplete = 'complete';

/// 일부 발화가 끝내 글자를 못 가졌다(용량 초과·파일 소실·전사 실패).
/// **완료와 갈라 둔다** — 지우는 판단이 둘을 같게 보면 안 된다.
const String kRoomTranscriptionIncomplete = 'incomplete';

/// 보존한 발화 수와 글자를 가진 발화 수로 방의 상태를 읽는다.
///
/// 순수 함수다. 다음 판이 실제 숫자를 넣어 부르면 되고, 지금은 이름과
/// 규칙만 굳혀 둔다. [lost]는 보존 자체를 못 한 발화 수다(용량 초과 등).
String resolveRoomTranscriptionState({
  required int captured,
  required int transcribed,
  required int lost,
}) {
  if (captured <= 0 && lost <= 0) return kRoomTranscriptionComplete;
  if (transcribed < captured) return kRoomTranscriptionPending;
  // 소리를 못 남긴 발화가 있으면 **다 전사해도 완료가 아니다.**
  return lost > 0 ? kRoomTranscriptionIncomplete : kRoomTranscriptionComplete;
}

/// 저장이 실패한 까닭.
class OriginPcmStoreFailure {
  const OriginPcmStoreFailure({
    required this.roomId,
    required this.pcmKey,
    required this.reason,
    required this.bytes,
  });

  final String roomId;

  /// 못 담은 발화의 열쇠. Duo에서는 발화 id(`duo_direct_utt_7`)다.
  final String pcmKey;

  /// `capacity` — 방 상한을 넘었다. `write_failed` — 디스크·권한 문제다.
  final String reason;
  final int bytes;
}

/// 상한 초과 사유. 로그와 콜백이 같은 글자를 쓴다.
const String kOriginPcmFailCapacity = 'capacity';
const String kOriginPcmFailWrite = 'write_failed';

/// 발화 열쇠를 **파일 이름으로 안전한 글자**만 남긴다.
///
/// 이 값이 곧 파일 이름이 되므로, 경로 구분자나 상위 폴더 표기가 섞이면
/// 창고 밖에 파일을 쓰게 된다. 열쇠는 우리가 만든 발화 id(`duo_direct_utt_7`)
/// 아니면 순번이라 정상 입력은 한 글자도 안 바뀐다.
String sanitizeOriginPcmKey(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  final safe = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  // 점만으로 이뤄진 이름(`.`, `..`)은 폴더를 가리킨다.
  if (safe.replaceAll('_', '').isEmpty) return '';
  return safe.length > 80 ? safe.substring(0, 80) : safe;
}

/// 발화 하나.
@immutable
class OriginPcmTurn {
  const OriginPcmTurn({
    required this.key,
    required this.file,
    required this.ms,
    required this.bytes,
  });

  /// 이 발화를 가리키는 열쇠. 대화 기록의 `pcm_key`와 같은 값이다.
  final String key;
  final String file;
  final int ms;
  final int bytes;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'key': key,
        'file': file,
        'ms': ms,
        'bytes': bytes,
      };

  static OriginPcmTurn? fromJson(Object? raw) {
    if (raw is! Map) return null;
    // 순번만 적던 시절의 매니페스트도 읽는다. 못 읽으면 스캔으로 돌아가므로
    // 치명적이지는 않지만, 굳이 버릴 이유도 없다.
    final legacy = raw['seq'];
    final key = (raw['key'] ??
            (legacy is int ? 'turn_${legacy.toString().padLeft(3, '0')}' : ''))
        .toString();
    final file = raw['file'];
    if (key.isEmpty || file is! String || file.isEmpty) return null;
    return OriginPcmTurn(
      key: key,
      file: file,
      ms: raw['ms'] is int ? raw['ms'] as int : 0,
      bytes: raw['bytes'] is int ? raw['bytes'] as int : 0,
    );
  }
}

/// 방 하나에 무엇이 남아 있는가.
@immutable
class OriginPcmManifest {
  const OriginPcmManifest({
    required this.roomId,
    required this.turns,
    required this.dropped,
    required this.totalBytes,
  });

  const OriginPcmManifest.empty(this.roomId)
      : turns = const <OriginPcmTurn>[],
        dropped = const <String>[],
        totalBytes = 0;

  final String roomId;
  final List<OriginPcmTurn> turns;

  /// 세션 상한에 걸려 **아예 쓰지 못한** 발화 열쇠.
  ///
  /// "파일이 없다"와 갈라 두는 값이다. 여기 없는데 파일도 없으면 OS가 지운
  /// 것이고, 여기 있으면 우리가 안 쓴 것이다. 로그에서 이 둘이 섞이면 창고가
  /// 새는 것인지 상한이 낮은 것인지 알 수 없다.
  final List<String> dropped;

  final int totalBytes;

  bool get isEmpty => turns.isEmpty;

  OriginPcmTurn? turnOf(String key) {
    final clean = sanitizeOriginPcmKey(key);
    for (final t in turns) {
      if (t.key == clean) return t;
    }
    return null;
  }
}

/// 발화별 PCM 임시 창고.
///
/// 뿌리 폴더를 주입받는다 — 테스트가 `Directory.systemTemp`를 넘겨 실제 파일
/// 입출력을 그대로 검증할 수 있고, `path_provider`를 흉내 낼 필요가 없다.
/// 주입하지 않으면 [getTemporaryDirectory]를 쓴다.
class OriginPcmStore {
  OriginPcmStore._();

  static final OriginPcmStore instance = OriginPcmStore._();

  /// 테스트용 뿌리. null이면 [getTemporaryDirectory].
  static Directory? debugRootOverride;

  /// 창고를 아예 끈다. 복원 기능이 붙기 전에 문제가 생기면 여기를 내린다.
  static bool enabled = true;

  /// 앱 실행당 한 번인 청소를 이미 돌렸는가.
  static bool _cleanedOnce = false;

  /// 방별 쓰기 직렬화. `put`이 `unawaited`로 불려 여러 개가 겹치면 매니페스트가
  /// 서로를 덮어쓴다.
  final Map<String, Future<void>> _chains = <String, Future<void>>{};

  /// 방별 누적 바이트. 상한 판정이 매번 디렉터리를 훑지 않게 들고 있는다.
  final Map<String, int> _bytes = <String, int>{};

  /// 상한에 걸려 못 쓴 발화 열쇠.
  final Map<String, List<String>> _dropped = <String, List<String>>{};

  /// 상한에 부딪힌 횟수. 실측 로그로 나간다.
  final Map<String, int> _limitHits = <String, int>{};

  /// 🔔 [STORE-FAIL] 발화 하나를 못 담았다. **동기 콜백이다** — 여기서
  /// 기다리는 일을 하면 그 지연이 통화 오디오 경로에 실린다([_noteFailure]).
  ///
  /// 붙이지 않아도 창고는 그대로 돈다. 로그는 콜백과 무관하게 언제나 남는다.
  void Function(OriginPcmStoreFailure failure)? onStoreFailed;

  /// 이 방에서 **끝내 못 담은** 발화들. 통화가 끝난 뒤에 읽는다.
  ///
  /// 매니페스트의 `dropped`와 같은 값이고, 그쪽은 앱이 죽어도 남는다
  /// ([OriginPcmManifest.dropped]). 통화 중에 굳이 파일을 읽을 이유가 없어
  /// 메모리 쪽을 먼저 본다.
  List<String> droppedKeysOf(String roomId) {
    final key = roomId.trim().isEmpty ? kOriginPcmPendingDir : roomId.trim();
    return List<String>.unmodifiable(_dropped[key] ?? const <String>[]);
  }

  /// 이 방의 소리가 **온전한가.** 거짓이면 못 담은 발화가 있다.
  bool isRoomPcmComplete(String roomId) => droppedKeysOf(roomId).isEmpty;

  // ══════════════════════════════════════════════════════════════════
  // 쓰기
  // ══════════════════════════════════════════════════════════════════

  /// 전사에 올린 그 바이트를 그대로 받는다.
  ///
  /// **던지지 않는다.** 디스크가 가득 찼든 권한이 없든, 대화가 먼저다. 못 쓴
  /// 발화는 복원 때 "PCM 없음"으로 처리되어 원문이 그대로 남는다.
  ///
  /// 호출부는 `unawaited`로 부른다 — 전사를 한 밀리초도 늦추지 않는다.
  ///
  /// ⚠️ **여기서 곧바로 WAV로 감싼다.** 쓰기는 큐를 거쳐 나중에 일어나므로,
  /// 감싸는 일을 뒤로 미루면 그 사이 호출부가 버퍼를 되쓸 때 **전사에 올린
  /// 소리와 파일에 남는 소리가 갈린다.** 어차피 만들어야 하는 배열이라
  /// 방어적 복사가 공짜로 딸려온다 — 저장되는 것은 언제나 put을 부른 순간의
  /// 소리다.
  Future<void> put(String roomId, int seq, Uint8List pcm) =>
      putKeyed(roomId, seq > 0 ? _seqKey(seq) : '', pcm);

  /// 발화를 **문자열 열쇠**로 담는다.
  ///
  /// Duo는 이미 `duo_direct_utt_7` 같은 발화 id를 갖고 있다. 그것을 그대로
  /// 열쇠로 쓰면 번호를 새로 매길 필요가 없고, 창고와 대화 기록이 같은
  /// 이름으로 같은 발화를 가리킨다.
  Future<void> putKeyed(String roomId, String pcmKey, Uint8List pcm) {
    final clean = sanitizeOriginPcmKey(pcmKey);
    if (!enabled || pcm.isEmpty || clean.isEmpty) return Future<void>.value();
    final key = roomId.trim().isEmpty ? kOriginPcmPendingDir : roomId.trim();
    final wav = pcm16ToWav(pcm, sampleRate: kStealthVoxSttSampleRate);
    return _serialize(key, () => _putInner(key, clean, wav));
  }

  Future<void> _putInner(String key, String pcmKey, Uint8List wavBytes) async {
    try {
      final int used = _bytes[key] ?? await _measure(key);
      final int wav = wavBytes.lengthInBytes;
      if (used + wav > kOriginPcmSessionMaxBytes) {
        // 🚧 상한. **여기서 멈추는 것은 보존뿐이다** — 전사도 대화도 그대로
        //   간다. 이미 써 둔 파일을 지워 자리를 내주지도 않는다.
        (_dropped[key] ??= <String>[]).add(pcmKey);
        _limitHits[key] = (_limitHits[key] ?? 0) + 1;
        if (_limitHits[key] == 1) {
          debugPrint('[ORIGIN-PCM] session_limit room=$key '
              'used=${_mb(used)}MB cap=${_mb(kOriginPcmSessionMaxBytes)}MB '
              '- 이후 발화는 보존하지 않는다');
        }
        // 🔔 [STORE-FAIL] **발화마다 남긴다.** 예전에는 방마다 첫 한 줄만
        //   나가서, 두 번째 이후로 못 담은 발화가 무엇이었는지 로그에 없었다.
        //   지금은 재검증을 못 하는 정도지만, 통화 후 일괄 전사로 가면 이
        //   발화들은 **글자 자체가 안 생긴다.** 그때 어느 발화였는지 모르면
        //   무엇이 사라졌는지도 모른다.
        _noteFailure(key, pcmKey, kOriginPcmFailCapacity, wav);
        await _writeManifest(key);
        return;
      }
      final dir = await _dirFor(key);
      final file = File('${dir.path}/${_fileNameOf(pcmKey)}');
      // flush: true — 복원은 대화가 끝나자마자 시작한다. OS 캐시에만 있는
      // 파일을 두고 [flush]가 "다 썼다"고 말하면, 그 보장이 반 걸음 모자란다.
      await file.writeAsBytes(wavBytes, flush: true);
      _bytes[key] = used + wav;
      await _writeManifest(key);
      // 🔎 [계측] **담긴 소리의 길이.** 실기기에서 "마이크가 잰 길이 →
      //   창고에 남은 길이 → 재전사가 들은 길이"를 한 줄로 잇는 근거다.
      //   실패만 찍던 시절에는 어느 발화가 얼마나 담겼는지 알 길이 없었다.
      debugPrint('[ORIGIN-PCM] stored room=$key key=$pcmKey '
          'ms=${pcm16DurationMs(wav - 44, sampleRate: kStealthVoxSttSampleRate)} '
          'bytes=$wav');
    } catch (error) {
      debugPrint('[ORIGIN-PCM] put_failed room=$key key=$pcmKey '
          'reason=${error.runtimeType}');
      // 디스크가 가득 찼거나 권한이 없다. 상한과 **같은 무게의 손실**이므로
      // 같은 자리에 남긴다 — 이 발화도 소리를 잃었다.
      (_dropped[key] ??= <String>[]).add(pcmKey);
      _noteFailure(key, pcmKey, kOriginPcmFailWrite, wavBytes.lengthInBytes);
    }
  }

  /// 🔔 [STORE-FAIL] 못 담았다는 사실을 **기다리게 하지 않고** 알린다.
  ///
  /// ⚠️ **여기서 무엇도 await하지 않는다.** 이 경로는 통화 중 마이크 갈래가
  /// `unawaited`로 부르는 자리라(`putKeyed`의 계약), 알림이 한 번이라도
  /// 기다리는 순간 그 지연이 오디오 경로에 실린다. 알리는 쪽이 늦으면
  /// 늦었지, 통화가 늦으면 안 된다.
  void _noteFailure(String key, String pcmKey, String reason, int bytes) {
    debugPrint('[DUO-PCM] store_failed room=$key utterance=$pcmKey '
        'reason=$reason bytes=$bytes');
    final sink = onStoreFailed;
    if (sink == null) return;
    try {
      sink(OriginPcmStoreFailure(
        roomId: key,
        pcmKey: pcmKey,
        reason: reason,
        bytes: bytes,
      ));
    } catch (_) {
      // 듣는 쪽이 터져도 창고는 계속 돈다.
    }
  }

  /// 방이 생기기 전에 받아 둔 발화를 실제 방으로 옮긴다.
  ///
  /// 옮기기가 실패하면 그 발화만 잃는다. **방이 이미 쓰고 있는 번호는 덮지
  /// 않는다** — 같은 번호가 양쪽에 있으면 방 것이 옳다.
  Future<void> adoptPending(String roomId) {
    final key = roomId.trim();
    if (!enabled || key.isEmpty || key == kOriginPcmPendingDir) {
      return Future<void>.value();
    }
    return _serialize(key, () => _adoptInner(key));
  }

  Future<void> _adoptInner(String roomId) async {
    try {
      final pending = await _roomDir(kOriginPcmPendingDir);
      if (!await pending.exists()) return;
      final target = await _dirFor(roomId);
      var moved = 0;
      final entries = await pending.list().toList();
      for (final entity in entries) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.endsWith('.wav')) continue;
        final dest = File('${target.path}/$name');
        if (await dest.exists()) continue;
        try {
          await entity.rename(dest.path);
          moved++;
        } catch (_) {
          // 다른 볼륨이면 rename이 안 된다. 복사한 뒤 지운다.
          try {
            await dest.writeAsBytes(await entity.readAsBytes(), flush: false);
            await entity.delete();
            moved++;
          } catch (_) {}
        }
      }
      // 옮긴 뒤 남은 것(매니페스트 등)은 통째로 버린다.
      try {
        await pending.delete(recursive: true);
      } catch (_) {}
      final pendingDropped = _dropped.remove(kOriginPcmPendingDir);
      if (pendingDropped != null && pendingDropped.isNotEmpty) {
        (_dropped[roomId] ??= <String>[]).addAll(pendingDropped);
      }
      _bytes.remove(kOriginPcmPendingDir);
      _limitHits.remove(kOriginPcmPendingDir);
      _bytes[roomId] = await _measure(roomId);
      await _writeManifest(roomId);
      if (moved > 0) {
        debugPrint('[ORIGIN-PCM] adopted room=$roomId turns=$moved');
      }
    } catch (error) {
      debugPrint('[ORIGIN-PCM] adopt_failed room=$roomId '
          'reason=${error.runtimeType}');
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // 읽기
  // ══════════════════════════════════════════════════════════════════

  /// 이 방의 밀린 쓰기가 전부 끝날 때까지 기다린다.
  ///
  /// **복원을 시작하기 직전에 딱 한 번 부른다.** 대화 중에는 절대 부르지
  /// 않는다 — [put]이 `unawaited`인 이유가 전사를 늦추지 않는 것인데, 여기서
  /// 기다리면 그 이유가 사라진다.
  ///
  /// 이 문이 없으면 마지막 발화에서 진다. `turn_100`의 쓰기가 아직 큐에 있는
  /// 채로 사용자가 대화를 끝내고, 복원이 곧바로 그 발화를 의심하면
  /// [read]가 null을 준다. 그러면 **소리가 있는데도 "PCM 없음"으로 강등되어**
  /// 고칠 수 있었던 낱말이 그대로 남는다. 기다리는 시간은 디스크 쓰기 몇
  /// 밀리초뿐이고, 그 시점에 사용자는 이미 대화를 끝냈다.
  Future<void> flush(String roomId) async {
    final key = roomId.trim().isEmpty ? kOriginPcmPendingDir : roomId.trim();
    // 기다리는 동안 새 쓰기가 체인에 붙을 수 있다. 체인이 더 자라지 않을
    // 때까지 따라간다. 대화가 끝난 뒤라 실제로는 한두 바퀴에 끝난다.
    for (var i = 0; i < 32; i++) {
      final chain = _chains[key];
      if (chain == null) return;
      try {
        await chain;
      } catch (_) {}
      if (identical(_chains[key], chain)) return;
    }
    debugPrint('[ORIGIN-PCM] flush_gave_up room=$key '
        '- 쓰기가 계속 붙는다. 복원은 있는 파일로 진행한다');
  }

  /// 의심 가는 발화 하나를 꺼낸다. **없으면 null이다.**
  ///
  /// 빈 바이트를 돌려주면 호출부가 무음을 전사기에 올리고 그 결과를 사람 말로
  /// 믿게 된다. 없는 것은 없다고 말한다.
  Future<Uint8List?> read(String roomId, int seq) =>
      readKeyed(roomId, seq > 0 ? _seqKey(seq) : '');

  Future<Uint8List?> readKeyed(String roomId, String pcmKey) async {
    final clean = sanitizeOriginPcmKey(pcmKey);
    if (roomId.trim().isEmpty || clean.isEmpty) return null;
    try {
      final dir = await _roomDir(roomId.trim());
      final file = File('${dir.path}/${_fileNameOf(clean)}');
      if (!await file.exists()) return null;
      return wavToPcm16(await file.readAsBytes());
    } catch (error) {
      debugPrint('[ORIGIN-PCM] read_failed room=$roomId key=$clean '
          'reason=${error.runtimeType}');
      return null;
    }
  }

  /// 무엇이 있고 무엇을 못 썼는가.
  ///
  /// 매니페스트가 깨져 있으면 **실제 파일 목록으로 되돌아간다** — 매니페스트는
  /// 편의이지 진실의 근거가 아니다.
  Future<OriginPcmManifest> manifest(String roomId) async {
    final key = roomId.trim();
    if (key.isEmpty) return OriginPcmManifest.empty(roomId);
    try {
      final dir = await _roomDir(key);
      if (!await dir.exists()) return OriginPcmManifest.empty(key);
      final parsed = await _readManifestFile(dir, key);
      if (parsed != null) return parsed;
      return OriginPcmManifest(
        roomId: key,
        turns: await _scanTurns(dir),
        dropped: List<String>.of(_dropped[key] ?? const <String>[]),
        totalBytes: await _sizeOf(dir),
      );
    } catch (error) {
      debugPrint('[ORIGIN-PCM] manifest_failed room=$key '
          'reason=${error.runtimeType}');
      return OriginPcmManifest.empty(key);
    }
  }

  Future<OriginPcmManifest?> _readManifestFile(
      Directory dir, String key) async {
    final file = File('${dir.path}/_manifest.json');
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final rawTurns = decoded['turns'];
      if (rawTurns is! List) return null;
      final turns = <OriginPcmTurn>[];
      for (final t in rawTurns) {
        final one = OriginPcmTurn.fromJson(t);
        if (one != null) turns.add(one);
      }
      final rawDropped = decoded['dropped'];
      return OriginPcmManifest(
        roomId: key,
        turns: turns,
        dropped: rawDropped is List
            ? rawDropped.map((e) => e.toString()).toList()
            : const <String>[],
        totalBytes: turns.fold<int>(0, (a, t) => a + t.bytes),
      );
    } catch (_) {
      debugPrint('[ORIGIN-PCM] manifest_corrupt room=$key '
          '- 파일 목록으로 대신한다');
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // 버리기
  // ══════════════════════════════════════════════════════════════════

  /// 이 방의 소리를 전부 지운다.
  ///
  /// **Final Canonical Origin이 확정되는 순간 부른다.** Final Target은 순수
  /// 텍스트 작업이라 소리가 필요 없고, 개인 음성을 필요보다 한 순간이라도 오래
  /// 들고 있을 이유가 없다. 복원이 실패해도 마찬가지로 부른다 — 같은 입력으로
  /// 같은 실패가 날 뿐이다.
  Future<void> discard(String roomId) async {
    final key = roomId.trim();
    if (key.isEmpty) return;
    try {
      final dir = await _roomDir(key);
      final int had = await _sizeOf(dir);
      if (await dir.exists()) await dir.delete(recursive: true);
      if (had > 0) {
        debugPrint('[ORIGIN-PCM] discarded room=$key freed=${_mb(had)}MB');
      }
    } catch (error) {
      debugPrint('[ORIGIN-PCM] discard_failed room=$key '
          'reason=${error.runtimeType}');
    } finally {
      _bytes.remove(key);
      _dropped.remove(key);
      _limitHits.remove(key);
      _chains.remove(key);
    }
  }

  /// 앱 실행당 한 번. 주인 없는 방을 나이로 회수한다.
  ///
  /// 판정 기준은 **나이 하나뿐이다.** 방 상태를 확인하려고 Firestore를 읽기
  /// 시작하면 앱 시작이 네트워크에 묶인다.
  static Future<void> cleanupOnce() async {
    if (_cleanedOnce) return;
    _cleanedOnce = true;
    await instance.cleanup();
  }

  /// 청소 본체. 테스트가 값을 바꿔 가며 부른다.
  Future<void> cleanup({
    Duration maxAge = kOriginPcmMaxAge,
    int maxBytes = kOriginPcmGlobalMaxBytes,
  }) async {
    try {
      final root = await _root();
      if (!await root.exists()) return;
      final now = DateTime.now();
      final alive = <Directory, DateTime>{};
      var freed = 0;

      // ⚠️ recursive: false로 방 폴더만 훑고, 크기·나이는 안에서 재귀로 잰다.
      //   이 저장소에는 하위 폴더를 못 보던 청소기가 릴리스에 그대로 들어간
      //   전례가 있다.
      final rooms = await root.list().toList();
      for (final entity in rooms) {
        if (entity is! Directory) continue;
        final DateTime touched = await _newestMtime(entity);
        if (now.difference(touched) > maxAge) {
          freed += await _sizeOf(entity);
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
          continue;
        }
        alive[entity] = touched;
      }

      // 살아남은 방들의 총량이 넘치면 오래된 방부터 통째로. 방 안에서 골라
      // 내지 않는다 — 반쯤 남은 방은 복원 품질만 흐리고 용량은 별로 줄지
      // 않는다.
      var total = 0;
      final sizes = <Directory, int>{};
      for (final dir in alive.keys) {
        final s = await _sizeOf(dir);
        sizes[dir] = s;
        total += s;
      }
      if (total > maxBytes) {
        final ordered = alive.keys.toList()
          ..sort((a, b) => alive[a]!.compareTo(alive[b]!));
        for (final dir in ordered) {
          if (total <= maxBytes) break;
          final s = sizes[dir] ?? 0;
          try {
            await dir.delete(recursive: true);
            total -= s;
            freed += s;
          } catch (_) {}
        }
      }

      if (freed > 0) {
        debugPrint('[ORIGIN-PCM] cleanup freed=${_mb(freed)}MB '
            'remaining=${_mb(total)}MB');
      }
    } catch (error) {
      debugPrint('[ORIGIN-PCM] cleanup_failed reason=${error.runtimeType}');
    }
  }

  /// 실측용 한 줄. 세션이 끝날 때 대화방이 부른다.
  ///
  /// 24시간·200MB·40MB는 근거 있는 측정값이 아니라 보호용 출발점이다. 이
  /// 네 숫자가 쌓여야 실제 값으로 바꿀 수 있다.
  void logSnapshot(String roomId) {
    final key = roomId.trim().isEmpty ? kOriginPcmPendingDir : roomId.trim();
    debugPrint('[ORIGIN-PCM] snapshot room=$key '
        'mb=${_mb(_bytes[key] ?? 0)} '
        'dropped=${(_dropped[key] ?? const <String>[]).length} '
        'limit_hits=${_limitHits[key] ?? 0}');
  }

  /// 테스트가 세션 상태를 초기화한다.
  @visibleForTesting
  void resetForTest() {
    _chains.clear();
    _bytes.clear();
    _dropped.clear();
    _limitHits.clear();
    _cleanedOnce = false;
  }

  // ══════════════════════════════════════════════════════════════════
  // 안쪽
  // ══════════════════════════════════════════════════════════════════

  Future<void> _serialize(String key, Future<void> Function() task) {
    final prev = _chains[key] ?? Future<void>.value();
    final next = prev.then((_) => task()).catchError((Object _) {});
    _chains[key] = next;
    return next;
  }

  Future<Directory> _root() async {
    final base = debugRootOverride ?? await getTemporaryDirectory();
    return Directory('${base.path}/$kOriginPcmDirName');
  }

  Future<Directory> _roomDir(String key) async =>
      Directory('${(await _root()).path}/$key');

  Future<Directory> _dirFor(String key) async {
    final dir = await _roomDir(key);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 순번을 열쇠로. 세 자리로 채워 폴더가 번호순으로 읽힌다.
  static String _seqKey(int seq) => 'turn_${seq.toString().padLeft(3, '0')}';

  String _fileNameOf(String pcmKey) => '$pcmKey.wav';

  Future<List<OriginPcmTurn>> _scanTurns(Directory dir) async {
    final turns = <OriginPcmTurn>[];
    try {
      final entries = await dir.list().toList();
      for (final e in entries) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        if (!name.endsWith('.wav')) continue;
        final int bytes = await e.length();
        turns.add(OriginPcmTurn(
          key: name.substring(0, name.length - 4),
          file: name,
          ms: pcm16DurationMs(
            bytes > 44 ? bytes - 44 : 0,
            sampleRate: kStealthVoxSttSampleRate,
          ),
          bytes: bytes,
        ));
      }
    } catch (_) {}
    turns.sort((a, b) => a.key.compareTo(b.key));
    return turns;
  }

  Future<void> _writeManifest(String key) async {
    try {
      final dir = await _roomDir(key);
      if (!await dir.exists()) return;
      final turns = await _scanTurns(dir);
      await File('${dir.path}/_manifest.json').writeAsString(
        jsonEncode(<String, dynamic>{
          'room_id': key,
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'sample_rate': kStealthVoxSttSampleRate,
          'turns': turns.map((t) => t.toJson()).toList(),
          'dropped': _dropped[key] ?? const <String>[],
        }),
        flush: false,
      );
    } catch (_) {
      // 매니페스트는 편의다. 못 써도 파일은 남아 있고 목록으로 읽힌다.
    }
  }

  Future<int> _measure(String key) async {
    try {
      return _sizeOf(await _roomDir(key));
    } catch (_) {
      return 0;
    }
  }

  Future<int> _sizeOf(Directory dir) async {
    var total = 0;
    try {
      if (!await dir.exists()) return 0;
      final entries = await dir.list(recursive: true).toList();
      for (final e in entries) {
        if (e is File) total += await e.length();
      }
    } catch (_) {}
    return total;
  }

  /// 이 방이 마지막으로 쓰인 때.
  ///
  /// **파일이 하나라도 있으면 파일들만 본다.** 폴더 자체의 mtime은 플랫폼마다
  /// 갱신 시점이 달라 믿을 수 없는데, 그것을 최댓값에 섞으면 반대 방향으로
  /// 틀린다 — 폴더가 새것으로 잡히는 플랫폼에서는 안의 파일이 아무리 늙어도
  /// 영영 회수되지 않아 창고가 조용히 샌다.
  ///
  /// 파일이 없는 빈 폴더일 때만 폴더 mtime으로 판정한다. 읽을 수 없으면
  /// **지금**으로 친다 — 판정하지 못하는 것을 지우지는 않는다.
  Future<DateTime> _newestMtime(Directory dir) async {
    DateTime? newest;
    try {
      final entries = await dir.list(recursive: true).toList();
      for (final e in entries) {
        if (e is! File) continue;
        final m = (await e.stat()).modified;
        if (newest == null || m.isAfter(newest)) newest = m;
      }
    } catch (_) {}
    if (newest != null) return newest;
    try {
      return (await dir.stat()).modified;
    } catch (_) {
      return DateTime.now();
    }
  }

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
}
