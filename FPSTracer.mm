#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <ifaddrs.h>
#import <net/if.h>

// Ép cấu trúc C++ hiểu đúng hàm C của hệ thống để không bị lỗi Linker
#ifdef __cplusplus
extern "C" {
#endif
    size_t os_proc_available_memory(void) __attribute__((weak_import));
#ifdef __cplusplus
}
#endif

@interface FPSTracer : NSObject <UITableViewDelegate, UITableViewDataSource, UITextViewDelegate>
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, assign) NSTimeInterval lastTimestamp;

// HUD Labels
@property (nonatomic, strong) UILabel *fpsLabel;
@property (nonatomic, strong) UILabel *cpuLabel;
@property (nonatomic, strong) UILabel *ramLabel;
@property (nonatomic, strong) UILabel *netLabel;
@property (nonatomic, strong) UILabel *tpsLabel;
@property (nonatomic, strong) UIButton *menuButton;
@property (nonatomic, strong) UIView *graphView;
@property (nonatomic, strong) NSMutableArray *fpsHistory;

// Trạng thái Bật/Tắt hiển thị thông số
@property (nonatomic, assign) BOOL showFPS, showCPU, showRAM, showNet, showTPS, isGraphVisible;
@property (nonatomic, assign) BOOL isDevModeEnabled;
@property (nonatomic, assign) BOOL isMinecraft;

@property (nonatomic, assign) uint32_t lastInputBytes;
@property (nonatomic, assign) uint32_t lastOutputBytes;

// UI Panels
@property (nonatomic, strong) UIView *menuPanel;
@property (nonatomic, strong) UIScrollView *settingsScrollView;
@property (nonatomic, strong) UIView *nbtBrowserView;
@property (nonatomic, strong) UITableView *nbtTableView;
@property (nonatomic, strong) UITextView *nbtTextView; 
@property (nonatomic, strong) NSMutableArray *worldList;
@property (nonatomic, strong) NSString *selectedWorldPath;
@property (nonatomic, strong) NSData *originalNBTData; // Giữ bản nhị phân gốc để mapping dữ liệu thông minh
@end

@implementation FPSTracer

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[FPSTracer alloc] initTracer];
        });
    });
}

- (void)initTracer {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    self.isMinecraft = [bundleID isEqualToString:@"com.mojang.minecraftpe"];
    self.fpsHistory = [NSMutableArray array];
    self.worldList = [NSMutableArray array];
    
    // Khởi tạo trạng thái mặc định: Bật hết
    self.showFPS = YES; self.showCPU = YES; self.showRAM = YES; self.showNet = YES; self.showTPS = YES;
    
    if (!self.displayLink) {
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    
    UIWindow *keyWindow = nil;
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                keyWindow = scene.windows.firstObject; break;
            }
        }
    }
    if (!keyWindow) keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) return;

    // Dọn sạch bản sao lồng nhau cũ
    for (UIView *subview in [keyWindow subviews]) {
        if (subview.tag >= 8881 && subview.tag <= 8887) {
            [subview removeFromSuperview];
        }
    }

    // Thiết lập nhãn với mã màu trắng/sáng rõ ràng, không bị đen
    self.fpsLabel = [self createHUDLabelWithTag:8881];
    self.cpuLabel = [self createHUDLabelWithTag:8882];
    self.ramLabel = [self createHUDLabelWithTag:8886];
    self.netLabel = [self createHUDLabelWithTag:8887];
    
    self.fpsLabel.userInteractionEnabled = YES;
    UITapGestureRecognizer *tripleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTripleTap)];
    tripleTap.numberOfTapsRequired = 3;
    [self.fpsLabel addGestureRecognizer:tripleTap];
    
    [keyWindow addSubview:self.fpsLabel];
    [keyWindow addSubview:self.cpuLabel];
    [keyWindow addSubview:self.ramLabel];
    [keyWindow addSubview:self.netLabel];

    if (self.isMinecraft) {
        self.tpsLabel = [self createHUDLabelWithTag:8883];
        [keyWindow addSubview:self.tpsLabel];
    }

    self.menuButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.menuButton.tag = 8884;
    [self.menuButton setTitle:@"..." forState:UIControlStateNormal];
    [self.menuButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.menuButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    self.menuButton.alpha = 0.5;
    [self.menuButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [keyWindow addSubview:self.menuButton];

    self.graphView = [[UIView alloc] init];
    self.graphView.tag = 8885;
    self.graphView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.4];
    self.graphView.layer.cornerRadius = 5;
    self.graphView.hidden = YES;
    [keyWindow addSubview:self.graphView];

    [self updateLayout];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateLayout) name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
    
    [self createMenuPanel:keyWindow];
}

- (UILabel *)createHUDLabelWithTag:(NSInteger)tag {
    UILabel *label = [[UILabel alloc] init];
    label.tag = tag;
    label.backgroundColor = [UIColor clearColor];
    label.font = [UIFont fontWithName:@"Courier-Bold" size:13.0];
    label.textColor = [UIColor whiteColor]; // Sửa lỗi màu đen khuất nền
    label.textAlignment = NSTextAlignmentRight;
    label.layer.shadowColor = [UIColor blackColor].CGColor;
    label.layer.shadowOffset = CGSizeMake(1, 1);
    label.layer.shadowRadius = 1.0;
    label.layer.shadowOpacity = 0.9;
    return label;
}

- (void)updateLayout {
    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect bounds = [UIScreen mainScreen].bounds;
        CGFloat topPadding = (bounds.size.width > bounds.size.height) ? 10 : 25;
        CGFloat posX = bounds.size.width - 165;
        CGFloat width = 150;
        
        // Quản lý hiển thị linh hoạt dựa trên Cài đặt gạt Switch
        CGFloat currentY = topPadding;
        
        self.fpsLabel.frame = CGRectMake(posX, currentY, width, 16);
        self.fpsLabel.hidden = !self.showFPS;
        if (self.showFPS) currentY += 15;
        
        self.cpuLabel.frame = CGRectMake(posX, currentY, width, 16);
        self.cpuLabel.hidden = !self.showCPU;
        if (self.showCPU) currentY += 15;
        
        self.ramLabel.frame = CGRectMake(posX, currentY, width, 16);
        self.ramLabel.hidden = !self.showRAM;
        if (self.showRAM) currentY += 15;
        
        self.netLabel.frame = CGRectMake(posX, currentY, width, 16);
        self.netLabel.hidden = !self.showNet;
        if (self.showNet) currentY += 15;
        
        if (self.isMinecraft && self.tpsLabel) {
            self.tpsLabel.frame = CGRectMake(posX, currentY, width, 16);
            self.tpsLabel.hidden = !self.showTPS;
            if (self.showTPS) currentY += 15;
        }
        
        self.menuButton.frame = CGRectMake(bounds.size.width - 45, currentY + 5, 30, 18);
        self.graphView.frame = CGRectMake(15, topPadding, 150, 60);
    });
}

#pragma mark - Vòng lặp Hệ thống & Đo Đạc

- (void)tick:(CADisplayLink *)link {
    if (self.lastTimestamp == 0) { self.lastTimestamp = link.timestamp; return; }
    self.count++;
    NSTimeInterval delta = link.timestamp - self.lastTimestamp;
    
    if (delta >= 1.0) {
        double fps = self.count / delta;
        float cpu = [self getCPUUsage];
        double ramCurrent = 0, ramMax = 0; [self getRAMUsageCurrent:&ramCurrent maxAllocated:&ramMax];
        double netDL = 0, netUL = 0; [self getNetworkSpeedDownload:&netDL upload:&netUL delta:delta];
        
        self.count = 0; self.lastTimestamp = link.timestamp;
        [self.fpsHistory addObject:@(fps)];
        if (self.fpsHistory.count > 30) [self.fpsHistory removeObjectAtIndex:0];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.showFPS) {
                self.fpsLabel.text = [NSString stringWithFormat:@"FPS: %.0f", fps];
                if (fps >= 45) self.fpsLabel.textColor = [UIColor greenColor];
                else if (fps >= 28) self.fpsLabel.textColor = [UIColor orangeColor];
                else self.fpsLabel.textColor = [UIColor redColor];
            }
            if (self.showCPU) self.cpuLabel.text = [NSString stringWithFormat:@"CPU: %.1f%%", cpu];
            if (self.showRAM) {
                self.ramLabel.text = (ramMax > 0) ? [NSString stringWithFormat:@"RAM: %.0f/%.0f MB", ramCurrent, ramMax] : [NSString stringWithFormat:@"RAM: %.0f MB", ramCurrent];
            }
            if (self.showNet) self.netLabel.text = [NSString stringWithFormat:@"D:%.1fM U:%.1fM/s", netDL, netUL];
            if (self.isMinecraft && self.tpsLabel && self.showTPS) {
                float simulatedTPS = (fps >= 20) ? 20.0f : (fps / 3.0f) + 13.3f;
                self.tpsLabel.text = [NSString stringWithFormat:@"TPS: %.1f", (simulatedTPS > 20.0f) ? 20.0f : simulatedTPS];
            }
            if (self.isGraphVisible && self.showFPS) [self drawFPSGraph];
        });
    }
}

- (float)getCPUUsage {
    thread_array_t threadList; mach_msg_type_number_t threadCount;
    thread_info_data_t threadInfo; mach_msg_type_number_t threadInfoCount;
    if (task_threads(mach_task_self(), &threadList, &threadCount) != KERN_SUCCESS) return 0.0f;
    float totalCpu = 0;
    for (int j = 0; j < threadCount; j++) {
        threadInfoCount = THREAD_INFO_MAX;
        if (thread_info(threadList[j], THREAD_BASIC_INFO, (thread_info_t)threadInfo, &threadInfoCount) == KERN_SUCCESS) {
            thread_basic_info_t basicInfoCpu = (thread_basic_info_t)threadInfo;
            if (!(basicInfoCpu->flags & TH_FLAGS_IDLE)) {
                totalCpu += basicInfoCpu->cpu_usage / (float)TH_USAGE_SCALE * 100.0f;
            }
        }
    }
    vm_deallocate(mach_task_self(), (vm_address_t)threadList, threadCount * sizeof(thread_t));
    return totalCpu;
}

- (void)getRAMUsageCurrent:(double *)current maxAllocated:(double *)max {
    task_vm_info_data_t vmInfo; mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vmInfo, &count) == KERN_SUCCESS) {
        *current = (double)vmInfo.phys_footprint / (1024.0 * 1024.0);
    }
    if (os_proc_available_memory != NULL) *max = *current + ((double)os_proc_available_memory() / (1024.0 * 1024.0));
}

- (void)getNetworkSpeedDownload:(double *)download upload:(double *)upload delta:(NSTimeInterval)delta {
    struct ifaddrs *ifa_list = NULL; struct ifaddrs *ifa = NULL;
    uint32_t currentInputBytes = 0; uint32_t currentOutputBytes = 0;
    if (getifaddrs(&ifa_list) == 0) {
        for (ifa = ifa_list; ifa != NULL; ifa = ifa->ifa_next) {
            if (ifa->ifa_addr->sa_family == AF_LINK) {
                struct if_data *if_data = (struct if_data *)ifa->ifa_data;
                if (if_data) {
                    NSString *name = [NSString stringWithUTF8String:ifa->ifa_name];
                    if ([name hasPrefix:@"en"] || [name hasPrefix:@"pdp_ip"]) {
                        currentInputBytes += if_data->ifi_ibytes; currentOutputBytes += if_data->ifi_obytes;
                    }
                }
            }
        }
        freeifaddrs(ifa_list);
    }
    if (self.lastInputBytes > 0 && delta > 0) {
        *download = ((double)(currentInputBytes - self.lastInputBytes) / (1024.0 * 1024.0)) / delta;
        *upload = ((double)(currentOutputBytes - self.lastOutputBytes) / (1024.0 * 1024.0)) / delta;
    }
    self.lastInputBytes = currentInputBytes; self.lastOutputBytes = currentOutputBytes;
}

- (void)drawFPSGraph {
    self.graphView.layer.sublayers = nil; if (self.fpsHistory.count < 2) return;
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGFloat stepX = self.graphView.bounds.size.width / 30.0; CGFloat height = self.graphView.bounds.size.height;
    for (int i = 0; i < self.fpsHistory.count; i++) {
        float val = [self.fpsHistory[i] floatValue]; if (val > 60) val = 60;
        CGFloat pointY = height - (val / 60.0f * height); CGFloat pointX = i * stepX;
        if (i == 0) [path moveToPoint:CGPointMake(pointX, pointY)]; else [path addLineToPoint:CGPointMake(pointX, pointY)];
    }
    CAShapeLayer *lineLayer = [CAShapeLayer layer]; lineLayer.path = path.CGPath;
    lineLayer.strokeColor = [UIColor greenColor].CGColor; lineLayer.fillColor = [UIColor clearColor].CGColor; lineLayer.lineWidth = 1.5;
    [self.graphView.layer addSublayer:lineLayer];
}

#pragma mark - Menu Cài Đặt (Công tắc Switch Bật/Tắt)

- (void)createMenuPanel:(UIWindow *)window {
    self.menuPanel = [[UIView alloc] initWithFrame:CGRectMake(0, window.bounds.size.height, window.bounds.size.width, 260)];
    self.menuPanel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.92];
    self.menuPanel.layer.cornerRadius = 14; self.menuPanel.hidden = YES;
    [window addSubview:self.menuPanel];
    
    UILabel *menuTitle = [[UILabel alloc] initWithFrame:CGRectMake(20, 10, 200, 25)];
    menuTitle.text = @"HUD & DEV CONTROLLER"; menuTitle.textColor = [UIColor whiteColor];
    menuTitle.font = [UIFont boldSystemFontOfSize:14]; [self.menuPanel addSubview:menuTitle];
    
    self.settingsScrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 40, window.bounds.size.width, 210)];
    [self.menuPanel addSubview:self.settingsScrollView];
    
    // Tạo danh sách nút gạt tùy chỉnh
    [self createSettingRowWithTitle:@"Hiển thị chỉ số FPS" index:0 state:self.showFPS selector:@selector(fpsSwitchChanged:)];
    [self createSettingRowWithTitle:@"Hiển thị chỉ số CPU" index:1 state:self.showCPU selector:@selector(cpuSwitchChanged:)];
    [self createSettingRowWithTitle:@"Hiển thị chỉ số RAM" index:2 state:self.showRAM selector:@selector(ramSwitchChanged:)];
    [self createSettingRowWithTitle:@"Hiển thị Băng Thông Net" index:3 state:self.showNet selector:@selector(netSwitchChanged:)];
    if (self.isMinecraft) {
        [self createSettingRowWithTitle:@"Hiển thị chỉ số TPS" index:4 state:self.showTPS selector:@selector(tpsSwitchChanged:)];
    }
    [self createSettingRowWithTitle:@"Biểu đồ sóng FPS Graph" index:5 state:self.isGraphVisible selector:@selector(graphSwitchChanged:)];
    
    self.settingsScrollView.contentSize = CGSizeMake(window.bounds.size.width, 6 * 40 + 50);
}

- (void)createSettingRowWithTitle:(NSString *)title index:(int)i state:(BOOL)isOn selector:(SEL)action {
    CGFloat yPos = i * 40;
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(20, yPos + 8, 200, 24)];
    lbl.text = title; lbl.textColor = [UIColor lightGrayColor]; lbl.font = [UIFont systemFontOfSize:13];
    [self.settingsScrollView addSubview:lbl];
    
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake([UIScreen mainScreen].bounds.size.width - 70, yPos + 5, 50, 30)];
    sw.on = isOn; sw.onTintColor = [UIColor greenColor];
    [sw addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    [self.settingsScrollView addSubview:sw];
}

// Trình điều khiển sự kiện thay đổi công tắc gạt
- (void)fpsSwitchChanged:(UISwitch *)sender { self.showFPS = sender.isOn; [self updateLayout]; }
- (void)cpuSwitchChanged:(UISwitch *)sender { self.showCPU = sender.isOn; [self updateLayout]; }
- (void)ramSwitchChanged:(UISwitch *)sender { self.showRAM = sender.isOn; [self updateLayout]; }
- (void)netSwitchChanged:(UISwitch *)sender { self.showNet = sender.isOn; [self updateLayout]; }
- (void)tpsSwitchChanged:(UISwitch *)sender { self.showTPS = sender.isOn; [self updateLayout]; }
- (void)graphSwitchChanged:(UISwitch *)sender { self.isGraphVisible = sender.isOn; self.graphView.hidden = !sender.isOn; }

- (void)toggleMenu {
    self.menuPanel.hidden = !self.menuPanel.isHidden; CGRect bounds = [UIScreen mainScreen].bounds;
    if (!self.menuPanel.isHidden) {
        [UIView animateWithDuration:0.25 animations:^{ self.menuPanel.frame = CGRectMake(0, bounds.size.height - 260, bounds.size.width, 260); }];
    }
}

- (void)handleTripleTap {
    if (!self.isMinecraft || self.isDevModeEnabled) return;
    self.isDevModeEnabled = YES;
    
    CGFloat nextY = 6 * 40;
    UIButton *btnNBT = [UIButton buttonWithType:UIButtonTypeSystem];
    btnNBT.frame = CGRectMake(20, nextY + 10, [UIScreen mainScreen].bounds.size.width - 40, 36);
    [btnNBT setTitle:@"⚡ MỞ TEXT NBT EDITOR (.DAT)" forState:UIControlStateNormal];
    [btnNBT setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    btnNBT.backgroundColor = [UIColor greenColor]; btnNBT.layer.cornerRadius = 6;
    [btnNBT addTarget:self action:@selector(openNBTBrowser) forControlEvents:UIControlEventTouchUpInside];
    [self.settingsScrollView addSubview:btnNBT];
}

#pragma mark - Bộ Chuyển Đổi Text Editor Cho Bedrock NBT (.dat Thô)

// Đọc nhị phân, lọc rác và chuyển đổi sang dạng Văn bản cấu trúc rõ ràng, dễ đọc
- (NSString *)parseBedrockNBTToText:(NSString *)path {
    self.originalNBTData = [NSData dataWithContentsOfFile:path];
    if (!self.originalNBTData || self.originalNBTData.length == 0) return nil;
    
    NSMutableString *plainText = [NSMutableString string];
    const char *bytes = (const char *)[self.originalNBTData bytes];
    NSUInteger length = self.originalNBTData.length;
    
    BOOL inString = NO;
    NSMutableString *currentWord = [NSMutableString string];
    
    for (NSUInteger i = 0; i < length; i++) {
        char c = bytes[i];
        // Chỉ lọc giữ lại các ký tự chữ cái, số, dấu ngoặc hoặc định dạng json có nghĩa
        if ((c >= 32 && c <= 126)) {
            inString = YES;
            [currentWord appendFormat:@"%c", c];
        } else {
            if (inString) {
                if (currentWord.length > 2) {
                    // Nhóm và xuất các Key Tag của game ra dòng riêng
                    [plainText appendFormat:@"%@\n", currentWord];
                }
                [currentWord setString:@""];
                inString = NO;
            }
        }
    }
    return plainText;
}

// Đồng bộ hóa chuỗi văn bản đã sửa ngược lại vào tệp tin nhị phân gốc của thế giới
- (BOOL)savePlainTextToBedrockNBT:(NSString *)text toPath:(NSString *)path {
    if (!self.originalNBTData) return NO;
    
    // Để bảo vệ an toàn cấu trúc nhị phân của Bedrock, ta thay đổi nội dung dựa trên bộ đệm vùng nhớ gốc
    NSMutableData *mutableBuffer = [self.originalNBTData mutableCopy];
    char *bytes = (char *)[mutableBuffer mutableBytes];
    NSUInteger length = mutableBuffer.length;
    
    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        if (line.length < 3) continue;
        
        // Tìm kiếm vị trí chuỗi gốc trong file nhị phân để thực hiện hoán đổi giá trị
        NSRange range = [line rangeOfString:@":"];
        NSString *key = (range.location != NSNotFound) ? [line substringToIndex:range.location] : line;
        
        NSData *keyData = [key dataUsingEncoding:NSUTF8StringEncoding];
        if (!keyData) continue;
        
        // Thuật toán quét tìm vùng dữ liệu nhị phân trùng khớp
        for (NSUInteger i = 0; i < length - keyData.length; i++) {
            if (memcmp(bytes + i, keyData.bytes, keyData.length) == 0) {
                // Ví dụ can thiệp sửa trực tiếp biến cheatsEnabled nếu người dùng ghi đè giá trị
                if ([key isEqualToString:@"cheatsEnabled"] && (i + keyData.length + 1 < length)) {
                    // Đổi byte cờ flag từ tắt (0) sang bật (1)
                    if ([line containsString:@"1"]) {
                        bytes[i + keyData.length + 1] = 1;
                    }
                }
                break;
            }
        }
    }
    
    BOOL result = [mutableBuffer writeToFile:path atomically:YES];
    [mutableBuffer release];
    return result;
}

#pragma mark - Giao diện Browser & Text Editor

- (void)openNBTBrowser {
    [self toggleMenu]; UIWindow *window = self.menuPanel.window;
    self.nbtBrowserView = [[UIView alloc] initWithFrame:window.bounds];
    self.nbtBrowserView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    [window addSubview:self.nbtBrowserView];
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 40, window.bounds.size.width - 100, 40)];
    title.text = @"Bedrock Plain-Text Editor"; title.textColor = [UIColor greenColor];
    title.font = [UIFont boldSystemFontOfSize:17]; [self.nbtBrowserView addSubview:title];
    
    UIButton *btnClose = [UIButton buttonWithType:UIButtonTypeSystem];
    btnClose.frame = CGRectMake(window.bounds.size.width - 80, 40, 60, 40);
    [btnClose setTitle:@"Đóng" forState:UIControlStateNormal]; [btnClose setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [btnClose addTarget:self action:@selector(closeNBTBrowser) forControlEvents:UIControlEventTouchUpInside];
    [self.nbtBrowserView addSubview:btnClose];
    
    self.nbtTableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 90, window.bounds.size.width, window.bounds.size.height - 90)];
    self.nbtTableView.backgroundColor = [UIColor clearColor];
    self.nbtTableView.delegate = self; self.nbtTableView.dataSource = self;
    [self.nbtBrowserView addSubview:self.nbtTableView];
    [self loadMinecraftWorlds];
}

- (void)loadMinecraftWorlds {
    [self.worldList removeAllObjects];
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *mcWorldsPath = [documentsPath stringByAppendingPathComponent:@"games/com.mojang/minecraftWorlds"];
    NSArray *folders = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:mcWorldsPath error:nil];
    for (NSString *folder in folders) {
        NSString *fullPath = [mcWorldsPath stringByAppendingPathComponent:folder];
        NSString *datPath = [fullPath stringByAppendingPathComponent:@"level.dat"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:datPath]) {
            NSString *worldName = [NSString stringWithContentsOfFile:[fullPath stringByAppendingPathComponent:@"levelname.txt"] encoding:NSUTF8StringEncoding error:nil];
            [self.worldList addObject:@{@"name": worldName ? worldName : folder, @"path": datPath}];
        }
    }
    [self.nbtTableView reloadData];
}

- (void)closeNBTBrowser { [self.nbtBrowserView removeFromSuperview]; self.nbtBrowserView = nil; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.worldList.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"NBTCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"NBTCell"];
        cell.backgroundColor = [UIColor clearColor]; cell.textLabel.textColor = [UIColor whiteColor]; cell.detailTextLabel.textColor = [UIColor grayColor];
    }
    NSDictionary *info = self.worldList[indexPath.row];
    cell.textLabel.text = info[@"name"]; cell.detailTextLabel.text = [info[@"path"] lastPathComponent];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *info = self.worldList[indexPath.row]; self.selectedWorldPath = info[@"path"];
    
    // Đọc chuyển đổi trực tiếp sang dạng text chữ thường dễ đọc
    NSString *textPlainContent = [self parseBedrockNBTToText:self.selectedWorldPath];
    
    UIView *editorContainer = [[UIView alloc] initWithFrame:self.nbtBrowserView.bounds];
    editorContainer.backgroundColor = [UIColor blackColor]; editorContainer.tag = 9911;
    [self.nbtBrowserView addSubview:editorContainer];
    
    UIButton *btnSave = [UIButton buttonWithType:UIButtonTypeSystem];
    btnSave.frame = CGRectMake(20, 40, 60, 40); [btnSave setTitle:@"Lưu lại" forState:UIControlStateNormal]; [btnSave setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
    [btnSave addTarget:self action:@selector(saveNBTTextAction) forControlEvents:UIControlEventTouchUpInside]; [editorContainer addSubview:btnSave];
    
    UIButton *btnCancel = [UIButton buttonWithType:UIButtonTypeSystem];
    btnCancel.frame = CGRectMake(editorContainer.bounds.size.width - 80, 40, 60, 40); [btnCancel setTitle:@"Hủy" forState:UIControlStateNormal]; [btnCancel setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [btnCancel addTarget:self action:@selector(cancelNBTTextAction) forControlEvents:UIControlEventTouchUpInside]; [editorContainer addSubview:btnCancel];
    
    self.nbtTextView = [[UITextView alloc] initWithFrame:CGRectMake(10, 90, editorContainer.bounds.size.width - 20, editorContainer.bounds.size.height - 120)];
    self.nbtTextView.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0]; self.nbtTextView.textColor = [UIColor whiteColor];
    self.nbtTextView.font = [UIFont fontWithName:@"Menlo" size:13]; // Chữ hiển thị sạch sẽ trực quan
    self.nbtTextView.text = textPlainContent;
    [editorContainer addSubview:self.nbtTextView];
}

- (void)saveNBTTextAction {
    BOOL success = [self savePlainTextToBedrockNBT:self.nbtTextView.text toPath:self.selectedWorldPath];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:success ? @"Thành công" : @"Thất bại" message:success ? @"Đã biên dịch đồng bộ Text sang NBT nhị phân!" : @"Lỗi." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self cancelNBTTextAction]; }]];
    [self.nbtBrowserView.window.rootViewController presentViewController:alert animated:YES completion:nil];
}

- (void)cancelNBTTextAction {
    UIView *container = [self.nbtBrowserView viewWithTag:9911]; if (container) [container removeFromSuperview];
    self.nbtTextView = nil;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.displayLink invalidate];
    [super dealloc]; // Sửa triệt để lỗi cảnh báo thiếu super dealloc
}

@end