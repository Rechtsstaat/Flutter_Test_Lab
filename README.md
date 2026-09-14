# 직방 매물 입력 연동 테스트 앱

통합 매물 입력 폼의 값을 앱 내부 WebView에 띄운 **인증된 직방 미러 페이지**에 주입하는 Flutter 프로토타입입니다. 미러 주소는 `https://mirror-dimension-lab.pages.dev/zigbang/form/oneroom/index.html`이며 Basic Auth는 앱에서 `mirror` / `money`로 처리합니다.

## 이 테스트로 확인하는 것과 확인하지 않는 것

확인하는 것:

- 통합 폼에서 입력한 값이 `직방에 보내기`를 통해 다음 화면으로 전달되는지
- 원격 직방 미러의 입력 요소에 JavaScript로 값이 실제 채워지는지
- 필수 핵심 항목을 DOM에서 다시 읽어 성공/실패를 표시하는지
- iPhone의 WKWebView에서도 위 흐름이 동작하는지

확인하지 않는 것:

- 실제 직방 사이트 로그인, 실제 공인중개사 계정 인증, 실제 매물 등록
- 직방의 현재 운영 화면/DOM과 원격 미러의 완전한 일치
- 주소 검색, 사진 업로드, 서버 검증, 등록 버튼 제출 또는 네트워크 자동화
- 직방 이용약관·보안 정책·CAPTCHA를 통과하는 자동화 가능 여부

즉, 이 앱은 **통합 폼 → 직방 형태의 재현 폼으로의 값 주입**만 검증합니다. 실제 플랫폼 연동은 별도 권한, 약관 검토 및 실제 계정 환경에서의 드라이런이 필요합니다.

## 동작 방식

1. 첫 화면의 통합 매물 입력 폼에는 기능 명세서의 50개 항목이 5개 아코디언 섹션으로 표시됩니다. 필수는 `*`로 표시됩니다.
2. 오른쪽 위 `자동 채우기`를 누르면 필수/선택 항목 모두 테스트 예시 값으로 채워집니다. 이후 각 값은 직접 수정할 수 있습니다.
3. 전송 시 거래·관리비·주차·입주 방식에 따른 조건부 필수값과 사진 5~20장, 제목 30자, 상세 설명 1000자를 검사합니다.
4. 버튼을 누르면 원격 미러를 열고 `window.FLR.strict`를 우선 사용합니다. 이 API가 없으면 DOM 값 setter, bubbling event, pointer event 체인으로 대체 입력합니다. 거래 유형·전체 층·관리비 부과 방식 후에는 300ms를 기다려 종속 UI를 갱신합니다.
5. 상단에 입력/검증 건수 및 명시적 제한·누락 사유가 표시됩니다.
6. 결과 화면 왼쪽 위 뒤로가기 버튼으로 통합 폼으로 돌아갈 수 있습니다.

성공 상태는 JavaScript 실행 자체가 아니라 입력 요소의 값을 DOM에서 다시 읽어 판정합니다. 미러에 없는 직방 원룸 항목은 다음처럼 명시합니다: 공급면적, 매매 금액, 세대당 주차 대수, 난방 방식, LH 전세임대 여부. 사진은 WebView 보안상 JavaScript로 기기 파일을 할당할 수 없으므로 미러의 파일 선택기로 사용자가 5~20장을 직접 선택해야 합니다.

## 사전 준비

- macOS 및 **Xcode 26.3 이상** (이 프로젝트는 현재 Xcode 26.3에서 확인)
- Flutter **3.47.3** / Dart 3.13.3
- CocoaPods (`sudo gem install cocoapods`가 필요할 수 있음)
- iPhone 실기기: **iOS 15.0 이상**

프로젝트 iOS 템플릿의 배포 대상은 iOS 15.0입니다. 연결한 iPhone이 이보다 낮으면 실행할 수 없습니다.

설치된 Flutter SDK는 다음 경로를 사용합니다. 아래 명령은 모두 이 경로를 명시하므로 PATH 설정이 필요 없습니다.

```bash
/Users/sunghyunkim/development/flutter/bin/flutter --version
```

출력에 `Flutter 3.47.3`이 표시되는지 확인하세요.

## 처음 실행하기

터미널에서 프로젝트 폴더로 이동한 뒤 패키지를 받고 실행합니다.

```bash
cd /Users/sunghyunkim/Code/Xcode/C6/jikbang
/Users/sunghyunkim/development/flutter/bin/flutter pub get
/Users/sunghyunkim/development/flutter/bin/flutter analyze
/Users/sunghyunkim/development/flutter/bin/flutter devices
```

연결된 iPhone 이름/ID가 마지막 명령 출력에 보이면, 해당 기기를 지정해 실행합니다.

```bash
/Users/sunghyunkim/development/flutter/bin/flutter run -d '<iPhone 기기 ID>'
```

예를 들어 `flutter devices`에 표시된 ID가 `00008110-001234567890801E`이면 다음과 같습니다.

```bash
/Users/sunghyunkim/development/flutter/bin/flutter run -d 00008110-001234567890801E
```

기기가 하나뿐이라면 `-d` 없이 실행해도 됩니다.

```bash
/Users/sunghyunkim/development/flutter/bin/flutter run
```

앱 실행 후에는 `자동 채우기` → `직방에 보내기` 순서로 눌러 상단의 성공 상태와 WebView 안의 채워진 값을 확인하세요.

## iPhone 실기기 실행 준비

### 1. iPhone 연결 및 개발자 모드

1. USB로 iPhone을 Mac에 연결하고, iPhone의 `이 컴퓨터를 신뢰`를 승인합니다.
2. iPhone에서 `설정 → 개인정보 보호 및 보안 → 개발자 모드`를 켭니다.
3. 재시작 안내가 나오면 재시작한 뒤, 다시 표시되는 개발자 모드 활성화를 승인합니다.
4. iPhone 잠금을 푼 상태로 두고 `flutter devices`에서 인식되는지 확인합니다.

### 2. 코드 서명 설정

처음 실기기에 설치할 때는 본인의 Apple ID 개발 팀으로 서명해야 합니다. Xcode에서 다음을 설정합니다.

```bash
open /Users/sunghyunkim/Code/Xcode/C6/jikbang/ios/Runner.xcworkspace
```

1. 좌측에서 `Runner` 프로젝트와 `Runner` 타깃을 선택합니다.
2. `Signing & Capabilities`에서 `Automatically manage signing`을 켭니다.
3. `Team`을 본인의 Apple ID/개발 팀으로 바꿉니다. 계정이 없다면 Xcode `Settings → Accounts`에 Apple ID를 먼저 추가합니다.
4. `Bundle Identifier`를 팀 내에서 고유한 값으로 변경합니다. 기본값 `com.example.jibangListingTest`는 다른 앱과 충돌할 수 있습니다. 예: `com.<본인이름>.jibangListingTest`
5. iPhone을 실행 대상(device)으로 선택한 뒤 Xcode의 Run 버튼으로 한 번 빌드하거나, 터미널에서 다시 `flutter run -d '<기기 ID>'`를 실행합니다.

무료 Apple ID도 개인 기기에서 테스트할 수 있지만 서명 프로비저닝이 짧은 기간 후 만료될 수 있습니다. 서명 오류가 나면 Xcode의 `Signing & Capabilities`에서 Team과 Bundle Identifier의 충돌 여부를 먼저 확인하세요.

### 3. 신뢰/개발 관련 오류

- 기기가 목록에 없으면: 케이블, 잠금 해제, `이 컴퓨터를 신뢰`, 개발자 모드를 다시 확인합니다.
- `No signing certificate` 또는 provisioning 오류면: Xcode에서 Apple ID를 추가하고 Runner 타깃의 Team/Bundle Identifier를 다시 설정합니다.
- 앱을 열 수 없다는 iPhone 경고가 나오면: 기기의 `설정 → 일반 → VPN 및 기기 관리`에서 해당 개발자 인증서를 신뢰합니다.
- iOS 버전이 15.0 미만이면: 기기를 업데이트하거나 더 높은 버전의 기기를 사용해야 합니다.

## 자주 쓰는 명령

```bash
cd /Users/sunghyunkim/Code/Xcode/C6/jikbang

# 의존성 설치
/Users/sunghyunkim/development/flutter/bin/flutter pub get

# 정적 검사
/Users/sunghyunkim/development/flutter/bin/flutter analyze

# 테스트
/Users/sunghyunkim/development/flutter/bin/flutter test

# 연결 기기 확인
/Users/sunghyunkim/development/flutter/bin/flutter devices

# 연결된 기본 기기에서 개발 실행
/Users/sunghyunkim/development/flutter/bin/flutter run

# 문제가 있을 때 iOS 빌드 산출물 정리 후 재설치
/Users/sunghyunkim/development/flutter/bin/flutter clean
/Users/sunghyunkim/development/flutter/bin/flutter pub get
/Users/sunghyunkim/development/flutter/bin/flutter run -d '<iPhone 기기 ID>'
```

## 주요 파일

| 파일 | 용도 |
|---|---|
| `lib/main.dart` | 통합 폼, 자동 채우기, CTA 활성화, WebView 주입 및 성공 상태 표시 |
| `pubspec.yaml` | Flutter/WebView 의존성 |
| `ios/Runner.xcodeproj/project.pbxproj` | iOS 배포 대상(iOS 15.0) 및 Xcode 서명 설정 |

## 주의

원격 미러는 테스트용 환경입니다. 실제 직방의 화면이나 API를 호출하지 않으며, 이 프로젝트로 실제 매물을 등록하지 않습니다. 실제 서비스에 적용하기 전에는 플랫폼의 공식 연동 수단, 이용약관, 개인정보 처리, 사용자 승인 및 에러 복구 방식을 별도로 검토해야 합니다.
