//
//  ViewController.m
//  AirDropTV — tvOS AirDrop 활성화 검증용 앱 (v3)
//
//  v1 결과(tvOS 16.6): 프레임워크 로드 ✓, 클래스 3종 ✓,
//                      모드 설정 즉시 재확인 시 0 유지, Documents 쓰기 불가
//  v2 변경: 런타임 권한 확인 추가, 모드 설정을 지연 재확인 및 뷰 계층
//           부착 방식으로 재시도, 송신 테스트를 쓰기 없이 수행
//

#import "ViewController.h"
#import <objc/runtime.h>
#import <dlfcn.h>
#include <sys/sysctl.h>

// 런타임에 자기 자신의 권한을 읽습니다. Security.framework 의 비공개 심벌이라
// 링크하지 않고 dlsym 으로 찾습니다. 없으면 그 단계만 건너뜁니다.
// SecTaskRef 는 공개 헤더에 없으므로 CFTypeRef 로 다룹니다.
typedef CFTypeRef (*CreateTaskFromSelfFn)(CFAllocatorRef);
typedef CFTypeRef (*CopyEntitlementFn)(CFTypeRef, CFStringRef, CFErrorRef *);

#pragma mark - 비공개 클래스 선언 (Sharing / SharingUI.framework)

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

#pragma mark -

@interface ViewController ()
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) SFAirDropDiscoveryController *discovery;
@end

@implementation ViewController

#pragma mark - 화면 구성

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    NSArray *titles = @[ @"1. 프레임워크 로드",
                         @"2. 클래스 존재 확인",
                         @"3. 권한 확인 (런타임)",
                         @"4. AirDrop 켜기",
                         @"5. 모드 다시 읽기",
                         @"6. 수신 대기 화면",
                         @"7. 보내기 테스트",
                         @"0. AirDrop 끄기" ];
    NSArray *sels = @[ @"doLoadFrameworks", @"doProbeClasses", @"doCheckEntitlements",
                       @"doEnableAirDrop", @"doReadMode", @"doStartReceiving",
                       @"doSendTest", @"doDisableAirDrop" ];

    UIStackView *buttons = [[UIStackView alloc] init];
    buttons.axis = UILayoutConstraintAxisVertical;
    buttons.spacing = 8;
    buttons.translatesAutoresizingMaskIntoConstraints = NO;

    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:titles[i] forState:UIControlStateNormal];
        [b addTarget:self
              action:NSSelectorFromString(sels[i])
    forControlEvents:UIControlEventPrimaryActionTriggered];
        [buttons addArrangedSubview:b];
    }

    self.logView = [[UITextView alloc] init];
    self.logView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
    self.logView.textColor = [UIColor greenColor];
    self.logView.font = [UIFont fontWithName:@"Menlo" size:22];
    // tvOS 의 UITextView 에는 editable 속성이 없습니다 (항상 읽기 전용).
    self.logView.userInteractionEnabled = NO;
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview:buttons];
    [self.view addSubview:self.logView];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [buttons.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:40],
        [buttons.topAnchor constraintEqualToAnchor:g.topAnchor constant:30],
        [buttons.widthAnchor constraintEqualToConstant:480],

        [self.logView.leadingAnchor constraintEqualToAnchor:buttons.trailingAnchor constant:30],
        [self.logView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-40],
        [self.logView.topAnchor constraintEqualToAnchor:g.topAnchor constant:30],
        [self.logView.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-30],
    ]];

    [self log:@"v3. 1번부터 순서대로 실행하십시오."];
}

- (void)log:(NSString *)fmt, ... {
    va_list args;
    va_start(args, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSLog(@"[AirDropTV] %@", s);
    dispatch_async(dispatch_get_main_queue(), ^{
        self.logView.text = [self.logView.text stringByAppendingFormat:@"\n%@", s];
        if (self.logView.text.length > 0) {
            NSRange end = NSMakeRange(self.logView.text.length - 1, 1);
            [self.logView scrollRangeToVisible:end];
        }
    });
}

- (NSString *)modeName:(long long)m {
    switch (m) {
        case 0: return @"Off";
        case 1: return @"ContactsOnly";
        case 2: return @"Everyone";
        default: return @"알 수 없음";
    }
}

#pragma mark - 1. 프레임워크 로드

- (void)doLoadFrameworks {
    [self log:@"\n--- 1. 프레임워크 로드 ---"];
    for (NSString *name in @[ @"Sharing", @"SharingUI" ]) {
        NSString *path = [NSString stringWithFormat:
                          @"/System/Library/PrivateFrameworks/%@.framework", name];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [self log:@"✗ %@.framework 경로 없음", name];
            continue;
        }
        BOOL loaded = [[NSBundle bundleWithPath:path] load];
        [self log:@"%@ %@.framework %@", loaded ? @"✓" : @"✗", name,
                  loaded ? @"로드 성공" : @"로드 실패"];
    }
}

#pragma mark - 2. 클래스 존재 확인

- (void)doProbeClasses {
    [self log:@"\n--- 2. 클래스 존재 확인 ---"];
    for (NSString *n in @[ @"SFAirDropDiscoveryController",
                           @"SFAirDropReceiverViewController",
                           @"SFAirDropSharingViewControllerTV" ]) {
        [self log:@"%@ %@", NSClassFromString(n) ? @"✓" : @"✗", n];
    }
}

#pragma mark - 3. 런타임 권한 확인 (핵심 진단)

// 설치된 바이너리에 권한이 실제로 살아있는지 확인합니다.
// 여기서 ✗ 가 나오면 TrollStore 설치 과정에서 권한이 보존되지 않은 것이고,
// ✓ 인데도 모드가 안 바뀌면 권한 문제가 아니라 API 동작 문제입니다.
- (void)doCheckEntitlements {
    [self log:@"\n--- 3. 권한 확인 (런타임) ---"];
    CreateTaskFromSelfFn createTask =
        (CreateTaskFromSelfFn)dlsym(RTLD_DEFAULT, "SecTaskCreateFromSelf");
    CopyEntitlementFn copyEnt =
        (CopyEntitlementFn)dlsym(RTLD_DEFAULT, "SecTaskCopyValueForEntitlement");
    if (!createTask || !copyEnt) {
        [self log:@"✗ SecTask 심벌을 찾지 못함 — 권한 확인 건너뜀"];
        [self log:@"   (이 단계만 실패한 것이며 4번은 그대로 진행하십시오)"];
    } else {

    CFTypeRef task = createTask(NULL);
    if (!task) {
        [self log:@"✗ SecTaskCreateFromSelf 실패"];
    } else {
    NSArray *keys = @[ @"com.apple.private.airdrop.discovery",
                       @"com.apple.private.airdrop.settings",
                       @"com.apple.private.security.no-sandbox",
                       @"platform-application",
                       @"application-identifier" ];
    for (NSString *k in keys) {
        CFErrorRef err = NULL;
        CFTypeRef v = copyEnt(task, (__bridge CFStringRef)k, &err);
        if (v) {
            [self log:@"✓ %@ = %@", k, (__bridge id)v];
            CFRelease(v);
        } else {
            [self log:@"✗ %@ (없음)", k];
        }
        if (err) CFRelease(err);
    }
    CFRelease(task);
    }
    }

    [self checkSharingDaemon];

    [self log:@"샌드박스 쓰기 가능 여부:"];
    [self probeWritable:NSTemporaryDirectory() label:@"tmp"];
    [self probeWritable:NSSearchPathForDirectoriesInDomains(
        NSCachesDirectory, NSUserDomainMask, YES).firstObject label:@"Caches"];
    [self probeWritable:NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject label:@"Documents"];
}

// sharingd 가 떠 있는지 확인합니다. 이 데몬이 없으면 setDiscoverableMode:
// 는 전달될 곳이 없어 아무 일도 일어나지 않습니다. 샌드박스 때문에 목록을
// 못 읽을 수도 있는데, 그 경우 "확인 불가" 로 표시됩니다.
- (void)checkSharingDaemon {
    int mib[3] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL };
    size_t size = 0;
    if (sysctl(mib, 3, NULL, &size, NULL, 0) < 0 || size == 0) {
        [self log:@"sharingd: 확인 불가 (프로세스 목록 접근 불가)"];
        return;
    }
    struct kinfo_proc *procs = malloc(size);
    if (!procs) { [self log:@"sharingd: 확인 불가 (메모리)"]; return; }
    if (sysctl(mib, 3, procs, &size, NULL, 0) < 0) {
        free(procs);
        [self log:@"sharingd: 확인 불가 (목록 읽기 실패)"];
        return;
    }
    int count = (int)(size / sizeof(struct kinfo_proc));
    pid_t found = 0;
    for (int i = 0; i < count; i++) {
        if (strcmp(procs[i].kp_proc.p_comm, "sharingd") == 0) {
            found = procs[i].kp_proc.p_pid;
            break;
        }
    }
    free(procs);
    if (found) [self log:@"✓ sharingd 실행 중 (pid %d, 전체 %d개 프로세스)", found, count];
    else       [self log:@"✗ sharingd 가 목록에 없음 (전체 %d개 프로세스)", count];
}

- (void)probeWritable:(NSString *)dir label:(NSString *)label {
    if (!dir) { [self log:@"   ✗ %@ 경로 없음", label]; return; }
    NSString *f = [dir stringByAppendingPathComponent:@"_probe.txt"];
    NSError *e = nil;
    BOOL ok = [@"x" writeToFile:f atomically:YES encoding:NSUTF8StringEncoding error:&e];
    if (ok) [[NSFileManager defaultManager] removeItemAtPath:f error:nil];
    [self log:@"   %@ %@ — %@", ok ? @"✓" : @"✗", label,
              ok ? @"쓰기 가능" : e.localizedDescription];
}

#pragma mark - 4. AirDrop 켜기

// v1 은 설정 직후 즉시 읽어 0 이면 실패로 판정했습니다. 설정이 sharingd 로
// 비동기 전달될 수 있으므로, 지연 재확인과 뷰 계층 부착 재시도를 함께 합니다.
- (void)doEnableAirDrop {
    [self log:@"\n--- 4. AirDrop 켜기 ---"];
    Class cls = NSClassFromString(@"SFAirDropDiscoveryController");
    if (!cls) { [self log:@"✗ DiscoveryController 없음. 1·2번 먼저."]; return; }

    if (!self.discovery) {
        self.discovery = [[cls alloc] init];
        [self log:@"컨트롤러 생성: %@", self.discovery];
    }

    // 1차 시도 — 그대로 설정
    [self trySetEveryone:@"1차(그대로)"];

    // v2 에서는 여기서 컨트롤러를 뷰 계층에 부착해 봤으나, view 로드 시점에
    // 앱이 즉시 종료됐습니다. SFAirDropDiscoveryController 의 view 는 건드리지
    // 않습니다.

    // 2차 시도 — ContactsOnly 를 거쳐 Everyone 으로. 일부 구현은 Off 에서
    // 곧장 Everyone 으로 가는 전이를 받지 않습니다.
    @try {
        [self.discovery setDiscoverableMode:SDAirDropDiscoverableModeContactsOnly];
        [self log:@"2차 ContactsOnly 설정 후 = %lld", [self.discovery discoverableMode]];
    } @catch (NSException *e) {
        [self log:@"✗ 2차 예외: %@", e.reason];
    }
    [self trySetEveryone:@"3차(Contacts 경유)"];

    // 지연 재확인 — 비동기 반영 가능성
    for (NSNumber *delay in @[ @1.0, @3.0 ]) {
        double d = [delay doubleValue];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            long long m = [self.discovery discoverableMode];
            [self log:@"   %.0f초 후 모드 = %lld (%@)%@", d, m, [self modeName:m],
                      m == 2 ? @"  ← 반영됨" : @""];
        });
    }
    [self log:@"(1초·3초 후 재확인 결과가 아래에 추가됩니다)"];
}

- (void)trySetEveryone:(NSString *)label {
    @try {
        [self.discovery setDiscoverableMode:SDAirDropDiscoverableModeEveryone];
    } @catch (NSException *e) {
        [self log:@"✗ %@ 예외: %@", label, e.reason];
        return;
    }
    long long m = [self.discovery discoverableMode];
    [self log:@"%@ 즉시 읽기 = %lld (%@)", label, m, [self modeName:m]];
}

#pragma mark - 5. 모드 다시 읽기

- (void)doReadMode {
    [self log:@"\n--- 5. 모드 다시 읽기 ---"];
    if (!self.discovery) { [self log:@"컨트롤러 없음. 4번 먼저."]; return; }
    long long m = [self.discovery discoverableMode];
    [self log:@"모드 = %lld (%@)", m, [self modeName:m]];
    [self log:@"※ 아이폰 공유 시트를 열어 이 애플TV가 보이는지 직접 확인하십시오."];
    [self log:@"   모드 값과 무관하게 보일 수 있습니다."];
}

#pragma mark - 6. 수신 대기

- (void)doStartReceiving {
    [self log:@"\n--- 6. 수신 대기 ---"];
    Class cls = NSClassFromString(@"SFAirDropReceiverViewController");
    if (!cls) { [self log:@"✗ ReceiverViewController 없음."]; return; }

    UIViewController *rec = [[cls alloc] init];
    [self presentViewController:rec animated:YES completion:^{
        if ([rec respondsToSelector:@selector(startAdvertising)]) {
            [(SFAirDropReceiverViewController *)rec startAdvertising];
            [self log:@"✓ startAdvertising 호출됨"];
            if (self.discovery) {
                [self log:@"   이때 모드 = %lld", [self.discovery discoverableMode]];
            }
        } else {
            [self log:@"✗ startAdvertising 셀렉터 없음"];
        }
    }];
    [self log:@"이 화면을 유지한 채 같은 Apple ID 아이폰에서 전송하십시오."];
    [self log:@"전송 후 Spartan 에서 확인:"];
    [self log:@"/var/mobile/Downloads/com.apple.AirDrop/"];
}

#pragma mark - 7. 보내기 테스트 (쓰기 권한에 의존하지 않음)

- (void)doSendTest {
    [self log:@"\n--- 7. 보내기 테스트 ---"];
    Class cls = NSClassFromString(@"SFAirDropSharingViewControllerTV");
    if (!cls) { [self log:@"✗ SharingViewControllerTV 없음."]; return; }

    NSString *file = [self makeOrFindSendableFile];
    if (!file) { [self log:@"✗ 보낼 파일을 확보하지 못했습니다."]; return; }
    [self log:@"보낼 파일: %@", file];

    NSURL *url = [NSURL fileURLWithPath:file];
    UIViewController *sharing = [[cls alloc] initWithSharingItems:@[ url ]];
    if ([sharing respondsToSelector:@selector(setCompletionHandler:)]) {
        [(SFAirDropSharingViewControllerTV *)sharing setCompletionHandler:^(NSError *e) {
            [self log:e ? [NSString stringWithFormat:@"완료(오류): %@", e] : @"✓ 전송 완료"];
            [self dismissViewControllerAnimated:YES completion:nil];
        }];
    }
    [self presentViewController:sharing animated:YES completion:nil];
}

// 쓰기 가능한 곳을 차례로 시도하고, 모두 실패하면 앱 번들의 Info.plist 를
// 보냅니다. 번들 읽기는 샌드박스와 무관하게 항상 가능합니다.
- (NSString *)makeOrFindSendableFile {
    NSString *body = [NSString stringWithFormat:@"AirDropTV 송신 테스트\n%@\n", [NSDate date]];
    NSArray *dirs = @[ NSTemporaryDirectory() ?: @"",
                       NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
                           NSUserDomainMask, YES).firstObject ?: @"",
                       NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                           NSUserDomainMask, YES).firstObject ?: @"" ];
    for (NSString *d in dirs) {
        if (d.length == 0) continue;
        NSString *f = [d stringByAppendingPathComponent:@"airdrop-test.txt"];
        NSError *e = nil;
        if ([body writeToFile:f atomically:YES encoding:NSUTF8StringEncoding error:&e]) {
            return f;
        }
        [self log:@"   쓰기 실패(%@): %@", d.lastPathComponent, e.localizedDescription];
    }
    NSString *plist = [[[NSBundle mainBundle] bundlePath]
                       stringByAppendingPathComponent:@"Info.plist"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:plist]) {
        [self log:@"   → 쓰기 불가. 앱 번들의 Info.plist 로 대체합니다."];
        return plist;
    }
    return nil;
}

#pragma mark - 0. 끄기

- (void)doDisableAirDrop {
    [self log:@"\n--- 0. AirDrop 끄기 ---"];
    if (!self.discovery) { [self log:@"컨트롤러 없음."]; return; }
    [self.discovery setDiscoverableMode:SDAirDropDiscoverableModeOff];
    [self log:@"모드 = %lld", [self.discovery discoverableMode]];
}

@end
