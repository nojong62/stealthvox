// ====================================================================
// 🎧 [MIC-ROUTE] 마이크를 열어도 블루투스 회선을 바꾸지 않는다
// --------------------------------------------------------------------
// `record` 플러그인의 안드로이드 기본값은 `manageBluetooth: true`다. 그러면
// 녹음이 시작될 때마다 `startBluetoothSco()`를 불러 이어폰을 **통화 회선
// (SCO, 협대역 16kHz)**으로 바꾸고 음악 회선(A2DP)을 멈춘다.
//
// 2026-09-16 실기기(S25 + 블루투스 이어폰, 서클톡):
//
//   12:16:57.289 LOCAL_RECORDING_STARTED
//   12:16:57.295 setCommunicationRouteForClient uid=앱 type:bt_sco
//   12:16:57.296 A2dpSuspended=true
//   12:16:57.300 bta_ag_sco_open sco_codec=2
//
// 그 뒤로 AI 목소리(TTS)가 전화 품질로 나가 작고 쉭쉭거렸고, 턴마다 마이크를
// 껐다 켜니 회선이 A2DP↔SCO로 오가며 잡음이 꼈다. 유튜브는 A2DP라 멀쩡했고,
// 앱을 나간 직후 1초쯤 작게 들리다 정상이 된 것도 SCO가 풀리는 시간이다.
//
// **재생 품질을 지킨다.** SCO를 켜지 않으면 TTS는 계속 A2DP로 나간다. 대신
// 이어폰 마이크는 못 쓰고 폰 마이크로 말한다 — 블루투스는 "고음질 재생
// (마이크 없음)"과 "통화 회선(양방향·협대역)" 둘뿐이라 둘 다 가질 수 없다.
// 실장님 결정(2026-09-16): 12곳 전부 이쪽.
//
// ⚠️ Duo 직접통화는 여기를 지나지 않는다 — WebRTC가 자체 라우팅을 한다.
// ====================================================================

import 'package:record/record.dart';

/// 마이크를 열 때 넘기는 안드로이드 설정. **모든 `RecordConfig`가 이걸 쓴다.**
const AndroidRecordConfig kMicAndroidConfig =
    AndroidRecordConfig(manageBluetooth: false);
