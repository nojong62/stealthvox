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

# 🎯 롤플레이 위젯 — 200개 긴급상황 데이터 하드코딩 작업 지시문

## 📋 작업 개요
`routine_mode_roleplay.dart` 파일에서 외부 JSON 파일(`assets/jsons/emergency_situations_200.json`)을 `rootBundle`로 읽던 방식을 제거하고, 200개 긴급상황 데이터를 Dart 코드 내부에 직접 하드코딩하여 바텀시트의 카테고리 탭별 상황 목록이 정상 표시되도록 수정한다.

## 📁 작업 대상 파일
- `routine_mode_roleplay.dart` (위젯 폴더 내)
- `200개_상황설정.txt` (위젯 폴더 내, 참조용 JSON 원본)

---

## 🔧 변경 1: 데이터 상수 추가 (파일 최하단, 마지막 클래스 닫는 중괄호 아래)

파일의 맨 아래쪽(모든 클래스 정의 바깥)에 아래 top-level 상수를 추가한다.
`200개_상황설정.txt` 파일의 JSON 내용을 참조하여 정확히 200개 항목을 Dart List 리터럴로 변환한다.

```dart
// ============================================================================
// 🚨 긴급 상황 200개 하드코딩 데이터
// ============================================================================
const List<Map<String, dynamic>> kEmergencySituations = [
  {'id': 1, 'category': '공항_비행기_교통', 'situation': '기내 의학 환자 발생'},
  {'id': 2, 'category': '공항_비행기_교통', 'situation': '화장실 갇힘 사고'},
  {'id': 3, 'category': '공항_비행기_교통', 'situation': '산소마스크 작동됨'},
  {'id': 4, 'category': '공항_비행기_교통', 'situation': '여권 분실 발견함'},
  {'id': 5, 'category': '공항_비행기_교통', 'situation': '캐리어 파손 확인'},
  {'id': 6, 'category': '공항_비행기_교통', 'situation': '위조지폐 의심됨'},
  {'id': 7, 'category': '공항_비행기_교통', 'situation': '입국 거부 위기'},
  {'id': 8, 'category': '공항_비행기_교통', 'situation': '소지품 오인 압수'},
  {'id': 9, 'category': '공항_비행기_교통', 'situation': '결제 오류 지연'},
  {'id': 10, 'category': '공항_비행기_교통', 'situation': '비행기 놓치기 직전'},
  {'id': 11, 'category': '공항_비행기_교통', 'situation': '탑승권 분실함'},
  {'id': 12, 'category': '공항_비행기_교통', 'situation': '미아 발생 신고'},
  {'id': 13, 'category': '공항_비행기_교통', 'situation': '승무원 부상 발생'},
  {'id': 14, 'category': '공항_비행기_교통', 'situation': '탑승 거부 당함'},
  {'id': 15, 'category': '공항_비행기_교통', 'situation': '버스 고장 멈춤'},
  {'id': 16, 'category': '공항_비행기_교통', 'situation': '잘못된 티켓 발권'},
  {'id': 17, 'category': '공항_비행기_교통', 'situation': '소매치기 발생'},
  {'id': 18, 'category': '공항_비행기_교통', 'situation': '짐 오인 교환됨'},
  {'id': 19, 'category': '공항_비행기_교통', 'situation': '스크린도어 낌'},
  {'id': 20, 'category': '공항_비행기_교통', 'situation': '비상 정지 발생'},
  {'id': 21, 'category': '공항_비행기_교통', 'situation': '지갑 두고 내림'},
  {'id': 22, 'category': '공항_비행기_교통', 'situation': '막차 취소 고립됨'},
  {'id': 23, 'category': '공항_비행기_교통', 'situation': '급격한 복통 발생'},
  {'id': 24, 'category': '공항_비행기_교통', 'situation': '부당 요금 요구'},
  {'id': 25, 'category': '공항_비행기_교통', 'situation': '난폭 운전 공포'},
  {'id': 26, 'category': '공항_비행기_교통', 'situation': '계약 사기 의심'},
  {'id': 27, 'category': '공항_비행기_교통', 'situation': '혼유 사고 발생'},
  {'id': 28, 'category': '공항_비행기_교통', 'situation': '차량 타이어 펑크'},
  {'id': 29, 'category': '공항_비행기_교통', 'situation': '차량 배터리 방전'},
  {'id': 30, 'category': '공항_비행기_교통', 'situation': '정산기 고장 멈춤'},
  {'id': 31, 'category': '공항_비행기_교통', 'situation': '예약 누락 발견'},
  {'id': 32, 'category': '공항_비행기_교통', 'situation': '선내 화재 경보'},
  {'id': 33, 'category': '공항_비행기_교통', 'situation': '소지품 바다 빠짐'},
  {'id': 34, 'category': '공항_비행기_교통', 'situation': '배 놓치고 고립'},
  {'id': 35, 'category': '공항_비행기_교통', 'situation': '집단 식중독 증상'},
  {'id': 36, 'category': '공항_비행기_교통', 'situation': '가방 문 열려있음'},
  {'id': 37, 'category': '공항_비행기_교통', 'situation': '반납 처리 오류'},
  {'id': 38, 'category': '공항_비행기_교통', 'situation': '공중 멈춤 사고'},
  {'id': 39, 'category': '공항_비행기_교통', 'situation': '접촉 사고 후 도주'},
  {'id': 40, 'category': '공항_비행기_교통', 'situation': '차량 출고 불가'},
  {'id': 41, 'category': '호텔_숙소_주거', 'situation': '예약 취소 당함'},
  {'id': 42, 'category': '호텔_숙소_주거', 'situation': '방 내부 몰카 의심'},
  {'id': 43, 'category': '호텔_숙소_주거', 'situation': '온수 안 나옴'},
  {'id': 44, 'category': '호텔_숙소_주거', 'situation': '엘리베이터 갇힘'},
  {'id': 45, 'category': '호텔_숙소_주거', 'situation': '익수 사고 발생'},
  {'id': 46, 'category': '호텔_숙소_주거', 'situation': '알레르기 발생'},
  {'id': 47, 'category': '호텔_숙소_주거', 'situation': '취객 시비 걸림'},
  {'id': 48, 'category': '호텔_숙소_주거', 'situation': '운동 기구 부상'},
  {'id': 49, 'category': '호텔_숙소_주거', 'situation': '화재 경보 대피'},
  {'id': 50, 'category': '호텔_숙소_주거', 'situation': '기밀 문서 유출'},
  {'id': 51, 'category': '호텔_숙소_주거', 'situation': '소지품 도난당함'},
  {'id': 52, 'category': '호텔_숙소_주거', 'situation': '숙소 사진과 다름'},
  {'id': 53, 'category': '호텔_숙소_주거', 'situation': '미끄러짐 부상'},
  {'id': 54, 'category': '호텔_숙소_주거', 'situation': '텐트 무너짐'},
  {'id': 55, 'category': '호텔_숙소_주거', 'situation': '멧돼지 출현함'},
  {'id': 56, 'category': '호텔_숙소_주거', 'situation': '텐트 불길 번짐'},
  {'id': 57, 'category': '호텔_숙소_주거', 'situation': '도어락 고장 갇힘'},
  {'id': 58, 'category': '호텔_숙소_주거', 'situation': '동파로 누수 발생'},
  {'id': 59, 'category': '호텔_숙소_주거', 'situation': '층간소음 시비'},
  {'id': 60, 'category': '호텔_숙소_주거', 'situation': '맹견 진입 위험'},
  {'id': 61, 'category': '호텔_숙소_주거', 'situation': '계단 실족 부상'},
  {'id': 62, 'category': '호텔_숙소_주거', 'situation': '저혈압 실신함'},
  {'id': 63, 'category': '호텔_숙소_주거', 'situation': '주인방 무단 침입'},
  {'id': 64, 'category': '호텔_숙소_주거', 'situation': '룸메이트 절도'},
  {'id': 65, 'category': '호텔_숙소_주거', 'situation': '상한 음식 서빙'},
  {'id': 66, 'category': '호텔_숙소_주거', 'situation': '차량 파손 발견'},
  {'id': 67, 'category': '호텔_숙소_주거', 'situation': '옥상 문 잠김 갇힘'},
  {'id': 68, 'category': '호텔_숙소_주거', 'situation': '독충에 물림'},
  {'id': 69, 'category': '호텔_숙소_주거', 'situation': '무단 주거 침입'},
  {'id': 70, 'category': '호텔_숙소_주거', 'situation': '신분증 도용 의심'},
  {'id': 71, 'category': '호텔_숙소_주거', 'situation': '난간 파손 위험'},
  {'id': 72, 'category': '호텔_숙소_주거', 'situation': '피부 화상 입음'},
  {'id': 73, 'category': '호텔_숙소_주거', 'situation': '독사 출현 비상'},
  {'id': 74, 'category': '호텔_숙소_주거', 'situation': '가스 누출 의심'},
  {'id': 75, 'category': '호텔_숙소_주거', 'situation': '옷 세탁 중 분실'},
  {'id': 76, 'category': '호텔_숙소_주거', 'situation': '금고 안 열림'},
  {'id': 77, 'category': '호텔_숙소_주거', 'situation': '지하 침수 발생'},
  {'id': 78, 'category': '호텔_숙소_주거', 'situation': '택배 분실 항의'},
  {'id': 79, 'category': '호텔_숙소_주거', 'situation': '유리창 깨짐'},
  {'id': 80, 'category': '호텔_숙소_주거', 'situation': '샹들리에 추락'},
  {'id': 81, 'category': '식당_쇼핑_유흥', 'situation': '머리카락 나옴'},
  {'id': 82, 'category': '식당_쇼핑_유흥', 'situation': '식중독 증상 발현'},
  {'id': 83, 'category': '식당_쇼핑_유흥', 'situation': '기름 불판 화재'},
  {'id': 84, 'category': '식당_쇼핑_유흥', 'situation': '주문 오인 대기'},
  {'id': 85, 'category': '식당_쇼핑_유흥', 'situation': '결제 중복 처리'},
  {'id': 86, 'category': '식당_쇼핑_유흥', 'situation': '커피 쏟아 화상'},
  {'id': 87, 'category': '식당_쇼핑_유흥', 'situation': '식판 엎음 사고'},
  {'id': 88, 'category': '식당_쇼핑_유흥', 'situation': '음식 도중 소진'},
  {'id': 89, 'category': '식당_쇼핑_유흥', 'situation': '바가지 요금 청구'},
  {'id': 90, 'category': '식당_쇼핑_유흥', 'situation': '지갑 소매치기'},
  {'id': 91, 'category': '식당_쇼핑_유흥', 'situation': '명품 훼손 시비'},
  {'id': 92, 'category': '식당_쇼핑_유흥', 'situation': '피부 부작용 발생'},
  {'id': 93, 'category': '식당_쇼핑_유흥', 'situation': '몰래카메라 발견'},
  {'id': 94, 'category': '식당_쇼핑_유흥', 'situation': '카트 충돌 부상'},
  {'id': 95, 'category': '식당_쇼핑_유흥', 'situation': '거스름돈 사기'},
  {'id': 96, 'category': '식당_쇼핑_유흥', 'situation': '여권 정보 오류'},
  {'id': 97, 'category': '식당_쇼핑_유흥', 'situation': '물건 파손 변상'},
  {'id': 98, 'category': '식당_쇼핑_유흥', 'situation': '지갑 분실 확인'},
  {'id': 99, 'category': '식당_쇼핑_유흥', 'situation': '휴지 없이 갇힘'},
  {'id': 100, 'category': '식당_쇼핑_유흥', 'situation': '유통기한 지남'},
  {'id': 101, 'category': '식당_쇼핑_유흥', 'situation': '취객 싸움 번짐'},
  {'id': 102, 'category': '식당_쇼핑_유흥', 'situation': '도난 경보 작동'},
  {'id': 103, 'category': '식당_쇼핑_유흥', 'situation': '소매치기 추격'},
  {'id': 104, 'category': '식당_쇼핑_유흥', 'situation': '에스컬레이터 낌'},
  {'id': 105, 'category': '식당_쇼핑_유흥', 'situation': '낙상 사고 발생'},
  {'id': 106, 'category': '식당_쇼핑_유흥', 'situation': '이물질 치아 파손'},
  {'id': 107, 'category': '식당_쇼핑_유흥', 'situation': '배달 사고 누락'},
  {'id': 108, 'category': '식당_쇼핑_유흥', 'situation': '가스통 폭발 위기'},
  {'id': 109, 'category': '식당_쇼핑_유흥', 'situation': '인파 압사 위험'},
  {'id': 110, 'category': '식당_쇼핑_유흥', 'situation': '주차 시비 폭행'},
  {'id': 111, 'category': '식당_쇼핑_유흥', 'situation': '다이아 분실 오해'},
  {'id': 112, 'category': '식당_쇼핑_유흥', 'situation': '신발 도난당함'},
  {'id': 113, 'category': '식당_쇼핑_유흥', 'situation': '책장 쓰러짐 사고'},
  {'id': 114, 'category': '식당_쇼핑_유흥', 'situation': '렌즈 파손 부상'},
  {'id': 115, 'category': '식당_쇼핑_유흥', 'situation': '잘못된 약 복용'},
  {'id': 116, 'category': '식당_쇼핑_유흥', 'situation': '교상 사고 발생'},
  {'id': 117, 'category': '식당_쇼핑_유흥', 'situation': '가방 줄 걸려 파손'},
  {'id': 118, 'category': '식당_쇼핑_유흥', 'situation': '칼날 부상 사고'},
  {'id': 119, 'category': '식당_쇼핑_유흥', 'situation': '변질된 음식 판매'},
  {'id': 120, 'category': '식당_쇼핑_유흥', 'situation': '침대 주저앉음'},
  {'id': 121, 'category': '공공장소_병원_비즈니스', 'situation': '의료진 공백 지연'},
  {'id': 122, 'category': '공공장소_병원_비즈니스', 'situation': '오진 가능성 확인'},
  {'id': 123, 'category': '공공장소_병원_비즈니스', 'situation': '호흡 곤란 환자'},
  {'id': 124, 'category': '공공장소_병원_비즈니스', 'situation': '수술 지연 항의'},
  {'id': 125, 'category': '공공장소_병원_비즈니스', 'situation': '잇몸 과다 출혈'},
  {'id': 126, 'category': '공공장소_병원_비즈니스', 'situation': '보이스피싱 의심'},
  {'id': 127, 'category': '공공장소_병원_비즈니스', 'situation': '카드 먹통 됨'},
  {'id': 128, 'category': '공공장소_병원_비즈니스', 'situation': '중요 택배 분실'},
  {'id': 129, 'category': '공공장소_병원_비즈니스', 'situation': '억울한 누명 씀'},
  {'id': 130, 'category': '공공장소_병원_비즈니스', 'situation': '긴급 출동 방해'},
  {'id': 131, 'category': '공공장소_병원_비즈니스', 'situation': '서류 조작 의심'},
  {'id': 132, 'category': '공공장소_병원_비즈니스', 'situation': '비자 발급 거부'},
  {'id': 133, 'category': '공공장소_병원_비즈니스', 'situation': '빔프로젝터 폭발'},
  {'id': 134, 'category': '공공장소_병원_비즈니스', 'situation': '랜섬웨어 감염됨'},
  {'id': 135, 'category': '공공장소_병원_비즈니스', 'situation': '정수기 누전 화재'},
  {'id': 136, 'category': '공공장소_병원_비즈니스', 'situation': '면접 서류 분실'},
  {'id': 137, 'category': '공공장소_병원_비즈니스', 'situation': '무단 침입 시위'},
  {'id': 138, 'category': '공공장소_병원_비즈니스', 'situation': '인감 도용 발견'},
  {'id': 139, 'category': '공공장소_병원_비즈니스', 'situation': '세금 폭탄 오류'},
  {'id': 140, 'category': '공공장소_병원_비즈니스', 'situation': '소송 상대 협박'},
  {'id': 141, 'category': '공공장소_병원_비즈니스', 'situation': '노트북 도난당함'},
  {'id': 142, 'category': '공공장소_병원_비즈니스', 'situation': '시험지 유출 비상'},
  {'id': 143, 'category': '공공장소_병원_비즈니스', 'situation': '화학 약품 누출'},
  {'id': 144, 'category': '공공장소_병원_비즈니스', 'situation': '등교 미아 발생'},
  {'id': 145, 'category': '공공장소_병원_비즈니스', 'situation': '셔틀버스 사고'},
  {'id': 146, 'category': '공공장소_병원_비즈니스', 'situation': '전시 작품 훼손'},
  {'id': 147, 'category': '공공장소_병원_비즈니스', 'situation': '유물 도난 경보'},
  {'id': 148, 'category': '공공장소_병원_비즈니스', 'situation': '무대 조명 추락'},
  {'id': 149, 'category': '공공장소_병원_비즈니스', 'situation': '영사기 화재 발생'},
  {'id': 150, 'category': '공공장소_병원_비즈니스', 'situation': '암표 사기 당함'},
  {'id': 151, 'category': '공공장소_병원_비즈니스', 'situation': '맹수 탈출 비상'},
  {'id': 152, 'category': '공공장소_병원_비즈니스', 'situation': '독초 오접촉 부상'},
  {'id': 153, 'category': '공공장소_병원_비즈니스', 'situation': '유기견 습격함'},
  {'id': 154, 'category': '공공장소_병원_비즈니스', 'situation': '열사병 환자 실신'},
  {'id': 155, 'category': '공공장소_병원_비즈니스', 'situation': '범죄 의심 비명'},
  {'id': 156, 'category': '공공장소_병원_비즈니스', 'situation': '부당해고 구제 신청'},
  {'id': 157, 'category': '공공장소_병원_비즈니스', 'situation': '부스 무너짐 사고'},
  {'id': 158, 'category': '공공장소_병원_비즈니스', 'situation': '생방송 방송 사고'},
  {'id': 159, 'category': '공공장소_병원_비즈니스', 'situation': '난입 소요 사태'},
  {'id': 160, 'category': '공공장소_병원_비즈니스', 'situation': '집단 감염 의심'},
  {'id': 161, 'category': '레저_관광_자연_기타', 'situation': '이식 조류 표류'},
  {'id': 162, 'category': '레저_관광_자연_기타', 'situation': '산소통 잔량 고갈'},
  {'id': 163, 'category': '레저_관광_자연_기타', 'situation': '보드 충돌 실신'},
  {'id': 164, 'category': '레저_관광_자연_기타', 'situation': '쥐가 나서 익수'},
  {'id': 165, 'category': '레저_관광_자연_기타', 'situation': '갑작스러운 불어남'},
  {'id': 166, 'category': '레저_관광_자연_기타', 'situation': '슬라이드 충돌'},
  {'id': 167, 'category': '레저_관광_자연_기타', 'situation': '낚싯바늘 눈 찔림'},
  {'id': 168, 'category': '레저_관광_자연_기타', 'situation': '실족 고립 조난'},
  {'id': 169, 'category': '레저_관광_자연_기타', 'situation': '저체온증 발생'},
  {'id': 170, 'category': '레저_관광_자연_기타', 'situation': '로프 끊어짐 위기'},
  {'id': 171, 'category': '레저_관광_자연_기타', 'situation': '충돌 골절 부상'},
  {'id': 172, 'category': '레저_관광_자연_기타', 'situation': '리프트 공중 멈춤'},
  {'id': 173, 'category': '레저_관광_자연_기타', 'situation': '타구 사고 부상'},
  {'id': 174, 'category': '레저_관광_자연_기타', 'situation': '파울볼 안면 강타'},
  {'id': 175, 'category': '레저_관광_자연_기타', 'situation': '심장마비 환자 발생'},
  {'id': 176, 'category': '레저_관광_자연_기타', 'situation': '바벨 낙하 깔림'},
  {'id': 177, 'category': '레저_관광_자연_기타', 'situation': '관절 탈구 부상'},
  {'id': 178, 'category': '레저_관광_자연_기타', 'situation': '레인 진입 기계 낌'},
  {'id': 179, 'category': '레저_관광_자연_기타', 'situation': '스케이트 날 부상'},
  {'id': 180, 'category': '레저_관광_자연_기타', 'situation': '롤러코스터 멈춤'},
  {'id': 181, 'category': '레저_관광_자연_기타', 'situation': '실제 유령 공포'},
  {'id': 182, 'category': '레저_관광_자연_기타', 'situation': '오발 사고 발생'},
  {'id': 183, 'category': '레저_관광_자연_기타', 'situation': '카트 전복 사고'},
  {'id': 184, 'category': '레저_관광_자연_기타', 'situation': '나무 걸려 조난'},
  {'id': 185, 'category': '레저_관광_자연_기타', 'situation': '줄 풀림 오인 비상'},
  {'id': 186, 'category': '레저_관광_자연_기타', 'situation': '사막 식수 고갈'},
  {'id': 187, 'category': '레저_관광_자연_기타', 'situation': '정글 독충 공격'},
  {'id': 188, 'category': '레저_관광_자연_기타', 'situation': '낙석 낙하 갇힘'},
  {'id': 189, 'category': '레저_관광_자연_기타', 'situation': '막배 끊겨 고립'},
  {'id': 190, 'category': '레저_관광_자연_기타', 'situation': '통유리 균열 발견'},
  {'id': 191, 'category': '레저_관광_자연_기타', 'situation': '낙뢰 사고 발생'},
  {'id': 192, 'category': '레저_관광_자연_기타', 'situation': '인파 밀집 압사'},
  {'id': 193, 'category': '레저_관광_자연_기타', 'situation': '캠핑카 일산화탄소'},
  {'id': 194, 'category': '레저_관광_자연_기타', 'situation': '고온 화상 입음'},
  {'id': 195, 'category': '레저_관광_자연_기타', 'situation': '음향 장비 감전'},
  {'id': 196, 'category': '레저_관광_자연_기타', 'situation': '울타리 돌파 충돌'},
  {'id': 197, 'category': '레저_관광_자연_기타', 'situation': '말에서 추락 부상'},
  {'id': 198, 'category': '레저_관광_자연_기타', 'situation': '탁구대 무너짐'},
  {'id': 199, 'category': '레저_관광_자연_기타', 'situation': '당구큐대 시비'},
  {'id': 200, 'category': '레저_관광_자연_기타', 'situation': '코인기기 화재'},
];
```

---

## 🔧 변경 2: `_loadEmergencySituations()` 함수 교체

현재 코드 (삭제 대상):
```dart
Future<void> _loadEmergencySituations() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/jsons/emergency_situations_200.json');
      final decoded = jsonDecode(jsonStr);
      final data = decoded as Map<String, dynamic>;
      final rawList = data['emergency_situations'];
      if (rawList == null) {
        debugPrint('❌ Emergency JSON: "emergency_situations" key not found');
        return;
      }
      final list = (rawList as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      debugPrint('✅ Emergency situations loaded: ${list.length}');
      if (mounted) setState(() => _emergencySituations = list);
    } catch (e, st) {
      debugPrint('❌ Emergency JSON Load Error: $e\n$st');
    }
  }
```

교체할 코드:
```dart
void _loadEmergencySituations() {
    _emergencySituations = kEmergencySituations
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    debugPrint('✅ Emergency situations loaded: ${_emergencySituations.length}');
  }
```

> ⚠️ 주의: `Future<void>` → `void`로 변경되므로, 이 함수를 호출하는 곳에서 `await` 키워드도 함께 제거해야 한다.

---

## 🔧 변경 3: `await _loadEmergencySituations()` 호출부에서 `await` 제거

파일 내에서 `await _loadEmergencySituations()`를 검색하면 2곳이 나온다:

### 3-A: `initState` 내부의 `_initAll()` 함수 안
```dart
// 변경 전
await _loadEmergencySituations();

// 변경 후
_loadEmergencySituations();
```

### 3-B: `_showSituationPicker()` 함수 안
```dart
// 변경 전
await _loadEmergencySituations();

// 변경 후
_loadEmergencySituations();
```

---

## 🔧 변경 4: 불필요한 import 제거 (해당되는 경우)

`rootBundle`을 더 이상 사용하지 않는다면, 파일 상단의 아래 import를 제거한다:
```dart
import 'package:flutter/services.dart'; // rootBundle
```
단, 이 import가 다른 곳에서도 사용 중인지 확인 후 제거할 것. 
`HapticFeedback`, `SystemChannels` 등 다른 services.dart 클래스를 사용 중이면 **제거하지 않는다**.

---

## ✅ 자체 검증 절차

작업 완료 후 아래 사항을 검증한다:

1. **컴파일 에러 확인**: `_loadEmergencySituations`의 반환 타입이 `void`로 변경되었으므로, `await`가 붙은 호출이 남아 있지 않은지 전체 파일에서 `await _loadEmergencySituations`를 검색하여 0건인지 확인한다.

2. **데이터 개수 확인**: `kEmergencySituations.length`가 정확히 `200`인지 확인한다.

3. **카테고리 매칭 확인**: 코드 내 `_showSituationPicker()`의 categories 배열 key 값과 `kEmergencySituations`의 category 값이 아래 5개로 정확히 일치하는지 확인한다:
   - `공항_비행기_교통` (id 1~40)
   - `호텔_숙소_주거` (id 41~80)
   - `식당_쇼핑_유흥` (id 81~120)
   - `공공장소_병원_비즈니스` (id 121~160)
   - `레저_관광_자연_기타` (id 161~200)

4. **기존 로직 미훼손 확인**: `_generateScenario()`, `_showSituationPicker()`, `_SituationPickerSheet` 클래스의 기존 로직은 변경하지 않았는지 확인한다. 이 함수들은 `_emergencySituations` 리스트만 참조하므로 데이터 소스만 바뀌면 정상 동작한다.

5. **`import 'dart:convert'`의 `jsonDecode`**: `_loadEmergencySituations`에서만 사용하던 것이라면 제거 가능하나, 파일 내 다른 곳에서도 `jsonDecode`/`jsonEncode`를 사용 중이면 유지한다.

---

## ⛔ 절대 건드리지 말 것 (CRITICAL RULES)

- **Box 7 통신 엔진** (`TtsQueueManager`, `DeepgramV2VoiceManager`, `ChunkedTtsFetcher`): 절대 수정 금지
- **`_SituationPickerSheet` 위젯 클래스**: UI 레이아웃 변경 없음 (데이터만 흘러들어가면 자동으로 정상 표시됨)
- **`_generateScenario()` 함수**: AI 시나리오 생성 로직 변경 없음
- **`RoleplayBrain` 클래스**: 프롬프트 및 비즈니스 로직 변경 없음
- **URL을 마크다운 링크로 변환하지 말 것**: 모든 URL은 순수 텍스트 문자열 유지
- **따옴표 이스케이프 주의**: 한국어 문자열 내에 작은따옴표가 포함된 항목이 없으므로 작은따옴표(`'`) 래핑 안전, 만약 있다면 큰따옴표(`"`)로 감쌀 것