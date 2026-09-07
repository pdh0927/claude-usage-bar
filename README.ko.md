# claude-usage-bar

[English](README.md)

Claude Code 사용량 한도(현재 세션, 주간)를 작은 링 게이지로 메뉴바에 보여주는 macOS 앱. 언제 5시간 한도가 꽉 찰지 몰라서 매번 확인하러 다니는 게 귀찮아서 만들었다.

`statusline.sh`에 한 줄만 추가해두면, Claude Code가 실행될 때마다 그 스크립트가 JSON 스냅샷을 하나 남기고, 이 앱은 그 파일을 보고 있다가 바뀔 때마다 아이콘을 다시 그린다.

**Anthropic 공식 제품 아님.** 그냥 개인 사이드 프로젝트다. Anthropic과 아무 제휴 없고, "Claude"/"Claude Code"는 그쪽 이름을 그대로 쓴 것뿐 — 이 앱이 어디서 데이터를 읽어오는지 설명하려고 언급한 것.

**Claude Code Pro나 Max 구독이 있어야 뭔가 보인다.** 이 앱이 읽는 값(`rate_limits.five_hour.used_percentage`, `rate_limits.seven_day.used_percentage`)은 Pro/Max 계정에서, 그것도 세션에서 Claude Code가 첫 응답을 하고 난 뒤부터만 statusLine 훅 JSON에 들어있다. 다른 플랜이거나 아직 메시지를 안 보냈으면 "데이터 없음" 아이콘만 뜬다 — 고장난 게 아니라 원래 그런 거다. Anthropic 문서의 "Rate limit usage" 항목 참고: https://code.claude.com/docs/en/statusline.md

## 동작 원리

Claude Code는 프롬프트를 렌더링할 때마다 `~/.claude/statusline.sh`를 호출하면서 현재 사용량이 담긴 JSON을 넘겨준다(Pro/Max라면). 여기에 한 줄 추가해서 그 두 퍼센트 값을 뽑아 `~/.claude/usage-status.json`에 써넣는다 — 임시 파일에 쓰고 `mv`로 옮기는 방식이라(원자적 쓰기), 앱이 파일을 읽다가 절반만 쓰인 걸 보는 일은 없다.

앱은 그 파일을 지켜보다가 바뀌면 아이콘을 다시 그릴 뿐이다. 타이머로 계속 확인하는 게 아니라, 파일이 실제로 바뀔 때만 반응한다.

## 설치

```sh
git clone <this-repo> claude-usage-bar
cd claude-usage-bar
./setup.sh
```

이 한 줄이 `statusline.sh`/`settings.json`을 알아서 연결하고 앱을 빌드해서 `/Applications`에 넣고 실행까지 해준다. 처음 실행할 때 Gatekeeper 경고가 뜰 텐데, 아래 나오지만 클릭 두 번이면 끝난다.

단계별로 하고 싶으면 `setup.sh`는 사실 `install.sh` → `build.sh` → `ditto` 설치를 순서대로 실행하는 것뿐이다. 각각 따로 돌려도 문제없다 — 예를 들어 Swift 코드 고친 뒤 `./build.sh`만 다시 돌리면 statusline 연결을 매번 다시 안 해도 된다.

`install.sh`는 이미 있는 걸 함부로 건드리지 않는다:
- `~/.claude/statusline.sh`가 없으면 최소한의 걸 하나 만든다.
- 이미 있으면 덮어쓰지 않고 스니펫(`statusline-snippet.sh` 참고)만 추가한다 — 단, 스크립트가 훅 JSON을 일반적인 방식(`input=$(cat)`)으로 받고 있을 때만. 그게 아니면 자동으로 건드리지 않고 스니펫만 화면에 출력해준다.
- `settings.json`에 `statusLine`이 없으면 하나 추가한다. 이미 다른 게 설정돼 있으면 손대지 않고 뭘 해야 할지 알려준다.

`/Applications`에 수동으로 설치/재설치하려면(예: `./build.sh`만 따로 돌린 뒤):

```sh
pkill -f ClaudeUsage.app/Contents/MacOS/ClaudeUsage 2>/dev/null
rm -r -f /Applications/ClaudeUsage.app
ditto ClaudeUsage.app /Applications/ClaudeUsage.app   # cp -R 말고, 이유는 아래
open /Applications/ClaudeUsage.app
```

여기서 `cp -R`은 쓰지 마라 — `/Applications/ClaudeUsage.app`이 이미 있으면 그 안으로 중첩 복사가 돼서, 껍데기만 바뀐 것처럼 보이고 실제로는 업데이트가 하나도 안 된다. 직접 겪어봤다. `ditto`는 어떤 상황이든 제대로 처리한다.

### Gatekeeper 경고

앱은 로컬에서 서명은 되어있지만(애드혹, 혹은 Xcode에 무료 Apple Development 인증서가 있으면 그걸로) Apple 노터라이즈는 안 받았다. 그래서 처음 더블클릭하면 macOS가 거부한다. `/Applications`에서 앱을 우클릭 → 열기 → 열기, 한 번만 하면 된다. 그다음부턴 macOS가 기억해서 그냥 정상적으로 실행된다. 로그인 시 자동 실행도 포함해서.

## 제거

```sh
pkill -f ClaudeUsage.app/Contents/MacOS/ClaudeUsage
rm -r -f /Applications/ClaudeUsage.app
```

완전히 지우고 싶으면 `~/.claude/statusline.sh`에서 스니펫 블록(`# >>> claude-usage-bar`와 `# <<< claude-usage-bar` 사이)을 지우고, `~/.claude/usage-status.json`도 삭제하면 된다.

## 표시 방식

드롭다운에 "아이콘으로 보기"와 "숫자로 보기"(예: `54%/29%`, 맨 처음 프로토타입이 이렇게 생겼었다) 둘 중 하나를 고를 수 있다. 고른 건 저장되고 다음 실행 때도 유지된다. 기본값은 아이콘. 둘 다 같은 파일 감시에서 그려지기 때문에 전환은 바로 반영된다.

## 알림

세션 또는 주간 사용량이 25%, 50%, 70%를 넘을 때마다 데스크탑 알림이 한 번씩 뜬다. 같은 창(window) 안에서는 한 번만 울리고 창이 리셋되면 다시 울릴 수 있다. 앱을 켰을 때 이미 넘어있던 임계값은 조용히 통과시킨다 — 안 그러면 80%에서 앱을 처음 켰을 때 세 개가 한꺼번에 울릴 테니까.

## 왜 이렇게 생겼나

아이콘은 색깔 있는 이중 링이다 — 바깥쪽이 현재 5시간 세션, 안쪽이 7일 주간, 둘 다 statusline 자체 컨텍스트 바에서 쓰는 것과 같은 70%/90% 기준으로 초록/노랑/빨강이 바뀐다. 실제 메뉴바 크기(20pt, 1배/2배, 라이트/다크)로 뽑은 이미지를 직접 눈으로 확인하고 정했는데, 그 작은 크기에서도 두 링이 충분히 구분됐다.

단색 템플릿 아이콘 대신 색을 쓴 이유는 서로 다른 기준으로 판단되는 두 값을 그 작은 크기에서 흑백 톤만으로 구분하긴 어려워서다. 대신 컬러 아이콘은 다크모드 자동 틴트를 못 받는다는 단점이 있는데, 이 정도면 괜찮은 맞바꿈이라고 생각한다. 어느 쪽이든 정확한 숫자는 링만 보고 짐작하게 하지 않는다 — 툴팁이랑 드롭다운에 항상 그대로 적혀 있다. 상태 파일이 없거나 못 읽으면 빈 링 대신 물음표 아이콘이 뜬다. "데이터 없음"이 "0% 사용"처럼 보이지 않게 하려고.

기술적으로는, 타이머로 폴링하는 대신 `~/.claude`(상태 파일의 부모 디렉터리)를 감시한다. 상태 파일은 `mv`로 원자적으로 교체되는데, 그때마다 inode가 새로 생긴다 — 파일 자체를 감시했다면 쓸 때마다 감시를 다시 걸어야 했을 거다. 디렉터리의 inode는 안 바뀌니까 디렉터리를 감시하면 그럴 필요가 없다. 한 번만 등록해두면 되고 평소엔 비용이 거의 안 든다.

시스템이 절전 상태였다가 깨어날 때는 좀 다른 문제가 있었다 — 프로세스는 살아있어도 커널의 파일 감시가 죽은 채로 돌아오는 경우가 있어서, 데이터는 바뀌는데 화면만 멈춰있는 상황이 생겼다. `NSWorkspace.didWakeNotification`을 구독해서 깨어날 때마다 감시를 다시 걸고 즉시 새로고침하게 고쳤다. 거기에 더해서, 아이콘/제목을 새로 지정해도 macOS가 다시 그리는 걸 건너뛰는 경우가 있길래(특히 화면이 절전에서 돌아온 직후) `needsDisplay`를 강제로 걸어서 데이터가 바뀌면 화면도 반드시 같이 바뀌게 해뒀다.

## 보안 관련

- `statusline.sh`는 훅 JSON을 셸 명령어에 절대 끼워 넣지 않는다 — `jq`한테 데이터로만 넘긴다. 그래서 JSON 내용으로 인젝션할 여지가 없다.
- 앱은 자기 홈 디렉터리 밑의 고정된 경로 하나만 읽는다. JSON이 이상하거나 없으면 다른 경우와 똑같이 "데이터 없음" 아이콘을 보여준다 — 에러를 숨긴 게 아니라, 파일이 없는 거랑 망가진 거랑 사용자 입장에서 딱히 다르게 할 수 있는 게 없어서 의도적으로 그렇게 처리했다.
- 이 저장소 어디에도 개인 경로, 사용자명, 팀 ID 같은 건 박혀있지 않다. 코드사이닝은 로컬에 있는 인증서를 아무거나 쓰고, 없으면 애드혹으로 넘어간다(`build.sh` 참고).

## 라이선스

MIT — `LICENSE` 참고.

