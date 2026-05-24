// ignore_for_file: avoid_print
/// Adaptive icon safe-zone padding tool
/// - Source image (300×300) is placed centered on a 450×450 transparent canvas
/// - Ratio: 300/450 = 66.7%  →  matches Android 72dp safe-zone inside 108dp canvas
/// - Also generates white monochrome version for Android 13+
/// Run: dart run tool/pad_icon.dart
library;

import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  print('[pad_icon] Loading source image...');

  final sourceFile = File('assets/images/stealthvox_source.png');
  if (!sourceFile.existsSync()) {
    print('ERROR: assets/images/stealthvox_source.png not found');
    exit(1);
  }

  final srcImg = img.decodePng(sourceFile.readAsBytesSync());
  if (srcImg == null) {
    print('ERROR: Failed to decode PNG');
    exit(1);
  }
  print('[pad_icon] Source: ${srcImg.width}x${srcImg.height}');

  // ── Canvas 크기 계산 ──────────────────────────────────────────────────
  // Adaptive icon safe-zone: 72dp / 108dp = 66.7%
  // → canvas = source * (108 / 72) = source * 1.5
  final canvasSize = (srcImg.width * 1.5).round(); // 300 → 450
  final offset = ((canvasSize - srcImg.width) / 2).round(); // 75px 각 방향

  // ── 투명 캔버스 생성 (foreground) ────────────────────────────────────
  final canvas = img.Image(
    width: canvasSize,
    height: canvasSize,
    numChannels: 4,
    withPalette: false,
  );
  for (final pixel in canvas) {
    pixel.setRgba(0, 0, 0, 0);
  }
  img.compositeImage(canvas, srcImg, dstX: offset, dstY: offset);

  final fgPath = 'assets/images/stealthvox_adaptive_fg.png';
  File(fgPath).writeAsBytesSync(img.encodePng(canvas));
  print('[pad_icon] Saved foreground: $fgPath  (${canvasSize}x${canvasSize})');

  // ── Monochrome 버전 생성 (Android 13+) ───────────────────────────────
  // 비투명 픽셀을 모두 흰색으로 변환 (시스템이 tint 색상 적용)
  final monoCanvas = img.Image(
    width: canvasSize,
    height: canvasSize,
    numChannels: 4,
    withPalette: false,
  );
  for (final pixel in monoCanvas) {
    pixel.setRgba(0, 0, 0, 0);
  }
  img.compositeImage(monoCanvas, srcImg, dstX: offset, dstY: offset);

  // 모든 픽셀의 RGB → white, alpha 유지
  for (final pixel in monoCanvas) {
    final a = pixel.a;
    if (a > 0) {
      pixel.setRgba(255, 255, 255, a.toInt());
    }
  }

  final monoPath = 'assets/images/stealthvox_monochrome.png';
  File(monoPath).writeAsBytesSync(img.encodePng(monoCanvas));
  print('[pad_icon] Saved monochrome: $monoPath  (${canvasSize}x${canvasSize})');

  // ── 일반 아이콘용 복사 (iOS / legacy Android) ────────────────────────
  File('assets/images/app_launcher_icon.png')
      .writeAsBytesSync(sourceFile.readAsBytesSync());
  print('[pad_icon] Copied → assets/images/app_launcher_icon.png');

  // ── Android 13 monochrome drawable 복사 ──────────────────────────────
  final monoDrawablePath =
      'android/app/src/main/res/drawable/ic_launcher_monochrome.png';
  File(monoDrawablePath)
      .writeAsBytesSync(File(monoPath).readAsBytesSync());
  print('[pad_icon] Copied → $monoDrawablePath');

  print('[pad_icon] Done ✓');
}
