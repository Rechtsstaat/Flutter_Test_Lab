# 통합 매물 등록 Flutter 프로토타입

로컬에서 입력한 50개 통합 매물 항목을 직방 매물 등록폼 **재현 페이지**에 주입해 보는 iPhone용 기능 검증 앱입니다. 실제 직방 서비스, 로그인, 등록 API에는 접속하거나 전송하지 않습니다.

## 구성

- 첫 화면: 7개 카테고리, 50개 모두 편집 가능한 입력 필드
- 활성 조건: 필수 29개 항목이 모두 채워졌을 때만 `직방에 보내기`가 활성화
- `자동 채우기`: 필수/선택 전체에 예시 데이터를 넣고, 이후에도 수정 가능
- 결과 화면: 번들된 오프라인 직방 재현 HTML을 WebView로 열고 입력값을 주입
- 성공 판정: JavaScript 호출 여부가 아니라 텍스트·드롭다운·체크박스·토글의 DOM 값을 다시 읽어 일치할 때만 성공으로 표시

### 재현 페이지에 매핑되는 항목

- 관리비 금액은 마스터 폼의 **만원** 값에서 재현 폼의 **원** 값으로 `× 10,000` 변환됩니다.
- 관리비 부과 방식·부과 기준은 재현 폼의 실제 선택지와 일치합니다. 포함 비목은 다중 선택입니다.
- 원룸 구조와 복층 여부는 `오픈형 / 분리형 / 복층형 원룸` 선택값으로 변환됩니다.
- 가전·전자레인지·가구·냉방 옵션, CCTV, 관심 태그, 중개 의뢰 방식이 재현 DOM에 반영됩니다. `기타 방법으로 확인`을 고르면 상세 입력란이 나타납니다.
- 주소 검색과 사진·평면도·360° 사진·동영상은 실제 검색/업로드가 필요한 기능이어서 재현 DOM 주입 대상에서 계속 제외됩니다.

원본 참고 파일은 수정하지 않았습니다. 앱이 쓰는 복사본은 `assets/zigbang/zigbang_listing_form.html`이고, `window.fillListingForm(payload)` 주입기가 그 안에 인라인으로 추가되어 있습니다.

## iPhone에서 실행

이 저장소에서 아래를 실행합니다. 현재 이 Mac에서는 Flutter가 PATH에 없어서 첫 줄을 포함했습니다.

```bash
export PATH="/Users/sunghyunkim/development/flutter/bin:$PATH"
cd /Users/sunghyunkim/Code/Xcode/C6/jikbang
flutter pub get
flutter devices
flutter run -d <아이폰-디바이스-ID>
```

처음 실제 기기에서 실행할 때 Xcode가 Apple Development 서명과 신뢰 설정을 요구할 수 있습니다. 필요하면 `ios/Runner.xcworkspace`를 Xcode로 열어 Runner의 Signing & Capabilities에서 본인 Team을 선택한 뒤 위 명령을 다시 실행합니다.

## 기능 테스트 순서

1. 앱 오른쪽 위 `자동 채우기`를 누릅니다. `직방에 보내기`가 활성화되는지 확인합니다.
2. 필요한 경우 입력값을 하나 수정한 뒤 `직방에 보내기`를 누릅니다.
3. 결과 화면 상단에 `성공: 직방 재현 폼에 N개 값을 입력했습니다.`가 나오는지 확인합니다.
4. WebView 안에서 동/호, 사용승인일, 보증금/월세, 면적, 층수, 욕실 수, 제목, 상세 설명, 임대인 정보 값이 보이는지 확인합니다. 이 값들은 성공 판정에도 사용됩니다.
5. 왼쪽 위 뒤로가기로 마스터 폼으로 복귀합니다.

## 검증 결과

```bash
flutter analyze                 # No issues found
flutter test                    # 2 tests passed
flutter build ios --debug --no-codesign
```

마지막 명령으로 `build/ios/iphoneos/Runner.app`이 생성되었고 `webview_flutter_wkwebview`가 포함되었습니다.

추가로 iPhone 16 Pro 시뮬레이터에서 번들 HTML을 실제 WKWebView로 열어 검증했습니다. JavaScript 채널을 통해 `성공: 직방 재현 폼에 42개 값을 입력했습니다. (재현 폼 미지원 10개, 대상 누락 0개)`가 표시됐으며, 이 성공 표시는 DOM 읽기 검증을 통과했을 때만 나옵니다.

## iOS 최소 버전 참고

프로젝트를 13.0으로 설정했지만, 이 Mac의 Flutter 3.47.3/Xcode 도구가 빌드 시 최소 배포 버전을 **iOS 15.0**으로 자동 마이그레이션합니다. 따라서 현재 검증된 결과물의 실제 최소 버전은 iOS 15입니다. iOS 13 지원이 필수라면 iOS 13을 지원하는 Flutter/Xcode 도구 조합으로 프로젝트를 생성·빌드해야 합니다.
