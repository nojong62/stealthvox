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

지시문: 인트로 화면에 Anyone 이용 방법 안내 카드 추가
대상 파일: lib/custom_code/widgets/intro_master.dart (프로젝트 내 실제 경로로 대체)
1. 사전 준비
powershellgit add -A
git commit -m "savepoint: before intro usage guide card"
2. 앵커 유일성 확인 (count=1 필수)
powershellSelect-String -Path "intro_master.dart" -Pattern "공부방 2분"
Select-String -Path "intro_master.dart" -Pattern "0x996F66D8"
→ 두 패턴 모두 정확히 1건씩 나와야 진행. 아니면 중단하고 보고.
3. str_replace 적용
old_str (정확히 일치해야 함):
dart                            Text("공부방 2분",
                                style: GoogleFonts.roboto(
                                    fontSize: 11,
                                    color: const Color(0xFFA7A7AE))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0x996F66D8),
new_str:
dart                            Text("공부방 2분",
                                style: GoogleFonts.roboto(
                                    fontSize: 11,
                                    color: const Color(0xFFA7A7AE))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Row(
                        children: [
                          Icon(Icons.lightbulb, color: Colors.amber, size: 20),
                          SizedBox(width: 8),
                          Text("이용 방법",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '대화하고 싶은 사람을 한 명 마음속에 떠올려 보세요. 그리고 그 사람이 바로 지금 눈앞에 있다고 생각하고, 하고 싶었던 말을 편하게 꺼내보세요. AI가 그 사람과 다르게 반응한다면, 그냥 넘기지 말고 "왜 그렇게 느껴?"하고 되물어 보세요. 묻고 답하다 보면, AI는 점점 더 그 사람에 가까워집니다. 진짜 그 사람과 마주 앉은 것처럼요.',
                        style: TextStyle(
                            color: Colors.white70, fontSize: 13, height: 1.6),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0x996F66D8),
4. 사후 grep 검증
powershellSelect-String -Path "intro_master.dart" -Pattern "이용 방법"
→ 2건 나와야 정상 (기존 Anyone 모드 다이얼로그 1건 + 새로 추가한 인트로 카드 1건). 1건뿐이면 삽입 실패, 3건 이상이면 중복 삽입 — 둘 다 중단하고 보고.
5. 포맷 (해당 파일만, 폴더 단위 금지)
powershelldart format intro_master.dart
6. 빌드 검증
powershellflutter analyze
flutter build apk --debug
7. 커밋
powershellgit add intro_master.dart
git commit -m "feat: intro 화면에 Anyone 이용 방법 안내 카드 추가 (로그인 버튼 위)"
8. 롤백 (문제 발생 시)
powershellgit reset --hard HEAD~1