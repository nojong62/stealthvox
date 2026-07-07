import 'package:flutter/material.dart';

import '/flutter_flow/flutter_flow_theme.dart';

class TermsResult {
  const TermsResult({
    required this.termsAccepted,
    required this.privacyAccepted,
    required this.ageConfirmed,
    required this.marketingAccepted,
  });

  final bool termsAccepted;
  final bool privacyAccepted;
  final bool ageConfirmed;
  final bool marketingAccepted;
}

class TermsAgreementSheet extends StatefulWidget {
  const TermsAgreementSheet({super.key});

  static Future<TermsResult?> show(BuildContext context) {
    return showModalBottomSheet<TermsResult>(
      context: context,
      isDismissible: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (context) => const TermsAgreementSheet(),
    );
  }

  @override
  State<TermsAgreementSheet> createState() => _TermsAgreementSheetState();
}

class _TermsAgreementSheetState extends State<TermsAgreementSheet> {
  static const Color _backgroundColor = Color(0xFF1E1E22);
  static const Color _brandBlue = Color(0xFF4A90D9);
  static const Color _primaryText = Colors.white;
  static const Color _secondaryText = Color(0xFFB8B8C0);
  static const Color _dividerColor = Color(0xFF36363C);
  static const Color _disabledButton = Color(0xFF4A4A52);

  bool _termsAccepted = false;
  bool _privacyAccepted = false;
  bool _ageConfirmed = false;
  bool _marketingAccepted = false;

  bool get _allAccepted =>
      _termsAccepted && _privacyAccepted && _ageConfirmed && _marketingAccepted;

  bool get _requiredAccepted =>
      _termsAccepted && _privacyAccepted && _ageConfirmed;

  void _setAllAccepted(bool value) {
    setState(() {
      _termsAccepted = value;
      _privacyAccepted = value;
      _ageConfirmed = value;
      _marketingAccepted = value;
    });
  }

  void _submit() {
    if (!_requiredAccepted) return;

    Navigator.pop(
      context,
      TermsResult(
        termsAccepted: _termsAccepted,
        privacyAccepted: _privacyAccepted,
        ageConfirmed: _ageConfirmed,
        marketingAccepted: _marketingAccepted,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final bottomPadding = MediaQuery.viewInsetsOf(context).bottom +
        MediaQuery.paddingOf(context).bottom;

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: _backgroundColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(24, 12, 24, 16 + bottomPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'StealthVox 회원가입',
              style: theme.titleMedium.override(
                fontFamily: theme.titleMediumFamily,
                color: _primaryText,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                useGoogleFonts: false,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '회원가입을 위하여 아래의 필수 약관에 동의해 주세요',
              style: theme.bodyMedium.override(
                fontFamily: theme.bodyMediumFamily,
                color: _secondaryText,
                fontSize: 14,
                useGoogleFonts: false,
              ),
            ),
            const SizedBox(height: 28),
            _AgreementRow(
              label: '전체 동의',
              checked: _allAccepted,
              isPrimary: true,
              onChanged: _setAllAccepted,
            ),
            const SizedBox(height: 18),
            const Divider(height: 1, thickness: 1, color: _dividerColor),
            const SizedBox(height: 18),
            _AgreementRow(
              label: '(필수) 서비스 이용약관 동의',
              checked: _termsAccepted,
              showTrailingLink: true,
              onChanged: (value) => setState(() => _termsAccepted = value),
              onTrailingTap: () {},
            ),
            _AgreementRow(
              label: '(필수) 개인정보 수집 및 이용 동의',
              checked: _privacyAccepted,
              showTrailingLink: true,
              onChanged: (value) => setState(() => _privacyAccepted = value),
              onTrailingTap: () {},
            ),
            _AgreementRow(
              label: '(필수) 만 14세 이상입니다',
              checked: _ageConfirmed,
              onChanged: (value) => setState(() => _ageConfirmed = value),
            ),
            _AgreementRow(
              label: '(선택) 마케팅 정보 수신 동의',
              checked: _marketingAccepted,
              onChanged: (value) => setState(() => _marketingAccepted = value),
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _requiredAccepted ? _submit : null,
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: _brandBlue,
                  disabledBackgroundColor: _disabledButton,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white.withValues(alpha: 0.45),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  '계속하기',
                  style: theme.titleSmall.override(
                    fontFamily: theme.titleSmallFamily,
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    useGoogleFonts: false,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: () => Navigator.pop<TermsResult?>(context, null),
              style: TextButton.styleFrom(
                foregroundColor: _secondaryText,
                padding: const EdgeInsets.symmetric(vertical: 10),
                textStyle: theme.bodyMedium.override(
                  fontFamily: theme.bodyMediumFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  useGoogleFonts: false,
                ),
              ),
              child: const Text('취소'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgreementRow extends StatelessWidget {
  const _AgreementRow({
    required this.label,
    required this.checked,
    required this.onChanged,
    this.isPrimary = false,
    this.showTrailingLink = false,
    this.onTrailingTap,
  });

  final String label;
  final bool checked;
  final ValueChanged<bool> onChanged;
  final bool isPrimary;
  final bool showTrailingLink;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final textStyle =
        (isPrimary ? theme.titleSmall : theme.bodyMedium).override(
      fontFamily: isPrimary ? theme.titleSmallFamily : theme.bodyMediumFamily,
      color: Colors.white,
      fontSize: isPrimary ? 17 : 15,
      fontWeight: isPrimary ? FontWeight.w700 : FontWeight.w500,
      useGoogleFonts: false,
    );

    return InkWell(
      onTap: () => onChanged(!checked),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            _CircleCheckBox(
              checked: checked,
              size: isPrimary ? 28 : 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              ),
            ),
            if (showTrailingLink) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: onTrailingTap,
                icon: const Icon(Icons.chevron_right_rounded),
                color: const Color(0xFF8F8F98),
                iconSize: 24,
                visualDensity: VisualDensity.compact,
                tooltip: '약관 보기',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CircleCheckBox extends StatelessWidget {
  const _CircleCheckBox({
    required this.checked,
    required this.size,
  });

  final bool checked;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checked ? const Color(0xFF4A90D9) : Colors.transparent,
        border: Border.all(
          color: checked ? const Color(0xFF4A90D9) : const Color(0xFF74747C),
          width: 1.6,
        ),
      ),
      child: checked
          ? Icon(
              Icons.check_rounded,
              size: size * 0.68,
              color: Colors.white,
            )
          : null,
    );
  }
}
