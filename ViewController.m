//
//  ViewController.m
//  AirDropTV — tvOS AirDrop 활성화 검증용 최소 앱
//
//  tvOS에서는 콘솔을 보기 어려우므로 모든 결과를 화면에 출력합니다.
//

#import "ViewController.h"
#import <objc/runtime.h>

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
                         @"3. AirDrop 켜기 (Everyone)",
                         @"4. 수신 대기 화면",
                         @"5. 보내기 테스트",
                         @"0. AirDrop 끄기" ];
    NSArray *sels = @[ @"doLoadFrameworks", @"doProbeClasses", @"doEnableAirDrop",
                       @"doStartReceiving", @"doSendTest", @"doDisableAirDrop" ];

    UIStackView *buttons = [[UIStackView alloc] init];
    buttons.axis = UILayoutConstraintAxisVertical;
    buttons.spacing = 12;
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
    self.logView.font = [UIFont fontWithName:@"Menlo" size:24];
    self.logView.editable = NO;
    self.logView.userInteractionEnabled = NO;
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview:buttons];
    [self.view addSubview:self.logView];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [buttons.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:40],
        [buttons.topAnchor constraintEqualToAnchor:g.topAnchor constant:40],
        [buttons.widthAnchor constraintEqualToConstant:560],

        [self.logView.leadingAnchor constraintEqualToAnchor:buttons.trailingAnchor constant:40],
        [self.logView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-40],
        [self.logView.topAnchor constraintEqualToAnchor:g.topAnchor constant:40],
        [self.logView.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-40],
    ]];

    [self log:@"준비됨. 1번부터 순서대로 실행하십시오."];
}

- (void)log:(NSString *)fmt, ... {
    va_list args;
    va_start(args, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSLog(@"[AirDropTV] %@", s);
    dispatch_async(dispatch_get_main_queue(), ^{
        self.logView.text = [self.logView.text stringByAppendingFormat:@"\n%@", s];
        NSRange end = NSMakeRange(self.logView.text.length - 1, 1);
        [self.logView scrollRangeToVisible:end];
    });
}

#pragma mark - 1. 프레임워크 로드

- (void)doLoadFrameworks {
    [self log:@"\n--- 1. 프레임워크 로드 ---"];
    for (NSString *name in @[ @"Sharing", @"SharingUI" ]) {
        NSString *path = [NSString stringWithFormat:
                          @"/System/Library/PrivateFrameworks/%@.framework", name];
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path];
        if (!exists) {
            [self log:@"✗ %@.framework 경로 없음", name];
            continue;
        }
        NSBundle *b = [NSBundle bundleWithPath:path];
        BOOL loaded = [b load];
        [self log:@"%@ %@.framework %@", loaded ? @"✓" : @"✗", name,
                  loaded ? @"로드 성공" : @"로드 실패"];
    }
}

#pragma mark - 2. 클래스 존재 확인 (tvOS 16.6 생존 여부 판정)

- (void)doProbeClasses {
    [self log:@"\n--- 2. 클래스 존재 확인 ---"];
    NSArray *names = @[ @"SFAirDropDiscoveryController",
                        @"SFAirDropReceiverViewController",
                        @"SFAirDropSharingViewControllerTV" ];
    BOOL allFound = YES;
    for (NSString *n in names) {
        Class c = NSClassFromString(n);
        if (c) {
            [self log:@"✓ %@", n];
        } else {
            [self log:@"✗ %@ — 없음", n];
            allFound = NO;
        }
    }
    if (!allFound) {
        [self log:@"→ 클래스명이 바뀌었을 수 있습니다. 아래 후보를 검색합니다."];
        [self dumpAirDropClasses];
    }
}

// 런타임 전체에서 AirDrop 관련 클래스명을 긁어옵니다 (클래스명 변경 시 추적용)
- (void)dumpAirDropClasses {
    unsigned int count = 0;
    Class *all = objc_copyClassList(&count);
    int hits = 0;
    for (unsigned int i = 0; i < count && hits < 40; i++) {
        const char *cn = class_getName(all[i]);
        NSString *n = [NSString stringWithUTF8String:cn];
        if ([n containsString:@"AirDrop"]) {
            [self log:@"   · %@", n];
            hits++;
        }
    }
    free(all);
    if (hits == 0) [self log:@"   (AirDrop 관련 클래스를 찾지 못함)"];
}

#pragma mark - 3. AirDrop 켜기

- (void)doEnableAirDrop {
    [self log:@"\n--- 3. AirDrop 켜기 ---"];
    Class cls = NSClassFromString(@"SFAirDropDiscoveryController");
    if (!cls) { [self log:@"✗ DiscoveryController 없음. 1·2번 먼저 실행."]; return; }

    if (!self.discovery) self.discovery = [[cls alloc] init];

    @try {
        [self.discovery setDiscoverableMode:SDAirDropDiscoverableModeEveryone];
    } @catch (NSException *e) {
        [self log:@"✗ setDiscoverableMode 예외: %@", e.reason];
        return;
    }

    long long mode = [self.discovery discoverableMode];
    [self log:@"현재 모드 = %lld (%@)", mode,
              mode == 2 ? @"Everyone" : (mode == 1 ? @"ContactsOnly" : @"Off")];
    if (mode == SDAirDropDiscoverableModeEveryone) {
        [self log:@"✓ 성공. 아이폰 공유 시트에 이 애플TV가 뜨는지 확인하십시오."];
    } else {
        [self log:@"✗ 값이 유지되지 않음 → airdrop.settings 권한 미적용 가능성."];
    }
}

- (void)doDisableAirDrop {
    [self log:@"\n--- 0. AirDrop 끄기 ---"];
    if (!self.discovery) { [self log:@"컨트롤러 없음."]; return; }
    [self.discovery setDiscoverableMode:SDAirDropDiscoverableModeOff];
    [self log:@"모드 = %lld", [self.discovery discoverableMode]];
}

#pragma mark - 4. 수신 대기

- (void)doStartReceiving {
    [self log:@"\n--- 4. 수신 대기 ---"];
    Class cls = NSClassFromString(@"SFAirDropReceiverViewController");
    if (!cls) { [self log:@"✗ ReceiverViewController 없음."]; return; }

    UIViewController *rec = [[cls alloc] init];
    [self presentViewController:rec animated:YES completion:^{
        if ([rec respondsToSelector:@selector(startAdvertising)]) {
            [(SFAirDropReceiverViewController *)rec startAdvertising];
            [self log:@"✓ startAdvertising 호출됨. 이 화면을 유지한 채 전송하십시오."];
        } else {
            [self log:@"✗ startAdvertising 셀렉터 없음."];
        }
    }];
    [self log:@"수신 화면 표시. 전송 후 Spartan에서 아래 경로를 확인:"];
    [self log:@"/var/mobile/Downloads/com.apple.AirDrop/"];
}

#pragma mark - 5. 보내기 테스트

- (void)doSendTest {
    [self log:@"\n--- 5. 보내기 테스트 ---"];
    Class cls = NSClassFromString(@"SFAirDropSharingViewControllerTV");
    if (!cls) { [self log:@"✗ SharingViewControllerTV 없음."]; return; }

    NSString *docs = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *file = [docs stringByAppendingPathComponent:@"airdrop-test.txt"];
    NSString *body = [NSString stringWithFormat:
        @"AirDropTV 송신 테스트\n생성 시각: %@\n", [NSDate date]];
    NSError *err = nil;
    [body writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (err) { [self log:@"✗ 테스트 파일 생성 실패: %@", err.localizedDescription]; return; }
    [self log:@"테스트 파일: %@", file];

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

@end
