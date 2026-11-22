# Cherry

<img src="Resources/Cherry.png" alt="Cherry 앱 아이콘" width="112">

Cherry는 Mac 메뉴 막대에서 자주 쓰는 아이콘만 골라 두고, 나머지는 필요할 때 꺼내 쓰는 메뉴 막대 정리 앱입니다. 맥북 노치 뒤에 가려진 아이콘도 `…` 아래 가로 목록에서 찾고, 해당 앱의 원래 메뉴를 열 수 있어요.

**[모요](https://moyoplan.com)에서 만들었습니다.**

## 설치

**macOS 14 이상**에서 사용할 수 있습니다. PKG와 DMG 모두 Apple Silicon과 Intel Mac을 지원합니다. [GitHub Releases](https://github.com/xeromank/cherry/releases)에서 Universal 설치 파일을 내려받습니다.

- **PKG**는 `.pkg` 파일을 열고 macOS 설치 프로그램에서 **계속 → 설치**를 누릅니다. 설치가 끝나면 Finder의 **응용 프로그램**에 있는 **Cherry**를 엽니다.
- **DMG**는 DMG 안의 Cherry를 더블클릭하고 **응용 프로그램으로 이동**을 누릅니다. 처음 열 때 차단되거나 기존 버전을 교체할 때는 DMG 창의 **Cherry**를 **Applications(응용 프로그램)**에 끌어다 놓고, 복사된 앱을 엽니다.

### macOS가 앱이나 PKG를 열지 않을 때

공개 프리뷰는 Developer ID 서명과 Apple 공증 전입니다. **‘Cherry를 열지 않음’** 또는 **‘Cherry-….pkg를 열지 않음’** 경고에 Apple이 악성 코드 여부를 확인할 수 없다고 나오면, 신뢰할 수 있는 출처에서 받은 파일에 대해 macOS의 **그래도 열기**를 사용할 수 있습니다. [Apple 지원 · Mac에서 앱 안전하게 열기](https://support.apple.com/ko-kr/102445)

1. [Cherry GitHub Releases](https://github.com/xeromank/cherry/releases)에서 직접 받은 파일인지 확인합니다. **DMG**라면 응용 프로그램에 복사한 **Cherry**를 열어보고, **PKG**라면 받은 **`.pkg`**를 Finder에서 열어봅니다. 경고에서는 **완료**를 누릅니다.
2. **시스템 설정 → 개인정보 보호 및 보안**에서 아래로 스크롤해 **보안**으로 이동합니다. 방금 차단된 **Cherry** 또는 **`.pkg` 파일 이름**을 확인하고 **그래도 열기**를 누릅니다.
3. 확인 창에서 **열기**를 누르고, 인증을 요청하면 진행합니다. PKG의 경우 macOS 설치 프로그램이 열리면 **계속 → 설치**를 누릅니다.

**그래도 열기** 버튼은 실행을 시도한 뒤 약 한 시간 동안 표시됩니다. 회사에서 관리하는 Mac에서 해당 항목이 계속 표시되지 않으면 IT 담당자에게 설치 가능 여부를 확인하세요. [Apple Mac 사용 설명서](https://support.apple.com/ko-kr/guide/mac-help/mh40617/mac) · [Apple 기기 관리 안내](https://support.apple.com/ko-kr/guide/deployment/dep61dc030/web)

### 첫 실행

첫 실행 화면에서 **권한 요청**을 누릅니다. **시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용**에서 **Cherry**를 허용합니다.

Cherry는 메뉴 막대 항목을 찾고 원래 메뉴를 열거나 배치를 바꾸는 데 손쉬운 사용 권한을 씁니다. 화면 기록 권한은 필요하지 않습니다.

## 사용하기

아래는 Cherry 실제 화면입니다. 메뉴 막대 항목에는 예시 아이콘을 사용했습니다.

### 가려진 메뉴 열기

![메뉴 막대 아래에 펼쳐진 Cherry의 가로 목록](docs/screenshots/ribbon.png)

1. 메뉴 막대의 **`…`**를 누르거나 **`⌃⇧Space`**(Control + Shift + Space)를 눌러 하단 바를 엽니다.
2. 아이콘 위에 마우스를 올리면 앱 이름이 보입니다. 원하는 아이콘을 **한 번 클릭**하면 해당 앱의 원래 메뉴가 열립니다.
3. 이름으로 찾으려면 하단 바에서 **`⌘F`**를 누릅니다. 하단 바는 **`Esc`** 또는 닫기 버튼으로 접을 수 있어요.

### 앱마다 표시 위치 정하기

![아이콘 우클릭 메뉴의 항상 표시와 하단 바에만 표시 항목](docs/screenshots/placement.png)

하단 바에서 아이콘을 **우클릭**하고 표시 위치를 선택합니다.

| 메뉴 | 동작 |
| --- | --- |
| **항상 표시** | 상단 메뉴 막대에 아이콘을 꺼내 둡니다. 하단 바를 닫아도 상단에서 바로 누를 수 있어요. |
| **하단 바에만 표시** | 하단 바를 닫으면 상단에서 숨깁니다. 다시 `…`를 열어 해당 메뉴를 사용할 수 있어요. |

손으로 배치하려면 하단 바의 **톱니바퀴**를 눌러 메뉴 막대에 구분선 `|`을 표시합니다. 상단에서 `⌘`을 누른 채 아이콘을 구분선 왼쪽으로 드래그하면 숨김, 오른쪽으로 옮기면 항상 표시됩니다. 배치를 마쳤으면 **완료**를 누릅니다.

메뉴 막대에 공간이 부족하거나 macOS에서 이동할 수 없는 항목은 원하는 위치에 표시되지 않을 수 있습니다. 이동이 실패하면 하단 바에 안내가 표시됩니다.

### 로그인할 때 자동 실행

![Cherry 설정 화면의 로그인 시 열기와 메뉴 막대 정리 안내](docs/screenshots/settings.png)

1. 하단 바의 **톱니바퀴**를 누릅니다.
2. **로그인 시 열기**를 켭니다. macOS에서 별도 허용을 요청하면 **로그인 항목 설정 열기**를 눌러 승인합니다.
3. 다음 로그인부터 Cherry는 메뉴 막대에서 시작합니다. 하단 바는 접힌 상태로 시작하고, 이 옵션은 기본적으로 꺼져 있습니다.

## 소스에서 빌드

Swift 5.10 이상을 포함한 Xcode 또는 Command Line Tools가 필요합니다.

```sh
git clone https://github.com/xeromank/cherry.git
cd cherry
swift test
./Scripts/build-app.sh
open dist/Cherry.app
```

Universal PKG는 `./Scripts/build-pkg.sh`로, Universal DMG는 `./Scripts/build-dmg.sh`로 만듭니다. 결과물은 `dist/`에 저장됩니다. Xcode 대신 Command Line Tools를 쓰려면 빌드 명령 앞에 `DEVELOPER_DIR=/Library/Developer/CommandLineTools`를 붙일 수 있습니다.

배포용 PKG를 서명하려면 Developer ID Application과 Developer ID Installer 인증서를 각각 지정합니다.

```sh
CHERRY_SIGNING_IDENTITY='Developer ID Application: …' \
  CHERRY_INSTALLER_SIGNING_IDENTITY='Developer ID Installer: …' \
  ./Scripts/build-pkg.sh --developer-id
```

## 기여하기

- **기능 제안**은 사용 상황과 필요한 동작을 적어 이슈로 남겨 주세요. [기능 제안 이슈 열기](https://github.com/xeromank/cherry/issues/new?template=feature-request.yml)
- **코드와 문서 개선**은 저장소를 포크한 뒤 PR을 보내 주세요. 변경사항과 확인 방법을 적고, 관련 이슈가 있으면 함께 연결해 주세요. [Pull requests](https://github.com/xeromank/cherry/pulls)

Cherry는 [MIT 라이선스](LICENSE)로 공개합니다.
