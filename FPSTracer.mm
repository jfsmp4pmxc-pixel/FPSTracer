#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <mach/processor_info.h>

@interface FPSTracer : NSObject
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, assign) NSTimeInterval lastTimestamp;
@property (nonatomic, strong) UILabel *fpsLabel;
@property (nonatomic, strong) UILabel *cpuLabel;
@end

@implementation FPSTracer

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if ([bundleID isEqualToString:@"com.mojang.minecraftpe"]) {
            NSLog(@"[FPSTracer] Minecraft PE detected! Injecting HUD (FPS, CPU)...");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [[FPSTracer alloc] initTracer];
            });
        }
    });
}

// Hàm lấy phần trăm CPU đang sử dụng của App
- (float)getCPUUsage {
    thread_array_t threadList;
    mach_msg_type_number_t threadCount;
    thread_info_data_t threadInfo;
    mach_msg_type_number_t threadInfoCount;
    thread_basic_info_t basicInfoCpu;
    
    if (task_threads(mach_task_self(), &threadList, &threadCount) != KERN_SUCCESS) {
        return 0.0f;
    }
    
    float totalCpu = 0;
    for (int j = 0; j < threadCount; j++) {
        threadInfoCount = THREAD_INFO_MAX;
        if (thread_info(threadList[j], THREAD_BASIC_INFO, (thread_info_t)threadInfo, &threadInfoCount) == KERN_SUCCESS) {
            basicInfoCpu = (thread_basic_info_t)threadInfo;
            if (!(basicInfoCpu->flags & TH_FLAGS_IDLE)) {
                totalCpu += basicInfoCpu->cpu_usage / (float)TH_USAGE_SCALE * 100.0f;
            }
        }
    }
    
    vm_deallocate(mach_task_self(), (vm_address_t)threadList, threadCount * sizeof(thread_t));
    return totalCpu;
}

// Logic màu sắc cho CPU (0 -> 30 xanh, 30 -> 65 xanh vàng, 65 -> 75 vàng, 75 -> 85 cam, 85 -> 100 đỏ)
- (UIColor *)getColorForUsage:(float)percentage {
    if (percentage >= 0 && percentage < 30) {
        return [UIColor greenColor];
    } else if (percentage >= 30 && percentage < 65) {
        return [UIColor colorWithRed:0.60 green:0.80 blue:0.20 alpha:1.0]; // Xanh vàng
    } else if (percentage >= 65 && percentage < 75) {
        return [UIColor yellowColor];
    } else if (percentage >= 75 && percentage < 85) {
        return [UIColor orangeColor];
    } else if (percentage >= 85 && percentage <= 100) {
        return [UIColor redColor];
    }
    return [UIColor greenColor];
}

- (void)initTracer {
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    self.lastTimestamp = 0;
    self.count = 0;

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

    if (keyWindow) {
        self.fpsLabel = [[UILabel alloc] init];
        self.cpuLabel = [[UILabel alloc] init];
        
        NSArray *labels = @[self.fpsLabel, self.cpuLabel];
        for (UILabel *label in labels) {
            label.backgroundColor = [UIColor clearColor];
            label.font = [UIFont boldSystemFontOfSize:15.0];
            label.textAlignment = NSTextAlignmentRight;
            
            label.layer.shadowColor = [UIColor blackColor].CGColor;
            label.layer.shadowOffset = CGSizeMake(0, 0);
            label.layer.shadowRadius = 1.2;
            label.layer.shadowOpacity = 1.0;
            label.layer.shouldRasterize = YES;
            label.layer.rasterizationScale = [UIScreen mainScreen].scale;
            
            [keyWindow addSubview:label];
        }
        
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
        CGFloat statusBarHeight = 20;
        
        if (@available(iOS 13.0, *)) {
            UIWindowScene *scene = (UIWindowScene *)[UIApplication sharedApplication].connectedScenes.anyObject;
            if (scene.statusBarManager.statusBarFrame.size.height > 0) {
                statusBarHeight = scene.statusBarManager.statusBarFrame.size.height;
            }
        }
        
        if (statusBarHeight > 50) statusBarHeight = 20;

        CGFloat labelWidth = 110;
        CGFloat labelHeight = 20;
        CGFloat posX = screenBounds.size.width - labelWidth - 16;
        CGFloat posY = (screenBounds.size.width > screenBounds.size.height) ? 10 : statusBarHeight;

        // Xếp 2 dòng gọn gàng ở góc trên cùng bên phải
        self.fpsLabel.frame = CGRectMake(posX, posY, labelWidth, labelHeight);
        self.cpuLabel.frame = CGRectMake(posX, posY + 18, labelWidth, labelHeight);
        
        [self.fpsLabel.superview bringSubviewToFront:self.fpsLabel];
        [self.cpuLabel.superview bringSubviewToFront:self.cpuLabel];
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
        float cpuUsage = [self getCPUUsage];
        
        self.count = 0;
        self.lastTimestamp = link.timestamp;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // 1. Cập nhật FPS
            self.fpsLabel.text = [NSString stringWithFormat:@"FPS: %.0f", fps];
            if (fps >= 45) self.fpsLabel.textColor = [UIColor greenColor];
            else if (fps >= 30) self.fpsLabel.textColor = [UIColor colorWithRed:0.60 green:0.80 blue:0.20 alpha:1.0];
            else if (fps >= 24) self.fpsLabel.textColor = [UIColor yellowColor];
            else self.fpsLabel.textColor = [UIColor redColor];
            
            // 2. Cập nhật CPU
            self.cpuLabel.text = [NSString stringWithFormat:@"CPU: %.1f%%", cpuUsage];
            self.cpuLabel.textColor = [self getColorForUsage:cpuUsage];
            
            [self.fpsLabel.superview bringSubviewToFront:self.fpsLabel];
            [self.cpuLabel.superview bringSubviewToFront:self.cpuLabel];
        });
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.displayLink invalidate];
    if ([super respondsToSelector:@selector(dealloc)]) {
        [super dealloc];
    }
}

@end