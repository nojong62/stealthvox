StealthVox 프로젝트 가이드 (FlutterFlow)

 📂 파일 위치 및 위젯 리스트
 모든 화면(Pages): `lib/` 폴더 내 각 이름별 폴더
 커스텀 액션: `lib/custom_code/actions/`
 전역 상태: `lib/app_state.dart`

 🛠️ 커스텀 위젯 (`lib/custom_code/widgets/`)
현재 구현된 위젯 파일들 (새 작업 시 참고):

 ⚙️ AI 작업 규칙
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

이 내용을 항상 기억하고 지시문에 포함해 줘.
=================================
지시문

[StealthVox Keepers 로딩 무한 회전 문제 수정 지시문]

현재 증상:
ChatHistoryListMaster 화면에서 Keepers 버튼을 누르면 저장된 표현이 없거나 일부 표현이 있어도 CircularProgressIndicator가 계속 돌고 목록/빈 화면이 정상 표시되지 않는다.

대상 파일:
- lib/custom_code/widgets/chat_history_list_master.dart

핵심 원인으로 의심되는 부분:
_buildKeepersBody()에서 Firestore 조회를 다음처럼 하고 있다.

currentUserReference!
  .collection('keepers')
  .where('is_deleted', isEqualTo: false)
  .orderBy('pinned_at', descending: true)
  .orderBy('created_at', descending: true)
  .snapshots()

이 쿼리는 Firestore 복합 인덱스가 없으면 에러가 나며,
현재 fallback StreamBuilder에도 fallbackSnap.hasError 처리가 없어 에러 상태에서 계속 로딩 스피너만 보일 수 있다.

수정 목표:
Keepers 화면은 어떤 경우에도 무한 로딩 상태로 남으면 안 된다.

수정 지시:

1. _buildKeepersBody()의 Firestore 쿼리를 단순화한다.

우선 1차 안정화에서는 아래처럼 조회한다.

- currentUserReference!.collection('keepers')
- where('is_deleted', isEqualTo: false)
- orderBy('created_at', descending: true)

pinned_at orderBy는 제거한다.

이유:
- pinned_at은 모든 Keeper 문서에 존재하지 않을 수 있다.
- pinned_at + created_at 복합 정렬은 Firestore 인덱스 문제가 생길 수 있다.
- 우선 created_at 기준으로 안정 조회한 뒤, Dart 쪽에서 pinned_at이 있는 항목을 위로 올리는 방식이 안전하다.

2. 정렬은 Firestore가 아니라 Dart에서 처리한다.

snapshot.data!.docs를 받은 뒤 다음 순서로 정렬한다.

- pinned_at이 있는 문서가 먼저
- pinned_at이 둘 다 있으면 pinned_at 최신순
- pinned_at이 없으면 created_at 최신순

즉, Firestore 쿼리는 단순하게 유지하고,
Keepers 최상단 고정 정렬은 클라이언트에서 처리한다.

3. snapshot.hasError 처리를 반드시 추가한다.

_buildKeepersBody() 안에서 snapshot.hasError가 true이면 무한 스피너를 보여주지 말고 에러 안내 UI를 보여준다.

예:
- “Keepers를 불러오지 못했습니다.”
- “잠시 후 다시 시도해 주세요.”
- debugPrint로 snapshot.error 출력

4. fallback StreamBuilder를 제거하거나, fallback에도 hasError 처리를 추가한다.

추천:
- fallback StreamBuilder는 제거한다.
- 단순 쿼리 하나만 사용한다.
- 에러/로딩/빈 목록/정상 목록 상태를 명확히 분기한다.

상태 분기 순서:
- if snapshot.hasError → 에러 안내 UI
- if snapshot.connectionState == ConnectionState.waiting → 로딩
- if !snapshot.hasData → 빈 목록 UI
- docs.isEmpty → 빈 목록 UI
- else → _buildKeepersList(sortedDocs)

5. Keepers 저장 시 모든 문서에 필수 기본 필드를 넣는다.

Keeper 문서 생성 시 반드시 아래 필드를 포함한다.

- is_deleted: false
- created_at: FieldValue.serverTimestamp()
- updated_at: FieldValue.serverTimestamp()
- pinned_at: null 또는 아예 미포함

중요:
is_deleted 필드가 없으면 where('is_deleted', isEqualTo: false) 쿼리에 잡히지 않는다.
따라서 기존에 is_deleted가 없는 Keeper 문서가 있다면 보정 마이그레이션도 필요하다.

6. 기존 Keeper 문서 보정 로직을 추가하거나 임시 보정한다.

이미 저장된 keepers 문서 중 is_deleted 필드가 없는 문서가 있으면:
- is_deleted: false
- updated_at: FieldValue.serverTimestamp()

를 추가한다.

이 보정은 임시 함수로 한 번 실행하거나,
Keepers 조회 전에 누락 필드가 있는 문서를 안전하게 처리하는 방식으로 구현한다.

7. _buildKeepersList()에 전달하기 전에 docs 타입 오류가 나지 않도록 확인한다.

현재 _buildKeepersList(List<QueryDocumentSnapshot> docs) 형태라면,
snapshot.data!.docs 타입과 맞는지 확인하고 필요하면 List<QueryDocumentSnapshot<Object?>> 형태로 맞춘다.

8. 완료 후 보고할 것:

- _buildKeepersBody() 수정 내용
- Firestore 쿼리 단순화 여부
- pinned_at 정렬을 Dart 쪽으로 옮겼는지 여부
- snapshot.hasError 처리 추가 여부
- is_deleted 누락 문서 대응 여부
- flutter analyze 결과