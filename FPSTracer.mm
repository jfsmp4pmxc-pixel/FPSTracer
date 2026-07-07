#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

//--- LỚP VIEW CONTROLLER ĐỂ XỬ LÝ XOAY ---
@interface TimerViewController : UIViewController
@end

@implementation TimerViewController
// Cho phép tự động xoay theo mọi hướng thiết bị hỗ trợ
- (BOOL)shouldAutorotate {
    return YES;
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}
@end


//--- LỚP FLOATING TIMER WINDOW ---
@interface FloatingTimerWindow : UIWindow {
    UILabel *_timerLabel;
    NSTimer *_timer;
    CFTimeInterval _startTime;
    CFTimeInterval _elapsedTime;
    
    // Các trạng thái: 0 = Chưa chạy (Đỏ), 1 = Đang chạy (Xanh lá), 2 = Dừng (Xanh biển)
    int _timerState; 
    
    CGPoint _initialTouchPoint;
}
@end

@implementation FloatingTimerWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Thiết lập Window ở lớp cao nhất để đè lên hệ thống
        self.windowLevel = UIWindowLevelAlert + 1000;
        self.backgroundColor = [UIColor clearColor];
        
        // Gán rootViewController để hệ thống tự xử lý xoay màn hình (Autorotate)
        TimerViewController *vc = [[TimerViewController alloc] init];
        vc.view.backgroundColor = [UIColor clearColor];
        vc.view.userInteractionEnabled = NO; // Để sự kiện touch đẩy thẳng ra Window xử lý
        self.rootViewController = vc;
        
        [self setHidden:NO];
        
        // Khởi tạo các giá trị mặc định
        _timerState = 0; 
        _elapsedTime = 0.0;
        
        // Cấu hình Label hiển thị thời gian (Ăn theo bounds của window)
        _timerLabel = [[UILabel alloc] initWithFrame:self.bounds];
        _timerLabel.text = @"00:00.00";
        _timerLabel.font = [UIFont fontWithName:@"Menlo" size:24.0];
        _timerLabel.textAlignment = NSTextAlignmentCenter;
        _timerLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        
        // Không nền, viền chữ đen bằng Shadow đổ viền bóng cứng
        _timerLabel.textColor = [UIColor redColor]; 
        _timerLabel.layer.shadowColor = [[UIColor blackColor] CGColor];
        _timerLabel.layer.shadowOffset = CGSizeZero;
        _timerLabel.layer.shadowRadius = 1.0;
        _timerLabel.layer.shadowOpacity = 1.0;
        
        [self addSubview:_timerLabel];
        
        // Gesture nhận diện Tap để điều khiển timer
        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        [self addGestureRecognizer:tapGesture];
    }
    return self;
}

//--- XỬ LÝ SỰ KIỆN CHẠM VÀO TIMER ---
- (void)handleTap {
    if (_timerState == 0) {
        _timerState = 1;
        _timerLabel.textColor = [UIColor greenColor];
        _startTime = CACurrentMediaTime() - _elapsedTime;
        
        _timer = [NSTimer scheduledTimerWithTimeInterval:0.01 
                                                  target:self 
                                                selector:@selector(updateTimer) 
                                                userInfo:nil 
                                                 repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
        
    } else if (_timerState == 1) {
        _timerState = 2;
        _timerLabel.textColor = [UIColor blueColor];
        [_timer invalidate];
        _timer = nil;
        
    } else if (_timerState == 2) {
        _timerState = 1;
        _timerLabel.textColor = [UIColor greenColor];
        _startTime = CACurrentMediaTime() - _elapsedTime;
        
        _timer = [NSTimer scheduledTimerWithTimeInterval:0.01 
                                                  target:self 
                                                selector:@selector(updateTimer) 
                                                userInfo:nil 
                                                 repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    }
}

//--- CẬP NHẬT ĐỊNH DẠNG TỚI MILIGIÂY ---
- (void)updateTimer {
    _elapsedTime = CACurrentMediaTime() - _startTime;
    
    int minutes = (int)(_elapsedTime / 60);
    int seconds = (int)(_elapsedTime) % 60;
    int fractions = (int)((_elapsedTime - (int)_elapsedTime) * 100);
    
    _timerLabel.text = [NSString stringWithFormat:@"%02d:%02d.%02d", minutes, seconds, fractions];
}

//--- XỬ LÝ KÉO THẢ TỰ ĐỘNG CHUYỂN HƯỚNG THEO MÀN HÌNH ---
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    // Lấy vị trí touch tương đối theo chính window để tránh lệch tọa độ khi xoay
    _initialTouchPoint = [touch locationInView:self];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    CGPoint currentTouchPoint = [touch locationInView:self];
    
    float offsetX = currentTouchPoint.x - _initialTouchPoint.x;
    float offsetY = currentTouchPoint.y - _initialTouchPoint.y;
    
    CGPoint newCenter = CGPointMake(self.center.x + offsetX, self.center.y + offsetY);
    
    // Giới hạn trong vùng an toàn của màn hình hiện tại (Tính cả chiều ngang/dọc)
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    if (newCenter.x < 0) newCenter.x = 0;
    if (newCenter.x > screenSize.width) newCenter.x = screenSize.width;
    if (newCenter.y < 0) newCenter.y = 0;
    if (newCenter.y > screenSize.height) newCenter.y = screenSize.height;
    
    self.center = newCenter;
}

@end

//--- LỚP APP DELEGATE ---
@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) FloatingTimerWindow *timerWindow;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Khởi tạo widget kích thước 160x40
    CGRect timerFrame = CGRectMake(100, 150, 160, 40);
    self.timerWindow = [[FloatingTimerWindow alloc] initWithFrame:timerFrame];
    
    return YES;
}

@end

//--- MAIN ---
int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}