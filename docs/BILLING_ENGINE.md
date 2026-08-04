# 과금 엔진 동작 정리

`lib/custom_code/actions/billing_ticker.dart` 기준. 2026-08-04.

---

## 0. 정책 요약

- **배율은 하나뿐이다.** 과금이 걸리는 모든 화면이 정상 요금(1.0x). 0.25배 할인은 없다.
- **무과금은 딱 한 곳** — 히스토리(스터디룸) 첫 페이지, 전체 목록을 보는 화면.
  거기서 어디로든 들어가면 전부 과금된다. Keepers도 정상 과금.
- **Duo만 규칙이 다르다** — 게스트가 입장해야 시작, 게스트가 나갈 때만 정지.
  대화 중 1분을 가만히 있어도 정지하지 않는다. 게스트는 무료, 호스트만 부담.
- **나머지 공부방** — 입장 즉시 시작, 60초 무동작 시 일시정지, 움직이면 재개.

---

## 1. 심장: 1초 타이머

```dart
void start() {
  _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
}
```

`resume()`이 호출될 때 타이머가 없으면 시작한다.
**한 번 시작되면 앱이 살아있는 동안 계속 돈다.** `pause()`는 타이머를 끄지 않고
`_paused` 플래그만 세운다.

타이머가 계속 돌기 때문에 매 초 표시등을 다시 판정할 수 있다.

---

## 2. 매 틱에 일어나는 일

```dart
void _onTick() {
  _updateBillingState();            // ① 표시등 판정
  if (!_isActuallyBilling) return;  // ② 같은 조건으로 차감 여부 결정

  _fractionalDebt += _rate.multiplier;                // ③ 빚 누적
  final whole = _fractionalDebt.floor();
  if (whole >= 1) {
    FFAppState().remainingTime = before - whole;      // ④ 로컬 차감
    _unflushedDeducted += whole;                      // ⑤ 서버로 보낼 몫 적립
    remainingSecondsNotifier.value = next;            // ⑥ 화면 잔여시간 갱신
  }

  if (60초 경과) flushNow();                          // ⑦ 서버 반영
}
```

**③④** 배율이 1.0 하나뿐이라 매 틱 정확히 1초씩 깎인다.
`_fractionalDebt`는 0.25배 시절 소수점을 모으던 장치라 지금은 항상 `1.0 → whole=1`이다.

**⑤⑦** 매 초 서버를 때리지 않는다. 로컬에서 깎아 `_unflushedDeducted`에 쌓아두고
**60초마다 한 번** Cloud Function `deductRemainingTime`으로 보낸다.
화면 숫자는 즉각 줄지만 서버 반영은 1분 단위다.

`pause()` 때도 `flushNow()`가 불려서 방을 나가면 남은 몫이 바로 정산된다.

---

## 3. 초록불이 켜지는 조건

```dart
bool get _isActuallyBilling =>
    !_paused &&                                  // 정지 아님
    FFAppState().remainingTimeLoaded &&          // 잔여시간 로딩 완료
    !FFAppState().hasConfirmedZeroTime;          // 잔여시간 남아 있음
```

**이 getter 하나를 표시등과 차감이 같이 쓴다.**
①에서 표시등을 정하고 ②에서 차감 여부를 정하는데 같은 식이라 한쪽만 참일 수 없다.

### 예전 버그 (2026-08-04 수정)

표시등이 `_paused`만 봤다. 차감은 위 세 조건을 다 봤다. 그래서 갈렸다.

| 상황 | 실제 차감 | 표시등(전) | 표시등(후) |
|---|---|---|---|
| 정상 대화 | O | 초록 | 초록 |
| 60초 무동작 정지 | X | 회색 | 회색 |
| **잔여시간 0** | X | **초록(틀림)** | 회색 |
| **잔여시간 로딩 전** | X | **초록(틀림)** | 회색 |

차감되는데 꺼져 있는 반대 방향은 없었으므로 과금 안전에는 문제가 없었고,
표시 정확도만 어긋나 있었다.

---

## 4. 정지/재개를 부르는 주체

| 주체 | 정지 | 재개 |
|---|---|---|
| 모드 입·퇴장 | 방 나갈 때 `pause()` | 입장 시 `resume()` + `logMode()` |
| 60초 무동작 | 각 모드 `_idleTick()` → `pause()` | `resumeFromActivity()` |
| 앱 백그라운드 | 3초 유예 후 `_pauseFromLifecycle()` | 복귀 시 자동 `resume()` |
| Duo 게스트 | 게스트 퇴장 | 게스트 입장 |

`resumeFromActivity(reason)`가 STT 결과, 마이크 시작, TTS 재생 등 곳곳에 박혀 있어
유저가 뭐라도 하면 되살아난다. 인자로 넘긴 이유가 로그에 남는다.

### 백그라운드 3초 유예

앱을 내리자마자 끊으면 권한 팝업이나 잠깐의 화면 전환에도 과금이 끊겼다 붙었다 한다.
그래서 3초 기다렸다가 진짜 나간 게 맞으면 정지한다.
3초 안에 돌아오면 `_cancelLifecyclePause()`로 취소된다.

---

## 5. 화면 표시

```dart
ValueListenableBuilder<int>(
  valueListenable: BillingTicker.instance.billingState,
  builder: (_, s, __) => CustomPaint(painter: BillingDotPainter(s)),
)
```

7개 화면(써클톡·시나리오톡·스탭익스팬드·Duo·히스토리·히스토리 목록·스텔스룸 메뉴)이
전부 엔진의 `ValueNotifier`를 직접 구독한다. 복사본이나 캐시가 없어 즉시 반영된다.

`billingState` 값: `0` = 차감 안 함, `2` = 차감 중.
(`1`은 예전 quarter 배율 자리. 배율이 하나로 합쳐져 더 이상 쓰지 않는다.)

`_updateBillingState()`는 값이 실제로 바뀔 때만 쓰기 때문에 매 초 판정해도
초당 리빌드가 일어나지 않는다.

```dart
if (billingState.value == next) return;   // 같으면 안 건드림
```

---

## 6. 로그로 검증하는 법

```
[BILLING] mode=free_talk (session start before=3600 rate=1.0)
[BILLING] resume
[BILLING] indicator=on            <- 초록불 켜짐
[BILLING] tick before=3600 after=3599
[BILLING] tick before=3599 after=3598
...
[BILLING] firestore save success  <- 60초마다
[BILLING] pause
[BILLING] indicator=off           <- 초록불 꺼짐
[USAGE_LOG] saved mode=free_talk seconds_used=124s actual=124s
```

**`indicator=on` 구간과 `tick` 구간이 항상 일치해야 정상이다.**
시간이 0이 되면 `indicator=off`가 찍히고 그 뒤로 `tick`이 안 나와야 한다.

---

## 7. 사용시간 이력

`pause()` 때마다 `saveUsageLog()`가 불려 Cloud Function `logUsageSession`으로
한 세션의 사용 이력을 남긴다. 중복 저장은 `_usageLogSaved` 플래그로 막는다.

- `seconds_used` — 실제 차감된 초 (before - after)
- `actual_seconds` — 벽시계 경과 초
- 차감이 없으면(`seconds_used <= 0`) 저장하지 않는다
