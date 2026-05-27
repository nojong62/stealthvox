// Automatic FlutterFlow imports
import '/backend/backend.dart';
import '/backend/schema/structs/index.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom widgets
import '/custom_code/actions/index.dart'; // Imports custom actions
import '/flutter_flow/custom_functions.dart'; // Imports custom functions
import 'package:flutter/material.dart';
// Begin custom widget code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingMaster extends StatefulWidget {
  const OnboardingMaster({
    Key? key,
    this.width,
    this.height,
  }) : super(key: key);

  final double? width;
  final double? height;

  @override
  _OnboardingMasterState createState() => _OnboardingMasterState();
}

class _OnboardingMasterState extends State<OnboardingMaster> {
  final PageController _pageController = PageController(initialPage: 0);
  int _currentPage = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkIfAlreadySeen();
  }

  Future<void> _checkIfAlreadySeen() async {
    // ⭐️ [테스트용] 무조건 보이도록 설정! 나중에 출시할 때는 true로 바꾸거나 삭제하세요.
    bool hasSeen = false;

    if (hasSeen && mounted) {
      context.goNamed('Intro');
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finishOnboarding() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', true);

    if (mounted) {
      context.goNamed('Intro');
    }
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.animateToPage(
        _currentPage + 1,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      _finishOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        width: widget.width ?? double.infinity,
        height: widget.height ?? double.infinity,
        color: const Color(0xFF0F172A),
      );
    }

    return Container(
      width: widget.width ?? double.infinity,
      height: widget.height ?? double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0F172A),
            Color(0xFF020617),
          ],
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            PageView(
              controller: _pageController,
              onPageChanged: (int page) {
                setState(() {
                  _currentPage = page;
                });
              },
              physics: const BouncingScrollPhysics(),
              children: [
                _buildPage(
                  stepText: "STEP 1. 로비 설정",
                  imageUrl:
                      "https://images.unsplash.com/photo-1516321497487-e288fb19713f?q=80&w=800&auto=format&fit=crop", // 임시 이미지 (나중에 변경 가능)
                  title: "나만의 AI 파트너 생성",
                  description:
                      "면접관, 해외 바이어, 외국인 친구 등\n오늘 연습할 상황과 대화 상대를 직접 설정하세요.\n입력된 정보에 맞춰 완벽한 롤플레잉 파트너가 준비됩니다.",
                ),
                _buildPage(
                  stepText: "STEP 2. 음성 대화방",
                  imageUrl:
                      "https://images.unsplash.com/photo-1589254065878-42c9da997008?q=80&w=800&auto=format&fit=crop", // 임시 이미지 (나중에 변경 가능)
                  title: "실전 같은 음성 롤플레잉",
                  description:
                      "화면의 마이크를 켜고 실제 대화하듯 말해보세요.\n문법이 틀려도, 말이 중간에 끊겨도\nAI가 문맥을 파악해 자연스럽게 대화를 이끌어줍니다.",
                ),
                _buildPage(
                  stepText: "STEP 3. 히스토리 & 복습",
                  imageUrl:
                      "https://images.unsplash.com/photo-1456406644174-8ddd4cd52a06?q=80&w=800&auto=format&fit=crop", // 임시 이미지 (나중에 변경 가능)
                  title: "대화 분석 및 역할 교대",
                  description:
                      "방금 나눈 대화의 텍스트 스크립트를 확인하고\n부족한 표현을 교정받으세요. 'Practice' 모드를 켜면\nAI와 역할을 서로 바꿔 더욱 깊이 있는 복습이 가능합니다.",
                ),
              ],
            ),

            // 상단 건너뛰기 버튼
            Positioned(
              top: 10,
              right: 20,
              child: AnimatedOpacity(
                opacity: _currentPage == 2 ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 300),
                child: TextButton(
                  onPressed: _currentPage == 2 ? null : _finishOnboarding,
                  child: const Text(
                    "건너뛰기",
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),

            // ⭐️ 하단 내비게이션 바 (점 아이콘 & 다음 버튼) ⭐️
            Positioned(
              bottom: 40,
              left: 32,
              right: 32,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 좌측: 인디케이터 (점)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(3, (index) => _buildDot(index)),
                  ),

                  // 우측: 작고 깔끔한 원형 아이콘 버튼
                  GestureDetector(
                    onTap: _nextPage,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A84FF),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0A84FF).withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Icon(
                          _currentPage == 2
                              ? Icons.check_rounded // 시작(완료) 아이콘
                              : Icons.arrow_forward_rounded, // 다음 페이지 아이콘
                          key: ValueKey<int>(_currentPage),
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ⭐️ 이미지와 텍스트를 함께 보여주는 페이지 헬퍼 위젯
  Widget _buildPage({
    required String stepText,
    required String imageUrl,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 스텝 라벨 (예: STEP 1. 로비 설정)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0A84FF).withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: const Color(0xFF0A84FF).withOpacity(0.5)),
            ),
            child: Text(
              stepText,
              style: GoogleFonts.notoSans(
                color: const Color(0xFF60A5FA),
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 32),

          // 사진(앱 스크린샷) 들어갈 영역
          Container(
            height: 240, // 이미지 높이
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
              image: DecorationImage(
                image: NetworkImage(imageUrl),
                fit: BoxFit.cover, // 이미지를 영역에 꽉 차게 덮음
              ),
            ),
          ),
          const SizedBox(height: 40),

          // 타이틀
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSans(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 20),

          // 구체적인 설명
          Text(
            description,
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSans(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    bool isActive = _currentPage == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      height: 8,
      width: isActive ? 24 : 8,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF0A84FF) : Colors.white24,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
