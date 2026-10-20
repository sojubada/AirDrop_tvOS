# AirDropTV

> **검증 완료 (2026-10-20, Apple TV 4K / tvOS 16.6 / TrollStore)**
> 탈옥 없이 AirDrop **송신·수신이 모두 동작**함을 실제 기기에서 확인했습니다.
> 핵심 발견 두 가지:
> 1. `setDiscoverableMode:` 는 **비동기**입니다. 즉시 읽으면 항상 0이고
>    약 1초 뒤에 2(Everyone)가 됩니다. 즉시 읽기로 판정하면 오판합니다.
> 2. `SFAirDropDiscoveryController` 의 `view` 에 접근하면 **앱이 즉시 종료**됩니다.
>    객체만 보관하고 메서드만 호출해야 합니다.
>
> 자세한 내용과 Argo 통합 방법은
> [`docs/ARGO-INTEGRATION-GUIDE.md`](docs/ARGO-INTEGRATION-GUIDE.md) 에 있습니다.

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
| 3 | 런타임 권한·`sharingd`·샌드박스 확인 | 권한 2개가 `= 1`, sharingd 실행 중 |
| 4 | discoverable 모드를 Everyone 으로 | **1초·3초 후** 값이 2면 성공 |
| 5 | 모드 다시 읽기 | 현재 값 확인 |
| 6 | 수신 대기 화면 + startAdvertising | 이 화면을 유지한 채 전송 |
| 7 | 파일 송신 | 아이폰이 목록에 뜨는지 |
| 0 | AirDrop 끄기 | 정리용 |

4번 수행 후, 같은 Apple ID의 아이폰에서 파일을 전송하고
Spartan으로 `/var/mobile/Downloads/com.apple.AirDrop/` 을 확인하십시오.

## Argo(파일 브라우저) 통합

검증이 끝난 뒤 이 기능을 `sojubada/argo`에 통합하기 위한 작업 지시서가
[`docs/ARGO-INTEGRATION-GUIDE.md`](docs/ARGO-INTEGRATION-GUIDE.md) 에 있습니다.
코드 작성을 외부(제미나이)에 맡길 때 그 문서를 그대로 전달하면 됩니다.

## 권한

`entitlements.plist`의 두 키가 핵심입니다.

- `com.apple.private.airdrop.discovery` — 기기 탐색·송신
- `com.apple.private.airdrop.settings` — AirDrop 서버로 광고(수신)

TrollStore는 설치 시 재서명하면서 이 권한들을 보존합니다.
워크플로가 `ldid -e` 출력을 검사해 두 키가 없으면 빌드를 실패시킵니다.
