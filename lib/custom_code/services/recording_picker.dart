import 'dart:typed_data';

/// 유저가 고른 녹음 파일.
class PickedRecording {
  const PickedRecording({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
}

/// 녹음 가져오기 입구를 모드 선택 화면에 보일지.
///
/// 파일 선택 패키지(`file_picker`)가 아직 pubspec에 없어 [pickRecording]이
/// 비어 있다. 패키지를 넣고 [pickRecording]을 채운 뒤, 폰에서 한 번 확인하고
/// 이 값을 true로 바꾼다. 그 전에는 버튼이 보이지 않는다.
const bool kRecordingImportEnabled = false;

/// 안드로이드 파일 선택창을 열어 오디오 파일 하나를 받는다. 취소하면 null.
///
/// TODO(file_picker): `file_picker`를 추가하고 `FileType.custom`으로
/// m4a·mp3·aac·wav·ogg·flac·3gp만 보이게 한 뒤 `withData: true`로 바이트를
/// 받아 돌려준다. 크기 한도는 `kRecordingMaxBytes`(recording_scenario_service).
Future<PickedRecording?> pickRecording() async => null;
