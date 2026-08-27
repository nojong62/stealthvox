import 'package:provider/provider.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:kakao_flutter_sdk_common/kakao_flutter_sdk_common.dart';
import 'auth/firebase_auth/firebase_user_provider.dart';
import 'auth/firebase_auth/auth_util.dart';

import 'backend/firebase/firebase_config.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import 'flutter_flow/flutter_flow_util.dart';
import 'flutter_flow/nav/nav.dart';
import 'index.dart';
import 'flutter_flow/revenue_cat_util.dart' as revenue_cat;

/// 🔍 [OVERFLOW-SCAN] 디버그 빌드 전용 — 레이아웃이 터진 **자리**를 남긴다.
///
/// Flutter는 한 프레임에 예외가 둘째부터는 본문을 접어
/// `Another exception was thrown: A RenderFlex overflowed by 15 pixels`만
/// 찍는다. 그 접힌 줄에는 어느 파일 몇 번째 줄인지가 없어서, 화면을 캡처해
/// 눈으로 찾는 수밖에 없었다(2026-08-27).
///
/// 매번 오류 카운터를 0으로 되돌려 접힘을 막는다. 그러면 모든 오버플로에
/// `The relevant error-causing widget was: ... file:line`이 붙어 나온다.
/// 로그에서 `[OVERFLOW-SCAN]`으로 모아 보면 된다.
void _installOverflowScanner() {
  if (!kDebugMode) return;
  final previous = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final text = details.exception.toString();
    if (text.contains('overflowed by')) {
      // 📌 [위치 같이 찍기] 전체 리포트는 logcat까지 오지 않는다. 크기만
      //   찍히면 어느 화면인지 다시 캡처로 찾아야 해서, 파일:줄번호를
      //   같은 줄에 붙인다. 위치는 informationCollector 안의 DebugCreator가
      //   들고 있다(원래 "The relevant error-causing widget was"로 나오는 값).
      var where = '';
      try {
        final Iterable<DiagnosticsNode> info =
            details.informationCollector?.call() ?? const <DiagnosticsNode>[];
        for (final node in info) {
          final line = node.toString();
          final at = line.indexOf('file:///');
          if (at >= 0) {
            where = ' @ ${line.substring(at).split(RegExp(r'[\s)]')).first}';
            break;
          }
        }
      } catch (_) {
        // 위치를 못 캐도 크기만은 남긴다.
      }
      debugPrint('🔍 [OVERFLOW-SCAN] $text$where');
    }
    // 접힘 해제 — 다음 예외도 전체 리포트로 찍히게 한다.
    FlutterError.resetErrorCount();
    previous?.call(details);
  };
}

/// 📐 [글자 배율 상한] 기기 글자 크기가 이 배율을 넘어도 여기서 자른다.
///
/// 안전망이지 해결책이 아니다. 2026-08-27 실기기 1.7배에서 나온 깨짐 6건은
/// 전부 고정 높이·스크롤 없음·유연하지 않은 Row 같은 **구조 결함**이었고,
/// 그건 배율과 상관없이 화면이 좁거나 글이 길어도 터진다. 그래서 그쪽을
/// 먼저 구조로 고쳤다. 이 상한은 아직 손대지 않은 화면과, 2.0처럼 더 크게
/// 쓰는 사용자를 위한 것이다.
///
/// 1.5는 접근성과 레이아웃 사이의 타협점이다. 낮추면 안전하지만 크게 보려고
/// 설정을 올린 사용자를 그만큼 무시하게 된다.
///
/// ⚠️ 이 값이 걸려 있으면 그 위 배율은 **테스트되지 않는다**. 실기기에서
///    더 큰 배율을 확인하려면 잠시 이 숫자를 올리고 돌려 봐야 한다.
const double kMaxTextScale = 1.5;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installOverflowScanner();
  GoRouter.optionURLReflectsImperativeAPIs = true;
  usePathUrlStrategy();

  await initFirebase();
  KakaoSdk.init(nativeAppKey: '339271f4dd4676bb030cab2f45de5091');

  await FlutterFlowTheme.initialize();

  final appState = FFAppState(); // Initialize FFAppState
  await appState.initializePersistedState();

  await revenue_cat.initialize(
    "",
    "goog_XfTPcusZVFeDsZEkFHYiFgUUUIK",
    debugLogEnabled: true,
    loadDataAfterLaunch: true,
  );

  await initializeFirebaseRemoteConfig();

  runApp(ChangeNotifierProvider(
    create: (context) => appState,
    child: MyApp(),
  ));
}

class MyApp extends StatefulWidget {
  // This widget is the root of your application.
  @override
  State<MyApp> createState() => _MyAppState();

  static _MyAppState of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>()!;
}

class MyAppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
      };
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = FlutterFlowTheme.themeMode;

  late AppStateNotifier _appStateNotifier;
  late GoRouter _router;
  String getRoute([RouteMatch? routeMatch]) {
    final RouteMatch lastMatch =
        routeMatch ?? _router.routerDelegate.currentConfiguration.last;
    final RouteMatchList matchList = lastMatch is ImperativeRouteMatch
        ? lastMatch.matches
        : _router.routerDelegate.currentConfiguration;
    return matchList.uri.path;
  }

  List<String> getRouteStack() =>
      _router.routerDelegate.currentConfiguration.matches
          .map((e) => getRoute(e))
          .toList();
  late Stream<BaseAuthUser> userStream;

  final authUserSub = authenticatedUserStream.listen((user) {
    revenue_cat.login(user?.uid);
  });

  @override
  void initState() {
    super.initState();

    _appStateNotifier = AppStateNotifier.instance;
    _router = createRouter(_appStateNotifier);
    userStream = stealthVoxFirebaseUserStream()
      ..listen((user) {
        _appStateNotifier.update(user);
      });
    jwtTokenStream.listen((_) {});
    Future.delayed(
      Duration(milliseconds: 1000),
      () => _appStateNotifier.stopShowingSplashImage(),
    );
  }

  @override
  void dispose() {
    authUserSub.cancel();

    super.dispose();
  }

  void setThemeMode(ThemeMode mode) => safeSetState(() {
        _themeMode = mode;
        FlutterFlowTheme.saveThemeMode(mode);
      });

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'StealthVox',
      scrollBehavior: MyAppScrollBehavior(),
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', '')],
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: false,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: false,
      ),
      themeMode: _themeMode,
      routerConfig: _router,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(maxScaleFactor: kMaxTextScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
