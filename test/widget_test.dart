import 'package:flutter_test/flutter_test.dart';
import 'package:jolrekha/config.dart';
import 'package:jolrekha/services/auth_service.dart';

void main() {
  test('phone numbers normalise to 01XXXXXXXXX', () {
    expect(AuthService.normalizePhone('01712345678'), '01712345678');
    expect(AuthService.normalizePhone('+880 1712-345678'), '01712345678');
    expect(AuthService.normalizePhone('8801712345678'), '01712345678');
    expect(AuthService.normalizePhone('01212345678'), isNull); // no such operator prefix
    expect(AuthService.normalizePhone('12345'), isNull);
  });

  test('leaderboard badges', () {
    expect(Points.badge(0), 'নতুন সদস্য');
    expect(Points.badge(60), 'সক্রিয় নাগরিক');
    expect(Points.badge(250), 'জলযোদ্ধা');
    expect(Points.badge(900), 'পরিবেশ বীর');
  });
}
