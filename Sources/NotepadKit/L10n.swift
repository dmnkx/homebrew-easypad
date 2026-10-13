import Foundation

let isKorean = Bundle.main.preferredLocalizations.first?.hasPrefix("ko") ?? false

/// English text is the key; Korean comes from the table below.
func L(_ english: String) -> String { isKorean ? korean[english] ?? english : english }

private let korean: [String: String] = [
    // menus
    "File": "파일", "Edit": "편집", "View": "보기", "Format": "서식", "Window": "윈도우",
    "About Notepad": "메모장 정보", "Settings...": "설정...", "Hide Notepad": "메모장 가리기", "Hide Others": "기타 가리기",
    "Show All": "모두 보기", "Quit Notepad": "메모장 종료",
    "New tab": "새 탭", "New Markdown tab": "새 Markdown 탭", "New window": "새 창", "Open...": "열기...", "Recent": "최근",
    "No recent files": "최근 파일 없음", "Clear list": "목록 지우기", "Save": "저장", "Save as...": "다른 이름으로 저장...",
    "Save all": "모두 저장", "Page setup...": "페이지 설정...", "Print...": "인쇄...", "Close tab": "탭 닫기", "Close window": "창 닫기",
    "Undo": "실행 취소", "Redo": "다시 실행", "Cut": "잘라내기", "Copy": "복사", "Paste": "붙여넣기", "Delete": "삭제",
    "Search with Bing": "Bing으로 검색", "Find": "찾기", "Find next": "다음 찾기", "Find previous": "이전 찾기", "Replace": "바꾸기",
    "Go to": "이동", "Select all": "모두 선택", "Time/Date": "시간/날짜", "Font...": "글꼴...",
    "Zoom": "확대/축소", "Zoom in": "확대", "Zoom out": "축소", "Restore default zoom": "기본 확대/축소 복원",
    "Status bar": "상태 표시줄", "Word wrap": "자동 줄 바꿈", "Markdown": "Markdown", "Formatted": "포맷", "Syntax": "구문",
    "Bold": "굵게", "Italic": "기울임꼴", "Strikethrough": "취소선", "Link": "링크", "Remove link": "링크 제거",
    "Clear formatting": "서식 지우기", "Headings": "제목", "Lists": "목록", "Table": "테이블", "Image": "이미지",
    "Title": "제목", "Subtitle": "부제", "Heading": "머리글", "Subheading": "부제목", "Section": "섹션", "Subsection": "하위 섹션", "Body": "본문",
    "Bulleted list": "글머리 기호 목록", "Numbered list": "번호 매기기 목록", "Task list": "작업 목록", "Check list": "체크리스트",
    "Insert table": "표 삽입", "Row above": "위에 행 삽입", "Row below": "아래에 행 삽입", "Column left": "왼쪽에 열 삽입",
    "Column right": "오른쪽에 열 삽입", "Delete row": "행 삭제", "Delete column": "열 삭제", "Delete table": "표 삭제",
    "Insert from this device": "이 장치에서 삽입", "Insert via link": "링크를 통해 삽입",
    "Minimize": "최소화", "Close other tabs": "다른 탭 닫기", "Close tabs to the right": "탭을 오른쪽으로 닫기",
    // dialogs
    "OK": "확인", "Cancel": "취소", "Insert": "삽입", "Notepad": "메모장",
    "Go to line": "줄로 이동", "Line number": "줄 번호", "The line number is beyond the total number of lines": "줄 번호가 전체 줄 수를 넘습니다.",
    "Display text": "텍스트 표시", "Address": "주소", "Insert image": "이미지 삽입",
    "Number of rows": "행 개수", "Number of columns": "열 개수",
    "This link might be unsafe": "이 링크는 안전하지 않을 수 있음", "Open link": "링크 열기",
    "You're about to open a link that hasn't been verified.\nOpening this link will take you outside of Notepad.\n\nOnly continue if you're sure this link is safe.":
        "확인되지 않은 링크를 열려고 합니다.\n이 링크를 열면 메모장 외부로 이동합니다.\n\n이 링크가 안전한 경우에만 계속하세요.",
    "Save as Markdown to keep formatting": "서식을 유지하려면 Markdown으로 저장",
    "This is a text file. To keep the current formatting, like bolding and headings, save it as a Markdown file (.md).":
        "텍스트 파일입니다. 굵게 및 제목 등의 현재 서식을 유지하려면 Markdown 파일(.md)로 저장합니다.",
    "Save as Markdown file": "Markdown 파일로 저장", "Save as text file": "텍스트 파일로 저장",
    "This file contains characters in Unicode format which will be lost if you save this file as an ANSI encoded text file. To keep the Unicode information, click Cancel below and then select one of the Unicode options from the Encoding drop down list. Continue?":
        "이 파일에는 ANSI로 인코딩된 문서로 저장하는 경우 손실될 유니코드 포맷 문자가 포함되어 있습니다. 유니코드 정보를 보존하려면 [취소]를 클릭한 다음 인코딩 드롭다운 목록에서 유니코드 옵션 중 하나를 선택하십시오. 계속하시겠습니까?",
    "Encoding:": "인코딩:", "Text documents (*.txt)": "텍스트 문서(*.txt)", "Markdown file (*.md)": "Markdown 파일(*.md)", "All files": "모든 파일",
    "UTF-8 with BOM": "UTF-8(BOM)",
    "Header:": "머리글:", "Footer:": "바닥글:", "Left:": "왼쪽:", "Right:": "오른쪽:", "Top:": "위쪽:", "Bottom:": "아래쪽:", "Page &p": "&p 페이지",
    // status bar
    " Ln %d, Col %d": " 줄 %d, 열 %d", "%d characters": "%d자", "%d of %d characters": "%d/%d자",
    "Plain text": "일반 텍스트", "Markdown syntax": "Markdown 구문",
    // settings
    "Settings": "설정", "App theme": "앱 테마", "Use system setting": "시스템 설정 사용", "Light": "밝게", "Dark": "어둡게", "Font": "글꼴",
    "Fit text within window by default": "기본적으로 창 안에 텍스트 맞춤", "Formatting": "서식", "Opening files": "파일 열기",
    "Open in a new tab": "새 탭에서 열기", "Open in a new window": "새 창에서 열기", "When Notepad starts": "메모장 시작 시",
    "Continue previous session": "이전 세션 계속하기",
    "Start new session and discard unsaved changes": "새 세션을 시작하고 저장되지 않은 변경 내용 버리기",
    "Recent Files": "최근에 사용한 파일", "Spelling": "맞춤법", "Spell check": "맞춤법 검사", "Autocorrect": "자동 수정",
]
