# 후속 이슈 — Duo presence: 호스트 이탈을 못 잡는 세 경우 (2026-08-17)

브랜치 `auth-google-provider`. **1차 Always-on 통역 구현에서 의도적으로 제외한 항목이다.**

> 이 문서는 고친 것이 아니라 **안 고치기로 한 것**의 기록이다. 2차에서 이 문서부터 읽는다.

---

## §1 한 줄 요약

Duo의 상대 presence는 **`duo_sessions/{roomId}` 문서의 존재 여부** 하나에 걸려 있다.
문서가 지워지지 않는 종료 경로가 셋 있고, 그 경우 게스트 화면의 마이크 상태등이
**밝은 채로 남는다** — "지금 말하면 된다"고 말하지만 받는 사람이 없다.

만능 통역에만 해당한다. 직접 대화는 릴레이 WebSocket의 `onPartnerPresence`가
소켓 단절을 즉시 알려주므로 이 문제가 없다.

---

## §2 삭제가 보장되는 경로 / 안 되는 경로

호스트일 때 문서를 지우는 곳은 `_handleAutoSaveAndExit` 한 자리뿐이다
(`lib/custom_code/widgets/routine_mode_duo.dart`).

| 종료 경로 | 문서 삭제 | 근거 |
| --- | --- | --- |
| 뒤로가기 / PopScope | ✅ | `onPopInvoked` → `_handleAutoSaveAndExit` |
| 게스트 퇴장 (대칭 종료) | ✅ | `_listenForPartnerJoined`의 `guestJustLeft` |
| 잔여시간 소진 | ✅ | `StealthRoomMaster._onBalanceExhausted` → `saveAndExitCurrentMode` |
| 맛보기 타이머 만료 | ✅ | 트라이얼 타이머 (직접 통화 전용) |
| **일반 호스트 앱 백그라운드** | ❌ | §3 |
| **앱 강제 종료** | ❌ | 문서에 presence·TTL이 없다 |
| **네트워크 단절** | ❌ | 위와 같음 |

## §3 백그라운드가 뚫린 이유

`didChangeAppLifecycleState`의 분기다.

```dart
if (_isTrialHost && _trialCallStarted) { ...exit...; return; }
if (!FFAppState().isGuestSession) return;   // ← 일반 호스트는 여기서 끝난다
if (state == paused) unawaited(_handleAutoSaveAndExit());
```

**맛보기 호스트와 초대 게스트만** 백그라운드에서 방을 닫는다. 일반 호스트는
앱을 내려도 방이 그대로 살아 있다. `StealthRoomMaster`의 lifecycle 핸들러도
`BillingTicker.flushNow()`만 하고 방은 건드리지 않는다.

셋 중 백그라운드만 **흔한 일**이다. 강제 종료와 네트워크 단절은 heartbeat 없이는
원리상 못 잡는다.

---

## §4 1차에서 하지 않기로 한 것 (2026-08-17 실장님 결정)

Always-on 통역의 실기기 검증 변수를 늘리지 않기 위해 presence 문제를 분리했다.
**아래는 이번 빌드에 넣지 않는다.**

- 일반 호스트가 background로 가는 즉시 방 종료
  → 알림 확인이나 잠깐 앱 전환만으로 방이 닫힌다. UX가 너무 강하다.
- 게스트의 단순 무활동 시간만으로 호스트 이탈 판단
  → **사람이 조용히 있는 정상 상황과 구분되지 않는다.**
- 임의의 N초 timeout으로 세션 종료
- Direct Talk lifecycle 동작 변경

## §5 2차 검토 방향

단순 timeout보다 **heartbeat 또는 명시적 readiness/presence 동기화**를 우선 본다.
1차 조사 때 미룬 `hostInterpReady`/`guestInterpReady` 필드 논의와 같은 자리에서
설계한다 — 둘 다 "상대가 지금 살아 있는가"를 문서로 주고받는 문제다.

실기기 1차 검증에서 **발화 유실이 실제로 관측되면** readiness 동기화의 우선순위가
올라간다. 유실이 없으면 presence만 따로 처리해도 된다.

---

## §6 곁다리 — 같이 미뤄 둔 것

조사 중 발견했으나 이번 작업 범위에서 뺀 History 버그가 하나 있다.

`_saveHistoryMessage`는 `nativeLang == targetLang`이면 `original_text`를 빈
문자열로 만든다. ORIGIN과 TARGET을 같게 설정한 사용자는 만능 통역 히스토리의
원문 칸이 빈다. 오디오와 무관하고 통역 동작에도 영향이 없다. 별도 수정 건.
