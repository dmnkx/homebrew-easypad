# PROCESS — EasyPad (Windows 11 메모장 macOS 포팅)

마지막 갱신: 2026-10-14

## 1. 목적

Windows 11 기본 메모장(스토어판 `Microsoft.WindowsNotepad` 11.2607.14.0)을 macOS에서 같은 기능으로 쓸 수 있게 네이티브 앱으로 다시 만든다.

원본 실행 파일을 옮기는 것이 아니라, 설치된 패키지에서 기능 목록과 UI 문자열을 읽어 내고 그에 맞춰 Swift/AppKit으로 새로 구현한다.

## 2. 목표

- 원본 메모장의 기능을 빠짐없이 구현한다. 옮길 수 없는 것은 이 문서에 이유와 함께 남긴다.
- macOS 13 이상에서 도는 유니버설(arm64 + x86_64) `.app`을 만든다.
- UI는 한국어와 영어를 지원하고, 문구는 원본 메모장의 것을 쓴다.
- 처음 개발한 PC는 WSL(Linux)이라 로컬 빌드가 안 되어 GitHub Actions의 macOS 러너에서 테스트하고 `.app`을 만들었다. 2026-10-13부터는 맥에서 직접 빌드하고 실행하며 작업한다.
- 화면 모양도 원본 메모장에 맞춘다(창 안의 메뉴 줄, 제목 표시줄 안의 탭). 사용자가 2026-10-13에 정한 방향이다.
- 코드는 최소한으로 유지한다. 플랫폼이 이미 제공하는 것(NSDocument, 찾기 막대, 맞춤법 검사, 인쇄)은 직접 만들지 않는다. 탭만은 원본 모양을 위해 직접 그린다(4.4절).

## 3. 현재 상태

**맥에서 빌드해 실행했고, 탭·메뉴·세션은 직접 눌러서 확인했다. 편집 기능(찾기, 인쇄, 서식, 표, 목록)은 아직 실행해 보지 않았다.**

| 항목 | 상태 |
|---|---|
| 소스 작성 | 완료 (Swift 약 1,900줄) |
| 저장소 | `git@github.com:dmnkx/homebrew-easypad.git`(2026-10-13에 `notepad-mac`에서 이름 변경, 예전 주소는 GitHub가 넘겨 준다), 공개 저장소, `main` 브랜치. Homebrew tap을 겸한다 |
| 앱 이름 | EasyPad (번들 ID `io.github.dmnkx.easypad`). SwiftPM 타깃 이름(`Notepad`, `NotepadKit`)은 그대로다 |
| 설치 | `brew install dmnkx/easypad/easypad` |
| CI 1회차 (`f287253`) | 실패, `swift test` 단계 |
| CI 2회차 (`69355cc`) | 실패. 오류 1건 확인: `main.swift`에서 `@MainActor` 함수 `runApp()` 호출 불가 |
| CI 3회차 (`8e0f412`) | 성공. `swift test`, `.app` 번들, 아티팩트 업로드까지 통과 |
| 테스트 | 6개 통과 (인코딩·줄 끝, 머리글/바닥글 코드, Markdown 왕복, 탭 묶음, 표 격자, 이미지 폴더 복사) |
| 맥 로컬 빌드 | `swift test`, `sh scripts/bundle.sh` 통과. x86_64 폐기 예정 경고 1건 |
| 2026-10-13 맥 작업 | 커밋 `eb67c1f`로 `main`에 들어 있고 푸시했다(9절) |
| 산출물 | GitHub Releases의 `EasyPad.zip`(`sh scripts/release.sh <버전>`으로 올린다). Actions 실행의 아티팩트 `EasyPad`에도 매번 올라간다. `v1.0`은 이름을 바꾸기 전의 `Notepad.zip`이다 |
| 실제 동작 확인 | 탭, 창 안 메뉴, 설정 창 열기, 세션 저장/복원은 확인. 나머지는 6.1절 |

화면과 동작에 관한 코드는 탭 묶음 말고는 테스트가 없다. 6.1절에서 "확인함" 표시가 없는 항목은 미검증이다.

## 4. 작업한 내역

### 4.1 환경 준비

- **REA MCP 설치**: 리버스 엔지니어링용 MCP 서버(`rea-agents` 6.4.0)를 Claude Code에 등록했다. Ghidra와 IDA는 설치하지 않아 네이티브 디컴파일은 쓰지 못했고, PE 리소스 검사 도구만 사용했다.
- **Ponytail 플러그인 설치**: 최소 코드 원칙을 강제하는 Claude Code 플러그인. 이 프로젝트의 코드는 그 규칙(필요한 것만, 플랫폼 기능 우선, 알려진 한계는 `shortcut:` 주석)에 따라 썼다.
- **GitHub CLI**: `~/.local/bin/gh`에 설치했으나 로그인은 하지 않았다.

### 4.2 원본 분석

분석 대상은 두 가지였고, 사용자가 스토어판을 포팅 대상으로 골랐다.

| 대상 | 위치 | 분석 결과 |
|---|---|---|
| 클래식 메모장 | `C:\Windows\System32\notepad.exe` + `ko-KR\notepad.exe.mui` | 메뉴, 단축키 표, 대화 상자, 문자열 표를 전부 해독함 |
| 스토어 메모장 | `C:\Program Files\WindowsApps\Microsoft.WindowsNotepad_11.2607.14.0_x64__8wekyb3d8bbwe` | UI 문자열 469개(영어), 465개(한국어), XAML 화면 구성 요소 이름, 매니페스트 |

- **문자열**: `resources.pri`(영어)와 언어 분할 패키지의 `resources.pri`(한국어)에서 데이터 항목을 순서대로 뽑아 짝을 맞췄다. 개수가 4개 달라 일부 구간은 짝이 어긋났고, 그 구간은 앞뒤 문맥으로 손으로 맞췄다.
- **화면 구성**: `NotepadXamlUI/*.xbf`에서 요소 이름을 뽑아 서식 도구 모음, 상태 표시줄, 설정 페이지, 탭 막대, 찾기 창의 구성을 확인했다.
- **단축키**: 스토어판 `Notepad.exe`에는 단축키 표 리소스가 없다(코드에서 등록). 그래서 단축키는 클래식판의 단축키 표와 Windows 11 메모장에 대한 일반 지식으로 채웠다. **원본에서 직접 확인한 값이 아니다.**
- **분석 스크립트**: `re/decode_res.py`(PE 메뉴/대화 상자/문자열/단축키 해독), `re/pri_dump.py`, `re/pri_sections.py`(PRI 덤프). 뽑아낸 문자열 덤프(`re/*.txt`, `re/*.json`)는 Microsoft의 문구라 `.gitignore`로 저장소에서 제외했다.

### 4.3 구현

SwiftPM 패키지, 라이브러리 타깃 `NotepadKit`에 모든 코드를 두고 실행 타깃 `Notepad`는 진입점만 가진다(테스트가 라이브러리를 직접 불러 쓰기 위함).

| 파일 | 내용 |
|---|---|
| `Sources/Notepad/Launch.swift` | `@main` 진입점 |
| `Sources/NotepadKit/App.swift` | `runApp()`, 설정값(`Settings`), 앱 델리게이트, 메뉴 막대, 설정 창 |
| `Sources/NotepadKit/Document.swift` | `NSDocument` 서브클래스, 저장 패널(형식·인코딩), 인쇄, 문서 컨트롤러, 세션 저장/복원 |
| `Sources/NotepadKit/Editor.swift` | 탭 하나의 창: 서식 도구 모음, 텍스트 뷰, 상태 표시줄, 편집·보기 명령 |
| `Sources/NotepadKit/Formatting.swift` | 서식 명령: 굵게/기울임/취소선, 제목, 목록, 링크, 이미지, 표 |
| `Sources/NotepadKit/Markdown.swift` | Markdown ↔ 서식 있는 텍스트 변환 |
| `Sources/NotepadKit/TextFile.swift` | 인코딩·줄 끝 감지와 저장, 머리글/바닥글 코드, 시간/날짜 문자열 |
| `Sources/NotepadKit/L10n.swift` | 영어 → 한국어 문자열 표 |
| `Tests/NotepadKitTests/NotepadTests.swift` | 테스트 3개 |
| `Info.plist`, `scripts/bundle.sh` | `.app` 번들 구성과 빌드 스크립트 |
| `.github/workflows/build.yml`, `scripts/ci-wait.sh` | CI와 결과 조회 스크립트 |

구현한 기능:

- **탭과 창**: 새 탭(`⌘N` 또는 `⌘T`, Markdown), 새 텍스트 탭(`⌘⇧N` 또는 `⌘⇧T`), 새 창(단축키 없음), 탭 닫기, 창 닫기, 다른 탭 닫기, 오른쪽 탭 닫기, 다음/이전 탭(`⌃Tab`, `⌃⇧Tab`). 탭 줄은 제목 표시줄 안에 직접 그린다. 탭마다 닫기 `×`(저장 안 한 탭은 ●), 끝에 `+`, 우클릭 메뉴가 있다.
- **창 안 메뉴 줄**: `파일 · 편집 · 보기` 버튼이 메뉴 막대와 같은 메뉴를 열고, 그 옆에 서식 버튼, 오른쪽 끝에 설정 톱니바퀴가 있다.
- **세션**: "이전 세션 계속하기". 종료할 때 열린 탭과 저장하지 않은 내용을 `~/Library/Application Support/Notepad/session.json`에 적고, 저장 여부를 묻지 않고 끝낸 뒤 다음 실행에서 되살린다. 파일 자체는 건드리지 않는다.
- **파일**: 아무 확장자나 열기, 최근 파일, 모두 저장. ANSI / UTF-16 LE / UTF-16 BE / UTF-8 / UTF-8(BOM) 감지와 저장, 줄 끝(CRLF/LF/CR) 유지, 저장 대화 상자에서 형식과 인코딩 선택, ANSI로 담을 수 없는 문자 경고, `.LOG` 파일 타임스탬프.
- **편집**: 실행 취소/다시 실행, 찾기/다음/이전/바꾸기, 줄 이동, 시간/날짜, Bing으로 검색, 모두 선택.
- **보기**: 확대/축소(10%~500%), 자동 줄 바꿈, 상태 표시줄(줄·열, 글자 수, 문서 종류, 배율, 줄 끝, 인코딩).
- **인쇄**: 페이지 설정에 머리글·바닥글·여백 항목 추가, 머리글/바닥글 코드(`&f` `&p` `&d` `&t` `&l` `&c` `&r` `&&`).
- **Markdown 서식 보기**: 제목 6단계, 굵게/기울임/취소선, 인라인 코드, 링크(열기 전 확인), 글머리·번호·작업 목록과 중첩, 표 삽입(마우스로 고르는 크기 격자 또는 행·열 개수 입력)과 행·열 추가/삭제, 이미지, 서식 지우기, 서식/구문 보기 전환. `.txt`에 서식을 넣고 저장하면 Markdown으로 저장할지 묻는다.
- **설정**(원본처럼 탭 하나로 열린다. 섹션별 카드, 항목마다 아이콘·이름·스위치 또는 팝업): 테마(시스템/밝게/어둡게), 글꼴, 자동 줄 바꿈, 서식 켬/끔, 파일 여는 방식(새 탭/새 창), 시작 방식, 최근 파일, 맞춤법 검사, 자동 수정.

### 4.4 설계 결정

- **`NSDocument` 기반**: 열기/저장 패널, 변경 표시, 닫을 때 저장 확인, 실행 취소 연동을 얻는다.
- **세션은 직접 구현**: macOS의 자동 저장은 저장된 파일에 변경을 바로 써 버려 메모장의 동작(파일은 그대로, 변경만 따로 보관)과 다르다.
- **탭은 직접 구현** (2026-10-13 변경): macOS 창 탭은 탭 막대가 항상 제목 표시줄 아래에 한 줄 더 붙어 원본 모양이 안 나온다. 그래서 탭마다 `NSWindow`를 하나씩 두되 선택된 탭의 창만 화면에 보이고, 탭을 바꾸면 같은 자리에 창을 바꿔 끼운다(`TabGroup`, `EditorWindowController.select()`). 문서와 창의 관계는 `NSDocument` 그대로다.
- **설정은 문서 없는 탭** (2026-10-13): 설정 탭은 `NSDocument`가 없는 `EditorWindowController`다. 편집기 부분(메뉴 줄, 본문, 상태 표시줄)을 숨기고 `SettingsView`를 스크롤 뷰에 넣어 보여 준다. 한 번에 하나만 열리고, 세션에는 저장하지 않는다.
- **제목 표시줄**: 제목 글자를 숨기고 내용이 제목 표시줄까지 차지하게 했다. 빈 `NSToolbar`(compact)는 제목 표시줄 높이를 탭에 맞게 키우는 용도다.
- **선택된 탭의 색**: 색을 칠하지 않는다. 탭 줄의 어두운 음영에서 선택된 탭 자리만 비워 메뉴 줄과 같은 바탕이 보이게 한다(칠한 색은 창 바탕과 6단계쯤 어긋났다).
- **TextKit 1 고정**: 표(`NSTextTable`)가 TextKit 2에서 지원되지 않는다.
- **Markdown은 직접 파싱**: 줄 단위 파서와 정규식 인라인 파서. 지원 문법만 다루고, 코드 펜스와 그 밖의 줄은 원문 그대로 통과시켜 왕복 변환에서 잃지 않게 했다. 빈 줄 규칙은 `renderMarkdown`과 `serializeMarkdown`이 서로 정확히 역이 되도록 맞췄다.
- **확대/축소는 스크롤 뷰 배율**: 서식 보기처럼 글꼴이 섞인 텍스트에도 한 줄로 적용된다.
- **문자열은 코드 안의 사전**: 리소스 번들 없이 영어를 키로 한국어를 찾는다.

### 4.5 커밋 이력

| 커밋 | 내용 |
|---|---|
| `1875128` | 최초 포팅 |
| `f287253` | 텍스트 저장소 수명 유지, 종료 시 미저장 문서 확인 |
| `69355cc` | CI가 빌드 오류를 주석(annotation)으로 노출 |
| `8e0f412` | 진입점을 `@main @MainActor`로 변경 (CI 2회차 오류 수정) |
| `98e8d88` | 이 문서 추가 |
| `eb67c1f` | 2026-10-13 맥 작업 전체: 창 모양을 원본에 맞춤, 직접 그린 탭, 설정 탭, 첫 실행에서 나온 버그 수정, 앱 아이콘. 9절 참고 |

## 5. 작업할 내역

우선순위 순.

1. **맥에서 실제 실행 점검**: 탭, 메뉴, 세션은 끝났다. 6.1절에서 "확인함"이 없는 항목(찾기, 인쇄, 저장 패널, 서식, 표, 목록 등)이 남았다.
2. **점검에서 나온 문제 수정**.
3. **원본과 대조**: Windows에서 스토어 메모장을 실행해 단축키와 메뉴 순서를 맞춘다(부록 A.6 참고).
4. **빠진 기능 중 옮길 수 있는 것 추가**: 7절 참고.
5. ~~앱 아이콘~~: 2026-10-13에 사용자가 만든 `AppIcon.png`를 넣었다.

CI가 실패하면 오류 줄이 최대 80줄까지 주석(annotation)으로 나온다.

### CI 결과 보는 법

저장소가 공개라 로그인 없이 실행 상태와 주석은 읽을 수 있다. 전체 로그는 로그인이 필요하다.

```sh
sh scripts/ci-wait.sh      # 현재 커밋의 실행이 끝날 때까지 기다렸다가 결과와 오류 줄을 출력
gh auth login              # 전체 로그가 필요하면 (gh run view --log-failed)
```

### 맥에서 직접 빌드

```sh
git clone git@github.com:dmnkx/homebrew-easypad.git && cd homebrew-easypad
swift test
sh scripts/bundle.sh       # build/EasyPad.app 생성
sh scripts/release.sh 1.2  # 버전을 올려 빌드, 푸시, GitHub Releases 업로드, cask 갱신까지
```

## 6. 수정해야 할 내역

### 6.1 확인이 필요한 동작 (컴파일은 되지만 실행해 본 적이 없어 틀렸을 수 있음)

2026-10-13에 맥에서 눌러 본 항목에는 **확인함**을 붙였다. 붙지 않은 항목은 아직 미검증이다.

- **문서 형식 등록**: `Info.plist`의 문서 형식보다 `DocumentController`의 재정의(`documentClass(forType:)`, `typeForContents(of:)`, `beginOpenPanel`)에 의존한다. 열기 패널에서 모든 파일이 선택되는지, Finder의 "다음으로 열기"에 나오는지 확인.
- **종료 흐름**: AppKit이 델리게이트보다 먼저 미저장 문서를 확인하는지 몰라 두 군데(`applicationShouldTerminate`, `reviewUnsavedDocuments`)에 같은 처리를 넣었다. **확인함**: 세션 유지 모드에서 `⌘Q`는 묻지 않고 종료된다. 새 세션 모드에서 저장 확인이 한 번만 뜨는지는 미확인.
- **세션 복원 시점**: `applicationShouldOpenUntitledFile`과 `applicationDidFinishLaunching` 어느 쪽이 먼저 불려도 되게 했다. **확인함**: 복원 후 빈 "제목 없음" 탭이 덤으로 뜨지 않는다.
- **탭 묶임**: 새 문서는 마지막에 쓰던 탭의 묶음(`EditorWindowController.active`)에 들어간다. **확인함**: 새 탭, 파일 열기는 같은 창의 탭이 된다. 새 창 명령과 "새 창에서 열기" 설정이 따로 창을 띄우는지는 미확인.
- **탭 줄**: **확인함**: 탭 클릭 전환, `×`(보이는 탭, 숨은 탭), `+`, 우클릭 메뉴 표시, `⌃Tab`/`⌃⇧Tab`, 빈 곳 끌어 창 옮기기, 저장 안 한 탭의 ● 표시. 우클릭 메뉴의 "다른 탭 닫기"/"오른쪽 탭 닫기" 실행, 저장 안 한 탭 여러 개를 닫을 때의 확인 창 순서, 전체 화면, 다크 모드는 미확인.
- **확대/축소와 자동 줄 바꿈**: 스크롤 뷰 배율을 바꾼 뒤 줄 바꿈 폭이 보이는 영역에 맞는지. 어긋나면 글꼴 크기 배율 방식으로 바꿔야 한다.
- **레이아웃**: 세로 `NSStackView`에서 도구 모음과 상태 표시줄이 제 높이만 차지하고 텍스트 영역이 나머지를 채우는지. **확인함**: 높이 배분은 맞다. 숨김/표시 전환은 미확인.
- **목록**: `NSTextList`를 붙인 문단에서 Return을 누르면 다음 항목이 자동으로 생기는지, 번호가 다시 매겨지는지. 직접 넣은 마커 문자열(`\t•\t`)과 AppKit이 만드는 마커가 일치하는지.
- **표**: **확인함**: 표 삽입 대화 상자와 3×3 표 삽입. 빈 칸에 입력이 되는지, 행·열 추가/삭제 뒤 커서 위치, 실행 취소는 미확인.
- **제목 다음 줄**: 제목에서 Return을 누르면 본문 서식으로 돌아오는지.
- **저장 패널**: 형식 팝업을 바꾸면 확장자가 따라 바뀌는지, 인코딩 선택이 저장에 반영되는지.
- **인쇄 머리글/바닥글**: 왼쪽·가운데·오른쪽 정렬이 탭 위치로 제대로 나오는지, 쪽 번호가 쪽마다 바뀌는지.
- **글꼴 패널**: 글꼴을 바꾸면 모든 탭에 반영되는지.
- **한국어 UI**: 빈 `ko.lproj` 폴더만으로 시스템 패널(저장, 인쇄, 글꼴)이 한국어로 뜨는지.
- **단축키 충돌**: `⌥Z`(자동 줄 바꿈)가 문자 입력(Ω)보다 먼저 잡히는지, `⌘E`(Bing 검색)와 `⌘G`(줄 이동)가 맥 기본 동작을 덮어도 괜찮은지.

### 6.2 알고 넣은 한계 (코드에 `shortcut:` 주석으로 표시)

| 위치 | 한계 | 고칠 시점 |
|---|---|---|
| `TextFile.swift` | BOM 없는 UTF-16을 감지하지 못한다 | 그런 파일이 실제로 나오면 |
| `Editor.swift` | 커서가 움직일 때마다 처음부터 줄 수를 센다 | 큰 파일에서 느리면 줄 시작 위치를 캐시 |
| `App.swift` | 서식 지우기가 `⌘\`이다 (원본은 Ctrl+Space, 맥에서는 입력 소스 전환) | 더 맞는 키가 정해지면 |
| `Markdown.swift` | 웹 이미지는 내려받지 않고 자리 표시 아이콘만 보인다 | 필요하면 비동기 로드 |
| `Markdown.swift` | 서식 보기에서 친 `*` `_` `` ` `` `[`를 이스케이프하지 않는다 | 왕복 변환에서 글이 바뀌기 시작하면 |
| `Editor.swift` | 탭이 많으면 폭만 줄고 스크롤되지 않는다. 탭을 끌어 순서를 바꾸거나 창으로 떼어낼 수 없다 | 탭을 수십 개씩 열어 두면 |

### 6.3 원본과 다른 동작

- **찾기**: macOS 기본 찾기 막대를 쓴다. 모양과 옵션 이름이 다르고, "맨 위에서 다음 찾음" 같은 상태 메시지가 없다.
- **바꾸기 단축키**: `⌘⌥F` (원본 Ctrl+H, 맥에서 `⌘H`는 가리기).
- **맞춤법 검사**: 전체 켬/끔만 있다. 원본은 파일 종류별로 켜고 끈다. 대신 `.txt .md .markdown .srt .lrc .lic` 파일에서만 켜지게 했다.
- **Markdown 저장**: 서식 보기에서 편집하면 블록 사이에 빈 줄을 넣고 목록 들여쓰기를 4칸으로 맞춘다. 원본 소스의 줄바꿈 모양이 바뀔 수 있다.
- **인용문, 수평선, 코드 블록**: 서식으로 그리지 않고 원문 그대로 보여 준다.
- **외부 변경 감지**: 저장할 때만 알린다. 원본은 다시 열지 묻는 창을 바로 띄운다.
- **세션 복원 후 선택 탭**: 마지막에 보던 탭이 아니라 맨 끝 탭이 선택된다(선택 탭은 세션에 저장하지 않는다).
- **이미지 복사 시점**: 문서 폴더 밖의 이미지는 저장할 때 `문서이름_Images` 폴더로 복사한다(2026-10-13). 서식 보기에서 저장할 때만 하고, 구문 보기에서 직접 적은 경로는 그대로 둔다. 다른 폴더로 "다른 이름으로 저장"해도 이미 상대 경로인 이미지는 따라 옮기지 않는다.
- **새 탭의 종류**: Markdown이 기본이다(사용자 결정, 2026-10-13). 원본은 일반 텍스트가 기본이고 "새 Markdown 탭"이 따로 있다.
- **새 문서의 줄 끝**: 원본과 같은 CRLF. 맥에서는 LF가 자연스러우므로 바꿀지 정해야 한다(`TextFile.init`의 기본값 한 곳).
- **ANSI**: 한국어 환경에서는 CP949, 그 밖에는 Windows-1252로 본다.

## 7. 구현하지 않은 것

| 기능 | 이유 |
|---|---|
| Copilot 쓰기 도구(쓰기, 다시 쓰기, 요약), 로그인, AI 크레딧 | Microsoft 계정과 서비스에 묶여 있다 |
| 새 소식, 첫 실행 안내 화면 | 원본 전용 안내 |
| 도움말, 피드백 보내기 | Microsoft 링크 |
| 유니코드 제어 문자 표시/삽입 메뉴 | 미구현. 쓰기 방향 전환은 macOS 기본 메뉴에 있다 |
| 창 안으로 파일 끌어다 놓아 열기 | 미구현. Dock 아이콘에 놓는 것은 된다 |
| 상태 표시줄 항목 클릭(줄 이동 열기 등) | 미구현 |
| 탭 끌어서 순서 바꾸기/창 분리 | 미구현. 탭을 직접 그리면서 macOS 탭의 끌기 기능도 없어졌다 |
| 신뢰할 수 없는 파일·이미지 경고 | 미구현. 링크 열기 확인만 있다 |
| `/p` 인쇄 명령줄, `ms-notepad:` 주소 | Windows 셸 전용 |

## 8. 주의할 점

- **저장소가 공개다.** 앱 이름은 EasyPad로 바꿨지만, 소스의 `L10n.swift`에는 원본 메모장의 한국어 UI 문구가 여전히 들어 있다.
- **Homebrew cask**: `Casks/easypad.rb`. 앱이 공증받지 않았기 때문에 설치 직후 격리 표시를 떼는 단계(`postflight_steps`의 `xattr`)가 들어 있다. Homebrew가 이 방식을 막으면 Apple 개발자 계정으로 서명·공증해야 한다.
- **서명**: 임시(ad-hoc) 서명이라 내려받은 앱은 처음 열 때 우클릭 → 열기를 하거나 `xattr -dr com.apple.quarantine Notepad.app`을 실행해야 한다.
- **단축키와 일부 동작은 원본에서 확인한 값이 아니다.** 4.2절 참고. Windows에서 원본을 실행해 대조하면 정확해진다.

## 9. 작업 기록

**규칙**: 작업할 때마다 사용자가 지시한 내용과 그에 따라 한 일을 이 절에 덧붙인다(2026-10-13 사용자 지시). 위쪽 절의 내용이 바뀌면 그 절도 같이 고친다.

### 2026-10-13 (맥, 커밋 `eb67c1f`)

| # | 사용자 지시 | 한 일 |
|---|---|---|
| 1 | "일단 실행해줘" | `swift test`(3개 통과), `sh scripts/bundle.sh`로 `build/Notepad.app`을 만들어 실행. 맥에서의 첫 실행이다. |
| 2 | "윈도우 메모장과 모양도 기능도 많이 달라" | 창을 캡처해 버그 2개를 고쳤다: 도구 모음 드롭다운에 "NSMenuItem"이 찍히던 것, 새 문서 제목이 "무제"로 뜨던 것("제목 없음"으로). 창 안에 `파일 · 편집 · 보기` 버튼과 설정 톱니바퀴를 넣고, 도구 모음 버튼을 테두리 없는 아이콘으로 바꿨다. 기능 쪽은 어떤 점이 다른지 사용자에게 물었고 아직 답을 받지 않았다. |
| 3 | "제목표시줄은 못없애는거지?" → 탭을 제목 표시줄 안으로 올리는 2번 안으로 진행 | macOS 창 탭을 끄고 탭 줄을 직접 구현(4.4절). 탭 우클릭 메뉴, `⌃Tab`/`⌃⇧Tab`, 여러 탭을 닫을 때 저장 안 한 탭을 하나씩 앞으로 가져와 묻는 처리, 탭 묶음 테스트 1개 추가. 두 번째 탭부터 안 그려지던 버그(제약을 뷰를 붙이기 전에 걸었음)를 고쳤다. |
| 4 | "화면 조작 권한을 주려면?" → cmux의 Computer Use를 켬 | 탭 클릭, `+`, `×`, 창 안 `보기` 메뉴, 톱니바퀴를 눌러 확인. 탭을 바꿀 때 창이 커졌다 작아지는 애니메이션을 껐다. |
| 5 | "전부 확인해줘" | 우클릭 메뉴, `⌃Tab`, 창 끌기, `파일`·`편집`·`보기` 메뉴, ● 표시, `⌘Q` 세션 복원을 확인. 버그 3개 수정: ① `⌘Q` 뒤 세션이 빈 목록으로 덮어써짐(종료 중 문서가 닫힌 뒤 다시 저장됨) ② 복원 후 파일 탭이 저장 안 한 탭 뒤로 밀림(비동기 열기) ③ 파일 메뉴에 macOS가 넣는 "최근 사용 열기"가 "최근"과 중복. |
| 6 | "UI가 너무 조잡해. 패딩을 넉넉하게, 메뉴표시줄의 폰트/아이콘을 1.5배로" | 메뉴 줄, 탭 줄, 본문, 상태 표시줄의 여백을 늘리고 메뉴 줄 글자와 아이콘을 1.5배로. 제목 표시줄을 높였다. |
| 7 | "너무 커졌어. 1.2배 정도로" | 메뉴 줄 배율을 1.2배(15.6pt)로. |
| 8 | "선택된 탭은 메뉴 표시줄과 같은 색, 선택되지 않은 탭은 더 흐리게" | 탭 줄에 어두운 음영을 깔고, 선택된 탭은 아래가 메뉴 줄에 이어지게(위 모서리만 둥글게), 나머지 탭은 불투명도 55%. |
| 9 | "탭 크기는 지금이 좋은데 패딩은 늘리기 전으로" | 탭 줄 높이를 탭에 맞게 줄이고(compact), 좌우 여백과 탭 간격을 되돌렸다. 탭 자체의 크기와 다른 줄의 여백은 그대로. "탭 줄의 여백"으로 해석한 것이다. |
| 10 | "파일명 글씨색을 더 찐하게. 탭과 메뉴표시줄 색을 똑같이" | 탭 제목을 기본 글자색으로. 선택된 탭 자리를 음영에서 비우는 방식으로 바꿔 색을 일치시켰다(캡처 픽셀 기준 탭·메뉴 줄·상태 표시줄 모두 242, 243, 242). |
| 11 | "+ 버튼 정렬이 안 맞아. 탭에서 조금 더 떨어뜨려줘" | `+`를 탭 제목과 같은 세로 중심에 맞추고 탭과의 간격을 6pt 늘렸다. |
| 12 | "작업한 내용과 지시한 내용을 작업할 때마다 PROCESS.md에 기록해줘" | 이 절을 만들고, 그동안 바뀐 사실에 맞춰 2~7절을 고쳤다. |
| 13 | "설정화면에 디자인 요소를 추가해줘. 너무 초짜가 만든 앱같아" | 설정 창을 격자에서 섹션별 카드로 다시 만들었다(`App.swift`). 섹션 제목 4개(모양, 텍스트 서식, 메모장 열기, 맞춤법), 둥근 카드, 항목마다 아이콘·이름·설명, 체크 상자 대신 스위치. 자동 수정 스위치를 눌러 설정값이 바뀌는 것을 확인했다. |
| 14 | "컴포넌트들이 너무 기본 스타일이라 멋이 없어. 모던한 스타일로" | 설정 창의 컨트롤을 다듬었다(`App.swift`). 큰 "설정" 제목(제목 표시줄 글자는 숨김), 색 있는 둥근 사각형 안의 흰 아이콘, 테두리 없는 카드, 이름 아래에서 시작하는 구분선, 테두리 없는 팝업, 글꼴 버튼은 "글꼴 이름 ›" 모양. 설정 창에 한정한 것으로 해석했다. |
| 15 | "아이콘을 전부 SF Symbols로 바꿔줘" | 코드 변경 없음. 아이콘을 만드는 곳을 전부 찾아보니 이미 모두 SF Symbols다(`symbolImage()`가 `NSImage(systemSymbolName:)`를 쓴다). "가가", "가나다", "BIU"처럼 글자로 보이는 것은 SF Symbols의 한국어 지역화 모양이다. 어느 아이콘이 걸리는지 사용자에게 물었다. |
| 16 | "그럼 배경색상을 전부 빼줘" | 설정 창 아이콘의 색 있는 둥근 사각형 배경을 없앴다(`App.swift`). 아이콘은 배경 없이 기본 글자색으로 그린다. 14번의 나머지(큰 제목, 테두리 없는 카드와 팝업)는 그대로. |
| 17 | "설정창을 새 창이 아니라 윈도우 메모장처럼 하나의 탭으로" | 설정 창을 없애고 설정을 탭으로 열게 했다(`App.swift`의 `SettingsView`, `Editor.swift`의 `showSettings()`). 카드는 탭 너비에 맞춰 늘어나고 내용이 길면 스크롤된다. 확인함: `⌘,`로 탭이 열림, 다른 탭에 있다가 다시 열면 같은 설정 탭으로 돌아감, `×`로 닫으면 옆 탭이 나타남. |
| 18 | "cmd + t 를 눌렀을 때 cmd + n 과 동일한 처리가 되도록" | 파일 메뉴에 `⌘T`를 가진 숨은 "새 탭" 항목을 하나 더 넣었다(`App.swift`). 메뉴 항목 하나는 단축키를 하나만 가질 수 있어서다. 확인함: `⌘T`로 새 탭이 열린다. |
| 19 | "기본 탭을 마크다운으로. cmd + shift + n or t를 누르면 텍스트 기반의 탭이 열리게" | 새 탭의 기본 종류를 Markdown으로 바꿨다(`DocumentController.defaultType`). `⌘N`/`⌘T`, `+` 버튼, 앱을 켤 때의 첫 탭이 모두 Markdown이다. `⌘⇧N`/`⌘⇧T`는 일반 텍스트 탭("새 텍스트 탭")을 연다. 그 자리에 있던 "새 Markdown 탭" 항목은 없앴고, "새 창"은 `⌘⇧N`을 내주어 단축키가 없어졌다. 세션에서 되살린 제목 없는 탭이 원래 종류(텍스트/Markdown)를 유지하게 했다. 확인함: `⌘T`는 "포맷", `⌘⇧T`와 `⌘⇧N`은 "일반 텍스트"로 열린다. |
| 20 | "이름 뒤에 마크다운 문법도 표기해줘. 이름만 가지고는 구분이 어려워" | 제목 메뉴의 항목 이름 뒤에 Markdown 기호를 붙였다(`Formatting.swift`의 `headingItems()`): 제목 `#`, 부제 `##` … 하위 섹션 `######`. "본문"은 기호가 없어 그대로다. 메뉴 줄의 제목 드롭다운과 서식 > 제목 메뉴 양쪽에 적용된다. 목록·표·이미지 메뉴는 바꾸지 않았다. |
| 21 | "정렬해서 보여주면 안돼? 저렇게 보이면 조잡스러워 보이잖아" | 제목 메뉴의 `#` 기호를 이름 옆에 바로 붙이지 않고 따로 한 열로 정렬했다(탭 위치 고정, 고정폭 글꼴, 흐린 색). 확인하다가 저장 안 한 탭의 ● 표시가 탭 오른쪽 끝에서 벗어나 떠 있는 것을 발견해 같이 고쳤다(`Editor.swift`, 닫기 버튼이 늘어나지 않게). |
| 22 | "제목, 부제, 머리글을 실제 크기로 보이게 할 수 있어?" | 제목 메뉴의 이름을 본문에 적용되는 것과 같은 비율과 굵기로 그린다(`Formatting.swift`, 본문과 같은 `headingFont()` 사용. 제목 2배, 부제 1.6배, 머리글 1.35배, 부제목 1.2배, 섹션 1.1배, 하위 섹션 1배, 모두 굵게). "본문"은 보통 크기. `#` 열은 그대로 정렬된다. 원본 메모장의 제목 드롭다운도 이렇게 보인다. |
| 23 | "표 삽입을 눌렀는데 반응이 없어" | 원인: 명령 이름 `insertTable:`을 `NSTextView`가 이미 자체적으로 받는다. 텍스트 뷰가 첫 응답자라 명령을 먼저 가로채고 아무 일도 하지 않았다. 명령 이름을 `insertMarkdownTable`로 바꿨다(`Formatting.swift`, `Editor.swift`). 편집기의 다른 명령 이름 30개도 같은 충돌이 있는지 검사했고 이것 하나뿐이었다. 확인함: 대화 상자(행·열 개수)가 뜨고 3×3 표가 들어간다. |
| 24 | "윈도우처럼 마우스로 표를 만들 수는 없어?" | 테이블 메뉴 맨 위에 크기 선택 격자를 넣었다(`Formatting.swift`의 `TableGridPicker`, 가로 10 × 세로 8칸). 마우스를 올리면 그만큼 칸이 강조되고 아래에 "행 × 열"이 나오며, 클릭하면 그 크기의 표가 들어간다. 대화 상자 방식("표 삽입...")은 키보드와 VoiceOver용으로 격자 아래에 남겼다. 테스트 1개 추가(격자 위치 → 크기 계산, 그 크기로 표 삽입). 확인함: 메뉴에 격자가 뜬다. 격자 칸을 실제 마우스로 클릭하는 것은 화면 조작 도구가 열린 메뉴 안을 누르지 못해 확인하지 못했다. |
| 25 | "마크다운은 이미지를 저장 못 하잖아. 로컬 주소값이 들어가는 거야?" → "원본처럼 이미지 폴더로 복사하는 방식으로 바꿔줘" | 저장할 때 문서 폴더 밖에 있는 이미지를 문서 옆 `문서이름_Images` 폴더로 복사하고, 문서에는 그 상대 경로(`![](note_Images/pic.png)`)를 적는다(`Formatting.swift`의 `gatherImages(for:)`, `Document.save(to:)`에서 호출). 원본 파일은 그대로 둔다. 이름이 같고 내용이 다른 이미지는 `-2`, `-3`을 붙이고, 같은 이미지는 다시 쓴다. 복사에 실패하면 원래 경로를 유지한다. 저장 전인 새 탭에서는 폴더가 없으므로 첫 저장 때 복사된다. 테스트 1개 추가(실제 저장을 거쳐 파일 내용과 복사본 확인), 전체 6개 통과. 6.2절의 해당 한계를 지웠다. |
| 26 | "app파일로 아카이빙 할 수 있어?" | 코드 변경 없음. `.app`은 `sh scripts/bundle.sh`가 이미 `build/Notepad.app`으로 만든다(유니버설, 임시 서명). 배포용으로 `ditto -c -k --keepParent build/Notepad.app build/Notepad.zip`으로 압축했다(405KB). `build/`는 `.gitignore` 대상이라 저장소에는 올라가지 않는다. |
| 27 | "앱 아이콘 넣어놨어. a_clean 어쩌구 파일이야" | 사용자가 넣은 `a_clean_app_icon_style_graphic_illustration_on_a.png`(1254×1254, 투명 배경)를 `AppIcon.png`로 이름을 바꾸고 앱 아이콘으로 연결했다. `scripts/bundle.sh`가 `sips`와 `iconutil`로 `AppIcon.icns`(16~1024px)를 만들어 번들에 넣고, `Info.plist`에 `CFBundleIconFile`을 추가했다. `build/Notepad.zip`도 다시 만들었다. |
| 28 | "지금까지 작업한 내용 커밋해줘" | 1~27번 작업을 브랜치 `mac-ui-pass`에 한 커밋으로 올렸다. `main`에서 바로 커밋하지 않고 브랜치를 만든 것이며, 푸시는 하지 않았다. |
| 29 | "main 브랜치에 합치고 푸시해줘" | `mac-ui-pass`를 `main`에 fast-forward로 합치고 `origin/main`에 푸시했다. 브랜치는 지웠다. |
| 30 | "다른 사람에게 전달하기 가장 좋은 방법은?" → `gh` 로그인 → "응 올려줘" | GitHub Releases에 `v1.0`을 만들고 `Notepad.zip`(2.6MB, `main`의 `a959ad5`에서 빌드)을 올렸다. https://github.com/dmnkx/notepad-mac/releases/tag/v1.0 릴리스 설명에 설치 방법과, 공증받지 않은 앱이라 처음 열 때 필요한 절차(시스템 설정의 "그래도 열기" 또는 `xattr`)를 적었다. 서명은 여전히 임시(ad-hoc)다. |
| 31 | "brew로 설치할 수 있도록 하고 싶은데 서명이 필요한가?" → "내 레포를 확인해줄래?" | 코드 변경 없음. 공식 cask는 서명·공증이 필요하지만 개인 tap은 필요 없다고 답했다. 사용자의 `homebrew-sssh`, `homebrew-myip`를 읽어 보니 저장소 하나가 소스이자 tap이고 Releases의 바이너리를 가리키는 방식이었다. |
| 32 | "앱이름을 easypad로 바꾸고 1번으로 해줘" (1번 = 저장소 이름을 `homebrew-`로 바꿔 tap으로 쓰기) | 앱 이름을 EasyPad로 바꿨다: `Info.plist`(이름, 실행 파일, 번들 ID), 메뉴·설정·경고 문구, 세션 폴더(`Application Support/EasyPad`), `bundle.sh`, CI, `ci-wait.sh`. 표시 이름의 대소문자는 "EasyPad"로 정했다(사용자는 "easypad"라고 적음). SwiftPM 타깃 이름은 그대로 뒀다. 저장소를 `homebrew-easypad`로 이름 변경. `Casks/easypad.rb`, `scripts/release.sh`, `README.md` 추가. 이 맥의 기존 설정과 세션은 새 이름으로 옮겼다. |
| 33 | 작업 중 질문: "`brew install --cask dmnkx/notepad` 이렇게는 안 돼?" | 두 부분짜리 이름은 Homebrew가 tap으로 해석해서 안 된다. `--cask` 없이 `brew install dmnkx/easypad/easypad`가 가장 짧은 한 줄이고, `brew tap dmnkx/easypad` 뒤에는 `brew install easypad`만으로 된다고 답했다. |

이 날 작업에서 확인하지 못한 것: 다크 모드, 전체 화면, 창을 아주 좁혔을 때의 탭 줄, 창이 활성/비활성일 때 각각의 색 일치(라이트 모드 한 상태에서만 측정), 설정 탭의 나머지 스위치·팝업과 글꼴 버튼, 설정 탭만 남기고 다른 탭을 모두 닫았을 때의 동작.

### 2026-10-14 (맥)

| # | 사용자 지시 | 한 일 |
|---|---|---|
| 34 | (32번의 마무리) | 커밋 `b236394`(이름 변경, cask, 릴리스 스크립트, README)를 올리고 `sh scripts/release.sh 1.1`로 `v1.1`을 냈다(`f3b2749`). 확인함: `brew install dmnkx/easypad/easypad`로 tap 등록과 설치가 되고, `/Applications/EasyPad.app`에 격리 표시가 붙지 않으며, 설치된 앱이 차단 없이 실행된다. CI도 성공. cask의 설치 후 단계는 Homebrew가 요구하는 새 문법(`postflight_steps`)으로 썼다. |

---

# 부록 A. 분석으로 알아낸 정보

REA(`rea-agents` 6.4.0)의 PE 리소스 검사 도구(`inspect_pe_resources`)가 리소스의 종류·이름·언어와 파일 내 위치를 알려 주고, 그 위치의 바이트를 `re/decode_res.py`로 해독했다. PRI와 XBF 파일은 REA가 다루지 않아 직접 만든 스크립트로 읽었다. 모든 분석은 실행 없이 파일만 읽는 정적 분석이다.

REA에 Ghidra/IDA를 연결하지 않았기 때문에 **함수 디컴파일은 하지 않았다.** 아래 내용은 전부 리소스, 매니페스트, 문자열에서 나온 것이고, 코드의 실제 동작을 본 것은 아니다.

## A.1 분석 대상

| 파일 | 크기 | SHA-256 | REA 증거 ID |
|---|---|---|---|
| `C:\Windows\System32\notepad.exe` (클래식) | 360,448 | 측정 안 함 | 없음 (리소스가 `.mui`에 있음) |
| `C:\Windows\System32\ko-KR\notepad.exe.mui` | 11,776 | `16ab5f4b577be5662fdf9a90ddb2d5fef7e3ee2671c5b23f9b380ecfc7576be0` | `ev_374daffafba4f8c13a836b168c82179dd71c2aad9f6c88df7fe244093d42a14f` |
| 스토어판 `Notepad\Notepad.exe` | 3,305,272 | `03745e9e21684c0e6d9fdc50d91caa0935f4baf50f626c11987ab7d6991d58d1` | `ev_34cab0a0924e4a4a0ede3b5c70b6e9c67885b1191701e54dab550fdd59accf61` |

- Windows 버전: 10.0.26300.9550
- 스토어판 패키지: `Microsoft.WindowsNotepad_11.2607.14.0_x64__8wekyb3d8bbwe`
- 한국어 리소스 패키지: `Microsoft.WindowsNotepad_11.2607.14.0_neutral_split.language-ko_8wekyb3d8bbwe`
- `en-US\notepad.exe.mui`(14,336바이트)도 있으나 해독하지 않았다.

## A.2 클래식 메모장 (`ko-KR\notepad.exe.mui`)

리소스 21개: MUI 1, 메뉴 1, 대화 상자 6, 문자열 표 9, 단축키 표 3, 버전 1.

### 메뉴 (괄호 안은 명령 ID)

- **파일**: 새로 만들기 Ctrl+N (1), 새 창 Ctrl+Shift+N (8), 열기 Ctrl+O (2), 저장 Ctrl+S (3), 다른 이름으로 저장 Ctrl+Shift+S (4), 페이지 설정 (5), 인쇄 Ctrl+P (6), 끝내기 (7)
- **편집**: 실행 취소 Ctrl+Z (16), 잘라내기 Ctrl+X (768), 복사 Ctrl+C (769), 붙여넣기 Ctrl+V (770), 삭제 Del (771), Bing으로 검색 Ctrl+E (28), 찾기 Ctrl+F (21), 다음 찾기 F3 (22), 이전 찾기 Shift+F3 (29), 바꾸기 Ctrl+H (23), 이동 Ctrl+G (24), 모두 선택 Ctrl+A (25), 시간/날짜 F5 (26)
- **서식**: 자동 줄 바꿈 (32), 글꼴 (33)
- **보기**: 확대하기/축소하기 → 확대 Ctrl+더하기 (34), 축소 Ctrl+빼기 (35), 기본값 복원 Ctrl+0 (36) / 상태 표시줄 (27)
- **도움말**: 도움말 보기 (64), 피드백 보내기 (66), 메모장 정보 (65)

잘라내기·복사·붙여넣기·삭제·Bing 검색은 리소스에서 비활성(grayed)으로 시작한다. 선택 영역이 있을 때 켜지는 것으로 보인다(추정).

### 단축키 표

`GLOBALACC`:

| 키 | 명령 | 키 | 명령 |
|---|---|---|---|
| Ctrl+N | 새로 만들기 (1) | F3 | 다음 찾기 (22) |
| Ctrl+Shift+N | 새 창 (8) | Shift+F3 | 이전 찾기 (29) |
| Ctrl+O | 열기 (2) | Ctrl+F | 찾기 (21) |
| Ctrl+S | 저장 (3) | Ctrl+H | 바꾸기 (23) |
| Ctrl+Shift+S | 다른 이름으로 저장 (4) | Ctrl+G | 이동 (24) |
| Ctrl+P | 인쇄 (6) | Ctrl+E | Bing으로 검색 (28) |
| Ctrl+W | 끝내기 (7) | Ctrl+= / Ctrl+숫자패드+ | 확대 (34) |
| F1 | 도움말 (64) | Ctrl+- / Ctrl+숫자패드- | 축소 (35) |
| | | Ctrl+0 / Ctrl+숫자패드0 | 배율 복원 (36) |

`MAINACC`: Ctrl+Ins 복사 (769), F5 시간/날짜 (26), Alt+Backspace 실행 취소 (16), Ctrl+Z (16), Ctrl+X (768), Ctrl+C (769), Ctrl+V (770), Ctrl+A (25).

`SLIPUPACC`: `MAINACC`와 같고, Esc / Ctrl+C / Ctrl+D / Ctrl+Z가 끝내기(7)로 연결된다. 용도는 확인하지 못했다.

### 대화 상자

| ID | 제목 | 구성 |
|---|---|---|
| 11 | 메모장 | "지금 인쇄 중", 진행 문구 2줄, 취소 |
| 12 | 페이지 설정 | 용지(크기, 공급), 방향(세로/가로), 여백(왼쪽/오른쪽/위쪽/아래쪽), 머리글, 바닥글, "값 입력" 링크, 미리 보기, 확인/취소/프린터 |
| 14 | 줄 이동 | 줄 번호 입력, 이동/취소 |
| 15 | (저장 대화 상자 덧붙임) | 인코딩 콤보 상자 |
| 1540 | 찾기 | 찾을 내용, 단어 단위로, 대/소문자 구분, 주위에 배치, 방향(위로/아래로), 다음 찾기/취소/도움말 |
| 1541 | 바꾸기 | 찾을 내용, 바꿀 내용, 단어 단위로, 대/소문자 구분, 랩 어라운드, 다음 찾기/바꾸기/모두 바꾸기/취소/도움말 |

### 문자열 표에서 확인한 동작

- **창 제목 형식**: `%1%2 - Windows 메모장`, 새 문서 이름 `제목 없음`
- **인코딩 목록**: ANSI, UTF-16 LE, UTF-16 BE, UTF-8, UTF-8(BOM), 열 때는 `자동 검색`
- **줄 끝 표시**: ` Windows (CRLF)`, ` Unix (LF)`, ` Macintosh (CR)`
- **상태 표시줄**: ` Ln %d, Col %d`, 배율 ` %d%%`, 찾기 결과 ` 맨 아래에서 다음 찾음` / ` 맨 위에서 다음 찾음`
- **머리글/바닥글**: 기본 머리글 `&f`, 기본 바닥글 `&p 페이지`, 코드 문자 목록 `fFpPtTdDcCrRlL` (파일, 쪽, 시간, 날짜, 가운데, 오른쪽, 왼쪽이 대소문자 구분 없이 쓰임)
- **파일 형식 필터**: `텍스트 문서(*.txt)`, `모든 파일`
- **저장 확인**: `변경 내용을 %1에 저장하시겠습니까?` + 저장 / 저장 안 함
- **경고와 오류**: 파일 없음(새로 만들지 물음), 열 수 없음, 권한 없음, 너무 큼, 메모리 부족, ANSI 저장 시 유니코드 손실, 찾을 수 없음(`"%%"을(를) 찾을 수 없습니다.`), 줄 번호가 전체 줄 수 초과, 인쇄 실패, 페이지가 너무 작음
- **파일 속성 표시용 문자열**: 압축됨, 암호화됨, 숨김, 오프라인, 읽기 전용, 시스템
- **그 밖**: `새 버전의 메모장도 사용할 수 있습니다.` + 해제/설치/시작 (스토어판 안내 배너)

## A.3 스토어 메모장 패키지

### 파일 구성 (260개 중 이미지 제외)

| 경로 | 크기 | 역할(추정) |
|---|---|---|
| `Notepad\Notepad.exe` | 3,305,272 | 본체 |
| `Notepad\NotepadXamlUI.dll` | 6,417,248 | XAML UI 구현 |
| `Notepad\riched20.dll` | 4,046,144 | 리치 에디트 컨트롤(편집기 엔진) |
| `Notepad\msptls.dll` | 2,012,992 | 줄 배치 엔진 |
| `OleControls\OleControls.dll` | 345,920 | 미확인 |
| `NotepadExplorerCommand\NotepadExplorerCommand.dll` | 308,544 | 탐색기 "메모장에서 편집" 메뉴 |
| `NotepadXamlUI\*.xbf` | 65개 | 컴파일된 XAML 화면 |
| `NotepadXamlUI\Assets\NotepadIcons.ttf` | 22,072 | 아이콘 글꼴 |
| `resources.pri` | 80,640 | 문자열(영어)과 리소스 색인 |
| `NotepadXamlUI.winmd` | 146,944 | UI 형식 메타데이터 (열어 보지 않음) |
| `Assets\NewTextDocument.txt` | 0 | "새 텍스트 문서" 틀 |

### 매니페스트 (앞부분 약 9,000자만 읽음)

- **실행**: `Notepad\Notepad.exe`, 전체 신뢰 데스크톱 앱, 시작 폴더 `%USERPROFILE%`
- **의존**: Windows App Runtime 2 (2.1.3.0 이상), VCLibs 14, 최소 Windows 10.0.22000
- **실행 별칭**: `notepad.exe`
- **프로토콜**: `ms-notepad`
- **파일 연결(확인한 범위)**: `.txt` `.log` `.scp` `.wtx` `.ini` `.inf` `.ps1` `.psd1` `.psm1`
- **셸 동사**: 편집(`%1`), 인쇄(`/p %1`), 지정 프린터로 인쇄(`/pt "%1" "%2" "%3" "%4"`)
- **업데이트**: 사용 중에는 미룸

### `Notepad.exe` 리소스 (20개)

아이콘 7개(256, 64, 48, 40, 32, 24, 16px), 대화 상자 4개(ID 11, 12, 14, 16), RCDATA 4개(ID 44, 51, 52, 53), 아이콘 그룹, 버전, 매니페스트, 기업 데이터 보호(EDP) 표식 2개.

**메뉴와 단축키 표 리소스가 없다.** 메뉴는 XAML에서, 단축키는 코드에서 만든다. 대화 상자 4개와 RCDATA는 해독하지 않았다.

### `Notepad.exe` 안의 문자열에서 찾은 것

- **설정/상태 이름**: `GhostFile`, `GhostFileEnabled`, `GhostFileRestoration`, `RecentFiles`, `RecentFilesEnabled`, `StatusBarShown`, `StatusBarVisible`, `TabState`, `lfFaceName`, `SettingCacheInitialized`
- **세션 복원 주소**: `ms-notepad:restore/{}`
- **Markdown**: `.md`, `.markdown`, `*.md`, `{0}.md`, `text/markdown`, `MarkdownToPlainText`, `KeepMarkdown`, `HasMarkdownSyntax`, `MarkdownImageFolderNameFmt`
- **`.LOG`**: 문자열 존재 (파일 첫 줄이 `.LOG`이면 열 때 시간을 덧붙이는 기능)
- **상태 표시줄 항목 이름**: `StatusBarLineColumn`, `StatusBarCharacterCount`, `StatusBarCharacterCountWithSelection`, `StatusBarZoomPercentage`, `StatusBarLineEndingsCRLF/LF/CR`
- **AI 메뉴 항목**: 어조(Default, Formal, Casual, Inspirational, Humor, Persuasive), 형식(Default, Paragraph, List, Business, Academic, Marketing, Poetry), 길이(Short, Medium, Long)
- **소스 경로 흔적**: `D:\a\_work\1\s\src\Notepad\SettingCache.cpp`

저장되지 않은 탭을 "ghost file"이라 부르는 것, 세션을 탭 상태(`TabState`)로 보관하는 것은 이름에서 추정한 것이다.

## A.4 화면 구성 (`NotepadXamlUI\*.xbf`의 요소 이름)

- **메뉴 막대** (`MainMenuBar`): 메뉴, 서식 도구 모음, 오른쪽에 AI 모델 내려받기 표시·Cowriter 버튼·새 소식 버튼·사용자 아바타·설정 버튼, 좁을 때는 더 보기 버튼으로 접힘
- **서식 도구 모음** (`FormattingToolbar`): 제목 드롭다운, 목록 드롭다운(들여쓰기/내어쓰기 포함), 표 드롭다운(표 삽입, 표 편집 → 왼쪽/오른쪽 열, 위/아래 행 삽입, 선택 → 표/열/행, 삭제), 이미지 드롭다운(기기에서, 링크로), 토글 버튼들, 넘칠 때 더 보기
- **상태 표시줄** (`StatusBar`): 줄·열, 글자 수, 서식 모드, 배율, 줄 끝, 인코딩 순
- **탭 막대** (`TabsBar`): 탭 끌기·순서 바꾸기·놓기 허용, 같은 너비, 탭 메뉴에 새 탭 / 탭 닫기 / 다른 탭 닫기 / 오른쪽 탭 닫기
- **찾기 창** (`FindReplaceDialog`): 펼침 버튼(바꾸기 줄 표시), 찾기 입력란, 아래로/위로 검색, 옵션 메뉴(대/소문자 구분, 주위에 배치), 닫기, 바꾸기 입력란, 바꾸기 / 모두 바꾸기. 좁을 때 쓰는 축약 배치가 따로 있음
- **설정** (`NotepadSettingsPage`): 모양(앱 테마) → 텍스트 서식(글꼴, 자동 줄 바꿈, 서식) → 메모장 열기(파일 여는 위치, 시작 시 동작, 최근 파일) → 맞춤법(맞춤법 검사, 자동 수정) → 고급 기능(Cowriter) → 정보(사용 조건, 서비스 계약, 개인정보, 타사 소프트웨어, 피드백, 도움말)
- **대화 상자**: 줄 이동, 링크, 표 삽입, 웹 이미지, 안전하지 않은 링크 경고, 첫 실행 안내, Cowriter 관련 여러 개
- **그 밖의 화면 조각**: `GhostFileSettingSection`, `RecentFilesSettingSection`, `OpenFileSettingSection`, `ThemeSettingSection`, `FontSettingSection`, `WordWrapSettingSection`, `FormatSettingSection`, `SpellCheckSettingSection`, `AutocorrectSettingSection`, `CowriterSettingSection`

## A.5 문자열(`resources.pri`)에서 읽은 기능 목록

영어 469개, 한국어 465개. 아래는 기능별로 묶은 것이다.

- **파일 메뉴**: New tab, New Markdown tab, New window, Open, Recent(No recent files, Clear list), Save, Save as, Save all, Page setup, Print, Close tab, Close window, Exit
- **편집 메뉴**: Undo, Cut, Copy, Paste, Delete, Search with Bing, Define with Bing, Find, Find next, Find previous, Replace, Go to, Select all, Time/Date, Font
- **보기 메뉴**: Zoom(Zoom in, Zoom out, Restore default zoom), Status bar, Word wrap, Markdown(Formatted, Syntax)
- **서식**: Bold, Italic, Strikethrough, Link, Clear formatting, Headings(Title, Subtitle, Heading, Subheading, Section, Subsection, Body), Lists(Bulleted list, Numbered list, Task list, Increase/Decrease indent, Check list, Untick list), Table(Insert table, Edit table, Row above/below, Column left/right, Select, Delete), Image(Insert from this device, Insert via link, Replace image)
- **링크**: Link to an existing webpage, Address, Display text, Text for the link (optional), Edit link, Remove link, Ctrl+Click to follow link, 안전하지 않은 링크 경고, 지원하지 않는 링크 종류 안내
- **이미지**: 외부 파일의 이미지를 문서 옆 `{}_Images` 폴더로 복사한다는 안내, 이미지 신뢰 확인, 이미지를 찾을 수 없을 때 안내
- **Markdown 보기 전환**: 지원하지 않는 문법 경고, 신뢰할 수 없는 파일을 서식 보기로 열지 확인, 외부에서 파일이 바뀌면 구문 보기로 전환, 서식 끄기("열린 파일의 모든 서식이 지워진다"는 경고)
- **저장**: Save as Markdown to keep formatting(Save as Markdown file / Save as text file), 파일 형식(Text documents, Markdown file, All files), 인코딩(ANSI, UTF-16 LE, UTF-16 BE, UTF-8, UTF-8 with BOM, Auto-Detect)
- **상태 표시줄**: ` Ln %d, Col %d`, 글자 수(선택 시 "n of m characters"), Plain text / Markdown syntax / Formatted, 배율, 줄 끝 3종
- **찾기 결과 안내(화면 읽기용)**: 찾은 위치의 줄·열, 위/아래에서 다시 찾음, 1개 바꿈, 마지막 항목 바꿈, 모두 바꿈, 문서 끝/시작 도달
- **탭**: New tab, Close tab, Close other tabs, Close tabs to the right, Open in a new tab / Open in a new window
- **세션과 외부 변경**: Continue previous session / Start new session and discard unsaved changes, "다른 앱에서도 바뀌었다"는 안내와 Keep changes / Reopen file / Keep for all
- **설정**: App theme(Use system setting, Light, Dark), Font(Family, Style, Size, 미리 보기 문장), Word wrap, Formatting, Opening files, When Notepad starts, Recent Files, Spell check(파일 종류별), Autocorrect
- **맞춤법 메뉴**: Add to dictionary, Remove from dictionary, Ignore once, Ignore all, Delete repeated word, No suggestions, Turn on/off spell check
- **텍스트 메뉴**: Right-to-left reading order, Show Unicode control characters, Insert Unicode control characters(LRM, RLM, ZWJ, ZWNJ 등 16종), Reconversion
- **인쇄**: 페이지 설정 항목(용지, 방향, 여백, 머리글, 바닥글), Now printing, `Page %d`
- **AI(Cowriter)**: Write, Rewrite, Summarise, Make shorter/longer, Change tone, Change format, 로그인, 크레딧, Microsoft 365 구독, Copilot+ PC 로컬 모델 관련 문구 다수
- **첫 실행 안내**: "Your essential text editor, elevated", "Lightweight formatting", "Smarter writing tools"

## A.6 확인하지 못한 것

- **스토어판 단축키**: 문자열에 직접 적힌 것은 `Close tab (Ctrl+W)`, `Italic (Ctrl+I)`, `Strikethrough (Ctrl+Shift+X)`, `Link (Ctrl+K)`, `Clear formatting (Ctrl+Space)`, `Ctrl+Plus`, `Ctrl+Minus`뿐이다. `New tab (Ctrl+{})`와 `Bold (Ctrl+{})`는 키가 빈칸으로 들어 있어 값은 코드에 있다. 나머지(새 창, 모두 저장, 자동 줄 바꿈 등)는 클래식판 표와 일반 지식으로 채웠다.
- **메뉴 항목 순서와 구분선 위치**: 스토어판 메뉴는 코드에서 만들어져 리소스로는 순서를 알 수 없다. 앱의 메뉴 순서는 클래식판과 문자열을 참고해 정했다.
- **동작의 세부**: 세션 저장 형식, 맞춤법 검사 기본 대상 파일 종류, 인코딩 자동 감지 규칙, 확대/축소 범위, 글자 수 세는 방식은 코드를 디컴파일해야 알 수 있다. 앱에는 알려진 동작을 기준으로 넣었다.
- **해독하지 않은 것**: `Notepad.exe`의 대화 상자 4개와 RCDATA 4개, `NotepadXamlUI.winmd`, `NotepadXamlUI.dll`, 매니페스트 뒷부분, 영어 `.mui`.
- **한·영 문자열 짝**: 개수가 달라 일부 구간(영어 92~107번, 316~321번, 371~372번 부근)은 자동으로 맞춘 짝이 한 칸씩 어긋난다. 앱에 쓴 문자열은 손으로 확인했다.

## A.7 분석을 다시 하려면

문자열 원본 덤프(`re/en.txt`, `re/ko.txt`, `re/pairs.json`, `re/names.txt`)는 저장소에 올리지 않았다. 스토어 메모장이 설치된 Windows의 WSL에서 다시 만들 수 있다.

```sh
B="/mnt/c/Program Files/WindowsApps"
MAIN="$B/Microsoft.WindowsNotepad_11.2607.14.0_x64__8wekyb3d8bbwe"
KO="$B/Microsoft.WindowsNotepad_11.2607.14.0_neutral_split.language-ko_8wekyb3d8bbwe"
python3 re/pri_dump.py "$MAIN/resources.pri" 4 > re/en.txt     # 영어 문자열
python3 re/pri_dump.py "$KO/resources.pri"     > re/ko.txt     # 한국어 문자열
python3 re/pri_sections.py "$MAIN/resources.pri"               # PRI 구획 목록
```

클래식판 리소스는 REA의 `inspect_pe_resources`가 알려 준 파일 내 위치를 넘겨 해독한다(형식 `종류:이름:오프셋:길이`).

```sh
python3 re/decode_res.py /mnt/c/Windows/System32/ko-KR/notepad.exe.mui \
  menu:1:2448:1216 acc:GLOBALACC:10212:160 acc:MAINACC:10372:64 acc:SLIPUPACC:10436:96 \
  str:1:6740:1226 str:2:7968:1078 str:3:9048:352 str:4:9400:328 \
  dlg:11:3664:204 dlg:12:3868:1248 dlg:14:5116:216 dlg:15:5332:132 dlg:1540:5464:608 dlg:1541:6072:668
```

메모장 버전이 바뀌면 패키지 폴더 이름과 오프셋이 달라진다.
