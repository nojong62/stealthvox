StealthVox 프로젝트 가이드 (FlutterFlow)

 📂 파일 위치 및 위젯 리스트
 모든 화면(Pages): `lib/` 폴더 내 각 이름별 폴더
 커스텀 액션: `lib/custom_code/actions/`
 전역 상태: `lib/app_state.dart`

 🛠️ 커스텀 위젯 (`lib/custom_code/widgets/`)
현재 구현된 위젯 파일들 (새 작업 시 참고):

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

이 내용을 항상 기억하고 지시문에 포함해 줘.
=================================
지시문

통합 지시문 (routine_mode_roleplay.dart) — 전 5곳
[변경 0] static 홀더 클래스 추가 (신규)
위치: Box 1 임포트 블록 맨 아래(현재 41행 import '/custom_code/actions/billing_ticker.dart'; 다음), Box 2 클래스 선언 위에 삽입:
dart// ====================================================================
// 🛡️ [v4] 시나리오 재진입 보존용 static 홀더 (App State 대체)
//   방을 나갔다 다시 들어와도 유저가 세팅/수정한 시나리오를 유지.
// ====================================================================
class _RoleplayScenarioStore {
  static String situation = '';
  static String aiRole = '';
  static String userRole = '';
}
[변경 1] RoleplayBrain에 200개 상황 const 추가
위치: class RoleplayBrain { 바로 다음 줄(현재 3361행 // === 주석 위)에 삽입:
dart  // 📋 [200개 기초 상황 — 카테고리 5종 × 40개] (v4 추가)
  static const List<String> _baseSituations200 = [
    // ── 공항_비행기_교통 (40개) ──
    '기내 의학 환자 발생', '화장실 갇힘 사고', '산소마스크 작동됨', '여권 분실 발견함', '캐리어 파손 확인', '위조지폐 의심됨',
    '입국 거부 위기', '소지품 오인 압수', '결제 오류 지연', '비행기 놓치기 직전', '탑승권 분실함', '미아 발생 신고',
    '승무원 부상 발생', '탑승 거부 당함', '버스 고장 멈춤', '잘못된 티켓 발권', '소매치기 발생', '짐 오인 교환됨', '스크린도어 낌',
    '비상 정지 발생', '지갑 두고 내림', '막차 취소 고립됨', '급격한 복통 발생', '부당 요금 요구', '난폭 운전 공포', '계약 사기 의심',
    '혼유 사고 발생', '차량 타이어 펑크', '차량 배터리 방전', '정산기 고장 멈춤', '예약 누락 발견', '선내 화재 경보',
    '소지품 바다 빠짐', '배 놓치고 고립', '집단 식중독 증상', '가방 문 열려있음', '반납 처리 오류', '공중 멈춤 사고',
    '접촉 사고 후 도주', '차량 출고 불가',
    // ── 호텔_숙소_주거 (40개) ──
    '예약 취소 당함', '방 내부 몰카 의심', '온수 안 나옴', '엘리베이터 갇힘', '익수 사고 발생', '알레르기 발생', '취객 시비 걸림',
    '운동 기구 부상', '화재 경보 대피', '기밀 문서 유출', '소지품 도난당함', '숙소 사진과 다름', '미끄러짐 부상', '텐트 무너짐',
    '멧돼지 출현함', '텐트 불길 번짐', '도어락 고장 갇힘', '동파로 누수 발생', '층간소음 시비', '맹견 진입 위험', '계단 실족 부상',
    '저혈압 실신함', '주인방 무단 침입', '룸메이트 절도', '상한 음식 서빙', '차량 파손 발견', '옥상 문 잠김 갇힘', '독충에 물림',
    '무단 주거 침입', '신분증 도용 의심', '난간 파손 위험', '피부 화상 입음', '독사 출현 비상', '가스 누출 의심', '옷 세탁 중 분실',
    '금고 안 열림', '지하 침수 발생', '택배 분실 항의', '유리창 깨짐', '샹들리에 추락',
    // ── 식당_쇼핑_유흥 (40개) ──
    '머리카락 나옴', '식중독 증상 발현', '기름 불판 화재', '주문 오인 대기', '결제 중복 처리', '커피 쏟아 화상', '식판 엎음 사고',
    '음식 도중 소진', '바가지 요금 청구', '지갑 소매치기', '명품 훼손 시비', '피부 부작용 발생', '몰래카메라 발견', '카트 충돌 부상',
    '거스름돈 사기', '여권 정보 오류', '물건 파손 변상', '지갑 분실 확인', '휴지 없이 갇힘', '유통기한 지남', '취객 싸움 번짐',
    '도난 경보 작동', '소매치기 추격', '에스컬레이터 낌', '낙상 사고 발생', '이물질 치아 파손', '배달 사고 누락', '가스통 폭발 위기',
    '인파 압사 위험', '주차 시비 폭행', '다이아 분실 오해', '신발 도난당함', '책장 쓰러짐 사고', '렌즈 파손 부상', '잘못된 약 복용',
    '교상 사고 발생', '가방 줄 걸려 파손', '칼날 부상 사고', '변질된 음식 판매', '침대 주저앉음',
    // ── 공공장소_병원_비즈니스 (40개) ──
    '의료진 공백 지연', '오진 가능성 확인', '호흡 곤란 환자', '수술 지연 항의', '잇몸 과다 출혈', '보이스피싱 의심', '카드 먹통 됨',
    '중요 택배 분실', '억울한 누명 씀', '긴급 출동 방해', '서류 조작 의심', '비자 발급 거부', '빔프로젝터 폭발', '랜섬웨어 감염됨',
    '정수기 누전 화재', '면접 서류 분실', '무단 침입 시위', '인감 도용 발견', '세금 폭탄 오류', '소송 상대 협박', '노트북 도난당함',
    '시험지 유출 비상', '화학 약품 누출', '등교 미아 발생', '셔틀버스 사고', '전시 작품 훼손', '유물 도난 경보', '무대 조명 추락',
    '영사기 화재 발생', '암표 사기 당함', '맹수 탈출 비상', '독초 오접촉 부상', '유기견 습격함', '열사병 환자 실신', '범죄 의심 비명',
    '부당해고 구제 신청', '부스 무너짐 사고', '생방송 방송 사고', '난입 소요 사태', '집단 감염 의심',
    // ── 레저_관광_자연_기타 (40개) ──
    '이식 조류 표류', '산소통 잔량 고갈', '보드 충돌 실신', '쥐가 나서 익수', '갑작스러운 불어남', '슬라이드 충돌', '낚싯바늘 눈 찔림',
    '실족 고립 조난', '저체온증 발생', '로프 끊어짐 위기', '충돌 골절 부상', '리프트 공중 멈춤', '타구 사고 부상', '파울볼 안면 강타',
    '심장마비 환자 발생', '바벨 낙하 깔림', '관절 탈구 부상', '레인 진입 기계 낌', '스케이트 날 부상', '롤러코스터 멈춤',
    '실제 유령 공포', '오발 사고 발생', '카트 전복 사고', '나무 걸려 조난', '줄 풀림 오인 비상', '사막 식수 고갈', '정글 독충 공격',
    '낙석 낙하 갇힘', '막배 끊겨 고립', '통유리 균열 발견', '낙뢰 사고 발생', '인파 밀집 압사', '캠핑카 일산화탄소', '고온 화상 입음',
    '음향 장비 감전', '울타리 돌파 충돌', '말에서 추락 부상', '탁구대 무너짐', '당구큐대 시비', '코인기기 화재',
  ];
[변경 2] generateDramaticScenario 시드 풀 교체
삭제 범위: 3368행 final genres = [ ~ 3410행 '- Genre hint this round: $pick';
교체:
dart      // 🎲 [v4 합본 풀] 200개 기초 상황 + 20개 장르 씨앗 → 변주 폭 확대
      const genreSeeds = [
        // 일상/긍정 (10개)
        '카페에서 새 메뉴 추천받기', '해외여행 중 현지인과 길 묻기', '새 이웃에게 인사하며 동네 소개',
        '옷가게에서 스타일 상담', '회사 점심시간 동료와 맛집 토크', '헬스장 첫날 트레이너와 상담',
        '공항 체크인 카운터 대화', '호텔 체크인하며 방 업그레이드 요청', '동네 서점에서 책 추천 대화',
        '반려동물 산책 중 견주끼리 대화',
        // 드라마틱/갈등 (10개)
        '불륜 발각, 부부 갈등', '직장 내 권력 다툼, 해고 위기', '형사 심문, 용의자 취조',
        '재벌가 상속 분쟁', '비밀 연인 들킴', '가족 비밀 폭로', '첫사랑 재회, 감정 충돌',
        '룸메이트 생활 규칙 갈등', '환불 요청하는데 매장 직원이 거부', '친구가 빌린 돈 안 갚음',
      ];
      final pool = [..._baseSituations200, ...genreSeeds];
      final pick = pool[Random().nextInt(pool.length)];
      // 200개 합본에 있으면 "그대로 쓸 구체 상황", 20개 씨앗이면 "확장할 장르 힌트"
      final bool isConcrete = _baseSituations200.contains(pick);

      final systemPrompt = "You are a creative director for a high-immersion English roleplay app.\n"
              "Your job is to create ONE vivid scene inspired by real-life situations, Netflix series, Korean/American dramas, or movies.\n"
              "\n"
              "OUTPUT: Return ONLY valid JSON, no extra text.\n"
              "{\n"
              '  "situation": "핵심 상황 요약 (10-15 Korean chars, e.g. 카페에서 신메뉴 추천)",\n'
              '  "ai_role": "AI 캐릭터 (10자 이내, with clear personality, e.g. 친절한 바리스타)",\n'
              '  "user_role": "유저 캐릭터 (8자 이내, e.g. 단골 손님)"\n'
              "}\n"
              "\n"
              "RULES:\n"
              "- situation: vivid and specific. Do NOT name any show/character.\n"
              "- ai_role: give a personality that fits the genre (friendly, enthusiastic, suspicious, furious, etc).\n"
              "- user_role: the user naturally belongs in the scene.\n"
              "- For everyday/positive genres: warm, helpful, curious personalities.\n"
              "- For dramatic/conflict genres: intense, confrontational, emotional personalities.\n" +
          (isConcrete
              ? '- USE THIS EXACT SITUATION as-is: "$pick". Do NOT invent a different one. Keep the situation field essentially equal to "$pick" (light wording polish within 10-15 Korean chars OK). Only assign a fitting ai_role and user_role.'
              : "- Genre hint this round: $pick");
(이하 final res = await client.post(...) 부분은 그대로 둠)
[변경 3-A] init 가드 — _fetchKeysAndInit 전체 교체
삭제 범위: 419행 Future<void> _fetchKeysAndInit() async { ~ 433행 }
교체:
dart  Future<void> _fetchKeysAndInit() async {
    try {
      await FirebaseRemoteConfig.instance.fetchAndActivate();
      if (mounted) {
        setState(() {
          _deepgramKey =
              FirebaseRemoteConfig.instance.getString('DeepgramAPIKey');
          _openAiKey = FirebaseRemoteConfig.instance.getString('OpenAIAPIKey');
        });
        // 🛡️ [v4 가드] 세팅된 시나리오가 있으면 재진입 시 보존, 없으면 새 제안
        if (_RoleplayScenarioStore.situation.isNotEmpty &&
            _RoleplayScenarioStore.aiRole.isNotEmpty &&
            _RoleplayScenarioStore.userRole.isNotEmpty) {
          setState(() {
            _scenarioSituation = _RoleplayScenarioStore.situation;
            _scenarioAiRole = _RoleplayScenarioStore.aiRole;
            _scenarioUserRole = _RoleplayScenarioStore.userRole;
            _scenarioKeyword = _RoleplayScenarioStore.situation;
          });
        } else {
          _generateScenario();
        }
      }
    } catch (e) {
      print('❌ Key Load Error: $e');
    }
  }
[변경 3-B] _generateScenario에 홀더 동기화 추가
삭제 범위: 443행 if (mounted && result != null) { ~ 454행 }
교체:
dart      if (mounted && result != null) {
        setState(() {
          _scenarioKeyword = result['situation'] ?? '';
          _scenarioSituation = result['situation'] ?? '';
          _scenarioAiRole = result['ai_role'] ?? '';
          _scenarioUserRole = result['user_role'] ?? '';
          _sessionDocId = null;
          _myHistoryRef = null;
          _localMessages.clear();
          _isConversationActive = false;
        });
        // 🛡️ [v4] 재진입 보존용 홀더 동기화
        _RoleplayScenarioStore.situation = _scenarioSituation;
        _RoleplayScenarioStore.aiRole = _scenarioAiRole;
        _RoleplayScenarioStore.userRole = _scenarioUserRole;
      }
[변경 3-C] 바텀시트 "확인" — 수정값 홀더 저장
삭제 범위: 524행 setState(() { ~ 533행 }); (확인 onTap 안의 setState)
교체:
dart                      setState(() {
                        _scenarioSituation = sit;
                        _scenarioAiRole = ai;
                        _scenarioUserRole = user;
                        _scenarioKeyword = sit;
                        _sessionDocId = null;
                        _myHistoryRef = null;
                        _localMessages.clear();
                        _isConversationActive = false;
                      });
                      // 🛡️ [v4] 유저 수정값 보존용 홀더 동기화
                      _RoleplayScenarioStore.situation = sit;
                      _RoleplayScenarioStore.aiRole = ai;
                      _RoleplayScenarioStore.userRole = user;

✅ 검증
bashflutter analyze
grep -c "_baseSituations200\|_RoleplayScenarioStore\|isConcrete" routine_mode_roleplay.dart

flutter analyze 에러 0
grep: _baseSituations200 2회↑, _RoleplayScenarioStore 10회↑(클래스 1 + read 3 + write 6), isConcrete 2회 → 정상.


참고로 나중에 로비 같은 다른 화면에서 상황을 골라 넘기고 싶어지면, 그때 이 static 홀더를 그대로 쓰면 됩니다 — 로비에서 _RoleplayScenarioStore.situation = ... 식으로 세팅만 하면 가드가 알아서 그걸 집어 시작합니다. 지금은 그 경로가 없으니 신경 안 쓰셔도 됩니다.