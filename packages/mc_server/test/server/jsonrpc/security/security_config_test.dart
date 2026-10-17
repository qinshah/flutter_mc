// 判据：SecurityConfig.java:6/:8-10/:12-24。
import 'package:mc_server/mc_server.dart';
import 'package:test/test.dart';

void main() {
  group('SecurityConfig.isValid（判据 :8-10，口径 ^[a-zA-Z0-9]{40}\$）', () {
    test('空串为 false', () => expect(SecurityConfig.isValid(''), isFalse));

    test('40 位字母数字为 true', () {
      expect(
        SecurityConfig.isValid('AbCdEf0123456789AbCdEf0123456789AbCdEf01'),
        isTrue,
      );
    });

    test('39 位 / 41 位为 false', () {
      expect(SecurityConfig.isValid('a' * 39), isFalse);
      expect(SecurityConfig.isValid('a' * 41), isFalse);
    });

    test('含非字母数字字符为 false', () {
      expect(SecurityConfig.isValid('${'a' * 39}-'), isFalse);
      expect(SecurityConfig.isValid('${'a' * 39}_'), isFalse);
    });
  });

  group('SecurityConfig.generateSecretKey（判据 :12-24）', () {
    test('长度 40 且字符集合法', () {
      for (var i = 0; i < 20; i++) {
        final key = SecurityConfig.generateSecretKey();
        expect(key.length, 40);
        expect(SecurityConfig.isValid(key), isTrue);
        expect(RegExp(r'^[a-zA-Z0-9]{40}$').hasMatch(key), isTrue);
      }
    });

    test('两次生成不同（SecureRandom）', () {
      expect(SecurityConfig.generateSecretKey(),
          isNot(SecurityConfig.generateSecretKey()));
    });
  });
}
