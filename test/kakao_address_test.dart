import 'package:flutter_test/flutter_test.dart';
import 'package:jibang_listing_test/kakao_address.dart';

void main() {
  test('stores road, jibun, postal code and legal dong code', () {
    final address = KakaoAddress.fromPostcode({
      'zonecode': '06236',
      'address': '서울 강남구 테헤란로 152',
      'addressType': 'R',
      'userSelectedType': 'R',
      'roadAddress': '서울 강남구 테헤란로 152',
      'jibunAddress': '서울 강남구 역삼동 737',
      'bcode': '1168010100',
      'buildingName': '강남파이낸스센터',
    });
    expect(address.toFormValues(), {
      'address': '서울 강남구 테헤란로 152',
      'roadAddress': '서울 강남구 테헤란로 152',
      'jibunAddress': '서울 강남구 역삼동 737',
      'postalCode': '06236',
      'legalDongCode': '1168010100',
      'buildingName': '강남파이낸스센터',
    });
  });

  test('uses the jibun line when the user selected it', () {
    final address = KakaoAddress.fromPostcode({
      'zonecode': '06236',
      'userSelectedType': 'J',
      'roadAddress': '서울 강남구 테헤란로 152',
      'jibunAddress': '서울 강남구 역삼동 737',
      'bcode': '1168010100',
      'buildingName': '',
    });
    expect(address.displayAddress, '서울 강남구 역삼동 737');
    expect(address.buildingName, isNull);
  });

  test('falls back to auto-mapped addresses after "선택 안함"', () {
    final address = KakaoAddress.fromPostcode({
      'zonecode': '06236',
      'userSelectedType': 'R',
      'roadAddress': '서울 강남구 테헤란로 152',
      'jibunAddress': '',
      'autoJibunAddress': '서울 강남구 역삼동 737',
      'noSelected': 'Y',
    });
    expect(address.jibunAddress, '서울 강남구 역삼동 737');
  });

  test('embed page loads the official script and reports via the channel', () {
    expect(
      postcodeHtml,
      contains(
        'https://t1.kakaocdn.net/mapjsapi/bundle/postcode/prod/postcode.v2.js',
      ),
    );
    expect(postcodeHtml, contains('.embed('));
    expect(postcodeHtml, contains('$postcodeChannelName.postMessage'));
    expect(postcodeHtml, isNot(contains('.open(')));
  });
}
