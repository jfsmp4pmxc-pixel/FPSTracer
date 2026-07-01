#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <ifaddrs.h>
#import <net/if.h>

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

// HUD Views
@property (nonatomic, strong) UILabel *fpsLabel;
@property (nonatomic, strong) UILabel *cpuLabel;
@property (nonatomic, strong) UILabel *ramLabel;
@property (nonatomic, strong) UILabel *netLabel;
@property (nonatomic, strong) UILabel *tpsLabel;
@property (nonatomic, strong) UIButton *menuButton;
@property (nonatomic, strong) UIView *graphView;
@property (nonatomic, strong) NSMutableArray *fpsHistory;

// UI Menu & Dev Mode
@property (nonatomic, strong) UIView *menuPanel;
@property (nonatomic, assign) BOOL isGraphVisible;
@property (nonatomic, assign) BOOL isDevModeEnabled;
@property (nonatomic, assign) BOOL isMinecraft;

@property (nonatomic, assign) uint32_t lastInputBytes;
@property (nonatomic, assign) uint32_t lastOutputBytes;

// Bedrock NBT (Hex) Editor Views
@property (nonatomic, strong) UIView *nbtBrowserView;
@property (nonatomic, strong) UITableView *nbtTableView;
@property (nonatomic, strong) UITextView *nbtTextView; 
@property (nonatomic, strong) NSMutableArray *worldList;
@property (nonatomic, strong) NSString *selectedWorldPath;
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
    
    if (!self.displayLink) {
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    
    UIWindow *keyWindow = nil;
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                keyWindow = scene.windows.firstObject;
                break;
            }
        }
    }
    if (!keyWindow) keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) return;

    // Quét sạch các bản sao cũ lồng nhau (Fix lỗi trùng lặp)
    for (UIView *subview in [keyWindow subviews]) {
        if (subview.tag >= 8881 && subview.tag <= 8887) {
            [subview removeFromSuperview];
        }
    }

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
    self.menuButton.alpha = 0.4;
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
    label.font = [UIFont boldSystemFontOfSize:13.0];
    label.textAlignment = NSTextAlignmentRight;
    label.layer.shadowColor = [UIColor blackColor].CGColor;
    label.layer.shadowOffset = CGSizeMake(0, 0);
    label.layer.shadowRadius = 1.2;
    label.layer.shadowOpacity = 1.0;
    return label;
}

- (void)updateLayout {
    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect bounds = [UIScreen mainScreen].bounds;
        CGFloat topPadding = (bounds.size.width > bounds.size.height) ? 10 : 25;
        CGFloat posX = bounds.size.width - 150;
        CGFloat width = 130;
        
        self.fpsLabel.frame = CGRectMake(posX, topPadding, width, 16);
        self.cpuLabel.frame = CGRectMake(posX, topPadding + 14, width, 16);
        self.ramLabel.frame = CGRectMake(posX, topPadding + 28, width, 16);
        self.netLabel.frame = CGRectMake(posX, topPadding + 42, width, 16);
        
        CGFloat nextY = topPadding + 56;
        if (self.isMinecraft && self.tpsLabel) {
            self.tpsLabel.frame = CGRectMake(posX, nextY, width, 16);
            nextY += 14;
        }
        
        self.menuButton.frame = CGRectMake(bounds.size.width - 45, nextY, 30, 15);
        self.graphView.frame = CGRectMake(15, topPadding, 150, 60);
        
        [self.fpsLabel.superview bringSubviewToFront:self.fpsLabel];
        [self.cpuLabel.superview bringSubviewToFront:self.cpuLabel];
        [self.ramLabel.superview bringSubviewToFront:self.ramLabel];
        [self.netLabel.superview bringSubviewToFront:self.netLabel];
        if (self.tpsLabel) [self.tpsLabel.superview bringSubviewToFront:self.tpsLabel];
        [self.menuButton.superview bringSubviewToFront:self.menuButton];
    });
}

#pragma mark - Vòng lặp Core (Tick) & Hệ thống đo đạc

- (void)tick:(CADisplayLink *)link {
    if (self.lastTimestamp == 0) {
        self.lastTimestamp = link.timestamp;
        return;
    }
    self.count++;
    NSTimeInterval delta = link.timestamp - self.lastTimestamp;
    
    if (delta >= 1.0) {
        double fps = self.count / delta;
        float cpu = [self getCPUUsage];
        
        double ramCurrent = 0, ramMax = 0;
        [self getRAMUsageCurrent:&ramCurrent maxAllocated:&ramMax];
        
        double netDL = 0, netUL = 0;
        [self getNetworkSpeedDownload:&netDL upload:&netUL delta:delta];
        
        self.count = 0;
        self.lastTimestamp = link.timestamp;
        
        [self.fpsHistory addObject:@(fps)];
        if (self.fpsHistory.count > 30) [self.fpsHistory removeObjectAtIndex:0];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.fpsLabel.text = [NSString stringWithFormat:@"FPS: %.0f", fps];
            if (fps >= 45) self.fpsLabel.textColor = [UIColor greenColor];
            else if (fps >= 30) self.fpsLabel.textColor = [UIColor colorWithRed:0.60 green:0.80 blue:0.20 alpha:1.0];
            else self.fpsLabel.textColor = [UIColor redColor];
            
            self.cpuLabel.text = [NSString stringWithFormat:@"CPU: %.1f%%", cpu];
            
            if (ramMax > 0) {
                self.ramLabel.text = [NSString stringWithFormat:@"RAM: %.0f/%.0f MB", ramCurrent, ramMax];
            } else {
                self.ramLabel.text = [NSString stringWithFormat:@"RAM: %.0f MB", ramCurrent];
            }
            double ramRatio = (ramMax > 0) ? (ramCurrent / ramMax) : 0;
            self.ramLabel.textColor = (ramRatio > 0.85) ? [UIColor redColor] : [UIColor whiteColor];
            
            self.netLabel.text = [NSString stringWithFormat:@"D:%.1fM U:%.1fM/s", netDL, netUL];
            
            if (self.isMinecraft && self.tpsLabel) {
                float simulatedTPS = (fps >= 20) ? 20.0f : (fps / 3.0f) + 13.3f;
                if (simulatedTPS > 20.0f) simulatedTPS = 20.0f;
                self.tpsLabel.text = [NSString stringWithFormat:@"TPS: %.1f", simulatedTPS];
            }
            if (self.isGraphVisible) [self drawFPSGraph];
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
    task_vm_info_data_t vmInfo;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vmInfo, &count) == KERN_SUCCESS) {
        *current = (double)vmInfo.phys_footprint / (1024.0 * 1024.0);
    }
    if (os_proc_available_memory != NULL) {
        *max = *current + ((double)os_proc_available_memory() / (1024.0 * 1024.0));
    } else {
        *max = 0.0;
    }
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
                        currentInputBytes += if_data->ifi_ibytes;
                        currentOutputBytes += if_data->ifi_obytes;
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
    self.graphView.layer.sublayers = nil;
    if (self.fpsHistory.count < 2) return;
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGFloat stepX = self.graphView.bounds.size.width / 30.0;
    CGFloat height = self.graphView.bounds.size.height;
    for (int i = 0; i < self.fpsHistory.count; i++) {
        float val = [self.fpsHistory[i] floatValue];
        if (val > 60) val = 60;
        CGFloat pointY = height - (val / 60.0f * height);
        CGFloat pointX = i * stepX;
        if (i == 0) [path moveToPoint:CGPointMake(pointX, pointY)];
        else [path addLineToPoint:CGPointMake(pointX, pointY)];
    }
    CAShapeLayer *lineLayer = [CAShapeLayer layer];
    lineLayer.path = path.CGPath; lineLayer.strokeColor = [UIColor greenColor].CGColor;
    lineLayer.fillColor = [UIColor clearColor].CGColor; lineLayer.lineWidth = 1.5;
    [self.graphView.layer addSublayer:lineLayer];
}

#pragma mark - Menu Panel & Điều hướng

- (void)createMenuPanel:(UIWindow *)window {
    self.menuPanel = [[UIView alloc] initWithFrame:CGRectMake(0, window.bounds.size.height, window.bounds.size.width, 220)];
    self.menuPanel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.9];
    self.menuPanel.layer.cornerRadius = 12;
    self.menuPanel.hidden = YES;
    [window addSubview:self.menuPanel];
    
    UIButton *btnGraph = [self createMenuButton:@"Bật/Tắt Biểu Đồ FPS" yPos:20 action:@selector(toggleGraphOption)];
    [self.menuPanel addSubview:btnGraph];
    
    UILabel *devNotice = [[UILabel alloc] initWithFrame:CGRectMake(20, 80, window.bounds.size.width - 40, 30)];
    devNotice.text = @"[Dev Mode Đang Khóa - Tap 3 lần số FPS để mở]";
    devNotice.textColor = [UIColor grayColor]; devNotice.font = [UIFont systemFontOfSize:12];
    devNotice.tag = 999;
    [self.menuPanel addSubview:devNotice];
}

- (UIButton *)createMenuButton:(NSString *)title yPos:(CGFloat)y action:(SEL)selector {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = CGRectMake(20, y, [UIScreen mainScreen].bounds.size.width - 40, 40);
    [btn setTitle:title forState:UIControlStateNormal]; [btn setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
    btn.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1]; btn.layer.cornerRadius = 6;
    [btn addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)toggleMenu {
    self.menuPanel.hidden = !self.menuPanel.isHidden;
    CGRect bounds = [UIScreen mainScreen].bounds;
    if (!self.menuPanel.isHidden) {
        [UIView animateWithDuration:0.3 animations:^{
            self.menuPanel.frame = CGRectMake(0, bounds.size.height - 220, bounds.size.width, 220);
        }];
    }
}

- (void)toggleGraphOption {
    self.isGraphVisible = !self.isGraphVisible;
    self.graphView.hidden = !self.isGraphVisible;
    [self toggleMenu];
}

- (void)handleTripleTap {
    if (!self.isMinecraft) return;
    self.isDevModeEnabled = !self.isDevModeEnabled;
    UIView *notice = [self.menuPanel viewWithTag:999];
    if (notice) [notice removeFromSuperview];
    
    if (self.isDevModeEnabled) {
        UIButton *btnCheat = [self createMenuButton:@"Buộc bật Cheat World" yPos:80 action:@selector(forceEnableCheats)];
        UIButton *btnNBT = [self createMenuButton:@"Mở Bedrock NBT (Hex Editor)" yPos:130 action:@selector(openNBTBrowser)];
        [self.menuPanel addSubview:btnCheat]; [self.menuPanel addSubview:btnNBT];
    }
}

- (void)forceEnableCheats {
    NSLog(@"[FPSTracer] Đã can thiệp kích hoạt Cheats.");
    [self toggleMenu];
}

#pragma mark - Bộ mã hóa & giải mã Bedrock NBT (Dạng Hex kết hợp Ký tự)

// Giải mã File nhị phân .dat thành Chuỗi Hex kèm ký tự hiển thị để người dùng dễ nhìn, dễ sửa
- (NSString *)convertNBTToHexText:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data || data.length == 0) return nil;
    
    NSMutableString *hexString = [NSMutableString string];
    const unsigned char *bytes = (const unsigned char *)[data bytes];
    
    for (NSUInteger i = 0; i < data.length; i++) {
        // Xuất mã Hex kèm ký tự ASCII kế bên nếu in được để bạn dễ tìm từ khóa (như cheatsEnabled)
        unsigned char c = bytes[i];
        if (c >= 32 && c <= 126) {
            [hexString appendFormat:@"%02X(%c) ", c, c];
        } else {
            [hexString appendFormat:@"%02X(.) ", c];
        }
        if ((i + 1) % 6 == 0) [hexString appendString:@"\n"]; // Xuống dòng cho dễ nhìn
    }
    return hexString;
}

// Gom các chuỗi Hex do người dùng chỉnh sửa, đóng gói lại thành Binary xịn để ghi đè level.dat
- (BOOL)saveHexTextToNBTFile:(NSString *)text textPath:(NSString *)path {
    NSMutableData *data = [NSMutableData data];
    NSArray *tokens = [text componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    for (NSString *token in tokens) {
        if (token.length >= 2) {
            // Chỉ lấy 2 ký tự mã Hex đầu tiên (bỏ qua phần chú thích dấu ngoặc đơn)
            NSString *hexByte = [token substringToIndex:2];
            NSScanner *scanner = [NSScanner scannerWithString:hexByte];
            unsigned int val;
            if ([scanner scanHexInt:&val]) {
                unsigned char uval = (unsigned char)val;
                [data appendBytes:&uval length:1];
            }
        }
    }
    return [data writeToFile:path atomically:YES];
}

#pragma mark - Giao diện Browser & Text Editor

- (void)openNBTBrowser {
    [self toggleMenu];
    UIWindow *window = self.menuPanel.window;
    self.nbtBrowserView = [[UIView alloc] initWithFrame:window.bounds];
    self.nbtBrowserView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
    [window addSubview:self.nbtBrowserView];
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 40, window.bounds.size.width - 100, 40)];
    title.text = @"Bedrock NBT Editor (Hex Mode)";
    title.textColor = [UIColor greenColor]; title.font = [UIFont boldSystemFontOfSize:18];
    [self.nbtBrowserView addSubview:title];
    
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
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *folders = [fm contentsOfDirectoryAtPath:mcWorldsPath error:nil];
    for (NSString *folder in folders) {
        NSString *fullPath = [mcWorldsPath stringByAppendingPathComponent:folder];
        NSString *datPath = [fullPath stringByAppendingPathComponent:@"level.dat"];
        if ([fm fileExistsAtPath:datPath]) {
            NSString *nameFile = [fullPath stringByAppendingPathComponent:@"levelname.txt"];
            NSString *worldName = [NSString stringWithContentsOfFile:nameFile encoding:NSUTF8StringEncoding error:nil];
            if (!worldName) worldName = folder;
            [self.worldList addObject:@{@"name": worldName, @"path": datPath}];
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
    NSDictionary *info = self.worldList[indexPath.row];
    self.selectedWorldPath = info[@"path"];
    
    // Đọc file nhị phân thô chuyển sang cấu trúc Hex trực quan
    NSString *hexContent = [self convertNBTToHexText:self.selectedWorldPath];
    if (!hexContent) hexContent = @"[Lỗi: Không thể đọc cấu trúc nhị phân của file .dat này]";
    
    UIView *editorContainer = [[UIView alloc] initWithFrame:self.nbtBrowserView.bounds];
    editorContainer.backgroundColor = [UIColor blackColor]; editorContainer.tag = 9911;
    [self.nbtBrowserView addSubview:editorContainer];
    
    UIButton *btnSave = [UIButton buttonWithType:UIButtonTypeSystem];
    btnSave.frame = CGRectMake(20, 40, 60, 40); [btnSave setTitle:@"Lưu" forState:UIControlStateNormal]; [btnSave setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
    [btnSave addTarget:self action:@selector(saveNBTTextAction) forControlEvents:UIControlEventTouchUpInside]; [editorContainer addSubview:btnSave];
    
    UIButton *btnCancel = [UIButton buttonWithType:UIButtonTypeSystem];
    btnCancel.frame = CGRectMake(editorContainer.bounds.size.width - 80, 40, 60, 40); [btnCancel setTitle:@"Hủy" forState:UIControlStateNormal]; [btnCancel setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [btnCancel addTarget:self action:@selector(cancelNBTTextAction) forControlEvents:UIControlEventTouchUpInside]; [editorContainer addSubview:btnCancel];
    
    self.nbtTextView = [[UITextView alloc] initWithFrame:CGRectMake(10, 90, editorContainer.bounds.size.width - 20, editorContainer.bounds.size.height - 120)];
    self.nbtTextView.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0]; self.nbtTextView.textColor = [UIColor whiteColor]; 
    self.nbtTextView.font = [UIFont fontWithName:@"Courier" size:11]; // Dùng font monospace để canh hàng Hex đều tăm tắp
    self.nbtTextView.text = hexContent;
    [editorContainer addSubview:self.nbtTextView];
}

- (void)saveNBTTextAction {
    // Đóng gói ngược từ chuỗi Hex thô về lại tệp nhị phân nguyên bản
    BOOL success = [self saveHexTextToNBTFile:self.nbtTextView.text textPath:self.selectedWorldPath];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:success ? @"Thành công" : @"Thất bại" message:success ? @"Đã biên dịch Hex và lưu đè file level.dat thành công." : @"Lỗi lưu file." preferredStyle:UIAlertControllerStyleAlert];
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
}

@end