# PROCESS — Windows 11 메모장 macOS 포팅

마지막 갱신: 2026-10-13

## 1. 목적

Windows 11 기본 메모장(스토어판 `Microsoft.WindowsNotepad` 11.2607.14.0)을 macOS에서 같은 기능으로 쓸 수 있게 네이티브 앱으로 다시 만든다.

원본 실행 파일을 옮기는 것이 아니라, 설치된 패키지에서 기능 목록과 UI 문자열을 읽어 내고 그에 맞춰 Swift/AppKit으로 새로 구현한다.

## 2. 목표

- 원본 메모장의 기능을 빠짐없이 구현한다. 옮길 수 없는 것은 이 문서에 이유와 함께 남긴다.
- macOS 13 이상에서 도는 유니버설(arm64 + x86_64) `.app`을 만든다.
- UI는 한국어와 영어를 지원하고, 문구는 원본 메모장의 것을 쓴다.
- 개발 PC가 WSL(Linux)이라 로컬 빌드가 안 되므로 GitHub Actions의 macOS 러너에서 테스트하고 `.app`을 만든다.
- 코드는 최소한으로 유지한다. 플랫폼이 이미 제공하는 것(NSDocument, 창 탭, 찾기 막대, 맞춤법 검사, 인쇄)은 직접 만들지 않는다.

## 3. 현재 상태

**빌드와 테스트는 CI에서 통과했다. 앱을 실제로 실행해 본 적은 아직 없다.**

| 항목 | 상태 |
|---|---|
| 소스 작성 | 완료 (Swift 약 1,900줄) |
| 저장소 | `git@github.com:dmnkx/notepad-mac.git`, 공개 저장소, `main` 브랜치 |
| CI 1회차 (`f287253`) | 실패, `swift test` 단계 |
| CI 2회차 (`69355cc`) | 실패. 오류 1건 확인: `main.swift`에서 `@MainActor` 함수 `runApp()` 호출 불가 |
| CI 3회차 (`8e0f412`) | 성공. `swift test`, `.app` 번들, 아티팩트 업로드까지 통과 |
| 테스트 | 3개 통과 (인코딩·줄 끝, 머리글/바닥글 코드, Markdown 왕복) |
| 산출물 | Actions 실행의 아티팩트 `Notepad` (`Notepad.zip` 안에 `Notepad.app`) |
| 실제 동작 확인 | 전혀 안 함 |

컴파일 경고가 있는지는 로그를 읽지 못해 모른다(전체 로그는 로그인이 필요). 화면과 동작에 관한 코드는 테스트가 없으므로 6.1절의 항목은 전부 미검증이다.

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

- **탭과 창**: 새 탭, 새 Markdown 탭, 새 창, 탭 닫기, 창 닫기, 다른 탭 닫기, 오른쪽 탭 닫기. macOS의 창 탭 기능을 그대로 쓴다.
- **세션**: "이전 세션 계속하기". 종료할 때 열린 탭과 저장하지 않은 내용을 `~/Library/Application Support/Notepad/session.json`에 적고, 저장 여부를 묻지 않고 끝낸 뒤 다음 실행에서 되살린다. 파일 자체는 건드리지 않는다.
- **파일**: 아무 확장자나 열기, 최근 파일, 모두 저장. ANSI / UTF-16 LE / UTF-16 BE / UTF-8 / UTF-8(BOM) 감지와 저장, 줄 끝(CRLF/LF/CR) 유지, 저장 대화 상자에서 형식과 인코딩 선택, ANSI로 담을 수 없는 문자 경고, `.LOG` 파일 타임스탬프.
- **편집**: 실행 취소/다시 실행, 찾기/다음/이전/바꾸기, 줄 이동, 시간/날짜, Bing으로 검색, 모두 선택.
- **보기**: 확대/축소(10%~500%), 자동 줄 바꿈, 상태 표시줄(줄·열, 글자 수, 문서 종류, 배율, 줄 끝, 인코딩).
- **인쇄**: 페이지 설정에 머리글·바닥글·여백 항목 추가, 머리글/바닥글 코드(`&f` `&p` `&d` `&t` `&l` `&c` `&r` `&&`).
- **Markdown 서식 보기**: 제목 6단계, 굵게/기울임/취소선, 인라인 코드, 링크(열기 전 확인), 글머리·번호·작업 목록과 중첩, 표 삽입과 행·열 추가/삭제, 이미지, 서식 지우기, 서식/구문 보기 전환. `.txt`에 서식을 넣고 저장하면 Markdown으로 저장할지 묻는다.
- **설정**: 테마(시스템/밝게/어둡게), 글꼴, 자동 줄 바꿈, 서식 켬/끔, 파일 여는 방식(새 탭/새 창), 시작 방식, 최근 파일, 맞춤법 검사, 자동 수정.

### 4.4 설계 결정

- **`NSDocument` 기반**: 열기/저장 패널, 변경 표시, 닫을 때 저장 확인, 실행 취소 연동을 얻는다.
- **세션은 직접 구현**: macOS의 자동 저장은 저장된 파일에 변경을 바로 써 버려 메모장의 동작(파일은 그대로, 변경만 따로 보관)과 다르다.
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

## 5. 작업할 내역

우선순위 순.

1. **맥에서 실제 실행 점검**: Actions 아티팩트를 내려받거나 직접 빌드해 6.1절의 항목을 하나씩 본다. 지금 가장 큰 미지수다.
2. **점검에서 나온 문제 수정**.
3. **원본과 대조**: Windows에서 스토어 메모장을 실행해 단축키와 메뉴 순서를 맞춘다(부록 A.6 참고).
4. **빠진 기능 중 옮길 수 있는 것 추가**: 7절 참고.
5. **앱 아이콘**: 원본 아이콘은 Microsoft 저작물이라 쓰지 않았다. 새로 만들어야 한다.

CI가 실패하면 오류 줄이 최대 80줄까지 주석(annotation)으로 나온다.

### CI 결과 보는 법

저장소가 공개라 로그인 없이 실행 상태와 주석은 읽을 수 있다. 전체 로그는 로그인이 필요하다.

```sh
sh scripts/ci-wait.sh      # 현재 커밋의 실행이 끝날 때까지 기다렸다가 결과와 오류 줄을 출력
gh auth login              # 전체 로그가 필요하면 (gh run view --log-failed)
```

### 맥에서 직접 빌드

```sh
git clone git@github.com:dmnkx/notepad-mac.git && cd notepad-mac
swift test
sh scripts/bundle.sh       # build/Notepad.app 생성
```

## 6. 수정해야 할 내역

### 6.1 확인이 필요한 동작 (컴파일은 되지만 실행해 본 적이 없어 틀렸을 수 있음)

- **문서 형식 등록**: `Info.plist`의 문서 형식보다 `DocumentController`의 재정의(`documentClass(forType:)`, `typeForContents(of:)`, `beginOpenPanel`)에 의존한다. 열기 패널에서 모든 파일이 선택되는지, Finder의 "다음으로 열기"에 나오는지 확인.
- **종료 흐름**: AppKit이 델리게이트보다 먼저 미저장 문서를 확인하는지 몰라 두 군데(`applicationShouldTerminate`, `reviewUnsavedDocuments`)에 같은 처리를 넣었다. 세션 유지 모드에서 묻지 않고 종료되는지, 새 세션 모드에서 저장 확인이 한 번만 뜨는지 확인.
- **세션 복원 시점**: `applicationShouldOpenUntitledFile`과 `applicationDidFinishLaunching` 어느 쪽이 먼저 불려도 되게 했다. 복원 후 빈 "제목 없음" 탭이 덤으로 뜨지 않는지 확인.
- **탭 묶임**: 새 창 명령과 "새 창에서 열기" 설정은 창을 띄우는 순간에만 `tabbingMode`를 `.disallowed`로 바꾼다. 의도대로 분리되는지 확인.
- **확대/축소와 자동 줄 바꿈**: 스크롤 뷰 배율을 바꾼 뒤 줄 바꿈 폭이 보이는 영역에 맞는지. 어긋나면 글꼴 크기 배율 방식으로 바꿔야 한다.
- **레이아웃**: 세로 `NSStackView`에서 도구 모음과 상태 표시줄이 제 높이만 차지하고 텍스트 영역이 나머지를 채우는지. 숨김/표시 전환도 확인.
- **목록**: `NSTextList`를 붙인 문단에서 Return을 누르면 다음 항목이 자동으로 생기는지, 번호가 다시 매겨지는지. 직접 넣은 마커 문자열(`\t•\t`)과 AppKit이 만드는 마커가 일치하는지.
- **표**: 빈 칸에 입력이 되는지, 행·열 추가/삭제 뒤 커서 위치, 실행 취소.
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
| `Formatting.swift` | 이미지를 원래 위치 그대로 참조한다 (원본은 `이름_Images` 폴더로 복사) | 문서를 옮겨 다녀야 하면 |

### 6.3 원본과 다른 동작

- **찾기**: macOS 기본 찾기 막대를 쓴다. 모양과 옵션 이름이 다르고, "맨 위에서 다음 찾음" 같은 상태 메시지가 없다.
- **바꾸기 단축키**: `⌘⌥F` (원본 Ctrl+H, 맥에서 `⌘H`는 가리기).
- **맞춤법 검사**: 전체 켬/끔만 있다. 원본은 파일 종류별로 켜고 끈다. 대신 `.txt .md .markdown .srt .lrc .lic` 파일에서만 켜지게 했다.
- **Markdown 저장**: 서식 보기에서 편집하면 블록 사이에 빈 줄을 넣고 목록 들여쓰기를 4칸으로 맞춘다. 원본 소스의 줄바꿈 모양이 바뀔 수 있다.
- **인용문, 수평선, 코드 블록**: 서식으로 그리지 않고 원문 그대로 보여 준다.
- **외부 변경 감지**: 저장할 때만 알린다. 원본은 다시 열지 묻는 창을 바로 띄운다.
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
| 탭 끌어서 순서 바꾸기/창 분리 | macOS 탭 기능이 대신한다 |
| 신뢰할 수 없는 파일·이미지 경고 | 미구현. 링크 열기 확인만 있다 |
| 앱 아이콘 | 원본은 저작물이라 제외 |
| `/p` 인쇄 명령줄, `ms-notepad:` 주소 | Windows 셸 전용 |

## 8. 주의할 점

- **저장소가 공개다.** 소스의 `L10n.swift`에는 원본 메모장의 한국어 UI 문구가 들어 있다. 비공개로 바꿀지 판단이 필요하다.
- **서명**: 임시(ad-hoc) 서명이라 내려받은 앱은 처음 열 때 우클릭 → 열기를 하거나 `xattr -dr com.apple.quarantine Notepad.app`을 실행해야 한다.
- **단축키와 일부 동작은 원본에서 확인한 값이 아니다.** 4.2절 참고. Windows에서 원본을 실행해 대조하면 정확해진다.

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
