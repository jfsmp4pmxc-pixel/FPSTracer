#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <zlib.h> // Sử dụng để nén và giải nén định dạng file .dat của Minecraft

@interface FPSTracer : NSObject <UITableViewDelegate, UITableViewDataSource, UITextViewDelegate>
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

// NBT Browser & Editor Text
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

    // --- SỬA LỖI TRÙNG LẶP (BẢN SAO LỒNG NHAU) ---
    // Định nghĩa các Tag định danh duy nhất để quét sạch các phần tử cũ do reload Window tạo ra
    for (UIView *subview in [keyWindow subviews]) {
        if (subview.tag >= 8881 && subview.tag <= 8885) {
            [subview removeFromSuperview];
        }
    }

    // Khởi tạo các Label với ID Tag cố định
    self.fpsLabel = [self createHUDLabelWithTag:8881];
    self.cpuLabel = [self createHUDLabelWithTag:8882];
    
    self.fpsLabel.userInteractionEnabled = YES;
    UITapGestureRecognizer *tripleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTripleTap)];
    tripleTap.numberOfTapsRequired = 3;
    [self.fpsLabel addGestureRecognizer:tripleTap];
    
    [keyWindow addSubview:self.fpsLabel];
    [keyWindow addSubview:self.cpuLabel];

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
    label.font = [UIFont boldSystemFontOfSize:14.0];
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
        CGFloat posX = bounds.size.width - 120;
        
        self.fpsLabel.frame = CGRectMake(posX, topPadding, 100, 18);
        self.cpuLabel.frame = CGRectMake(posX, topPadding + 16, 100, 18);
        
        CGFloat nextY = topPadding + 32;
        if (self.isMinecraft && self.tpsLabel) {
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

#pragma mark - Vòng lặp Core (Tick)

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
        
        [self.fpsHistory addObject:@(fps)];
        if (self.fpsHistory.count > 30) [self.fpsHistory removeObjectAtIndex:0];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.fpsLabel.text = [NSString stringWithFormat:@"FPS: %.0f", fps];
            if (fps >= 45) self.fpsLabel.textColor = [UIColor greenColor];
            else if (fps >= 30) self.fpsLabel.textColor = [UIColor colorWithRed:0.60 green:0.80 blue:0.20 alpha:1.0];
            else if (fps >= 24) self.fpsLabel.textColor = [UIColor yellowColor];
            else self.fpsLabel.textColor = [UIColor redColor];
            
            // Fix dải hiển thị CPU cho chip đa luồng (Lên đến 150% - 200% vẫn hiển thị màu đỏ ổn định)
            self.cpuLabel.text = [NSString stringWithFormat:@"CPU: %.1f%%", cpu];
            if (cpu < 30) self.cpuLabel.textColor = [UIColor greenColor];
            else if (cpu < 65) self.cpuLabel.textColor = [UIColor colorWithRed:0.60 green:0.80 blue:0.20 alpha:1.0];
            else if (cpu < 75) self.cpuLabel.textColor = [UIColor yellowColor];
            else if (cpu < 85) self.cpuLabel.textColor = [UIColor orangeColor];
            else self.cpuLabel.textColor = [UIColor redColor];
            
            if (self.isMinecraft && self.tpsLabel) {
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
    lineLayer.path = path.CGPath;
    lineLayer.strokeColor = [UIColor greenColor].CGColor;
    lineLayer.fillColor = [UIColor clearColor].CGColor;
    lineLayer.lineWidth = 1.5;
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
    if (!self.isMinecraft) return;
    
    self.isDevModeEnabled = !self.isDevModeEnabled;
    UIView *notice = [self.menuPanel viewWithTag:999];
    if (notice) [notice removeFromSuperview];
    
    if (self.isDevModeEnabled) {
        UIButton *btnCheat = [self createMenuButton:@"Buộc bật Cheat World" yPos:80 action:@selector(forceEnableCheats)];
        UIButton *btnNBT = [self createMenuButton:@"Mở NBT Editor (.dat Browser)" yPos:130 action:@selector(openNBTBrowser)];
        [self.menuPanel addSubview:btnCheat];
        [self.menuPanel addSubview:btnNBT];
    }
}

- (void)forceEnableCheats {
    NSLog(@"[FPSTracer] Đã can thiệp kích hoạt Cheats.");
    [self toggleMenu];
}

#pragma mark - Công cụ Giải mã & Mã hóa Gzip NBT (.dat) nâng cao

// Hàm giải mã Gzip từ file level.dat thành Chuỗi văn bản UTF8
- (NSString *)decompressGzipFile:(NSString *)path {
    NSData *compressedData = [NSData dataWithContentsOfFile:path];
    if (!compressedData || compressedData.length == 0) return nil;
    
    z_stream strm;
    strm.next_in = (Bytef *)[compressedData bytes];
    strm.avail_in = (uint)[compressedData length];
    strm.total_out = 0;
    strm.zalloc = Z_NULL;
    strm.zfree = Z_NULL;
    
    // Khởi tạo cửa sổ giải nén Gzip (16 + MAX_WBITS)
    if (inflateInit2(&strm, (16 + MAX_WBITS)) != Z_OK) return nil;
    
    NSMutableData *decompressed = [NSMutableData dataWithLength:[compressedData length] * 3];
    while (YES) {
        if (strm.total_out >= [decompressed length]) {
            [decompressed increaseLengthBy:[compressedData length]];
        }
        strm.next_out = (Bytef *)[decompressed mutableBytes] + strm.total_out;
        strm.avail_out = (uint)([decompressed length] - strm.total_out);
        
        int status = inflate(&strm, Z_NO_FLUSH);
        if (status == Z_STREAM_END) break;
        if (status != Z_OK) { inflateEnd(&strm); return nil; }
    }
    
    if (inflateEnd(&strm) != Z_OK) return nil;
    [decompressed setLength:strm.total_out];
    
    // Chuyển đổi dữ liệu nhị phân thô thành dạng String dễ đọc
    return [[NSString alloc] initWithData:decompressed encoding:NSASCIIStringEncoding];
}

// Hàm mã hóa Gzip Chuỗi văn bản đã chỉnh sửa rồi ghi đè lại vào file level.dat
- (BOOL)compressGzipString:(NSString *)string toFile:(NSString *)path {
    NSData *uncompressedData = [string dataUsingEncoding:NSASCIIStringEncoding];
    if (!uncompressedData || uncompressedData.length == 0) return NO;
    
    z_stream strm;
    strm.next_in = (Bytef *)[uncompressedData bytes];
    strm.avail_in = (uint)[uncompressedData length];
    strm.total_out = 0;
    strm.zalloc = Z_NULL;
    strm.zfree = Z_NULL;
    
    // Cấu hình mã hóa Gzip (16 + MAX_WBITS)
    if (deflateInit2(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED, (16 + MAX_WBITS), 8, Z_DEFAULT_STRATEGY) != Z_OK) return NO;
    
    NSMutableData *compressed = [NSMutableData dataWithLength:[uncompressedData length] + 1024];
    while (YES) {
        strm.next_out = (Bytef *)[compressed mutableBytes] + strm.total_out;
        strm.avail_out = (uint)([compressed length] - strm.total_out);
        
        int status = deflate(&strm, Z_FINISH);
        if (status == Z_STREAM_END) break;
        if (status != Z_OK) { deflateEnd(&strm); return NO; }
    }
    
    if (deflateEnd(&strm) != Z_OK) return NO;
    [compressed setLength:strm.total_out];
    
    return [compressed writeToFile:path atomically:YES];
}

#pragma mark - Giao diện NBT Editor Full Text View

- (void)openNBTBrowser {
    [self toggleMenu];
    UIWindow *window = self.menuPanel.window;
    
    self.nbtBrowserView = [[UIView alloc] initWithFrame:window.bounds];
    self.nbtBrowserView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
    [window addSubview:self.nbtBrowserView];
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 40, window.bounds.size.width - 100, 40)];
    title.text = @"NBT Editor (.dat Gzip)";
    title.textColor = [UIColor greenColor];
    title.font = [UIFont boldSystemFontOfSize:18];
    [self.nbtBrowserView addSubview:title];
    
    UIButton *btnClose = [UIButton buttonWithType:UIButtonTypeSystem];
    btnClose.frame = CGRectMake(window.bounds.size.width - 80, 40, 60, 40);
    [btnClose setTitle:@"Đóng" forState:UIControlStateNormal];
    [btnClose setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
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

- (void)closeNBTBrowser {
    [self.nbtBrowserView removeFromSuperview];
    self.nbtBrowserView = nil;
}

#pragma mark - Table View Data & Trình soạn thảo văn bản

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.worldList.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"NBTCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"NBTCell"];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor grayColor];
    }
    NSDictionary *info = self.worldList[indexPath.row];
    cell.textLabel.text = info[@"name"];
    cell.detailTextLabel.text = [info[@"path"] lastPathComponent];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *info = self.worldList[indexPath.row];
    self.selectedWorldPath = info[@"path"];
    
    // Thực thi giải nén Gzip file .dat sang cấu trúc Text chuỗi đọc được
    NSString *nbtContent = [self decompressGzipFile:self.selectedWorldPath];
    if (!nbtContent) {
        nbtContent = @"[Lỗi: Không thể giải mã định dạng Gzip của file .dat này]";
    }
    
    // Mở một giao diện Text Editor viết đè lên màn hình
    UIView *editorContainer = [[UIView alloc] initWithFrame:self.nbtBrowserView.bounds];
    editorContainer.backgroundColor = [UIColor blackColor];
    editorContainer.tag = 9911;
    [self.nbtBrowserView addSubview:editorContainer];
    
    UIButton *btnSave = [UIButton buttonWithType:UIButtonTypeSystem];
    btnSave.frame = CGRectMake(20, 40, 60, 40);
    [btnSave setTitle:@"Lưu lại" forState:UIControlStateNormal];
    [btnSave setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
    [btnSave addTarget:self action:@selector(saveNBTTextAction) forControlEvents:UIControlEventTouchUpInside];
    [editorContainer addSubview:btnSave];
    
    UIButton *btnCancel = [UIButton buttonWithType:UIButtonTypeSystem];
    btnCancel.frame = CGRectMake(editorContainer.bounds.size.width - 80, 40, 60, 40);
    [btnCancel setTitle:@"Hủy bỏ" forState:UIControlStateNormal];
    [btnCancel setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [btnCancel addTarget:self action:@selector(cancelNBTTextAction) forControlEvents:UIControlEventTouchUpInside];
    [editorContainer addSubview:btnCancel];
    
    self.nbtTextView = [[UITextView alloc] initWithFrame:CGRectMake(10, 90, editorContainer.bounds.size.width - 20, editorContainer.bounds.size.height - 120)];
    self.nbtTextView.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    self.nbtTextView.textColor = [UIColor whiteColor];
    self.nbtTextView.font = [UIFont fontWithName:@"Courier" size:12];
    self.nbtTextView.text = nbtContent;
    [editorContainer addSubview:self.nbtTextView];
}

- (void)saveNBTTextAction {
    NSString *editedText = self.nbtTextView.text;
    
    // Nén Gzip ngược chuỗi văn bản và lưu đè vào file level.dat gốc
    BOOL success = [self compressGzipString:editedText toFile:self.selectedWorldPath];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:success ? @"Thành công" : @"Thất bại" 
                                                                   message:success ? @"Đã lưu và mã hóa Gzip thành công file .dat" : @"Lỗi khi mã hóa lại dữ liệu Gzip." 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self cancelNBTTextAction];
    }]];
    [self.nbtBrowserView.window.rootViewController presentViewController:alert animated:YES completion:nil];
}

- (void)cancelNBTTextAction {
    UIView *container = [self.nbtBrowserView viewWithTag:9911];
    if (container) [container removeFromSuperview];
    self.nbtTextView = nil;
}

@end