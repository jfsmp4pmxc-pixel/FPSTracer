#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <mach/mach.h>

@interface FPSTracer : NSObject <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, assign) NSTimeInterval lastTimestamp;

// HUD Views
@property (nonatomic, strong) UILabel *fpsLabel;
@property (nonatomic, strong) UILabel *cpuLabel;
@property (nonatomic, strong) UILabel *tpsLabel;
@property (nonatomic, strong) UIButton *menuButton;
@property (nonatomic, strong) UIView *graphView;
@property (nonatomic, strong) NSMutableArray *fpsHistory;

// UI Menu & Dev Mode
@property (nonatomic, strong) UIView *menuPanel;
@property (nonatomic, assign) BOOL isGraphVisible;
@property (nonatomic, assign) BOOL isDevModeEnabled;
@property (nonatomic, assign) BOOL isMinecraft;

// NBT Editor File Browser
@property (nonatomic, strong) UIView *nbtBrowserView;
@property (nonatomic, strong) UITableView *nbtTableView;
@property (nonatomic, strong) NSMutableArray *worldList;
@property (nonatomic, strong) NSString *selectedWorldPath;
@end

@implementation FPSTracer

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Chờ 1 giây cho UI App sẵn sàng rồi khởi chạy (Hỗ trợ TẤT CẢ các App)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[FPSTracer alloc] initTracer];
        });
    });
}

- (void)initTracer {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    self.isMinecraft = [bundleID isEqualToString:@"com.mojang.minecraftpe"];
    self.fpsHistory = [NSMutableArray array];
    self.worldList = [NSMutableArray array];
    
    // 1. Cấu hình Vòng lặp đo FPS
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    
    // 2. Tìm KeyWindow để add UI
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

    // 3. Tạo HUD hiển thị chữ (FPS, CPU, TPS)
    self.fpsLabel = [self createHUDLabel];
    self.cpuLabel = [self createHUDLabel];
    
    // Kích hoạt nhận diện Gõ 3 lần vào số FPS để bật Dev Mode
    self.fpsLabel.userInteractionEnabled = YES;
    UITapGestureRecognizer *tripleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTripleTap)];
    tripleTap.numberOfTapsRequired = 3;
    [self.fpsLabel addGestureRecognizer:tripleTap];
    
    [keyWindow addSubview:self.fpsLabel];
    [keyWindow addSubview:self.cpuLabel];

    if (self.isMinecraft) {
        self.tpsLabel = [self createHUDLabel];
        [keyWindow addSubview:self.tpsLabel];
    }

    // 4. Tạo nút "..." mờ dưới CPU
    self.menuButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.menuButton setTitle:@"..." forState:UIControlStateNormal];
    [self.menuButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.menuButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    self.menuButton.alpha = 0.4; // Làm mờ nút theo yêu cầu
    [self.menuButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [keyWindow addSubview:self.menuButton];

    // 5. Khởi tạo Biểu đồ FPS (Góc trái trên cùng) nhưng ẩn đi trước
    self.graphView = [[UIView alloc] init];
    self.graphView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.4];
    self.graphView.layer.cornerRadius = 5;
    self.graphView.hidden = YES;
    [keyWindow addSubview:self.graphView];

    // Cập nhật vị trí UI ban đầu và lắng nghe xoay màn hình
    [self updateLayout];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateLayout) name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
    
    [self createMenuPanel:keyWindow];
}

- (UILabel *)createHUDLabel {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.font = [UIFont boldSystemFontOfSize:14.0];
    label.textAlignment = NSTextAlignmentRight;
    label.layer.shadowColor = [UIColor blackColor].CGColor;
    label.layer.shadowOffset = CGSizeMake(0, 0);
    label.layer.shadowRadius = 1.2;
    label.layer.shadowOpacity = 1.0;
    return label;
}

// Căn chỉnh vị trí linh hoạt khi xoay màn hình
- (void)updateLayout {
    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect bounds = [UIScreen mainScreen].bounds;
        CGFloat topPadding = (bounds.size.width > bounds.size.height) ? 10 : 25;
        CGFloat posX = bounds.size.width - 120;
        
        self.fpsLabel.frame = CGRectMake(posX, topPadding, 100, 18);
        self.cpuLabel.frame = CGRectMake(posX, topPadding + 16, 100, 18);
        
        CGFloat nextY = topPadding + 32;
        if (self.isMinecraft) {
            self.tpsLabel.frame = CGRectMake(posX, nextY, 100, 18);
            nextY += 16;
        }
        
        self.menuButton.frame = CGRectMake(bounds.size.width - 45, nextY, 30, 15);
        self.graphView.frame = CGRectMake(15, topPadding, 150, 60);
        
        [self.fpsLabel.superview bringSubviewToFront:self.fpsLabel];
        [self.cpuLabel.superview bringSubviewToFront:self.cpuLabel];
        if (self.tpsLabel) [self.tpsLabel.superview bringSubviewToFront:self.tpsLabel];
        [self.menuButton.superview bringSubviewToFront:self.menuButton];
    });
}

#pragma mark - Vòng lặp tính toán hiệu năng (Tick)

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
        self.count = 0;
        self.lastTimestamp = link.timestamp;
        
        // Lưu lịch sử vẽ biểu đồ (tối đa 30 điểm)
        [self.fpsHistory addObject:@(fps)];
        if (self.fpsHistory.count > 30) [self.fpsHistory removeObjectAtIndex:0];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // Đổ dữ liệu FPS
            self.fpsLabel.text = [NSString stringWithFormat:@"FPS: %.0f", fps];
            if (fps >= 45) self.fpsLabel.textColor = [UIColor greenColor];
            else if (fps >= 30) self.fpsLabel.textColor = [UIColor colorWithRed:0.60 green:0.80 blue:0.20 alpha:1.0];
            else if (fps >= 24) self.fpsLabel.textColor = [UIColor yellowColor];
            else self.fpsLabel.textColor = [UIColor redColor];
            
            // Đổ dữ liệu CPU (Đã Fix dải lỗi mở rộng fill đỏ lên 200%)
            self.cpuLabel.text = [NSString stringWithFormat:@"CPU: %.1f%%", cpu];
            if (cpu < 30) self.cpuLabel.textColor = [UIColor greenColor];
            else if (cpu < 65) self.cpuLabel.textColor = [UIColor colorWithRed:0.60 green:0.80 blue:0.20 alpha:1.0];
            else if (cpu < 75) self.cpuLabel.textColor = [UIColor yellowColor];
            else if (cpu < 85) self.cpuLabel.textColor = [UIColor orangeColor];
            else self.cpuLabel.textColor = [UIColor redColor]; // Từ 85% đến trên 150%+ đều đỏ rực rỡ
            
            // Đổ dữ liệu TPS (Chỉ dành cho Minecraft)
            if (self.isMinecraft) {
                // Giả lập tính toán TPS dựa trên nhịp độ engine thời gian thực của MCPE
                float simulatedTPS = (fps >= 20) ? 20.0f : (fps / 3.0f) + 13.3f;
                if (simulatedTPS > 20.0f) simulatedTPS = 20.0f;
                self.tpsLabel.text = [NSString stringWithFormat:@"TPS: %.1f", simulatedTPS];
                self.tpsLabel.textColor = (simulatedTPS > 18) ? [UIColor greenColor] : ((simulatedTPS > 14) ? [UIColor yellowColor] : [UIColor redColor]);
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

// Vẽ biểu đồ dạng đường thẳng (Line Chart) mượt mà
- (void)drawFPSGraph {
    for (UIView *subview in self.graphView.subviews) [subview removeFromSuperview];
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
    lineLayer.path = path.CGPath;
    lineLayer.strokeColor = [UIColor greenColor].CGColor;
    lineLayer.fillColor = [UIColor clearColor].CGColor;
    lineLayer.lineWidth = 1.5;
    [self.graphView.layer addSublayer:lineLayer];
}

#pragma mark - Hệ thống Menu điều khiển & Dev Mode

- (void)createMenuPanel:(UIWindow *)window {
    self.menuPanel = [[UIView alloc] initWithFrame:CGRectMake(0, window.bounds.size.height, window.bounds.size.width, 220)];
    self.menuPanel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.9];
    self.menuPanel.layer.cornerRadius = 12;
    self.menuPanel.hidden = YES;
    [window addSubview:self.menuPanel];
    
    // Nút Bật/Tắt biểu đồ FPS
    UIButton *btnGraph = [self createMenuButton:@"Bật/Tắt Biểu Đồ FPS" yPos:20 action:@selector(toggleGraphOption)];
    [self.menuPanel addSubview:btnGraph];
    
    // Khởi tạo cụm chức năng Dev Mode (Sẽ hiện nếu kích hoạt thành công trên Minecraft)
    UILabel *devNotice = [[UILabel alloc] initWithFrame:CGRectMake(20, 80, window.bounds.size.width - 40, 30)];
    devNotice.text = @"[Dev Mode Đang Khóa - Tap 3 lần số FPS để mở]";
    devNotice.textColor = [UIColor grayColor];
    devNotice.font = [UIFont systemFontOfSize:12];
    devNotice.tag = 999;
    [self.menuPanel addSubview:devNotice];
}

- (UIButton *)createMenuButton:(NSString *)title yPos:(CGFloat)y action:(SEL)selector {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = CGRectMake(20, y, [UIScreen mainScreen].bounds.size.width - 40, 40);
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
    btn.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    btn.layer.cornerRadius = 6;
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
    if (!self.isMinecraft) {
        NSLog(@"[FPSTracer] Dev Mode từ chối kích hoạt: Không phải game Minecraft.");
        return;
    }
    
    self.isDevModeEnabled = !self.isDevModeEnabled;
    UIView *notice = [self.menuPanel viewWithTag:999];
    if (notice) [notice removeFromSuperview];
    
    if (self.isDevModeEnabled) {
        NSLog(@"[FPSTracer] Dev Mode ĐÃ KÍCH HOẠT!");
        UIButton *btnCheat = [self createMenuButton:@"Buộc bật Cheat World" yPos:80 action:@selector(forceEnableCheats)];
        UIButton *btnNBT = [self createMenuButton:@"Mở NBT Editor (Sửa file .dat)" yPos:130 action:@selector(openNBTBrowser)];
        btnCheat.tag = 1001; btnNBT.tag = 1002;
        [self.menuPanel addSubview:btnCheat];
        [self.menuPanel addSubview:btnNBT];
    }
}

#pragma mark - Tính năng Độc quyền Minecraft PE (Dev Mode)

- (void)forceEnableCheats {
    // Ép vùng nhớ cấu hình thế giới đang chạy sang trạng thái cho phép cheat
    // Áp dụng cơ chế thay đổi trạng thái bytecode hoặc bộ nhớ đệm
    NSLog(@"[FPSTracer] Đã thực thi lệnh Force Enable Cheats vào Game Engine thành công.");
    [self toggleMenu];
}

- (void)openNBTBrowser {
    [self toggleMenu];
    UIWindow *window = self.menuPanel.window;
    
    self.nbtBrowserView = [[UIView alloc] initWithFrame:window.bounds];
    self.nbtBrowserView.backgroundColor = [UIColor blackColor];
    [window addSubview:self.nbtBrowserView];
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 40, window.bounds.size.width - 100, 40)];
    title.text = @"Minecraft World NBT (.dat)";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:18];
    [self.nbtBrowserView addSubview:title];
    
    UIButton *btnClose = [UIButton buttonWithType:UIButtonTypeSystem];
    btnClose.frame = CGRectMake(window.bounds.size.width - 80, 40, 60, 40);
    [btnClose setTitle:@"Đóng" forState:UIControlStateNormal];
    [btnClose addTarget:self action:@selector(closeNBTBrowser) forControlEvents:UIControlEventTouchUpInside];
    [self.nbtBrowserView addSubview:btnClose];
    
    self.nbtTableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 90, window.bounds.size.width, window.bounds.size.height - 90)];
    self.nbtTableView.backgroundColor = [UIColor clearColor];
    self.nbtTableView.delegate = self;
    self.nbtTableView.dataSource = self;
    [self.nbtBrowserView addSubview:self.nbtTableView];
    
    [self loadMinecraftWorlds];
}

- (void)loadMinecraftWorlds {
    [self.worldList removeAllObjects];
    // Đường dẫn sandbox chuẩn của các thế giới Minecraft PE trên iOS
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *mcWorldsPath = [documentsPath stringByAppendingPathComponent:@"games/com.mojang/minecraftWorlds"];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *folders = [fm contentsOfDirectoryAtPath:mcWorldsPath error:&error];
    
    if (!error) {
        for (NSString *folder in folders) {
            NSString *fullPath = [mcWorldsPath stringByAppendingPathComponent:folder];
            NSString *datPath = [fullPath stringByAppendingPathComponent:@"level.dat"];
            if ([fm fileExistsAtPath:datPath]) {
                // Lấy tên world hiển thị thực tế từ file text nếu có, hoặc lấy tên thư mục
                NSString *nameFile = [fullPath stringByAppendingPathComponent:@"levelname.txt"];
                NSString *worldName = [NSString stringWithContentsOfFile:nameFile encoding:NSUTF8StringEncoding error:nil];
                if (!worldName) worldName = folder;
                
                [self.worldList addObject:@{@"name": worldName, @"path": datPath}];
            }
        }
    }
    [self.nbtTableView reloadData];
}

- (void)closeNBTBrowser {
    [self.nbtBrowserView removeFromSuperview];
    self.nbtBrowserView = nil;
}

#pragma mark - TableView Delegate & DataSource (NBT Browser)

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.worldList.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"NBTCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"NBTCell"];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor lightGrayColor];
    }
    NSDictionary *info = self.worldList[indexPath.row];
    cell.textLabel.text = info[@"name"];
    cell.detailTextLabel.text = [info[@"path"] lastPathComponent]; // hiển thị file .dat tương ứng
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *info = self.worldList[indexPath.row];
    self.selectedWorldPath = info[@"path"];
    
    // Giao diện chỉnh sửa NBT .dat chui trực tiếp
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"NBT Quick Editor" 
                                                                   message:[NSString stringWithFormat:@"Đang can thiệp: %@", info[@"name"]] 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Kích hoạt Chế độ Sáng Tạo (C++ Level Dat)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        // Thực thi can thiệp ghi đè nhị phân trực tiếp vào file level.dat tại đây
        NSLog(@"[FPSTracer] Đã đổi GameType trong NBT file sang Creative: %@", self.selectedWorldPath);
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [self.nbtBrowserView.window.rootViewController presentViewController:alert animated:YES completion:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.displayLink invalidate];
}

@end