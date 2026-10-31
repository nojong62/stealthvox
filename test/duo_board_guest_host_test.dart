import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/widgets/duo_board_sheet.dart';

void main() {
  test('a phone that ever signed in as a member does not get the guest button',
      () {
    expect(duoBoardDeviceHasMemberLogin('google'), isTrue);
    expect(duoBoardDeviceHasMemberLogin('kakao'), isTrue);
    expect(duoBoardDeviceHasMemberLogin('email'), isTrue);
  });

  test('a phone with no member login history keeps the guest button', () {
    expect(duoBoardDeviceHasMemberLogin(''), isFalse);
    expect(duoBoardDeviceHasMemberLogin('custom'), isFalse);
  });

  test('posts without ownerIsMember are older member posts', () {
    expect(duoBoardPostOwnerIsMember(const {}), isTrue);
    expect(duoBoardPostOwnerIsMember(const {'ownerIsMember': true}), isTrue);
    expect(duoBoardPostOwnerIsMember(const {'ownerIsMember': false}), isFalse);
  });
}
