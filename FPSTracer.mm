#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <mach/mach.h> // Thư viện để lấy thông tin RAM hệ thống

@interface FPSTracer : NSObject
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, assign) NSTimeInterval lastTimestamp;
@property (nonatomic, strong) UILabel *infoLabel; // Đổi thành infoLabel để chứa cả FPS và RAM
@end

@implementation FPSTracer

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if ([bundleID isEqualToString:@"com.mojang.minecraftpe"]) {
            NSLog(@"[FPSTracer] Minecraft PE detected! Injecting FPS & RAM Tracker...");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [[FPSTracer alloc] initTracer];
            });
        } else {
            NSLog(@"[FPSTracer] App: %@ is not Minecraft PE. Skipping...", bundleID);
        }
    });
}

// Hàm lấy dung lượng RAM mà App đang dùng (đơn vị: MB)
- (double)getMemoryUsage {
    task_vm_info_data_t vmInfo;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    kern_return_t kernelReturn = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vmInfo, &count);
    
    if (kernelReturn == KERN_SUCCESS) {
        // phys_footprint chứa lượng RAM thực tế app đang chiếm giữ
        return (double)vmInfo.phys_footprint / (1024.0 * 1024.0);
    }
    return 0.0;
}

- (void)initTracer {
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    self.lastTimestamp = 0;
    self.count = 0;

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
        self.infoLabel = [[UILabel alloc] init];
        self.infoLabel.backgroundColor = [UIColor clearColor];
        self.infoLabel.font = [UIFont boldSystemFontOfSize:16.0]; // Chỉnh nhỏ lại một chút để hiển thị 2 dòng đẹp hơn
        self.infoLabel.textAlignment = NSTextAlignmentRight;
        self.infoLabel.numberOfLines = 2; // Cho phép hiển thị 2 dòng (Dòng 1: FPS, Dòng 2: RAM)
        
        // Tạo viền đen mỏng xung quanh chữ bằng Shadow kỹ thuật cao
        self.infoLabel.layer.shadowColor = [UIColor blackColor].CGColor;
        self.infoLabel.layer.shadowOffset = CGSizeMake(0, 0);
        self.infoLabel.layer.shadowRadius = 1.2;
        self.infoLabel.layer.shadowOpacity = 1.0;
        self.infoLabel.layer.masksToBounds = NO;
        self.infoLabel.layer.shouldRasterize = YES;
        self.infoLabel.layer.rasterizationScale = [UIScreen mainScreen].scale;

        [keyWindow addSubview:self.infoLabel];
        
        [self updateLabelPosition];
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(updateLabelPosition) 
                                                     name:UIApplicationDidChangeStatusBarOrientationNotification 
                                                   object:nil];
    }
}

- (void)updateLabelPosition {
    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        CGFloat statusBarHeight = 0;
        
        if (@available(iOS 13.0, *)) {
            UIWindowScene *scene = (UIWindowScene *)[UIApplication sharedApplication].connectedScenes.anyObject;
            statusBarHeight = scene.statusBarManager.statusBarFrame.size.height;
        } else {
            statusBarHeight = [UIApplication sharedApplication].statusBarFrame.size.height;
        }
        
        if (statusBarHeight == 0 || statusBarHeight > 50) {
            statusBarHeight = 20; 
        }

        // Tăng chiều rộng lên 100 và chiều cao lên 45 để chứa đủ text RAM (ví dụ: "512 MB")
        CGFloat labelWidth = 100;
        CGFloat labelHeight = 45;
        
        CGFloat posX = screenBounds.size.width - labelWidth - 16;
        CGFloat posY = (statusBarHeight > 0 && screenBounds.size.width > screenBounds.size.height) ? 10 : statusBarHeight;

        self.infoLabel.frame = CGRectMake(posX, posY, labelWidth, labelHeight);
        [self.infoLabel.superview bringSubviewToFront:self.infoLabel];
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
        double ramUsed = [self getMemoryUsage]; // Lấy số RAM hiện tại
        
        self.count = 0;
        self.lastTimestamp = link.timestamp;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // Cấu hình chuỗi hiển thị 2 dòng: FPS ở trên, RAM ở dưới
            NSString *fpsText = [NSString stringWithFormat:@"%.0f FPS", fps];
            NSString *ramText = [NSString stringWithFormat:@"%.0f MB", ramUsed];
            
            // Đổi màu chữ của toàn bộ Label theo mức độ FPS như bạn yêu cầu
            UIColor *textColor = [UIColor greenColor];
            if (fps >= 45 && fps <= 60) {
                textColor = [UIColor greenColor];
            } else if (fps >= 30 && fps < 45) {
                textColor = [UIColor colorWithRed:0.60 green:0.80 blue:0.20 alpha:1.0]; // Vàng xanh
            } else if (fps >= 24 && fps < 30) {
                textColor = [UIColor yellowColor];
            } else if (fps >= 0 && fps < 24) {
                textColor = [UIColor redColor];
            }
            
            // Áp dụng text và màu
            self.infoLabel.textColor = textColor;
            self.infoLabel.text = [NSString stringWithFormat:@"%@\n%@", fpsText, ramText];
            
            // Đảm bảo không bị game đè khi load map nặng
            [self.infoLabel.superview bringSubviewToFront:self.infoLabel];
        });
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.displayLink invalidate];
}

@end