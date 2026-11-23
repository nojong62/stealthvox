import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/native_expression.dart';

String _wrap(Object content) => jsonEncode({
      'choices': [
        {
          'message': {'content': content is String ? content : jsonEncode(content)}
        }
      ]
    });

void main() {
  test('reads expression, meaning and usage', () {
    final e = parseNativeExpressionResponse(_wrap({
      'expression': 'call it a day',
      'meaning': '그만 끝내다',
      'usage': '일을 마무리할 때 써요.',
    }));
    expect(e, isNotNull);
    expect(e!.expression, 'call it a day');
    expect(e.meaning, '그만 끝내다');
    expect(e.usage, '일을 마무리할 때 써요.');
  });

  test('empty expression is null', () {
    expect(parseNativeExpressionResponse(_wrap({'expression': ' '})), isNull);
  });

  test('broken body is null', () {
    expect(parseNativeExpressionResponse('not json'), isNull);
    expect(parseNativeExpressionResponse(_wrap('not json')), isNull);
  });
}
