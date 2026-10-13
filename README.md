# EasyPad

Windows 11 메모장을 macOS용으로 다시 만든 앱입니다. macOS 13 이상, Apple Silicon과 Intel 모두 지원합니다.

## 설치

```sh
brew install dmnkx/easypad/easypad
```

업데이트는 `brew upgrade easypad`, 삭제는 `brew uninstall easypad`입니다.

Homebrew 없이 쓰려면 [Releases](https://github.com/dmnkx/homebrew-easypad/releases)에서 `EasyPad.zip`을 받아 `/Applications`에 넣습니다. 공증받지 않은 앱이라 처음 열 때 macOS가 막으면 터미널에서 `xattr -dr com.apple.quarantine /Applications/EasyPad.app`을 실행합니다.

## 주요 기능

- 제목 표시줄 안의 탭, 종료해도 유지되는 세션(저장하지 않은 글 포함)
- Markdown 서식 보기: 제목, 목록, 표, 링크, 이미지
- 인코딩(ANSI, UTF-8, UTF-16)과 줄 끝(CRLF, LF, CR) 유지
- 한국어와 영어 UI

## 직접 빌드

```sh
swift test
sh scripts/bundle.sh       # build/EasyPad.app
sh scripts/release.sh 1.2  # 버전 올리고 릴리스까지
```

작업 기록과 설계 결정은 [PROCESS.md](PROCESS.md)에 있습니다.
