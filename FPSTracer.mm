#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

@interface FPSTracer : NSObject
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, assign) NSTimeInterval lastTimestamp;
@property (nonatomic, strong) UILabel *fpsLabel;
@end

@implementation FPSTracer

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Kiểm tra Bundle ID của ứng dụng hiện tại
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if ([bundleID isEqualToString:@"com.mojang.minecraftpe"]) {
            NSLog(@"[FPSTracer] Minecraft PE detected! Injecting FPS Tracker...");
            // Khởi tạo tracker trên main thread sau khi ứng dụng sẵn sàng
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [[FPSTracer alloc] initTracer];
            });
        } else {
            NSLog(@"[FPSTracer] App: %@ is not Minecraft PE. Skipping...", bundleID);
        }
    });
}

- (void)initTracer {
    // 1. Khởi tạo CADisplayLink để đo FPS chính xác
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    self.lastTimestamp = 0;
    self.count = 0;

    // 2. Tạo UI Label để hiển thị số FPS độc lập
    UIWindow *keyWindow = nil;
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                keyWindow = scene.windows.firstObject;
                break;
            }
        }
    }
    if (!keyWindow) {
        keyWindow = [UIApplication sharedApplication].keyWindow;
    }

    if (keyWindow) {
        // Tạo label hiển thị số ở góc trên bên phải
        self.fpsLabel = [[UILabel alloc] init];
        self.fpsLabel.backgroundColor = [UIColor clearColor]; // Không nền
        self.fpsLabel.font = [UIFont boldSystemFontOfSize:18.0];
        self.fpsLabel.textAlignment = NSTextAlignmentRight;
        
        // Tạo viền đen mỏng cho chữ (bằng cách subclass hoặc dùng thuộc tính layer)
        // Cách tối ưu và mỏng nhẹ nhất cho dylib: sử dụng shadow để tạo hiệu ứng viền mỏng
        self.fpsLabel.layer.shadowColor = [UIColor blackColor].CGColor;
        self.fpsLabel.layer.shadowOffset = CGSizeMake(0, 0);
        self.fpsLabel.layer.shadowRadius = 1.0;
        self.fpsLabel.layer.shadowOpacity = 1.0;
        self.fpsLabel.layer.masksToBounds = NO;
        self.fpsLabel.layer.shouldRasterize = YES;
        self.fpsLabel.layer.rasterizationScale = [UIScreen mainScreen].scale;

        [keyWindow addSubview:self.fpsLabel];
        
        // Cập nhật vị trí ban đầu và lắng nghe sự kiện xoay màn hình
        [self updateLabelPosition];
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(updateLabelPosition) 
                                                     name:UIApplicationDidChangeStatusBarOrientationNotification 
                                                   object:nil];
    }
}

// Hàm tự động tính toán lại vị trí khi xoay màn hình (Auto-rotation)
- (void)updateLabelPosition {
    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        CGFloat statusBarHeight = 0;
        
        // Lấy chiều cao status bar để né tai thỏ/Dynamic Island nếu cần
        if (@available(iOS 13.0, *)) {
            UIWindowScene *scene = (UIWindowScene *)[UIApplication sharedApplication].connectedScenes.anyObject;
            statusBarHeight = scene.statusBarManager.statusBarFrame.size.height;
        } else {
            statusBarHeight = [UIApplication sharedApplication].statusBarFrame.size.height;
        }
        
        if (statusBarHeight == 0 || statusBarHeight > 50) {
            statusBarHeight = 20; // Backup nếu là màn hình ngang hoàn toàn mất status bar
        }

        CGFloat labelWidth = 60;
        CGFloat labelHeight = 30;
        
        // Đặt ở góc phải trên cùng, có đệm khoảng cách an toàn (padding)
        CGFloat posX = screenBounds.size.width - labelWidth - 16;
        CGFloat posY = (statusBarHeight > 0 && screenBounds.size.width > screenBounds.size.height) ? 10 : statusBarHeight;

        self.fpsLabel.frame = CGRectMake(posX, posY, labelWidth, labelHeight);
        // Đưa label lên lớp trên cùng để không bị game đè mất
        [self.fpsLabel.superview bringSubviewToFront:self.fpsLabel];
    });
}

- (void)tick:(CADisplayLink *)link {
    if (self.lastTimestamp == 0) {
        self.lastTimestamp = link.timestamp;
        return;
    }
    
    self.count++;
    NSTimeInterval delta = link.timestamp - self.lastTimestamp;
    
    if (delta >= 1.0) {
        double fps = self.count / delta;
        self.count = 0;
        self.lastTimestamp = link.timestamp;
        
        // Cập nhật UI trên Main Thread
        dispatch_async(dispatch_get_main_queue(), ^{
            self.fpsLabel.text = [NSString stringWithFormat:@"%.0f", fps];
            
            // Đổi màu theo logic yêu cầu
            if (fps >= 45 && fps <= 60) {
                self.fpsLabel.textColor = [UIColor greenColor]; // Xanh lá
            } 
            else if (fps >= 30 && fps < 45) {
                // Màu vàng xanh (Lime/Yellow-Green)
                self.fpsLabel.textColor = [UIColor colorWithRed:0.60 green:0.80 blue:0.20 alpha:1.0]; 
            } 
            else if (fps >= 24 && fps < 30) {
                self.fpsLabel.textColor = [UIColor yellowColor]; // Vàng
            } 
            else if (fps >= 0 && fps < 24) {
                self.fpsLabel.textColor = [UIColor redColor]; // Đỏ
            } else {
                // Trường hợp màn hình ProMotion 120Hz (FPS > 60)
                self.fpsLabel.textColor = [UIColor greenColor];
            }
        });
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.displayLink invalidate];
}

@end
