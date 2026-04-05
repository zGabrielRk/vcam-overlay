// VcamOverlay Tweak
// Overlay flutuante estilo LordVCAM, ativada por volume +/-
// Integra com vcamrootless.dylib (temp.mov em /var/jb/var/mobile/Library/)

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

// ─── Caminho do vídeo usado pelo vcamrootless ────────────────────────────────
static NSString *const kTempMovPath = @"/var/jb/var/mobile/Library/temp.mov";

// ─── Estado global ────────────────────────────────────────────────────────────
static BOOL gVcamEnabled = YES;
static BOOL gAudioSource = NO;
static BOOL gShortcutFloating = YES;
static NSString *gSelectedVideoPath = nil;

// ─── Forward declarations ─────────────────────────────────────────────────────
@class VcamOverlayWindow;
static VcamOverlayWindow *sharedOverlay = nil;

// ─── VcamOverlayWindow ────────────────────────────────────────────────────────
@interface VcamOverlayWindow : UIWindow <UIDocumentPickerDelegate, UINavigationControllerDelegate, UIImagePickerControllerDelegate>
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *selectBtn;
@property (nonatomic, strong) UIButton *disableBtn;
@property (nonatomic, strong) UIButton *galleryBtn;
@property (nonatomic, strong) UIButton *streamBtn;
@property (nonatomic, strong) UISwitch *audioSwitch;
@property (nonatomic, strong) UISwitch *shortcutSwitch;
- (void)show;
- (void)hide;
- (void)toggle;
@end

@implementation VcamOverlayWindow

- (instancetype)init {
    // Ocupa tela toda para capturar toque fora do card e fechar
    self = [super initWithFrame:[UIScreen mainScreen].bounds];
    if (self) {
        self.windowLevel = UIWindowLevelAlert + 100;
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
        self.hidden = YES;
        self.alpha = 0;
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    // ── Card escuro ──────────────────────────────────────────────────────────
    self.cardView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 380)];
    self.cardView.center = CGPointMake(self.bounds.size.width / 2,
                                       self.bounds.size.height / 2);
    self.cardView.backgroundColor = [UIColor colorWithRed:0.13 green:0.13 blue:0.16 alpha:0.97];
    self.cardView.layer.cornerRadius = 18;
    self.cardView.layer.masksToBounds = YES;
    [self addSubview:self.cardView];

    CGFloat W = self.cardView.bounds.size.width;
    CGFloat pad = 14;
    CGFloat y = 14;

    // ── Header: ícone + título + versão + botão fechar ───────────────────────
    UILabel *icon = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, 30, 30)];
    icon.text = @"📷";
    icon.font = [UIFont systemFontOfSize:22];
    [self.cardView addSubview:icon];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(pad + 34, y, 180, 30)];
    self.titleLabel.text = @"VcamRootless";
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [self.cardView addSubview:self.titleLabel];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(W - 44, y, 32, 32);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:16];
    [closeBtn setTitleColor:[UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:1] forState:UIControlStateNormal];
    closeBtn.backgroundColor = [UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:0.2];
    closeBtn.layer.cornerRadius = 16;
    closeBtn.layer.masksToBounds = YES;
    [closeBtn addTarget:self action:@selector(hide) forControlEvents:UIControlEventTouchUpInside];
    [self.cardView addSubview:closeBtn];

    y += 36;

    // ── Status (vídeo selecionado / tempo restante) ──────────────────────────
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, W - pad * 2, 18)];
    [self updateStatusLabel];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:12];
    [self.cardView addSubview:self.statusLabel];
    y += 24;

    // ── Separador ────────────────────────────────────────────────────────────
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(pad, y, W - pad * 2, 1)];
    sep.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
    [self.cardView addSubview:sep];
    y += 10;

    // ── Linha 1: Stream | Gallery ────────────────────────────────────────────
    CGFloat btnH = 44;
    CGFloat half = (W - pad * 3) / 2;

    self.streamBtn = [self makeButton:@"⚡ Stream"
                                color:[UIColor colorWithRed:0.18 green:0.18 blue:0.22 alpha:1]
                                 bold:NO];
    self.streamBtn.frame = CGRectMake(pad, y, half, btnH);
    [self.streamBtn addTarget:self action:@selector(streamTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.cardView addSubview:self.streamBtn];

    self.galleryBtn = [self makeButton:@"🖼 Gallery"
                                 color:[UIColor colorWithRed:0.45 green:0.20 blue:0.90 alpha:1]
                                  bold:YES];
    self.galleryBtn.frame = CGRectMake(pad * 2 + half, y, half, btnH);
    [self.galleryBtn addTarget:self action:@selector(galleryTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.cardView addSubview:self.galleryBtn];
    y += btnH + 10;

    // ── Linha 2: Select | Disable ────────────────────────────────────────────
    self.selectBtn = [self makeButton:@"🎞 Select"
                                color:[UIColor colorWithRed:0.45 green:0.20 blue:0.90 alpha:1]
                                 bold:YES];
    self.selectBtn.frame = CGRectMake(pad, y, half, btnH);
    [self.selectBtn addTarget:self action:@selector(selectTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.cardView addSubview:self.selectBtn];

    self.disableBtn = [self makeButton:gVcamEnabled ? @"⊘ Disable" : @"✓ Enable"
                                 color:[UIColor colorWithRed:0.18 green:0.18 blue:0.22 alpha:1]
                                  bold:NO];
    self.disableBtn.frame = CGRectMake(pad * 2 + half, y, half, btnH);
    [self.disableBtn addTarget:self action:@selector(disableTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.cardView addSubview:self.disableBtn];
    y += btnH + 12;

    // ── Separador ────────────────────────────────────────────────────────────
    UIView *sep2 = [[UIView alloc] initWithFrame:CGRectMake(pad, y, W - pad * 2, 1)];
    sep2.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
    [self.cardView addSubview:sep2];
    y += 12;

    // ── Toggle: Audio Source ─────────────────────────────────────────────────
    UISwitch *tmpAudioSwitch = nil;
    [self addToggleRow:@"Audio Source" yPos:&y width:W pad:pad
              isOn:gAudioSource
           selector:@selector(audioToggled:)
             swRef:&tmpAudioSwitch];
    self.audioSwitch = tmpAudioSwitch;

    // ── Toggle: Shortcut Floating Window ────────────────────────────────────
    UISwitch *tmpShortcutSwitch = nil;
    [self addToggleRow:@"Shortcut Floating Window" yPos:&y width:W pad:pad
              isOn:gShortcutFloating
           selector:@selector(shortcutToggled:)
             swRef:&tmpShortcutSwitch];
    self.shortcutSwitch = tmpShortcutSwitch;

    y += 6;

    // ── Resize card ao tamanho real ──────────────────────────────────────────
    CGRect f = self.cardView.frame;
    f.size.height = y;
    self.cardView.frame = f;
    self.cardView.center = CGPointMake(self.bounds.size.width / 2,
                                        self.bounds.size.height / 2);
}

- (UIButton *)makeButton:(NSString *)title color:(UIColor *)color bold:(BOOL)bold {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.backgroundColor = color;
    btn.titleLabel.font = bold ? [UIFont boldSystemFontOfSize:14] : [UIFont systemFontOfSize:14];
    btn.layer.cornerRadius = 10;
    btn.layer.masksToBounds = YES;
    return btn;
}

- (void)addToggleRow:(NSString *)label
                yPos:(CGFloat *)y
               width:(CGFloat)W
                 pad:(CGFloat)pad
               isOn:(BOOL)isOn
            selector:(SEL)sel
              swRef:(UISwitch **)swRef {
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(pad, *y, W - pad * 2 - 60, 30)];
    lbl.text = label;
    lbl.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    lbl.font = [UIFont systemFontOfSize:14];
    [self.cardView addSubview:lbl];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
    sw.on = isOn;
    sw.onTintColor = [UIColor colorWithRed:1.0 green:0.75 blue:0.0 alpha:1];
    [sw addTarget:self action:sel forControlEvents:UIControlEventValueChanged];
    CGFloat swW = sw.frame.size.width;
    CGFloat swH = sw.frame.size.height;
    sw.frame = CGRectMake(W - pad - swW, *y + (30 - swH) / 2, swW, swH);
    [self.cardView addSubview:sw];
    if (swRef) *swRef = sw;
    *y += 38;
}

- (void)updateStatusLabel {
    BOOL hasVideo = [[NSFileManager defaultManager] fileExistsAtPath:kTempMovPath];
    if (!gVcamEnabled) {
        self.statusLabel.text = @"● VCam Disabled";
        self.statusLabel.textColor = [UIColor colorWithRed:1 green:0.3 blue:0.3 alpha:1];
    } else if (hasVideo) {
        self.statusLabel.text = @"● VCam Active — video loaded";
        self.statusLabel.textColor = [UIColor colorWithRed:0.3 green:1 blue:0.4 alpha:1];
    } else {
        self.statusLabel.text = @"⚠ No video selected";
        self.statusLabel.textColor = [UIColor colorWithRed:1 green:0.8 blue:0 alpha:1];
    }
}

// ── Ações ──────────────────────────────────────────────────────────────────────

- (void)selectTapped {
    // Abre picker de vídeo da galeria
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (rootVC.presentedViewController) rootVC = rootVC.presentedViewController;

    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[@"public.movie"];
    picker.allowsEditing = NO;
    picker.delegate = self;
    [rootVC presentViewController:picker animated:YES completion:nil];
    [self hide];
}

- (void)galleryTapped {
    // Mesma ação que Select por ora
    [self selectTapped];
}

- (void)streamTapped {
    // Mostra alerta para inserir URL de stream
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (rootVC.presentedViewController) rootVC = rootVC.presentedViewController;

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Stream URL"
        message:@"Enter a video URL to use as camera source"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"http://...";
        tf.keyboardType = UIKeyboardTypeURL;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Use" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *urlStr = alert.textFields.firstObject.text;
        if (urlStr.length > 0) {
            [self downloadAndSetStreamURL:[NSURL URLWithString:urlStr]];
        }
    }]];
    [rootVC presentViewController:alert animated:YES completion:nil];
    [self hide];
}

- (void)downloadAndSetStreamURL:(NSURL *)url {
    // Download assíncrono do vídeo para temp.mov
    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession]
        downloadTaskWithURL:url
          completionHandler:^(NSURL *loc, NSURLResponse *resp, NSError *err) {
        if (loc && !err) {
            NSError *moveErr;
            [[NSFileManager defaultManager] removeItemAtPath:kTempMovPath error:nil];
            [[NSFileManager defaultManager] moveItemAtURL:loc
                                                    toURL:[NSURL fileURLWithPath:kTempMovPath]
                                                    error:&moveErr];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateStatusLabel];
            });
        }
    }];
    [task resume];
}

- (void)disableTapped {
    gVcamEnabled = !gVcamEnabled;
    NSString *title = gVcamEnabled ? @"⊘ Disable" : @"✓ Enable";
    [self.disableBtn setTitle:title forState:UIControlStateNormal];
    self.disableBtn.backgroundColor = gVcamEnabled
        ? [UIColor colorWithRed:0.18 green:0.18 blue:0.22 alpha:1]
        : [UIColor colorWithRed:0.1 green:0.55 blue:0.2 alpha:1];

    if (!gVcamEnabled) {
        // Renomeia o arquivo para desativar sem deletar
        NSString *bakPath = [kTempMovPath stringByAppendingString:@".bak"];
        [[NSFileManager defaultManager] moveItemAtPath:kTempMovPath toPath:bakPath error:nil];
    } else {
        NSString *bakPath = [kTempMovPath stringByAppendingString:@".bak"];
        [[NSFileManager defaultManager] moveItemAtPath:bakPath toPath:kTempMovPath error:nil];
    }
    [self updateStatusLabel];
}

- (void)audioToggled:(UISwitch *)sw {
    gAudioSource = sw.isOn;
}

- (void)shortcutToggled:(UISwitch *)sw {
    gShortcutFloating = sw.isOn;
    // Mostra/esconde botão flutuante de atalho
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"VcamShortcutToggle"
        object:@(gShortcutFloating)];
}

// ── UIImagePickerControllerDelegate ──────────────────────────────────────────

- (void)imagePickerController:(UIImagePickerController *)picker
didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    NSURL *videoURL = info[UIImagePickerControllerMediaURL];
    if (videoURL) {
        NSError *err;
        [[NSFileManager defaultManager] removeItemAtPath:kTempMovPath error:nil];
        [[NSFileManager defaultManager] copyItemAtPath:videoURL.path
                                                toPath:kTempMovPath
                                                 error:&err];
        gSelectedVideoPath = videoURL.path;
    }
    [picker dismissViewControllerAnimated:YES completion:^{
        [self updateStatusLabel];
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

// ── Show / Hide / Toggle ──────────────────────────────────────────────────────

- (void)show {
    [self updateStatusLabel];
    self.hidden = NO;
    [self makeKeyAndVisible];
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 1;
        self.cardView.transform = CGAffineTransformIdentity;
    }];
}

- (void)hide {
    [UIView animateWithDuration:0.18 animations:^{
        self.alpha = 0;
        self.cardView.transform = CGAffineTransformMakeScale(0.93, 0.93);
    } completion:^(BOOL f) {
        self.hidden = YES;
        // Devolve foco para a janela anterior
        for (UIWindow *w in [UIApplication sharedApplication].windows.reverseObjectEnumerator.allObjects) {
            if (w != self && !w.hidden) {
                [w makeKeyWindow];
                break;
            }
        }
    }];
}

- (void)toggle {
    if (self.hidden || self.alpha < 0.1) [self show];
    else [self hide];
}

// Tap fora do card fecha
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *t = touches.anyObject;
    CGPoint pt = [t locationInView:self];
    if (!CGRectContainsPoint(self.cardView.frame, pt)) {
        [self hide];
    }
}

@end


// ─── Botão flutuante de atalho ────────────────────────────────────────────────
@interface VcamShortcutButton : UIButton
@end

@implementation VcamShortcutButton
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 200, 48, 48)];
    if (self) {
        [self setTitle:@"📷" forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont systemFontOfSize:26];
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
        self.layer.cornerRadius = 24;
        self.layer.masksToBounds = YES;
        [self addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
            initWithTarget:self action:@selector(panned:)];
        [self addGestureRecognizer:pan];

        [[NSNotificationCenter defaultCenter]
            addObserver:self
            selector:@selector(visibilityChanged:)
            name:@"VcamShortcutToggle"
            object:nil];
    }
    return self;
}

- (void)tapped {
    if (!sharedOverlay) {
        sharedOverlay = [[VcamOverlayWindow alloc] init];
    }
    [sharedOverlay toggle];
}

- (void)panned:(UIPanGestureRecognizer *)gr {
    CGPoint delta = [gr translationInView:self.superview];
    self.center = CGPointMake(self.center.x + delta.x, self.center.y + delta.y);
    [gr setTranslation:CGPointZero inView:self.superview];
}

- (void)visibilityChanged:(NSNotification *)n {
    BOOL visible = [n.object boolValue];
    self.hidden = !visible;
}
@end


// ─── Window para o botão flutuante ────────────────────────────────────────────
static UIWindow *shortcutWindow = nil;

static void setupShortcutButton(void) {
    if (!gShortcutFloating) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (shortcutWindow) return;
        shortcutWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        shortcutWindow.windowLevel = UIWindowLevelAlert + 50;
        shortcutWindow.backgroundColor = [UIColor clearColor];
        shortcutWindow.userInteractionEnabled = YES;

        VcamShortcutButton *btn = [[VcamShortcutButton alloc] init];
        [shortcutWindow addSubview:btn];
        shortcutWindow.hidden = NO;
    });
}


// ─── Hooks de volume ──────────────────────────────────────────────────────────
static float sLastVolume = -1;
static BOOL sIgnoreNextChange = NO;

%hook AVSystemController
- (BOOL)setActiveCategoryVolumeTo:(float)volume {
    if (sIgnoreNextChange) {
        sIgnoreNextChange = NO;
        return %orig;
    }
    if (sLastVolume >= 0) {
        // Volume mudou → botão pressionado
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!sharedOverlay) {
                sharedOverlay = [[VcamOverlayWindow alloc] init];
            }
            [sharedOverlay toggle];
        });
        // Restaura volume anterior para não mudar o áudio de fato
        sIgnoreNextChange = YES;
        %orig(sLastVolume);
        return YES;
    }
    sLastVolume = volume;
    return %orig;
}
%end


// ─── Constructor ──────────────────────────────────────────────────────────────
%ctor {
    @autoreleasepool {
        // Aguarda UIApplication estar pronta
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            // Lê volume atual como baseline
            AVAudioSession *session = [AVAudioSession sharedInstance];
            [session setActive:YES error:nil];
            sLastVolume = session.outputVolume;
            setupShortcutButton();
        });
    }
}
