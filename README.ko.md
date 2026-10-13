**Language:** [English](README.md) | 한국어

# EasyPad

> Windows 11 메모장을 macOS용으로 다시 만든 텍스트 편집기입니다.

![EasyPad 창: 제목 표시줄 안의 탭, 메뉴 줄, 서식이 적용된 Markdown 문서](docs/screenshot.png)

```sh
brew install dmnkx/easypad/easypad
```

## EasyPad는 무엇인가요?

Windows 11에 들어 있는 메모장은 탭, 종료해도 남는 세션, 가벼운 Markdown 서식을 갖춘 편집기입니다. EasyPad는 그 메모장을 macOS에서 같은 모양과 같은 기능으로 쓸 수 있게 Swift와 AppKit으로 새로 만든 네이티브 앱입니다.

원본 실행 파일을 옮긴 것이 아닙니다. Windows에 설치된 메모장의 메뉴 구성과 화면 문구를 읽어 내고, 그에 맞춰 처음부터 다시 구현했습니다. Microsoft가 만들거나 보증한 앱이 아니며 Microsoft와 관계가 없습니다.

이 저장소는 소스 저장소이면서 Homebrew tap(`dmnkx/easypad`)입니다. 설치하면 GitHub Releases에 올라간 빌드를 내려받습니다.

## 주요 기능

- **제목 표시줄 안의 탭** — 탭마다 닫기 버튼이 있고, 저장하지 않은 탭은 점(●)으로 표시됩니다.
- **세션 유지** — 앱을 끄면 열려 있던 탭과 저장하지 않은 글까지 그대로 보관했다가 다음에 켤 때 되살립니다. 끌 때 저장 여부를 묻지 않습니다.
- **Markdown 서식 보기** — 제목, 굵게, 기울임꼴, 취소선, 링크, 글머리·번호·작업 목록, 표, 이미지를 서식이 적용된 모습으로 편집합니다. 원문 그대로 보는 구문 보기로 언제든 바꿀 수 있습니다.
- **인코딩과 줄 끝 유지** — ANSI, UTF-8, UTF-8(BOM), UTF-16 LE/BE와 CRLF, LF, CR을 감지해 열고, 저장할 때 그대로 유지합니다.
- **메모장의 나머지 기능** — 찾기와 바꾸기, 줄 이동, 시간/날짜 삽입, 확대/축소, 자동 줄 바꿈, 상태 표시줄, 머리글·바닥글이 있는 인쇄, `.LOG` 파일.
- **한국어와 영어** — macOS 언어 설정을 따릅니다.
- **유니버설 앱** — Apple Silicon과 Intel 맥 모두에서 동작합니다.

## 요구 사항

- macOS 13 (Ventura) 이상
- [Homebrew](https://brew.sh) (Homebrew로 설치할 때)

## 설치

### Homebrew (권장)

```sh
brew install dmnkx/easypad/easypad
```

`/Applications/EasyPad.app`으로 설치됩니다. tap을 먼저 등록해 두면 이름만으로 설치할 수 있습니다.

```sh
brew tap dmnkx/easypad
brew install easypad
```

### 직접 내려받기

1. [Releases](https://github.com/dmnkx/homebrew-easypad/releases/latest)에서 `EasyPad.zip`을 내려받아 압축을 풉니다.
2. `EasyPad.app`을 응용 프로그램 폴더로 옮깁니다.
3. EasyPad는 Apple 공증을 받지 않은 앱이라, 이렇게 받은 경우 처음 열 때 macOS가 막습니다. 터미널에서 아래 명령을 한 번 실행하면 열립니다.

   ```sh
   xattr -dr com.apple.quarantine /Applications/EasyPad.app
   ```

   또는 앱을 한 번 열어 차단 메시지를 본 뒤, **시스템 설정 > 개인정보 보호 및 보안** 맨 아래의 **그래도 열기**를 누릅니다.

Homebrew로 설치하면 이 과정이 자동으로 처리됩니다.

## 사용법

### 탭과 창

| 하려는 일 | 방법 |
| --- | --- |
| 새 탭 (Markdown) | `⌘N` 또는 `⌘T`, 또는 탭 줄의 `+` |
| 새 일반 텍스트 탭 | `⇧⌘N` 또는 `⇧⌘T` |
| 새 창 | 파일 > 새 창 |
| 다음 / 이전 탭 | `⌃Tab` / `⌃⇧Tab` |
| 탭 닫기 | `⌘W`, 또는 탭의 `×` |
| 창 닫기 (모든 탭) | `⇧⌘W` |
| 다른 탭 닫기, 오른쪽 탭 닫기 | 탭을 우클릭 |

새 탭은 Markdown 문서로 시작합니다. 서식 없는 글만 쓸 때는 일반 텍스트 탭을 여세요.

### 파일

| 하려는 일 | 방법 |
| --- | --- |
| 열기 | `⌘O` (어떤 확장자든 엽니다) |
| 저장 | `⌘S` |
| 다른 이름으로 저장 | `⇧⌘S` (파일 형식과 인코딩을 고릅니다) |
| 모두 저장 | `⌥⌘S` |
| 인쇄 | `⌘P` |
| 페이지 설정 | 파일 > 페이지 설정 (머리글, 바닥글, 여백) |

Finder에서 파일을 Dock의 EasyPad 아이콘에 끌어다 놓아도 열립니다.

### Markdown 서식

창 안 메뉴 줄의 버튼이나 서식 메뉴로 서식을 적용합니다.

| 서식 | 단축키 | 저장되는 Markdown |
| --- | --- | --- |
| 제목 6단계 | 메뉴 줄의 제목 버튼 | `#` ~ `######` |
| 굵게 | `⌘B` | `**글**` |
| 기울임꼴 | `⌘I` | `*글*` |
| 취소선 | `⇧⌘X` | `~~글~~` |
| 링크 | `⌘K` | `[글](주소)` |
| 목록 | 메뉴 줄의 목록 버튼 | `-`, `1.`, `- [ ]` |
| 표 | 메뉴 줄의 표 버튼 | `\| a \| b \|` |
| 이미지 | 메뉴 줄의 이미지 버튼 | `![](경로)` |
| 서식 지우기 | `⌘\` | |

- **표**는 표 버튼을 눌러 나오는 격자 위에서 마우스로 크기를 골라 넣습니다. 같은 메뉴에서 행과 열을 추가하거나 지웁니다.
- **이미지**를 넣고 저장하면 이미지 파일이 문서 옆 `문서이름_Images` 폴더로 복사되고, 문서에는 그 상대 경로가 기록됩니다. 문서와 이 폴더를 함께 옮기면 다른 컴퓨터에서도 이미지가 보입니다.
- **보기 > Markdown**에서 서식 보기(포맷)와 원문 보기(구문)를 바꿉니다.
- 일반 텍스트 파일에 서식을 넣고 저장하면 Markdown 파일로 저장할지 묻습니다.

### 편집과 보기

| 하려는 일 | 단축키 |
| --- | --- |
| 찾기 | `⌘F` |
| 다음 / 이전 찾기 | `F3` / `⇧F3` |
| 바꾸기 | `⌥⌘F` |
| 줄로 이동 | `⌘G` |
| 시간/날짜 넣기 | `F5` |
| 선택한 글을 Bing으로 검색 | `⌘E` |
| 확대 / 축소 / 원래대로 | `⌘=` / `⌘-` / `⌘0` |
| 자동 줄 바꿈 | `⌥Z` |

파일의 첫 줄이 `.LOG`이면, 열 때마다 끝에 현재 시간과 날짜가 덧붙습니다.

### 설정

`⌘,` 또는 메뉴 줄 오른쪽의 톱니바퀴를 누르면 설정이 탭으로 열립니다.

- **모양** — 앱 테마 (시스템 설정 사용, 밝게, 어둡게)
- **텍스트 서식** — 글꼴, 자동 줄 바꿈, 서식 켬/끔
- **EasyPad 열기** — 파일을 새 탭에서 열지 새 창에서 열지, 시작할 때 이전 세션을 이어갈지, 최근에 사용한 파일
- **맞춤법** — 맞춤법 검사, 자동 수정

## 업데이트

```sh
brew upgrade easypad
```

## 삭제

```sh
brew uninstall easypad
```

설정과 보관된 세션(저장하지 않은 글 포함)까지 지우려면 `--zap`을 붙입니다.

```sh
brew uninstall --zap easypad
```

tap도 필요 없으면 지웁니다.

```sh
brew untap dmnkx/easypad
```

Homebrew 없이 설치했다면 아래를 직접 지우면 됩니다.

- `/Applications/EasyPad.app`
- `~/Library/Application Support/EasyPad` — 보관된 세션
- `~/Library/Preferences/io.github.dmnkx.easypad.plist` — 설정

## 알려진 한계

- Apple 공증을 받지 않았습니다. Homebrew 밖에서 받으면 처음 열 때 위의 절차가 필요합니다.
- 탭을 끌어서 순서를 바꾸거나 창으로 떼어낼 수 없습니다.
- 찾기와 바꾸기는 macOS 기본 찾기 막대를 씁니다. 원본의 찾기 창과 모양이 다릅니다.
- 웹 주소로 넣은 이미지는 내려받지 않고 자리 표시 아이콘만 보입니다.
- 인용문, 수평선, 코드 블록은 서식으로 그리지 않고 원문 그대로 보여 줍니다.
- 원본의 Copilot 기능(쓰기, 다시 쓰기, 요약)은 Microsoft 계정과 서비스에 묶여 있어 없습니다.

## 소스에서 빌드

Xcode 명령줄 도구가 필요합니다 (`xcode-select --install`).

```sh
git clone https://github.com/dmnkx/homebrew-easypad.git
cd homebrew-easypad
swift test                 # 테스트
sh scripts/bundle.sh       # build/EasyPad.app 생성
```

릴리스는 `sh scripts/release.sh <버전>`으로 냅니다. 버전 올리기, 테스트, 빌드, cask 갱신, GitHub Releases 업로드를 한 번에 합니다.

작업 기록과 설계 결정, 원본 분석 내용은 [PROCESS.md](PROCESS.md)에 있습니다.
