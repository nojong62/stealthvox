# 키보드 Overflow 위험 점검 보고서

**작성일:** 2026-05-18  
**현재 브랜치:** `feature/tts-first-chunk-5words`  
**점검 대상:** `lib/` 하위 전체 페이지 및 커스텀 위젯  
**수정 없음 — 점검 보고만 수행**

---

## 공통 구조 관찰

FlutterFlow 생성 `*_widget.dart` 래퍼는 거의 전부 동일한 패턴:

```dart
Scaffold(  // resizeToAvoidBottomInset 미설정 → 기본값 true
  body: Column(
    children: [
      Container(height: MediaQuery.sizeOf(context).height * 1.0,  // 고정 높이
        child: CustomWidget(height: screen_height),
      ),
    ],
  ),
)
```

이 패턴에서 키보드 올라오면 Scaffold body 높이가 줄어드는데 `Column` 안의 `Container(height: screen_height)`는 여전히 screen_height를 요구 → **Column에서 "BOTTOM OVERFLOWED BY xxx PIXELS" 발생 가능**

---

## 페이지별 점검 결과

---

### 1. Intro (로그인/회원가입)

| 항목 | 상태 |
|---|---|
| 파일 경로 | `lib/intro/intro_widget.dart` + `lib/custom_code/widgets/intro_master.dart` |
| 화면 이름 | 로그인 / 회원가입 |
| 입력 필드 존재 여부 | **YES** — Email, Password TextField (항상 화면에 표시) |
| resizeToAvoidBottomInset 설정 | 외부 Scaffold 미설정 (기본 true). 내부 Scaffold도 미설정 (기본 true) — 중첩 Scaffold |
| SingleChildScrollView 적용 여부 | 내부 `intro_master.dart`에 있음 (`SafeArea > SingleChildScrollView`) |
| **overflow 위험도** | **높음** |
| 추천 수정 | 외부 `intro_widget.dart` Scaffold에 `resizeToAvoidBottomInset: false` 추가 (내부 Scaffold의 SingleChildScrollView가 키보드를 처리하도록 위임). 또는 외부 body에서 `Column` 제거하고 `CustomWidget`을 직접 body로 사용 |
| 실제 수정 필요 여부 | **YES — 최우선 수정 대상** |

**위험 이유:** 외부 `Column > Container(height: screen_height)` 구조에서 키보드 올라오면 outer Scaffold가 body를 줄이지만 Container는 여전히 screen_height 유지 → RenderFlex overflow. 내부 SingleChildScrollView는 있지만 외부 fixed-height Container 안에 갇혀 있어 overflow 메시지 발생.

---

### 2. CloneTestPage (Clone AI 채팅 + 클론 생성)

| 항목 | 상태 |
|---|---|
| 파일 경로 | `lib/clone_test_page/clone_test_page_widget.dart` + `lib/custom_code/widgets/routine_mode_clone.dart` |
| 화면 이름 | Clone AI 채팅 / 클론 생성 |
| 입력 필드 존재 여부 | **YES** — 클론 생성 다이얼로그: 이름 TextField + 특징 TextField(maxLines:5). 클론 수정 다이얼로그: TextField(maxLines:6) |
| resizeToAvoidBottomInset 설정 | 외부 Scaffold 미설정 (기본 true). 메인 위젯 자체는 Scaffold 없이 Container 반환 |
| SingleChildScrollView 적용 여부 | 클론 생성 다이얼로그: `Dialog > SingleChildScrollView`. 클론 수정 다이얼로그: `SingleChildScrollView(padding: EdgeInsets.only(bottom: viewInsets.bottom))` — 명시적 처리 있음 |
| **overflow 위험도** | **중간** |
| 추천 수정 | 클론 생성 다이얼로그(`_showCloneDashboard`)에 수정 다이얼로그처럼 `MediaQuery.of(ctx).viewInsets.bottom` 처리 추가. 외부 wrapper의 `resizeToAvoidBottomInset: false` 설정 |
| 실제 수정 필요 여부 | **부분적 필요** (수정 다이얼로그는 처리됨, 생성 다이얼로그 보완 필요) |

---

### 3. ChatHistory 목록 (스터디룸)

| 항목 | 상태 |
|---|---|
| 파일 경로 | `lib/chat_history/chat_history_widget.dart` + `lib/custom_code/widgets/chat_history_list_master.dart` |
| 화면 이름 | Study Room (채팅 기록 목록) |
| 입력 필드 존재 여부 | **제한적 YES** — 제목 수정 AlertDialog 내 TextField만 있음. 메인 화면에는 없음 |
| resizeToAvoidBottomInset 설정 | 외부 Scaffold 미설정 |
| SingleChildScrollView 적용 여부 | 필터바에 horizontal ScrollView 있음. 다이얼로그 내 별도 처리 없음 |
| **overflow 위험도** | **낮음** |
| 추천 수정 | AlertDialog는 Flutter가 자동으로 keyboard inset 처리하므로 실제 overflow 가능성 낮음. 필요시 다이얼로그 내 `padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom)` 추가 |
| 실제 수정 필요 여부 | 낮음 (AlertDialog 자체 처리로 충분) |

---

### 4. ChatDetail (채팅 복습/학습)

| 항목 | 상태 |
|---|---|
| 파일 경로 | `lib/chat_detail/chat_detail_widget.dart` + `lib/custom_code/widgets/chat_history_master.dart` |
| 화면 이름 | ChatDetail (스터디룸 상세, 쉐도잉 등 다중 Phase) |
| 입력 필드 존재 여부 | **없음** — 텍스트 입력 없음 |
| resizeToAvoidBottomInset 설정 | 외부 Scaffold 미설정. 내부 다중 Scaffold 모두 미설정 |
| SingleChildScrollView 적용 여부 | 없음 (Scaffold > SafeArea > Column 구조) |
| **overflow 위험도** | **없음** (키보드 사용 없음) |
| 실제 수정 필요 여부 | **없음** |

---

### 5. Lobby (로비)

| 항목 | 상태 |
|---|---|
| 파일 경로 | `lib/lobby/lobby_widget.dart` + `lib/custom_code/widgets/lobby_master.dart` |
| 입력 필드 존재 여부 | **없음** |
| resizeToAvoidBottomInset 설정 | 외부 Scaffold 미설정 |
| SingleChildScrollView 적용 여부 | 내부에 `Expanded > SingleChildScrollView` 있음 |
| **overflow 위험도** | **없음** (키보드 사용 없음) |
| 실제 수정 필요 여부 | **없음** |

---

### 6. StealthRoom (모드 선택 메뉴)

| 항목 | 상태 |
|---|---|
| 파일 경로 | `lib/stealth_room/stealth_room_widget.dart` + `lib/custom_code/widgets/stealth_room_master.dart` |
| 입력 필드 존재 여부 | **없음** (모드 선택 버튼만 있음) |
| resizeToAvoidBottomInset 설정 | 외부 Scaffold 미설정 |
| SingleChildScrollView 적용 여부 | 없음 |
| **overflow 위험도** | **없음** (키보드 사용 없음) |
| 실제 수정 필요 여부 | **없음** |

---

### 7. Store (스토어)

| 항목 | 상태 |
|---|---|
| 파일 경로 | `lib/store/store_widget.dart` + `lib/custom_code/widgets/store_master.dart` |
| 입력 필드 존재 여부 | **없음** |
| resizeToAvoidBottomInset 설정 | 외부 Scaffold 미설정. 내부 Scaffold도 미설정 |
| SingleChildScrollView 적용 여부 | 내부에 `Expanded > SingleChildScrollView` 있음 |
| **overflow 위험도** | **없음** (키보드 사용 없음) |
| 실제 수정 필요 여부 | **없음** |

---

### 8. Onboarding

| 항목 | 상태 |
|---|---|
| 파일 경로 | `lib/onboarding/onboarding_widget.dart` + `lib/custom_code/widgets/onboarding_master.dart` |
| 입력 필드 존재 여부 | **없음** |
| resizeToAvoidBottomInset 설정 | 외부 Scaffold 미설정 |
| SingleChildScrollView 적용 여부 | 없음 (onboarding_master.dart에 미존재) |
| **overflow 위험도** | **없음** |
| 실제 수정 필요 여부 | **없음** |

---

### 9. Roleplay / StepExpand (내부 모드 위젯)

| 항목 | 상태 |
|---|---|
| 파일 경로 | `lib/custom_code/widgets/routine_mode_roleplay.dart` / `routine_mode_step_expand.dart` |
| 입력 필드 존재 여부 | **없음** (음성/마이크 기반 인터페이스) |
| resizeToAvoidBottomInset 설정 | Scaffold 없음 (Container 직접 반환) |
| SingleChildScrollView 적용 여부 | roleplay: 있음. step_expand: 있음 |
| **overflow 위험도** | **없음** |
| 실제 수정 필요 여부 | **없음** (roleplay는 수정 금지) |

---

## 수정 우선순위 요약

| 우선순위 | 파일 | 위험도 | 이유 |
|---|---|---|---|
| **1순위** | `lib/intro/intro_widget.dart` | 높음 | Email/Password 항상 표시. 키보드 필수 사용. 외부 fixed-height Column 구조 |
| **2순위** | `lib/clone_test_page/clone_test_page_widget.dart` + `routine_mode_clone.dart` 클론 생성 다이얼로그 | 중간 | 클론 생성 다이얼로그 bottomInset 처리 미흡 |
| **3순위** | 나머지 전체 | 없음~낮음 | 텍스트 입력 필드 없음 |

---

## 1순위 수정 방법 (참고용)

`lib/intro/intro_widget.dart` Scaffold에 `resizeToAvoidBottomInset: false` 추가:

```dart
child: Scaffold(
  key: scaffoldKey,
  resizeToAvoidBottomInset: false,  // ← 추가
  backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
  body: Column(
    ...
  ),
),
```

내부 `intro_master.dart`의 `SafeArea > SingleChildScrollView` 구조가 키보드 인셋을 자체 처리하므로 외부 Scaffold의 resize 기능은 비활성화해도 안전.
