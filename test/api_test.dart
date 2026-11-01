import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fn_audio/api.dart';

void main() {
  group('normalizeBaseUrl', () {
    test('去空格与尾部斜杠', () {
      expect(ApiClient.normalizeBaseUrl('  http://192.168.1.10:8080/ '),
          'http://192.168.1.10:8080');
      expect(ApiClient.normalizeBaseUrl('https://music.example.com/'),
          'https://music.example.com');
    });

    test('非法协议与空串抛异常', () {
      expect(() => ApiClient.normalizeBaseUrl(''), throwsFormatException);
      expect(() => ApiClient.normalizeBaseUrl('ftp://1.2.3.4'),
          throwsFormatException);
      expect(() => ApiClient.normalizeBaseUrl('not a url'),
          throwsFormatException);
    });
  });

  group('setBaseUrl 持久化与优先级', () {
    test('手动地址生效，恢复默认回退', () async {
      SharedPreferences.setMockInitialValues({});
      final api = ApiClient.instance;
      await api.loadSession();
      final fallback = ApiClient.platformDefault;
      expect(api.baseUrl, fallback);

      await api.setBaseUrl('http://10.0.0.5:9000/');
      expect(api.baseUrl, 'http://10.0.0.5:9000');
      expect(api.dio.options.baseUrl, 'http://10.0.0.5:9000');

      // 重新加载后仍从持久化中恢复
      await api.setBaseUrl(null);
      expect(api.baseUrl, fallback);
    });
  });
}
