StealthVox 프로젝트 가이드 (FlutterFlow)

 📂 파일 위치 및 위젯 리스트
 모든 화면(Pages): `lib/` 폴더 내 각 이름별 폴더
 커스텀 액션: `lib/custom_code/actions/`
 전역 상태: `lib/app_state.dart`

 🛠️ 커스텀 위젯 (`lib/custom_code/widgets/`)
현재 구현된 위젯 파일들 (새 작업 시 참고):
"임시/ 폴더에는 적용하지 말 것"

 ⚙️ AI 작업 규칙

- 새 기능 추가 시 반드시 주제별 주석 블록으로 구분할 것.
- 기존 블록 내부에 의미 없이 이어붙이지 말 것.
- 기능이 커지면 private helper method로 분리할 것.
- build() 내부 코드를 계속 비대하게 만들지 말 것.
- 상태 변수도 기능별 블록으로 정리할 것.
- dispose(), timer, stream 정리 코드는 lifecycle 블록으로 모을 것.

1. 복사붙여넣기: FlutterFlow 웹 에디터에 바로 적용할 수 있게 `import`와 클래스 구조 전체를 제공한다.
2. 디자인: `lib/flutter_flow/flutter_flow_theme.dart`의 테마 변수를 최우선으로 사용한다.
3. 작업 시작 전에 반드시 다음 순서로 진행해 주세요.
0. 네가 이해한 지시문 내용을 요약해서 맞는지 동의를 받는다.
1. git status 확인
2. 현재 브랜치 확인
3. 새 작업 브랜치 생성
4. 현재 상태를 백업 커밋
5. 관련 파일 전체 분석
6. 수정 대상 파일과 수정 계획 먼저 요약
7. 코드 수정
8. flutter pub get 실행
9. flutter analyze 실행
10. 오류 발생 시 원인 분석 후 수정 반복
11. 최종적으로 git diff 확인
12. 수정된 파일 목록, 핵심 변경사항, 남은 이슈 보고
13. main 브랜치에 머지해 줘.
14. 원격 저장소에 push 해줘

주의사항:
- 기존 정상 작동 기능을 깨지 말 것
- FlutterFlow generated code 구조를 함부로 대규모 변경하지 말 것
- 앱 실행/빌드 가능성을 최우선으로 할 것
- 불확실한 부분은 임의 삭제하지 말고 보고할 것
- 완료후 관리자가 APK 라고 적으면, 날자와 시간이 이름에 들어간 APK만들어 줘. 

이 내용을 항상 기억하고 지시문에 포함해 줘.
=================================
지시문 

# [B-정석 / 코어] usage_logs 서버 전용화 지시서

## 배경 / 목적
현재 `billing_ticker.saveUsageLog()`가 클라이언트에서 `users/{uid}/usage_logs`에 직접 `.add()` 한다.
규칙은 `allow write: if false`라 차단되어 `permission-denied`가 난다.
→ **서버 콜러블 `logUsageSession`**을 신설해 Admin SDK로 기록한다(규칙 우회). 클라 직접쓰기는 제거.
created_at / after_seconds / before_seconds는 **서버 권위로 확정(정합형)**.

### 설계 요점
- **규칙 무변경**: `write:false` 유지가 곧 "클라 직접쓰기 영구 차단". Admin SDK는 규칙 우회 → 양립.
- **store_master 무변경**: 세션당 1줄 모델 유지(Usage / Admin Time Log 화면 그대로).
- **정합형**: 서버가 `remainingTime` 재조회 = `after`, `before = after + seconds_used`(역산).
- **식별자 선설계**: 서버가 `room_id`/`session_id`를 옵션(기본 "")으로 받음. 이번엔 클라가 ""로 전송.
  실제 값 배선(모드 파일)은 **후속 "식별자 보강" 지시서**에서 → 그땐 서버 재배포 불필요(클라 전용).

### 영향 범위
- `firebase/functions/index.js` (함수 1개 **추가**)
- `lib/custom_code/actions/billing_ticker.dart` (메서드 1개 추가 + saveUsageLog 쓰기 1곳 교체)
- 무변경: `firestore.rules`, `store_master.dart`, Box 7, 다른 모드 파일

---

## Phase 0 — 세이브포인트
```bash
git add -A && git commit -m "savepoint: before usage_logs server-side (logUsageSession)"
```

## Phase 1 — 사전 검증
```bash
# 서버: 의존성 존재 & 중복 정의 없음
grep -c "logUsageSession"            firebase/functions/index.js   # 기대값: 0 (아직 없음)
grep -c "admin.firestore"            firebase/functions/index.js   # 1 이상 (admin 사용 중)
grep -c "functions.https.onCall"     firebase/functions/index.js   # 1 이상 (패턴 존재)

# 클라: 앵커/기준 카운트
grep -c "_callLogUsageSession"               lib/custom_code/actions/billing_ticker.dart  # 0
grep -c "collection('usage_logs')"           lib/custom_code/actions/billing_ticker.dart  # 1 (saveUsageLog의 .add)
grep -c "firestore save success"             lib/custom_code/actions/billing_ticker.dart  # 1 (EDIT B 앵커 유일성)
```
> 위 기준값과 다르면 **중단** 후 보고.

---

## Phase 2 — 수정

### 🟦 EDIT 2-S (서버) — index.js **끝에 함수 추가**
> 파일 **맨 끝(최상위 스코프)** 에 아래 블록을 그대로 append.
> (top-level `exports.X`는 위치 무관. `admin`/`functions`는 이미 import됨 = Phase 1에서 확인)

```javascript

// 🔧 [B-정석] usage_logs 서버 전용 기록. 클라는 이 콜러블만 호출하고
//   created_at/after/before는 서버 권위로 확정한다(정합형).
//   Admin SDK는 Firestore 규칙(write:false)을 우회하므로 클라 직접쓰기 차단과 양립한다.
exports.logUsageSession = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Request must be authenticated."
    );
  }
  const uid = context.auth.uid;

  const mode = typeof data.mode === "string" ? data.mode : "";
  const rate = typeof data.rate === "number" ? data.rate : null;
  const secondsUsed = data.seconds_used;
  const actualSeconds = data.actual_seconds;
  const roomId = typeof data.room_id === "string" ? data.room_id : "";
  const sessionId = typeof data.session_id === "string" ? data.session_id : "";

  if (
    typeof secondsUsed !== "number" ||
    !Number.isInteger(secondsUsed) ||
    secondsUsed <= 0 ||
    secondsUsed > 86400
  ) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "seconds_used must be a positive integer (<= 86400)."
    );
  }
  if (
    typeof actualSeconds !== "number" ||
    !Number.isInteger(actualSeconds) ||
    actualSeconds < 0 ||
    actualSeconds > 86400
  ) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "actual_seconds must be a non-negative integer (<= 86400)."
    );
  }

  // 정합형: after = 서버가 현재 remainingTime 재조회, before = 역산.
  const userRef = admin.firestore().doc("users/" + uid);
  const snap = await userRef.get();
  const afterSeconds =
    snap.exists && typeof snap.data().remainingTime === "number"
      ? snap.data().remainingTime
      : 0;
  const beforeSeconds = afterSeconds + secondsUsed;

  await admin
    .firestore()
    .collection("users")
    .doc(uid)
    .collection("usage_logs")
    .add({
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      mode: mode,
      rate: rate,
      seconds_used: secondsUsed,
      actual_seconds: actualSeconds,
      before_seconds: beforeSeconds,
      after_seconds: afterSeconds,
      room_id: roomId,
      session_id: sessionId,
    });

  functions.logger.info("logUsageSession", {
    uid: uid,
    mode: mode,
    seconds_used: secondsUsed,
    before: beforeSeconds,
    after: afterSeconds,
  });

  return {
    ok: true,
    before_seconds: beforeSeconds,
    after_seconds: afterSeconds,
  };
});
```

---

### 🟩 클라이언트 — billing_ticker.dart (str_replace, 아래→위 순서)

#### ✅ EDIT 2-B (먼저 / 위쪽 라인) — `_callDeductTime` 뒤에 신규 메서드 추가

**find:** (이 블록은 파일 내 유일 = Phase 1 `firestore save success`=1로 확인)
```dart
      _addBillingLog('[BILLING] firestore save success');
      _lastFlushResult =
          'OK (-${seconds}s) @ ${DateTime.now().toIso8601String().substring(11, 19)}';
    }
  }
```

**replace:**
```dart
      _addBillingLog('[BILLING] firestore save success');
      _lastFlushResult =
          'OK (-${seconds}s) @ ${DateTime.now().toIso8601String().substring(11, 19)}';
    }
  }

  /// 🔧 [B-정석] usage_logs 서버 전용 기록 콜러블 호출.
  ///   created_at/after_seconds/before_seconds는 서버가 권위로 확정(정합형).
  ///   room_id/session_id는 후속 보강 전까지 빈 문자열로 전송.
  Future<void> _callLogUsageSession({
    required int secondsUsed,
    required int actualSeconds,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final idToken = await user.getIdToken();
    final projectId = FirebaseFirestore.instance.app.options.projectId;

    final response = await http
        .post(
          Uri.parse(
              'https://$_kBillingRegion-$projectId.cloudfunctions.net/logUsageSession'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode({
            'data': {
              'mode': _sessionMode,
              'rate': _sessionRateValue,
              'seconds_used': secondsUsed,
              'actual_seconds': actualSeconds,
              'room_id': '', // TODO[plumb]: Duo 방 ID (후속 보강)
              'session_id': '', // TODO[plumb]: chat_history sessionDocId (후속 보강)
            }
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception(
          'logUsageSession HTTP ${response.statusCode}: ${response.body}');
    }
  }
```

#### ✅ EDIT 2-A (나중 / 아래쪽 라인) — saveUsageLog의 Firestore 직접쓰기 교체

**find:**
```dart
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('usage_logs')
          .add({
        'created_at': FieldValue.serverTimestamp(),
        'mode': _sessionMode,
        'seconds_used': secondsUsed,
        'actual_seconds': actualSeconds,
        'rate': _sessionRateValue,
        'before_seconds': beforeSeconds,
        'after_seconds': afterSeconds,
      });
```

**replace:**
```dart
      // 🔧 [B-정석] 클라 직접 쓰기 제거 → 서버 콜러블이 권위로 기록.
      await _callLogUsageSession(
        secondsUsed: secondsUsed,
        actualSeconds: actualSeconds,
      );
```

> 참고: `beforeSeconds`/`afterSeconds` 지역변수는 로그 출력(`[USAGE_LOG] saved ... before=$beforeSeconds`)에 계속 쓰이므로 **제거하지 말 것**. `FieldValue` 심볼은 이 블록에서만 쓰였지만 `cloud_firestore` import는 `FirebaseFirestore.instance`가 계속 사용하므로 import 제거 불필요.

---

## Phase 3 — 검증
```bash
# 클라
grep -c "_callLogUsageSession"               lib/custom_code/actions/billing_ticker.dart  # 기대값: 2
grep -c "cloudfunctions.net/logUsageSession" lib/custom_code/actions/billing_ticker.dart  # 1
grep -c "collection('usage_logs')"           lib/custom_code/actions/billing_ticker.dart  # 0 (직접쓰기 제거됨)
grep -c "'before_seconds': beforeSeconds"    lib/custom_code/actions/billing_ticker.dart  # 0 (클라 전송 제거)
# 중괄호 균형
echo "{ = $(grep -o '{' lib/custom_code/actions/billing_ticker.dart | wc -l) , } = $(grep -o '}' lib/custom_code/actions/billing_ticker.dart | wc -l)"  # 좌우 동일

# 서버
grep -c "logUsageSession"  firebase/functions/index.js   # 1 이상
node -e "require('./firebase/functions/index.js')" 2>&1 | head -5   # 문법 로드 에러 없으면 OK (없을 시 무시 가능)
```

## Phase 4 — 분석 / 포맷 / 배포
```bash
flutter analyze lib/custom_code/actions/billing_ticker.dart
dart format lib/custom_code/actions/billing_ticker.dart   # ⚠️ 이 파일 1개만

cd firebase
firebase deploy --only functions:logUsageSession   # 신규 함수만 우선 배포 가능
# (또는) firebase deploy --only functions:functions
```
> `analyze` 신규 경고/에러 0건이어야 함. 배포 로그에서 `logUsageSession` create/update 확인.

## Phase 5 — 롤백
```bash
git checkout -- lib/custom_code/actions/billing_ticker.dart firebase/functions/index.js
git reset --hard HEAD~1
# 함수 롤백이 필요하면: 이전 index.js로 되돌린 뒤 재배포, 또는
#   firebase functions:delete logUsageSession  (신규 함수 제거)
```

---

## 배포 후 실기기 확인
1. 차감이 발생하는 세션을 1회 진행 후 종료(pause/dispose).
2. 관리자 로그에서 `[USAGE_LOG] saved mode=... seconds_used=...` 출력 + `permission-denied` **소멸** 확인.
3. Firestore 콘솔 `users/{uid}/usage_logs` 새 문서: `before_seconds = after_seconds + seconds_used` 정합, `room_id=""`, `session_id=""`, `created_at` 서버시간 확인.
4. store_master **Usage 화면**(최근 세션/오늘·주 합산)과 **Admin Time Log**가 기존과 동일하게 표시되는지(세션 1줄) 확인.

---

## 다음 단계 (별도 지시서)
**식별자 보강**: 각 모드(Anyone/Roleplay/StepExpand/Duo)에서 `sessionDocId`/`roomId`가 확정되는 시점에
`BillingTicker.instance`로 전달 → `_callLogUsageSession`의 `room_id`/`session_id` 빈문자열을 실제값으로 교체.
서버는 이미 두 필드를 수용하므로 **클라 전용 변경**(서버 재배포 불필요). 모드 파일 배선이라 별도 리뷰로 분리.