# Argo 통합 가이드 (제미나이 작업 지시서)

이 문서는 `sojubada/AirDrop_tvOS`의 AirDrop 활성화 코드를
`sojubada/argo`(Spartan 기반 tvOS 파일 브라우저, 앱 이름 **Argo**)에
통합하기 위한 작업 지시서입니다. 코드 작성자(제미나이)가 이 문서만 읽고
작업할 수 있도록 필요한 맥락과 API 서명을 모두 담았습니다.

---

## 0. 선행 조건 — 이것이 확인되기 전에는 착수하지 말 것

AirDrop_tvOS 저장소의 검증 앱(AirDropTV)을 실제 애플TV에서 실행해
**아래 3가지가 모두 확인된 뒤에** 이 통합을 시작합니다.

| 확인 항목 | 통과 기준 |
|---|---|
| 클래스 생존 | `SFAirDropDiscoveryController`, `SFAirDropReceiverViewController`, `SFAirDropSharingViewControllerTV` 3개가 모두 존재 |
| 권한 적용 | `setDiscoverableMode:` 호출 후 `discoverableMode`가 `2`(Everyone)로 유지 |
| 수신 성공 | 아이폰에서 보낸 파일이 `/var/mobile/Downloads/com.apple.AirDrop/<UUID>/Files/` 에 생성 |

**검증 결과에 따라 작업 범위가 달라집니다.**

- 3개 모두 통과 → 이 문서 전체를 수행
- 수신만 실패 → **5장(수신)을 건너뛰고** 4장(송신)과 6장(설정 토글)만 수행
- 클래스 이름이 다름 → 검증 앱이 화면에 출력한 실제 클래스명으로 2장의 선언부를 교체한 뒤 수행

---

## 1. 대상 저장소 구조와 기술 환경

- 저장소: `sojubada/argo`
- 번들 ID: `com.sojubada.argo`
- 원본: `WhitetailAni/Spartan` (tvOS 파일 브라우저, SwiftUI)
- 대상 기기: Apple TV 4K, **tvOS 16.6**
- 배포: TrollStore로 미서명 `.tipa` 설치 (탈옥 아님)
- 빌드: 로컬 Xcode 없음. GitHub Actions에서 XcodeGen + xcodebuild

Spartan의 기존 디렉터리 구성(참고):

```
External/            외부 의존성
RootHelper/          루트 헬퍼
SpartanRootHelper/   루트 헬퍼 번들
Spartan/             앱 본체 (SwiftUI)
SwiftTryCatch.h/.m   Obj-C 예외를 Swift에서 잡기 위한 브리지
spawn.h              프로세스 실행용 헤더
```

**중요**: Spartan은 이미 Objective-C 파일과 브리징 헤더를 쓰고 있습니다.
따라서 AirDrop 코드를 Objective-C로 추가하는 것이 가장 자연스럽습니다.
비공개 API를 Swift에서 `NSClassFromString` + `perform(_:)`으로 다루면
가변 인자·블록 전달에서 문제가 생기므로 **Obj-C로 작성하십시오.**

---

## 2. 사용할 비공개 API (검증된 서명)

`/System/Library/PrivateFrameworks/Sharing.framework` 에 있습니다.
아래 선언을 그대로 쓰십시오. 추측하거나 변형하지 마십시오.

```objc
typedef NS_ENUM(long long, SDAirDropDiscoverableMode) {
    SDAirDropDiscoverableModeOff          = 0,
    SDAirDropDiscoverableModeContactsOnly = 1,
    SDAirDropDiscoverableModeEveryone     = 2,
};

@interface SFAirDropDiscoveryController : UIViewController
- (void)setDiscoverableMode:(long long)mode;
- (long long)discoverableMode;
- (id)discoverableModeToString:(long long)mode;
@end

@interface SFAirDropReceiverViewController : UIViewController
- (void)startAdvertising;
- (void)stopAdvertising;
@end

@interface SFAirDropSharingViewControllerTV : UIViewController
- (instancetype)initWithSharingItems:(NSArray *)items;
- (void)setCompletionHandler:(void (^)(NSError *error))handler;
@end
```

프레임워크는 지연 로드가 필요합니다.

```objc
[[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/Sharing.framework"] load];
```

### 반드시 지킬 안전 규칙

1. **모든 클래스는 `NSClassFromString`으로 존재를 확인한 뒤 사용합니다.**
   nil 클래스에 `alloc`을 보내면 조용히 nil이 되거나 크래시합니다.
   클래스가 없으면 **AirDrop 관련 UI 자체를 숨기십시오.** 오류 팝업을
   띄우지 말고, 기능이 없는 것처럼 동작해야 합니다.
2. 비공개 API 호출은 `@try/@catch`로 감쌉니다. Spartan의 `SwiftTryCatch`를
   재사용하거나 Obj-C 쪽에서 직접 감싸면 됩니다.
3. tvOS 16.6 외의 버전은 고려하지 않습니다. 버전 분기를 만들지 마십시오.

---

## 3. 추가할 파일 — `AirDropBridge`

Swift(SwiftUI) 쪽에서 쓸 수 있는 **최소한의 깨끗한 API**만 노출합니다.
비공개 API의 복잡함은 이 파일 안에 가둡니다.

**`Spartan/AirDrop/AirDropBridge.h`**

```objc
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AirDropBridge : NSObject

/// 이 기기에서 AirDrop을 쓸 수 있는지. NO 면 관련 UI를 전부 숨길 것.
@property (class, nonatomic, readonly) BOOL isAvailable;

/// 현재 discoverable 모드 (0=Off, 1=ContactsOnly, 2=Everyone)
@property (class, nonatomic, readonly) long long currentMode;

/// 수신 광고를 켭니다. 성공하면 YES.
+ (BOOL)enableReceiving;

/// 수신 광고를 끕니다.
+ (void)disableReceiving;

/// 파일을 다른 기기로 보내는 공유 화면을 띄웁니다.
+ (void)presentSenderForFileAtPath:(NSString *)path
                  fromViewController:(UIViewController *)presenter
                          completion:(nullable void (^)(NSError * _Nullable))completion;

/// 수신 대기 화면 컨트롤러를 만들어 돌려줍니다. 사용할 수 없으면 nil.
+ (nullable UIViewController *)makeReceiverViewController;

/// AirDrop 수신 파일이 쌓이는 경로
@property (class, nonatomic, readonly) NSString *inboxPath;

@end

NS_ASSUME_NONNULL_END
```

**`Spartan/AirDrop/AirDropBridge.m`** 구현 요점

- `isAvailable`: 프레임워크 로드 후 3개 클래스 모두 `NSClassFromString` 통과
- `SFAirDropDiscoveryController` 인스턴스는 **static 변수로 보관**합니다.
  매번 새로 만들면 모드가 유지되지 않을 수 있습니다.
- `enableReceiving`: 모드를 Everyone으로 설정한 뒤 **다시 읽어서 2인지 확인**해
  그 결과를 반환합니다. 설정만 하고 성공으로 간주하지 마십시오.
- `inboxPath`: `/var/mobile/Downloads/com.apple.AirDrop`
- `makeReceiverViewController`: `SFAirDropReceiverViewController`를 만들고,
  **표시된 뒤에** `startAdvertising`을 호출해야 합니다. 생성 직후 호출하면
  효과가 없을 수 있으므로, 호출 책임은 5장의 SwiftUI 래퍼에 둡니다.

브리징 헤더(Spartan의 기존 `*-Bridging-Header.h`)에 `AirDropBridge.h`를
추가해 Swift에서 보이게 하십시오. 기존 브리징 헤더 내용을 지우지 말고
한 줄만 추가합니다.

---

## 4. 송신 — 기존 파일 메뉴에 항목 추가

Spartan에는 파일을 길게 눌렀을 때 나오는 메뉴(정보 보기, 이름 변경, 이동,
복사, 휴지통 등)가 이미 있습니다. **그 메뉴에 한 항목을 추가**합니다.

- 항목 이름: `AirDrop으로 보내기`
- 표시 조건: `AirDropBridge.isAvailable == true` **그리고** 대상이 디렉터리가 아닐 때
- 동작: `presentSenderForFileAtPath:fromViewController:completion:` 호출

SwiftUI에서 `UIViewController`를 present해야 하므로, 현재 화면의
`UIViewController`를 얻는 헬퍼가 필요합니다. Spartan에 이미 그런 헬퍼가
있으면 재사용하고, 없으면 `UIApplication.shared.connectedScenes`에서
keyWindow의 `rootViewController`를 찾아 쓰십시오.

**디렉터리 송신은 구현하지 마십시오.** 폴더 AirDrop은 tvOS에서 동작이
불확실하고, 필요하면 사용자가 Spartan의 zip 압축 기능으로 묶은 뒤 보내면
됩니다.

---

## 5. 수신 — 전용 화면 추가

### 5-1. 수신 화면

`SFAirDropReceiverViewController`를 `UIViewControllerRepresentable`로 감싸
SwiftUI 화면으로 만듭니다.

```swift
struct AirDropReceiveView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        AirDropBridge.makeReceiverViewController() ?? UIViewController()
    }
    func updateUIViewController(_ vc: UIViewController, context: Context) {}
}
```

표시된 직후 `startAdvertising`을 호출해야 합니다.
`makeUIViewController` 안이 아니라 `onAppear` 시점에 호출하도록
브리지에 `+ (void)startAdvertisingOn:(UIViewController *)vc` 같은 메서드를
하나 더 두는 방식이 안전합니다.

### 5-2. 받은 파일 보여주기

수신 화면이 떠 있는 동안 `AirDropBridge.inboxPath`를 **2초 간격으로
폴링**해 새 파일을 목록에 표시합니다. 파일시스템 알림(FSEvents, DispatchSource)
대신 폴링을 쓰는 이유는, 샌드박스 환경에서 알림이 오지 않는 경우가 있어
단순한 폴링이 더 확실하기 때문입니다.

- 실제 파일은 `<inboxPath>/<UUID>/Files/` 아래에 있습니다.
  UUID 디렉터리를 한 단계 더 들어가야 합니다.
- 새 파일이 보이면 목록에 추가하고, 탭하면 Spartan의 기존 파일 상세 화면을
  재사용해 엽니다. 새 뷰어를 만들지 마십시오.

### 5-3. 즐겨찾기 등록

Spartan에는 즐겨찾기 기능이 이미 있습니다. 첫 실행 시
`/var/mobile/Downloads/com.apple.AirDrop` 를 **`AirDrop 수신함`이라는
이름으로 즐겨찾기에 자동 추가**하십시오. 이것만으로도 수신 파일 접근이
대부분 해결됩니다. 이미 등록돼 있으면 중복 추가하지 마십시오.

---

## 6. 설정 토글

Argo 설정 화면에 섹션 하나를 추가합니다.

- `AirDrop 수신` 토글 — 켜면 `enableReceiving`, 끄면 `disableReceiving`
- 토글 아래에 현재 상태를 **읽어서** 표시: `currentMode`를 그대로 보여줍니다
- `AirDropBridge.isAvailable == false` 면 이 섹션 전체를 숨깁니다

### 반드시 처리할 것 — 모드가 유지되지 않는 문제

`setDiscoverableMode:`는 디스크 설정을 바꾸는 것이 아니라 실행 중인
`sharingd` 데몬의 상태를 바꿉니다. 따라서

- **재부팅하면 Off로 돌아갑니다.**
- 앱이 백그라운드로 갔다 오면 꺼져 있을 수 있습니다.
- iOS 16.2부터 Everyone 모드가 일정 시간 후 자동으로 꺼지는 제한이
  생겼습니다. tvOS 16.6에도 같은 제한이 있을 가능성이 있습니다.

그래서 UI는 **저장된 토글 값을 믿지 말고 항상 실제 모드를 읽어** 표시해야
합니다. 그리고 앱이 포그라운드로 돌아올 때(`scenePhase == .active`)
토글이 켜져 있으면 `enableReceiving`을 **다시 호출**하십시오.

---

## 7. 권한 파일 병합

Argo의 기존 `entitlements.plist`에 **아래 두 키를 추가**합니다.
기존 키(루트 헬퍼·파일시스템 접근용)를 **지우거나 바꾸지 마십시오.**

```xml
<key>com.apple.private.airdrop.discovery</key>
<true/>
<key>com.apple.private.airdrop.settings</key>
<true/>
```

### 알아둘 위험

TrollStore 문서에 따르면 `platform-application` 권한은 샌드박스의 일부가
오히려 더 조여지는 부작용이 있고, 그것을 풀려면 추가 비공개 권한이
필요합니다. Argo는 파일시스템 접근을 위해 `no-sandbox` 계열 권한을 쓰고
있을 가능성이 높습니다.

따라서 **단독 앱에서 되던 AirDrop이 Argo에서는 안 될 수 있습니다.**
통합 후 AirDrop이 동작하지 않으면 가장 먼저 이 조합을 의심하십시오.
이때 권한을 추측으로 더 넣지 말고, 어떤 권한 조합에서 실패하는지
기록해 보고하십시오.

---

## 8. IPA 설치 연계 (선택 — 검증 필요)

Argo의 목표 중 하나가 "IPA를 골라 애플TV에 설치"입니다.
AirDrop으로 받은 IPA를 그 자리에서 설치하면 흐름이 완결됩니다.

TrollStore는 URL 스킴으로 설치를 받습니다.

```
apple-magnifier://install?url=<IPA_의_URL>
```

문제는 이것이 **http(s) URL을 기대**한다는 점입니다. 로컬 파일 경로를
그대로 넘기는 것은 동작이 확인되지 않았습니다. 우회 방법은 Argo 안에
작은 로컬 HTTP 서버를 띄워 해당 IPA만 서빙하고,
`http://127.0.0.1:<포트>/파일.ipa` 를 넘기는 것입니다.

**이 방식은 아직 검증되지 않았습니다.** WebDAV 작업으로 HTTP 코드가
이미 들어온 뒤에 시도하는 것이 효율적이므로, **8장은 5·6장이 끝난 뒤
별도 작업으로 미루십시오.** 지금 구현하지 마십시오.

---

## 9. 하지 말아야 할 것

- 검증용 버튼(프레임워크 로드, 클래스 존재 확인)을 Argo UI에 넣지 마십시오.
  내부 가드로만 씁니다.
- `sharingd`나 `PineBoard`를 후킹하려 하지 마십시오. 탈옥 환경이 아니므로
  불가능합니다.
- Spartan의 기존 파일 조작·루트 헬퍼 코드를 수정하지 마십시오.
  AirDrop 기능은 **추가만** 합니다.
- GitHub Actions 워크플로를 임의로 수정하지 마십시오.
  (참고: AirDrop_tvOS에서 XcodeGen이 Xcode 16.3 포맷으로 프로젝트를 만들어
  러너의 Xcode 15가 열지 못하는 문제가 있었습니다. Argo에서 같은 증상이
  나면 `project.yml`의 `options`에 `projectFormat: xcode15_0`을 넣으면
  됩니다. 그 외에는 손대지 마십시오.)
- 새 서드파티 의존성을 추가하지 마십시오. 전부 시스템 프레임워크로 됩니다.

---

## 10. 완료 기준

다음이 모두 충족되면 작업 완료입니다.

1. AirDrop을 쓸 수 없는 기기에서 Argo가 **아무 변화 없이** 정상 동작한다
   (관련 UI가 숨겨지고 크래시하지 않는다)
2. 설정에서 수신을 켜면 아이폰 공유 시트에 애플TV가 나타난다
3. 토글 상태가 실제 모드를 반영하고, 앱을 다시 열면 재적용된다
4. 파일 메뉴의 `AirDrop으로 보내기`로 파일을 아이폰에 보낼 수 있다
5. 수신한 파일이 수신 화면 목록과 즐겨찾기 양쪽에서 보인다
6. GitHub Actions 빌드가 통과하고 `.tipa`가 릴리스에 첨부된다

## 11. 참고 자료

- 검증 앱 소스: 이 저장소의 `ViewController.m` — 비공개 API 호출 방식의
  동작하는 예제입니다. 선언부와 호출 순서를 그대로 참고하십시오.
- 권한 파일: 이 저장소의 `entitlements.plist`
- `lechium/Breezy` — tvOS AirDrop 연구 원본 (탈옥 전제이므로 수신 핸들러
  부분은 적용 불가, API 서명 참고용)
