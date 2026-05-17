# Claude Code 지시문: AppsFlyer Duo 초대 링크 & 게스트 자동 입장 구현

---

## ⚙️ 작업 절차 (모든 작업에 항상 적용 — 순서 엄수)

### 1단계: Git 상태 확인
```bash
git status
git branch
```
현재 브랜치와 변경된 파일 목록을 확인하고 보고하라.

### 2단계: 새 작업 브랜치 생성
```bash
git checkout -b feature/appsflyer-duo-invite
```
이미 동일 이름의 브랜치가 있으면 `feature/appsflyer-duo-invite-2` 등으로 구분한다.

### 3단계: 백업 커밋 (작업 전 현재 상태 보존)
```bash
git add -A
git commit -m "chore: backup before appsflyer duo invite implementation"
```

### 4단계: 대상 파일 전체 분석
아래 파일들을 전체 읽고, 현재 상태를 파악한 뒤 수정 계획을 요약 보고하라.
파일이 없으면 즉시 중단하고 보고하라.
```
lib/app_state.dart
lib/custom_code/actions/init_apps_flyer.dart
lib/custom_code/actions/appsflyermanager.dart
lib/custom_code/widgets/routine_mode_duo.dart
android/app/src/main/AndroidManifest.xml
android/app/src/main/kotlin/com/aienglishpractice/stealthvox/MainActivity.kt
```

### 5단계: 수정 계획 요약 보고 (코드 수정 전)
- 수정할 파일 목록
- 각 파일별 변경 내용 요약 (추가/교체/삭제 구분)
- 수정하지 않을 파일과 그 이유

### 6단계: 코드 수정
아래 [파일별 수정 지시]에 따라 순서대로 수정한다.
각 파일 수정 후 반드시 자가 검증 명령어를 실행하고 결과를 보고하라.

### 7단계: 빌드 검증
```bash
flutter pub get
flutter analyze lib/app_state.dart \
  lib/custom_code/actions/appsflyermanager.dart \
  lib/custom_code/actions/init_apps_flyer.dart \
  lib/custom_code/widgets/routine_mode_duo.dart
flutter build apk --debug
```
- `flutter analyze`: 에러 0개 필수. warning은 보고만 한다.
- `flutter build apk`: 빌드 성공 필수.
- 오류 발생 시 원인 분석 후 수정하고 재실행한다. 수정 반복은 최대 3회까지.
- 3회 반복 후에도 해결 안 되면 중단하고 원인과 함께 보고한다.

### 8단계: Git diff 확인 및 최종 커밋
```bash
git diff HEAD~1
git add -A
git commit -m "feat: appsflyer duo invite deeplink & guest auto-join"
```
diff 결과에서 의도하지 않은 변경이 있으면 보고하라.

### 9단계: 최종 보고
- 수정된 파일 목록
- 파일별 핵심 변경 사항
- `flutter analyze` 결과
- `flutter build apk` 결과
- 남은 이슈 또는 불확실한 부분

---

## ⚠️ 주의사항 (항상 준수)

1. **기존 정상 작동 기능을 깨지 말 것.**
   수정 대상이 아닌 함수/로직은 절대 건드리지 않는다.

2. **FlutterFlow generated code 구조를 함부로 대규모 변경하지 말 것.**
   각 파일 상단의 `// DO NOT REMOVE OR MODIFY THE CODE ABOVE!` 블록은 절대 수정하지 않는다.

3. **앱 실행/빌드 가능성을 최우선으로 할 것.**
   빌드가 깨지는 변경은 즉시 롤백하고 보고한다.

4. **불확실한 부분은 임의 삭제하지 말고 보고할 것.**
   판단이 어려운 코드는 주석 처리하고 보고하거나, 작업을 중단하고 질문한다.

5. **전체 파일 교체 시 FlutterFlow import 블록 보존.**
   파일 상단 자동 import 주석 7줄은 항상 그대로 유지한다.

---

## 변경 대상 파일 목록 (총 4개)

| 순서 | 파일 | 변경 유형 |
|------|------|-----------|
| 1 | `lib/app_state.dart` | 부분 수정 (3곳) |
| 2 | `lib/custom_code/actions/appsflyermanager.dart` | 전체 교체 |
| 3 | `lib/custom_code/actions/init_apps_flyer.dart` | 전체 교체 |
| 4 | `lib/custom_code/widgets/routine_mode_duo.dart` | 부분 수정 (3곳) |

`AndroidManifest.xml`과 `MainActivity.kt`는 현재 설정이 올바르므로 **수정하지 않는다.**

---

## [파일 1] lib/app_state.dart

### 목적
`isGuestSession`, `duoRoomId`를 앱 재시작 후에도 유지되도록 SharedPreferences에 영속 저장하고,
`clearDuoInviteState()` 정리 메서드를 추가한다.

### 변경 1-A: `initializePersistedState()` 내부에 3블록 추가

아래 기존 코드를 찾아라:
```dart
    _safeInit(() {
      _inviterUid = prefs.getString('ff_inviterUid') ?? _inviterUid;
    });
  }
```

`_inviterUid` 블록 **다음**, 함수 닫는 `}` **바로 앞에** 아래 3블록을 삽입한다:

```dart
    _safeInit(() {
      _isGuestSession = prefs.getBool('ff_isGuestSession') ?? _isGuestSession;
    });
    _safeInit(() {
      _duoRoomId = prefs.getString('ff_duoRoomId') ?? _duoRoomId;
    });
    _safeInit(() {
      _pendingInviteType = prefs.getString('ff_pendingInviteType') ?? _pendingInviteType;
    });
```

### 변경 1-B: `isGuestSession` setter에 prefs 저장 추가

기존:
```dart
  bool _isGuestSession = false;
  bool get isGuestSession => _isGuestSession;
  set isGuestSession(bool value) {
    _isGuestSession = value;
  }
```

교체:
```dart
  bool _isGuestSession = false;
  bool get isGuestSession => _isGuestSession;
  set isGuestSession(bool value) {
    _isGuestSession = value;
    prefs.setBool('ff_isGuestSession', value);
  }
```

### 변경 1-C: `duoRoomId` setter 교체 + `pendingInviteType` + `clearDuoInviteState()` 추가

기존 (클래스 마지막 부분):
```dart
  String _duoRoomId = '';
  String get duoRoomId => _duoRoomId;
  set duoRoomId(String value) {
    _duoRoomId = value;
  }
}
```

교체 (클래스 닫는 `}` 포함):
```dart
  String _duoRoomId = '';
  String get duoRoomId => _duoRoomId;
  set duoRoomId(String value) {
    _duoRoomId = value;
    prefs.setString('ff_duoRoomId', value);
  }

  String _pendingInviteType = '';
  String get pendingInviteType => _pendingInviteType;
  set pendingInviteType(String value) {
    _pendingInviteType = value;
    prefs.setString('ff_pendingInviteType', value);
  }

  /// Duo 입장 성공 후 초대 상태 일괄 초기화
  void clearDuoInviteState() {
    _isGuestSession = false;
    _duoRoomId = '';
    _pendingInviteType = '';
    prefs.setBool('ff_isGuestSession', false);
    prefs.setString('ff_duoRoomId', '');
    prefs.setString('ff_pendingInviteType', '');
  }
}
```

### 자가 검증 (파일 1)
```bash
grep -n "ff_isGuestSession\|ff_duoRoomId\|clearDuoInviteState\|pendingInviteType" lib/app_state.dart
```
출력에 위 키워드가 각각 2회 이상 나타나야 한다.

---

## [파일 2] lib/custom_code/actions/appsflyermanager.dart

### 목적
- AppsFlyer payload 파싱 + FFAppState 저장을 `_handlePayload()` 공통 메서드로 통합
- SDK 초기화는 `AppsFlyerManager.initialize()` 한 곳에서만 처리
- `appsflyermanager()` 빈 함수는 FlutterFlow export 구조를 위해 유지

### 전체 파일 교체

파일 전체를 아래 내용으로 교체한다.
상단 FlutterFlow import 블록(`// DO NOT REMOVE OR MODIFY THE CODE ABOVE!` 포함 8줄)은 **그대로 복사**한다.

```dart
// Automatic FlutterFlow imports
import '/backend/backend.dart';
import '/backend/schema/structs/index.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom actions
import '/flutter_flow/custom_functions.dart'; // Imports custom functions
import 'package:flutter/material.dart';
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'package:appsflyer_sdk/appsflyer_sdk.dart';

// FlutterFlow export 유지용 no-op (삭제 금지)
Future<void> appsflyermanager() async {
  debugPrint('[AppsFlyerManager] no-op placeholder called');
}

class AppsFlyerManager {
  static AppsflyerSdk? _instance;
  static bool _isInitialized = false;

  /// 유일한 SDK 초기화 진입점.
  /// FlutterFlow에서 initAppsFlyer(devKey, appId) → 여기 호출됨.
  static Future<void> initialize({
    required String devKey,
    required String appId,
  }) async {
    if (_isInitialized) {
      debugPrint('[AppsFlyerManager] already initialized, skipping');
      return;
    }
    try {
      final AppsFlyerOptions options = AppsFlyerOptions(
        afDevKey: devKey,
        appId: appId,
        showDebug: true, // 테스트 기간 동안 true 유지
        timeToWaitForATTUserAuthorization: 15,
      );

      _instance = AppsflyerSdk(options);

      // Unified Deep Link (앱 설치된 상태 — 권장 경로)
      _instance!.onDeepLinking((DeepLinkResult res) {
        debugPrint('[AppsFlyer] onDeepLinking status: ${res.status}');
        if (res.status == Status.FOUND) {
          try {
            final clickEvent = res.deepLink?.clickEvent ?? {};
            final params = Map<String, dynamic>.from(clickEvent);
            if (res.deepLink?.deepLinkValue != null) {
              params['deep_link_value'] = res.deepLink!.deepLinkValue!;
            }
            debugPrint('[AppsFlyer] raw payload (onDeepLinking): $params');
            _handlePayload(params);
          } catch (e) {
            debugPrint('[AppsFlyer] onDeepLinking parse error: $e');
          }
        }
      });

      // Deferred Deep Link (앱 미설치 → 설치 후 첫 실행)
      _instance!.onInstallConversionData((res) {
        debugPrint('[AppsFlyer] onInstallConversionData raw: $res');
        _routeCallback(res, _handlePayload);
      });

      // App Open Attribution (구형 폴백)
      _instance!.onAppOpenAttribution((res) {
        debugPrint('[AppsFlyer] onAppOpenAttribution raw: $res');
        _routeCallback(res, _handlePayload);
      });

      await _instance!.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );

      _isInitialized = true;
      debugPrint('[AppsFlyerManager] initialized successfully');
    } catch (e) {
      debugPrint('[AppsFlyerManager] init error: $e');
    }
  }

  /// onInstallConversionData / onAppOpenAttribution 응답을 파싱해
  /// _handlePayload 형태로 변환하는 어댑터
  static void _routeCallback(
    dynamic res,
    void Function(Map<String, dynamic>) handler,
  ) {
    try {
      if (res == null) return;
      final raw = res as Map<dynamic, dynamic>;
      if ((raw['status']?.toString() ?? '') != 'success') return;
      final payload = raw['data'] ?? raw;
      if (payload == null) return;
      final params = Map<String, dynamic>.from(payload as Map);
      debugPrint('[AppsFlyer] raw payload (routeCallback): $params');
      handler(params);
    } catch (e) {
      debugPrint('[AppsFlyerManager] _routeCallback error: $e');
    }
  }

  /// 세 콜백 경로 공통 파싱 + FFAppState 저장
  static void _handlePayload(Map<String, dynamic> params) {
    try {
      // room_id 우선, 없으면 duo_room_id → deep_link_sub2 순서로 폴백
      final String roomId = (params['room_id'] ??
              params['duo_room_id'] ??
              params['deep_link_sub2'] ??
              '')
          .toString()
          .trim();

      // inviter_id 우선, 없으면 deep_link_sub1 폴백
      final String inviterUid =
          (params['inviter_id'] ?? params['deep_link_sub1'] ?? '')
              .toString()
              .trim();

      final String deepLinkValue =
          (params['deep_link_value'] ?? '').toString().trim();
      final String inviteType =
          (params['invite_type'] ?? '').toString().trim();

      debugPrint('[AppsFlyer] parsed roomId: $roomId');
      debugPrint('[AppsFlyer] parsed inviterUid: $inviterUid');
      debugPrint('[AppsFlyer] parsed deepLinkValue: $deepLinkValue');
      debugPrint('[AppsFlyer] parsed inviteType: $inviteType');

      // Duo 초대 판정
      final bool isDuoInvite =
          deepLinkValue == 'duo_chat' || inviteType == 'duo';

      if (isDuoInvite && roomId.isNotEmpty) {
        FFAppState().isGuestSession = true;
        FFAppState().duoRoomId = roomId;
        FFAppState().inviterUid = inviterUid;
        FFAppState().pendingInviteType = 'duo';
        FFAppState().update(() {});
        debugPrint('[AppsFlyer] saved duo invite state — roomId: $roomId');
      } else {
        debugPrint(
            '[AppsFlyer] not a duo invite or roomId empty, skipping state save');
      }
    } catch (e) {
      debugPrint('[AppsFlyerManager] _handlePayload error: $e');
    }
  }
}
```

### 자가 검증 (파일 2)
```bash
grep -n "_handlePayload\|_routeCallback\|onDeepLinking\|onInstallConversionData\|duo_room_id" lib/custom_code/actions/appsflyermanager.dart
```
각 키워드가 1회 이상 출력되어야 한다.

---

## [파일 3] lib/custom_code/actions/init_apps_flyer.dart

### 목적
`initAppsFlyer`를 FlutterFlow 진입점으로 유지하되, 내부 로직은 전부 `AppsFlyerManager.initialize()`에 위임한다.
SDK를 직접 생성하는 코드를 모두 제거한다.

### 전체 파일 교체

```dart
// Automatic FlutterFlow imports
import '/backend/backend.dart';
import '/backend/schema/structs/index.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom actions
import '/flutter_flow/custom_functions.dart'; // Imports custom functions
import 'package:flutter/material.dart';
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'appsflyermanager.dart' show AppsFlyerManager;

/// FlutterFlow에서 호출하는 단일 진입점.
/// 실제 초기화와 payload 파싱은 AppsFlyerManager로 위임한다.
Future<void> initAppsFlyer(
  String? devKey,
  String? appId,
) async {
  if (devKey == null || devKey.isEmpty || appId == null || appId.isEmpty) {
    debugPrint('[initAppsFlyer] devKey or appId is null/empty, skipping');
    return;
  }
  debugPrint('[initAppsFlyer] delegating to AppsFlyerManager.initialize()');
  await AppsFlyerManager.initialize(devKey: devKey, appId: appId);
}
```

### 자가 검증 (파일 3)
```bash
grep -n "AppsFlyerManager\|AppsflyerSdk\|onDeepLinking" lib/custom_code/actions/init_apps_flyer.dart
```
- `AppsFlyerManager` : 1회 이상 ✅
- `AppsflyerSdk` : **0회** (직접 SDK 생성 제거 확인) ✅
- `onDeepLinking` : **0회** (콜백 등록 없어야 함) ✅

---

## [파일 4] lib/custom_code/widgets/routine_mode_duo.dart

### 변경 4-A: `_shareInviteCode()` 파라미터 보강

기존 `_params` 맵 정의 부분을 찾아라:
```dart
      final Map<String, String> _params = {
        'deep_link_value': 'duo_chat',
        'deep_link_sub1': user.uid,
        'deep_link_sub2': _roomId,
        'inviter_id': user.uid,
        'room_id': _roomId,
        'pid': 'friend_invite',
        'c': 'in_app_share',
        'af_dp': 'stealthvox://',
        'af_force_deeplink': 'true',
      };
```

아래로 교체한다:
```dart
      final Map<String, String> _params = {
        'deep_link_value': 'duo_chat',
        'invite_type': 'duo',
        'entry_mode': 'guest',
        'room_id': _roomId,
        'duo_room_id': _roomId,
        'deep_link_sub1': user.uid,
        'deep_link_sub2': _roomId,
        'inviter_id': user.uid,
        'af_dp': 'stealthvox://duo',
        'af_force_deeplink': 'true',
        'pid': 'friend_invite',
        'c': 'in_app_share',
      };
      debugPrint('[Duo] inviteLink roomId: $_roomId');
```

그리고 `inviteLink` 변수 생성 직후, `Share.share()` 호출 **전에** 아래 로그를 추가한다:
```dart
      debugPrint('[Duo] inviteLink: $inviteLink');
```

### 변경 4-B: `_joinAsGuest()` 비로그인 게스트 처리 보강

기존:
```dart
      await _duoSessionRef!.update({
        'isPartnerJoined': true,
        'partnerUid': FirebaseAuth.instance.currentUser?.uid,
        'partnerJoinedAt': FieldValue.serverTimestamp(),
      });
      FFAppState().isGuestSession = false;
      FFAppState().duoRoomId = '';
```

아래로 교체한다:
```dart
      final String? firebaseUid = FirebaseAuth.instance.currentUser?.uid;
      final String guestUid =
          firebaseUid ?? 'guest_${DateTime.now().millisecondsSinceEpoch}';
      await _duoSessionRef!.update({
        'isPartnerJoined': true,
        'partnerUid': guestUid,
        'partnerJoinedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('[Duo] _joinAsGuest success — guestUid: $guestUid, roomId: $roomId');
      FFAppState().clearDuoInviteState();
```

### 변경 4-C: `initState` — `widget.roomId` 우선 처리

기존 `addPostFrameCallback` 블록:
```dart
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (FFAppState().isGuestSession == true &&
          FFAppState().duoRoomId.isNotEmpty) {
        _joinAsGuest(FFAppState().duoRoomId);
      }
    });
```

아래로 교체한다:
```dart
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // widget.roomId 우선 사용, 없으면 FFAppState 폴백
      final String? pendingRoomId =
          (widget.roomId != null && widget.roomId!.isNotEmpty)
              ? widget.roomId
              : (FFAppState().isGuestSession &&
                      FFAppState().duoRoomId.isNotEmpty
                  ? FFAppState().duoRoomId
                  : null);
      if (pendingRoomId != null) {
        debugPrint(
            '[Duo] initState — auto joining as guest, roomId: $pendingRoomId');
        _joinAsGuest(pendingRoomId);
      }
    });
```

### 자가 검증 (파일 4)
```bash
grep -n "invite_type\|duo_room_id\|clearDuoInviteState\|guestUid\|pendingRoomId\|\[Duo\] inviteLink" lib/custom_code/widgets/routine_mode_duo.dart
```
각 키워드가 1회 이상 출력되어야 한다.

---

## AndroidManifest.xml / MainActivity.kt — 수정하지 않음

현재 설정 확인 결과 모두 정상:
- `android:exported="true"` ✅
- `android:launchMode="singleTop"` ✅
- `flutter_deeplinking_enabled=false` ✅
- `stealthvox://` scheme intent-filter ✅
- OneLink `https://stealthvox.onelink.me/31o1` pathPrefix intent-filter ✅
- `MainActivity`: 기본 `FlutterActivity` — AppsFlyer Dart SDK가 처리하므로 `onNewIntent` 불필요 ✅

두 파일 모두 **변경하지 않는다.**

---

## 테스트 확인용 로그 키워드

```bash
adb logcat | grep -E "\[AppsFlyer\]|\[Duo\]|\[AppsFlyerManager\]|\[initAppsFlyer\]"
```

| 단계 | 확인할 로그 키워드 |
|------|-------------------|
| 초대 링크 생성 | `[Duo] inviteLink roomId:` |
| 링크 URL 확인 | `[Duo] inviteLink: https://stealthvox.onelink.me` |
| AppsFlyer 수신 | `[AppsFlyer] raw payload` |
| roomId 파싱 | `[AppsFlyer] parsed roomId: <실제 ID>` |
| 상태 저장 | `[AppsFlyer] saved duo invite state` |
| 자동 입장 시작 | `[Duo] initState — auto joining as guest` |
| 입장 성공 | `[Duo] _joinAsGuest success — guestUid` |

**테스트 A (앱 설치된 상태):**
링크 클릭 → `onDeepLinking` 경로 → `[AppsFlyer] raw payload (onDeepLinking)` 확인

**테스트 B (앱 미설치 → 설치 후):**
Play Store → 설치 → `onInstallConversionData` 경로 → `[AppsFlyer] raw payload (routeCallback)` 확인
