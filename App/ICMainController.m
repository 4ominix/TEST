#import "ICMainController.h"
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <CoreImage/CoreImage.h>
#import <QuartzCore/QuartzCore.h>
#import "ICPaths.h"
#import "ICSettings.h"
#import "ICFrameEngine.h"
#import "ICMediaSource.h"
#import "ICAdjustments.h"
#import <math.h>

@interface ICMainController()<PHPickerViewControllerDelegate>
@property(nonatomic,strong) UIImageView *preview;
@property(nonatomic,strong) UILabel *message;
@property(nonatomic,strong) UILabel *diagnostics;
@property(nonatomic,strong) UIButton *choose;
@property(nonatomic,strong) UISwitch *enabled;
@property(nonatomic,strong) UISwitch *loop;
@property(nonatomic,strong) UISwitch *mirror;
@property(nonatomic,strong) UISwitch *floating;
@property(nonatomic,strong) UISegmentedControl *fit;
@property(nonatomic,strong) UISegmentedControl *rotation;
@property(nonatomic,strong) ICAdjustments *adjustments;
@property(nonatomic,strong) UIStackView *controlsContainer;
@property(nonatomic,strong) NSDictionary *settings;
@property(nonatomic,strong) ICFrameEngine *engine;
@property(nonatomic,strong) CIContext *context;
@property(nonatomic,strong) NSTimer *previewTimer;
@property(nonatomic,strong) NSTimer *statusTimer;
@property(nonatomic,strong) dispatch_queue_t settingsQueue;
@property(nonatomic) BOOL busy;
@property(nonatomic) BOOL booting;
@property(nonatomic) BOOL wantsPreview;
@property(nonatomic) double gestureX;
@property(nonatomic) double gestureY;
@property(nonatomic) double gestureZoom;
@end
@implementation ICMainController
- (UILabel *)label {UILabel *label=[UILabel new];label.numberOfLines=0;label.textColor=UIColor.secondaryLabelColor;label.font=[UIFont systemFontOfSize:13];return label;}
- (UISwitch *)addSwitch:(NSString *)title stack:(UIStackView *)stack {
    UIStackView *row=[UIStackView new];row.axis=UILayoutConstraintAxisHorizontal;
    UILabel *label=[UILabel new];label.text=title;UISwitch *value=[UISwitch new];
    [value addTarget:self action:@selector(change:) forControlEvents:UIControlEventValueChanged];
    [row addArrangedSubview:label];[row addArrangedSubview:value];[stack addArrangedSubview:row];return value;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"iCamV3";self.overrideUserInterfaceStyle=UIUserInterfaceStyleLight;
    self.view.backgroundColor=UIColor.systemBackgroundColor;self.settings=ICDefaults();
    self.settingsQueue=dispatch_queue_create("com.icamv3.rebuild.controller.settings",DISPATCH_QUEUE_SERIAL);
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:scroll];
    UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=14;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:18],[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-18],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-36]]];
    self.preview=[UIImageView new];self.preview.backgroundColor=UIColor.blackColor;self.preview.contentMode=UIViewContentModeScaleAspectFit;
    self.preview.clipsToBounds=YES;self.preview.layer.cornerRadius=16;self.preview.userInteractionEnabled=YES;
    [self.preview.heightAnchor constraintEqualToAnchor:self.preview.widthAnchor multiplier:.75].active=YES;[stack addArrangedSubview:self.preview];
    [self.preview addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)]];
    [self.preview addGestureRecognizer:[[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinch:)]];
    self.choose=[UIButton buttonWithType:UIButtonTypeSystem];[self.choose setTitle:@"Chọn ảnh hoặc video" forState:UIControlStateNormal];self.choose.titleLabel.font=[UIFont boldSystemFontOfSize:20];
    [self.choose addTarget:self action:@selector(pick) forControlEvents:UIControlEventTouchUpInside];[stack addArrangedSubview:self.choose];
    self.enabled=[self addSwitch:@"Bật camera ảo" stack:stack];self.loop=[self addSwitch:@"Lặp video" stack:stack];self.mirror=[self addSwitch:@"Lật ngang" stack:stack];
    self.floating=[self addSwitch:@"Điều khiển nổi" stack:stack];
    self.fit=[[UISegmentedControl alloc] initWithItems:@[@"Fit",@"Fill"]];self.rotation=[[UISegmentedControl alloc] initWithItems:@[@"0°",@"90°",@"180°",@"270°"]];
    for(UISegmentedControl *control in @[self.fit,self.rotation]){[control addTarget:self action:@selector(change:) forControlEvents:UIControlEventValueChanged];[stack addArrangedSubview:control];}
    UIButton *openControls=[UIButton buttonWithType:UIButtonTypeSystem];[openControls setTitle:@"Camera control" forState:UIControlStateNormal];
    [openControls addTarget:self action:@selector(toggleControls) forControlEvents:UIControlEventTouchUpInside];[stack addArrangedSubview:openControls];
    self.adjustments=[ICAdjustments new];self.adjustments.translatesAutoresizingMaskIntoConstraints=NO;
    [self.adjustments.widthAnchor constraintEqualToConstant:194].active=YES;
    // A hidden arranged stack collapses; its child's preferred height must yield.
    NSLayoutConstraint *panelHeight=[self.adjustments.heightAnchor constraintEqualToConstant:238];
    panelHeight.priority=999;panelHeight.active=YES;
    self.controlsContainer=[UIStackView new];self.controlsContainer.axis=UILayoutConstraintAxisVertical;self.controlsContainer.alignment=UIStackViewAlignmentCenter;
    [self.controlsContainer addArrangedSubview:self.adjustments];self.controlsContainer.hidden=YES;[stack addArrangedSubview:self.controlsContainer];
    __weak typeof(self) weakSelf=self;self.adjustments.didChange=^(NSError *error){[weakSelf refreshSettings];weakSelf.message.text=error.localizedDescription?:@"Đã lưu vị trí/zoom.";};
    self.adjustments.didClose=^{weakSelf.controlsContainer.hidden=YES;};
    UIButton *reset=[UIButton buttonWithType:UIButtonTypeSystem];[reset setTitle:@"Đặt lại cấu hình · tắt camera ảo" forState:UIControlStateNormal];
    [reset addTarget:self action:@selector(reset) forControlEvents:UIControlEventTouchUpInside];[stack addArrangedSubview:reset];
    self.message=[self label];self.diagnostics=[self label];self.diagnostics.hidden=YES;[stack addArrangedSubview:self.message];[stack addArrangedSubview:self.diagnostics];
    UIButton *details=[UIButton buttonWithType:UIButtonTypeSystem];[details setTitle:@"Thông tin hoạt động" forState:UIControlStateNormal];
    [details addTarget:self action:@selector(toggleDiagnostics) forControlEvents:UIControlEventTouchUpInside];[stack addArrangedSubview:details];
    UIButton *share=[UIButton buttonWithType:UIButtonTypeSystem];[share setTitle:@"Chia sẻ thông tin hoạt động" forState:UIControlStateNormal];
    [share addTarget:self action:@selector(shareDiagnostics) forControlEvents:UIControlEventTouchUpInside];[stack addArrangedSubview:share];
    self.message.text=@"Giao diện đã mở. Đang kiểm tra bootstrap…";[self sync];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(background:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(foreground:) name:UIApplicationWillEnterForegroundNotification object:nil];
}
- (void)viewDidAppear:(BOOL)animated {[super viewDidAppear:animated];[self start];}
- (void)toggleControls {self.controlsContainer.hidden=!self.controlsContainer.hidden;if(!self.controlsContainer.hidden)[self.adjustments refresh];}
- (void)toggleDiagnostics {self.diagnostics.hidden=!self.diagnostics.hidden;if(!self.diagnostics.hidden)[self readDiagnostics];}
- (void)viewDidDisappear:(BOOL)animated {[super viewDidDisappear:animated];[self stop];}
- (void)background:(NSNotification *)note {[self stop];}
- (void)foreground:(NSNotification *)note {if(self.view.window && !self.presentedViewController)[self start];}
- (void)start {
    self.wantsPreview=YES;
    if(self.booting)return;self.booting=YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSError *error=nil;NSDictionary *settings=ICDefaults();ICFrameEngine *engine=nil;CIContext *context=nil;
        @try {
            settings=ICReadSettings(&error);
            engine=self.engine?:[[ICFrameEngine alloc] initForPreview:YES];
            context=self.context?:[CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer:@NO}];
            if(!context && !error)error=ICError(@"Không khởi tạo được GPU preview.");
        } @catch(NSException *exception) {error=ICError(exception.reason);}
        dispatch_async(dispatch_get_main_queue(),^{
            self.booting=NO;self.settings=settings;self.engine=engine;self.context=context;[self sync];
            self.message.text=error.localizedDescription?:@"Chọn nguồn media. Preview không đồng nghĩa camera hệ thống đã được thay thế.";
            // A stop/picker presentation may have happened during initialization.
            if(!self.wantsPreview || !self.view.window || self.presentedViewController || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive){[engine setSuspended:YES];return;}
            [engine setSuspended:NO];[self.previewTimer invalidate];[self.statusTimer invalidate];
            __weak typeof(self) weakSelf=self;
            self.previewTimer=[NSTimer scheduledTimerWithTimeInterval:1.0/15 repeats:YES block:^(NSTimer *timer){[weakSelf draw];}];
            self.statusTimer=[NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer){[weakSelf refreshSettings];[weakSelf readDiagnostics];}];
            [self readDiagnostics];
        });
    });
}
- (void)stop {self.wantsPreview=NO;[self.previewTimer invalidate];self.previewTimer=nil;[self.statusTimer invalidate];self.statusTimer=nil;[self.engine setSuspended:YES];}
- (void)sync {
    self.enabled.on=[self.settings[@"Enabled"] boolValue];self.loop.on=[self.settings[@"Loop"] boolValue];self.mirror.on=[self.settings[@"Mirror"] boolValue];
    self.floating.on=[self.settings[@"Floating"] boolValue];self.fit.selectedSegmentIndex=[self.settings[@"Fill"] boolValue]?1:0;
    self.rotation.selectedSegmentIndex=[self.settings[@"Rotation"] intValue]/90;if(self.engine)[self.adjustments refresh];
}
- (void)refreshSettings {
    dispatch_async(self.settingsQueue,^{NSDictionary *s=ICReadSettings(NULL);dispatch_async(dispatch_get_main_queue(),^{self.settings=s;[self sync];});});
}
- (void)draw {
    CGSize viewport=self.preview.bounds.size;if(viewport.width<=0 || viewport.height<=0)return;
    size_t height=(size_t)MAX(64,MIN(1920,lround(480*viewport.height/viewport.width)));
    CVPixelBufferRef pixels=[self.engine copyFrameForWidth:480 height:height format:kCVPixelFormatType_32BGRA];
    if(!pixels){self.preview.image=nil;return;}
    CGImageRef rendered=NULL;
    @try {
        CIImage *image=[CIImage imageWithCVPixelBuffer:pixels];rendered=[self.context createCGImage:image fromRect:image.extent];
        if(rendered)self.preview.image=[UIImage imageWithCGImage:rendered];
    } @catch(NSException *error){self.message.text=error.reason;} @finally {if(rendered)CGImageRelease(rendered);CVPixelBufferRelease(pixels);}
}
- (void)edit:(void (^)(NSMutableDictionary *))edit {
    dispatch_async(self.settingsQueue,^{NSError *error=nil;ICUpdateSettings(edit,&error);
        dispatch_async(dispatch_get_main_queue(),^{[self refreshSettings];self.message.text=error.localizedDescription?:@"Đã lưu. Xem số hook và frame ở chẩn đoán để xác nhận camera thực tế.";});});
}
- (void)change:(id)sender {
    NSString *key=nil;NSNumber *value=nil;
    if(sender==self.enabled){key=@"Enabled";value=@(self.enabled.on);}else if(sender==self.loop){key=@"Loop";value=@(self.loop.on);}
    else if(sender==self.mirror){key=@"Mirror";value=@(self.mirror.on);}else if(sender==self.floating){key=@"Floating";value=@(self.floating.on);}
    else if(sender==self.fit){key=@"Fill";value=@(self.fit.selectedSegmentIndex==1);}else if(sender==self.rotation){key=@"Rotation";value=@(self.rotation.selectedSegmentIndex*90);}
    if(key)[self edit:^(NSMutableDictionary *s){s[key]=value;}];
}
- (void)reset {[self edit:^(NSMutableDictionary *s){[s setDictionary:ICDefaults()];}];}
- (void)pan:(UIPanGestureRecognizer *)gesture {
    if(gesture.state==UIGestureRecognizerStateBegan){self.gestureX=[self.settings[@"X"] doubleValue];self.gestureY=[self.settings[@"Y"] doubleValue];}
    if(gesture.state==UIGestureRecognizerStateEnded){CGPoint p=[gesture translationInView:self.preview];double x=self.gestureX+2*p.x/MAX(1,self.preview.bounds.size.width),y=self.gestureY+2*p.y/MAX(1,self.preview.bounds.size.height);[self edit:^(NSMutableDictionary *s){s[@"X"]=@(x);s[@"Y"]=@(y);}];}
}
- (void)pinch:(UIPinchGestureRecognizer *)gesture {
    if(gesture.state==UIGestureRecognizerStateBegan)self.gestureZoom=[self.settings[@"Zoom"] doubleValue];
    if(gesture.state==UIGestureRecognizerStateEnded){double zoom=self.gestureZoom*gesture.scale;[self edit:^(NSMutableDictionary *s){s[@"Zoom"]=@(zoom);}];}
}
- (void)pick {
    if(self.busy || self.presentedViewController)return;
    [self stop];PHPickerConfiguration *configuration=[PHPickerConfiguration new];configuration.selectionLimit=1;
    configuration.filter=[PHPickerFilter anyFilterMatchingSubfilters:@[PHPickerFilter.imagesFilter,PHPickerFilter.videosFilter]];
    configuration.preferredAssetRepresentationMode=PHPickerConfigurationAssetRepresentationModeCurrent;
    PHPickerViewController *picker=[[PHPickerViewController alloc] initWithConfiguration:configuration];picker.delegate=self;[self presentViewController:picker animated:YES completion:nil];
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    // A page sheet need not trigger viewDidAppear on the presenting controller.
    // Resume explicitly on dismissal, including when the user cancels selection.
    [picker dismissViewControllerAnimated:YES completion:^{[self start];}];NSItemProvider *provider=results.firstObject.itemProvider;if(!provider)return;
    BOOL video=[provider hasItemConformingToTypeIdentifier:UTTypeMovie.identifier];NSString *type=video?UTTypeMovie.identifier:UTTypeImage.identifier;
    self.busy=YES;self.choose.enabled=NO;self.message.text=@"Đang nhập media…";
    [provider loadFileRepresentationForTypeIdentifier:type completionHandler:^(NSURL *url,NSError *loadError){
        NSError *error=loadError;NSString *name=nil,*destination=nil;NSFileManager *fm=NSFileManager.defaultManager;
        @try {
        NSString *base=ICStorageDirectory(&error);
        if(url && base && !error) {
            NSString *extension=url.pathExtension.lowercaseString;NSCharacterSet *invalid=NSCharacterSet.alphanumericCharacterSet.invertedSet;
            if(!extension.length || extension.length>8 || [extension rangeOfCharacterFromSet:invalid].location!=NSNotFound)extension=video?@"mov":@"jpg";
            name=[NSString stringWithFormat:@"source-%@.%@",NSUUID.UUID.UUIDString,extension];destination=[base stringByAppendingPathComponent:name];
            if([fm createDirectoryAtPath:base withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0775} error:&error]) {
                // Copy synchronously inside the provider callback: its URL expires on return.
                if([fm copyItemAtURL:url toURL:[NSURL fileURLWithPath:destination] error:&error])
                    [fm setAttributes:@{NSFilePosixPermissions:@0644,NSFileProtectionKey:NSFileProtectionNone} ofItemAtPath:destination error:&error];
                if(!error){ICMediaSource *probe=[[ICMediaSource alloc] initWithPath:destination kind:video?@"video":@"image" error:&error];if(!probe || ![probe imageAtTime:CACurrentMediaTime() loop:NO])error=error?:probe.error?:ICError(@"Media không có frame giải mã được.");}
            }
        } else if(!error)error=ICError(@"Thư viện không trả về media hoặc không tìm thấy bootstrap.");
        if(!error) {
            NSString *old=ICReadSettings(NULL)[@"Media"];
            ICUpdateSettings(^(NSMutableDictionary *s){s[@"Media"]=name;s[@"Kind"]=video?@"video":@"image";},&error);
            if(!error && old.length && ![old isEqual:name])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
                if(![ICReadSettings(NULL)[@"Media"] isEqual:old]){NSString *path=ICManagedMediaPath(old,NULL);if(path)[fm removeItemAtPath:path error:NULL];}
            });
        }
        } @catch(NSException *exception) {error=ICError(exception.reason);}
        if(error && destination && ![ICReadSettings(NULL)[@"Media"] isEqual:name])[fm removeItemAtPath:destination error:NULL];
        NSError *resultError=error;dispatch_async(dispatch_get_main_queue(),^{self.busy=NO;self.choose.enabled=YES;[self refreshSettings];self.message.text=resultError.localizedDescription?:@"Đã nhập nguồn mới. Bật camera ảo để kiểm tra trên Camera.";});
    }];
}
- (void)readDiagnostics {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSError *error=nil;NSString *base=ICStorageDirectory(&error);NSMutableArray *lines=[NSMutableArray new];
        if(base)for(NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:base error:NULL]) {
            if(![name hasPrefix:@"Status."] || ![name hasSuffix:@".plist"])continue;
            NSDictionary *d=[NSDictionary dictionaryWithContentsOfFile:[base stringByAppendingPathComponent:name]];
            if(![d isKindOfClass:NSDictionary.class] || ![d[@"Time"] isKindOfClass:NSNumber.class] || fabs(NSDate.date.timeIntervalSince1970-[d[@"Time"] doubleValue])>10)continue;
            if(![d[@"Host"] isEqual:@"mediaserverd"] && ![d[@"Host"] isEqual:@"cameracaptured"])continue;
            [lines addObject:[NSString stringWithFormat:@"%@: %@ · hooks %@ · frame %@",d[@"Host"],d[@"State"],d[@"Hooks"],d[@"Replaced"]]];
        }
        NSString *text=error.localizedDescription?:(lines.count?[lines componentsJoinedByString:@"\n"]:@"Chưa có heartbeat từ camera host. Mở Camera; nếu vẫn trống, kiểm tra injection RootHide. Preview chỉ xác nhận bộ đọc media trong app.");
        dispatch_async(dispatch_get_main_queue(),^{self.diagnostics.text=text;});
    });
}
- (void)shareDiagnostics {
    NSString *text=[NSString stringWithFormat:@"iCamV3 Rebuild 2.0.0\n%@\n%@\nRoot: %@\nNếu app crash, gửi .ips và .deb thực tế.",self.message.text,self.diagnostics.text,ICStorageDirectory(NULL)?:@"missing"];
    UIActivityViewController *share=[[UIActivityViewController alloc] initWithActivityItems:@[text] applicationActivities:nil];
    share.popoverPresentationController.sourceView=self.view;
    share.popoverPresentationController.sourceRect=CGRectMake(CGRectGetMidX(self.view.bounds),CGRectGetMaxY(self.view.safeAreaLayoutGuide.layoutFrame)-1,1,1);
    [self presentViewController:share animated:YES completion:nil];
}
- (void)dealloc {[NSNotificationCenter.defaultCenter removeObserver:self];[self stop];}
@end
