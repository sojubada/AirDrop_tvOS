# AirDropTV

tvOS 16.6 애플TV에서 AirDrop을 활성화할 수 있는지 검증하는 최소 앱입니다.
맥에 Xcode 없이 **GitHub Actions**에서 빌드하고, TrollStore로 설치합니다.

## 빌드 (Xcode 불필요)

GitHub 러너의 macOS 이미지에 Xcode가 들어있고, XcodeGen이 `project.yml`로
`.xcodeproj`를 생성하므로 로컬에는 아무것도 설치하지 않아도 됩니다.

### 릴리스로 받기 (권장)

```bash
git tag v1.0
git push origin v1.0
```

Actions가 끝나면 Releases 페이지에 `AirDropTV.tipa`가 첨부됩니다.
다운로드 URL은 다음 형태이며 TrollStore에 그대로 넣으면 됩니다.

```
https://github.com/sojubada/AirDrop_tvOS/releases/download/v1.0/AirDropTV.tipa
```

### 수동 실행 (터미널 없이)

Actions 탭 → Build AirDropTV → Run workflow.
`build-<번호>` 이름의 릴리스가 생기고 `.tipa`가 첨부됩니다.
태그를 밀 필요가 없으므로 브라우저만으로 처리됩니다.

## 설치

1. 애플TV에서 TrollStore 실행
2. 우측 상단 링크 버튼 → 위 릴리스 URL 입력 → Install
3. 홈 화면의 AirDropTV 실행

## 사용

화면 왼쪽 버튼을 1번부터 순서대로 누릅니다. 결과는 오른쪽 로그창에 표시됩니다.

| 버튼 | 하는 일 | 판정 |
|---|---|---|
| 1 | Sharing / SharingUI.framework 로드 | 경로·로드 성공 여부 |
| 2 | AirDrop 클래스 3종 존재 확인 | ✗ 면 런타임에서 후보 이름을 나열 |
| 3 | discoverable 모드를 Everyone 으로 | `모드 = 2` 면 권한 적용 성공 |
| 4 | 수신 대기 화면 + startAdvertising | 이 화면을 유지한 채 전송 |
| 5 | 테스트 파일 송신 | 아이폰이 목록에 뜨는지 |
| 0 | AirDrop 끄기 | 정리용 |

4번 수행 후, 같은 Apple ID의 아이폰에서 파일을 전송하고
Spartan으로 `/var/mobile/Downloads/com.apple.AirDrop/` 을 확인하십시오.

## 권한

`entitlements.plist`의 두 키가 핵심입니다.

- `com.apple.private.airdrop.discovery` — 기기 탐색·송신
- `com.apple.private.airdrop.settings` — AirDrop 서버로 광고(수신)

TrollStore는 설치 시 재서명하면서 이 권한들을 보존합니다.
워크플로가 `ldid -e` 출력을 검사해 두 키가 없으면 빌드를 실패시킵니다.
