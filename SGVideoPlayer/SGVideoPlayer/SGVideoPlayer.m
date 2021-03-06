//
//  SGVideoPlayer.m
//  SGPlayer iOS
//
//  Created by TRS on 2019/5/8.
//  Copyright © 2019 yegail. All rights reserved.
//

#import "SGVideoPlayer.h"
#import <AVFoundation/AVFoundation.h>
#import "AFNetworkReachabilityManager.h"

#define BarrageStatus @"BarrageStatus"

static CGFloat const barAnimateSpeed = 0.5f;
static CGFloat const barShowDuration = 5.0f;
static CGFloat const opacity = 1.0f;
static CGFloat const bottomBaHeight = 40.0f;
static CGFloat const playBtnSideLength = 60.0f;

/*此标识用于避免网络状态发生更改时，重复多次弹出节约流量提示*/
static BOOL isPresentAlert;

@interface SGVideoPlayer()

/**videoPlayer superView*/
@property (nonatomic, strong) UIView *playSuprView;
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UIButton *closeBtn;
@property (nonatomic, strong) UIButton *playOrPauseBtn;
@property (nonatomic, strong) UILabel *totalDurationLabel;
@property (nonatomic, strong) UILabel *progressLabel;
@property (nonatomic, strong) UIProgressView *loadingProgress;//缓存进度
@property (nonatomic, strong) UISlider *slider;//播放进度
@property (nonatomic, strong) UIWindow *keyWindow;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicatorView;
@property (nonatomic, assign) CGRect playerOriginalFrame;
@property (nonatomic, strong) UIButton *zoomScreenBtn;

/**video player, 可播放普通视频、AR视频*/
@property (nonatomic, strong) SGPlayer * player;

@property (nonatomic, strong) UITableView *bindTableView;
@property (nonatomic, assign) CGRect currentPlayCellRect;
@property (nonatomic, strong) NSIndexPath *currentIndexPath;

@property (nonatomic, assign) BOOL isOriginalFrame;
@property (nonatomic, assign) BOOL isFullScreen;
@property (nonatomic, assign) BOOL barHiden;
@property (nonatomic, assign) BOOL inOperation;
@property (nonatomic, assign) BOOL smallWinPlaying;

/*此标识用于记录进入后台前的播放状态，用于切换到前台后判断是否继续播放?*/
@property (nonatomic, assign) BOOL isPlayingBeforeResignActive;

/*此标识用于避免网络状态发生更改时，重复多次弹出节约流量提示*/
@property (nonatomic, assign) BOOL isLocalFilePlay;


@end

@implementation SGVideoPlayer

#pragma mark - public method

- (instancetype)init {
    if (self = [super init]) {
        
        self.backgroundColor = [UIColor blackColor];
        
        self.keyWindow = [UIApplication sharedApplication].keyWindow;
        
        //screen orientation change
        [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusBarOrientationChange:) name:UIDeviceOrientationDidChangeNotification object:[UIDevice currentDevice]];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appwillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(afNetworkingReachabilityDidChange:) name:AFNetworkingReachabilityDidChangeNotification object:nil];
        
        self.barHiden = YES;
        [self showOrHidenBar];
    }
    return self;
}

- (void)replaceVideoWithURL:(NSURL *)contentURL {
    [self replaceVideoWithURL:contentURL
                    videoType:SGVideoTypeNormal];
}

- (void)replaceVideoWithURL:(NSURL *)contentURL
                  videoType:(SGVideoType)videoType {
    
    [self replaceVideoWithURL:contentURL
                    videoType:videoType
                  displayMode:SGDisplayModeNormal];
}

- (void)replaceVideoWithURL:(NSURL *)contentURL
                  videoType:(SGVideoType)videoType
                displayMode:(SGDisplayMode)displayMode {
    
    self.player.displayMode = displayMode;
    self.player.hasGrayFilter = YES;
    [self.player replaceVideoWithURL:contentURL videoType:videoType];
    
    [self insertSubview:self.player.view atIndex:0];
    [self insertSubview:self.activityIndicatorView belowSubview:self.playOrPauseBtn];
    [self.activityIndicatorView startAnimating];
    
    //play from start
    [self playOrPause:self.playOrPauseBtn];
    //[self addSubview:self.topBar];
    [self addSubview:self.bottomBar];
    [self insertSubview:self.playOrPauseBtn aboveSubview:self.activityIndicatorView];
    
    //whether is onlive play.
    BOOL isLive = [contentURL.pathExtension isEqualToString:@"m3u8"];
    self.progressLabel.hidden = self.totalDurationLabel.hidden = self.slider.hidden = self.loadingProgress.hidden = isLive;
    self.slider.value = 0;
    self.progressLabel.text = @"00:00";
    self.isOriginalFrame = NO;
    
    [self afNetworkingReachabilityViaWWANAlert];
}

- (void)playPause {
    [self playOrPause:self.playOrPauseBtn];
}

- (void)destroyPlayer {
    [self.player stop];
    [self.player removePlayerNotificationTarget:self];
    [self.slider removeFromSuperview];
    [self.loadingProgress removeFromSuperview];
    self.slider = nil;
    self.loadingProgress = nil;
    [self removeFromSuperview];
}

- (void)playerBindTableView:(UITableView *)bindTableView currentIndexPath:(NSIndexPath *)currentIndexPath {
    self.bindTableView = bindTableView;
    self.currentIndexPath = currentIndexPath;
}

- (void)playerScrollIsSupportSmallWindowPlay:(BOOL)support {
    
    NSAssert(self.bindTableView != nil, @"必须绑定对应的tableview！！！");
    
    if (self.player.state != SGPlayerStatePlaying) {
        return;
    }
    
    self.currentPlayCellRect = [self.bindTableView rectForRowAtIndexPath:self.currentIndexPath];
    self.currentIndexPath = self.currentIndexPath;
    
    CGFloat cellBottom = self.currentPlayCellRect.origin.y + self.currentPlayCellRect.size.height;
    CGFloat cellUp = self.currentPlayCellRect.origin.y;
    
    if (self.bindTableView.contentOffset.y > cellBottom) {
        if (!support) {
            [self destroyPlayer];
            return;
        }
        [self smallWindowPlay];
        return;
    }
    
    if (cellUp > self.bindTableView.contentOffset.y + self.bindTableView.frame.size.height) {
        if (!support) {
            [self destroyPlayer];
            return;
        }
        [self smallWindowPlay];
        return;
    }
    
    if (self.bindTableView.contentOffset.y < cellBottom){
        if (!support) return;
        [self returnToOriginView];
        return;
    }
    
    if (cellUp < self.bindTableView.contentOffset.y + self.bindTableView.frame.size.height){
        if (!support) return;
        [self returnToOriginView];
        return;
    }
}

#pragma mark - layoutSubviews

- (void)layoutSubviews {
    [super layoutSubviews];
    
    self.player.view.frame = self.bounds;
    
    if (!self.isOriginalFrame) {
        self.playerOriginalFrame = self.frame;
        self.playSuprView = self.superview;
        self.topBar.frame = CGRectMake(0, 20, self.playerOriginalFrame.size.width, bottomBaHeight);
        self.bottomBar.frame = CGRectMake(0, self.playerOriginalFrame.size.height - bottomBaHeight, self.self.playerOriginalFrame.size.width, bottomBaHeight);
        self.playOrPauseBtn.frame = CGRectMake(5, (self.playerOriginalFrame.size.height - playBtnSideLength - bottomBaHeight + 5), playBtnSideLength, playBtnSideLength);
        self.activityIndicatorView.center = CGPointMake(self.playerOriginalFrame.size.width / 2, self.playerOriginalFrame.size.height / 2);
        self.isOriginalFrame = YES;
    }
}

#pragma mark - status hiden

- (void)setStatusBarHidden:(BOOL)hidden {
    UIView *statusBar = [[[UIApplication sharedApplication] valueForKey:@"statusBarWindow"] valueForKey:@"statusBar"];
    statusBar.hidden = hidden;
}

#pragma mark - Screen Orientation

- (void)statusBarOrientationChange:(NSNotification *)notification {
    if (self.smallWinPlaying) return;
    UIDeviceOrientation orientation = [UIDevice currentDevice].orientation;
    if (orientation == UIDeviceOrientationLandscapeLeft) {
        [self orientationLeftFullScreen];
    }else if (orientation == UIDeviceOrientationLandscapeRight) {
        [self orientationRightFullScreen];
    }else if (orientation == UIDeviceOrientationPortrait) {
        [self smallScreen];
    }
}

- (void)actionClose {
    if ([UIApplication sharedApplication].statusBarOrientation == UIInterfaceOrientationPortrait) {
        if(self.closeBlock) {self.closeBlock(self);}
    }else {
        [self smallScreen];
    }
}

- (void)actionFullScreen {
    if (!self.isFullScreen) {
        [self orientationLeftFullScreen];
    }else {
        [self smallScreen];
    }
}

- (void)orientationLeftFullScreen {
    if ([self.superview isKindOfClass:[UIWindow class]]) return;
    self.isFullScreen = YES;
    self.zoomScreenBtn.selected = YES;
    [self.keyWindow addSubview:self];
    
    [self updateConstraintsIfNeeded];
    
    [UIView animateWithDuration:0.3 animations:^{
        self.transform = CGAffineTransformMakeRotation(M_PI / 2);
        self.frame = self.keyWindow.bounds;
        self.topBar.frame = CGRectMake(0, 20, self.keyWindow.bounds.size.height, bottomBaHeight);
        self.bottomBar.frame = CGRectMake(0, self.keyWindow.bounds.size.width - bottomBaHeight, self.keyWindow.bounds.size.height, bottomBaHeight);
        self.playOrPauseBtn.frame = CGRectMake((self.keyWindow.bounds.size.height - playBtnSideLength) / 2, (self.keyWindow.bounds.size.width - playBtnSideLength) / 2, playBtnSideLength, playBtnSideLength);
        self.activityIndicatorView.center = CGPointMake(self.keyWindow.bounds.size.height / 2, self.keyWindow.bounds.size.width / 2);
    }];
    
    [self setStatusBarHidden:YES];
}

- (void)orientationRightFullScreen {
    if ([self.superview isKindOfClass:[UIWindow class]]) return;
    self.isFullScreen = YES;
    self.zoomScreenBtn.selected = YES;
    [self.keyWindow addSubview:self];
    
    [self updateConstraintsIfNeeded];
    
    [UIView animateWithDuration:0.3 animations:^{
        self.transform = CGAffineTransformMakeRotation(-M_PI / 2);
        self.frame = self.keyWindow.bounds;
        self.topBar.frame = CGRectMake(0, 0, self.keyWindow.bounds.size.height, bottomBaHeight);
        self.bottomBar.frame = CGRectMake(0, self.keyWindow.bounds.size.width - bottomBaHeight, self.keyWindow.bounds.size.height, bottomBaHeight);
        self.playOrPauseBtn.frame = CGRectMake((self.keyWindow.bounds.size.height - playBtnSideLength) / 2, (self.keyWindow.bounds.size.width - playBtnSideLength) / 2, playBtnSideLength, playBtnSideLength);
        self.activityIndicatorView.center = CGPointMake(self.keyWindow.bounds.size.height / 2, self.keyWindow.bounds.size.width / 2);
    }];
    
    [self setStatusBarHidden:YES];
}

- (void)smallScreen {
    self.isFullScreen = NO;
    self.zoomScreenBtn.selected = NO;
    [[UIDevice currentDevice] setValue:[NSNumber numberWithInteger:UIDeviceOrientationPortrait] forKey:@"orientation"];
    
    if (self.bindTableView) {
        UITableViewCell *cell = [self.bindTableView cellForRowAtIndexPath:self.currentIndexPath];
        [cell.contentView addSubview:self];
    }
    else {
        [self.playSuprView addSubview:self];
    }
    
    [UIView animateWithDuration:0.3 animations:^{
        self.transform = CGAffineTransformMakeRotation(0);
        self.frame = self.playerOriginalFrame;
        self.topBar.hidden = NO;
        self.topBar.frame = CGRectMake(0, 20, self.playerOriginalFrame.size.width, bottomBaHeight);
        self.bottomBar.frame = CGRectMake(0, self.playerOriginalFrame.size.height - bottomBaHeight, self.self.playerOriginalFrame.size.width, bottomBaHeight);
        self.playOrPauseBtn.frame = CGRectMake(5, (self.playerOriginalFrame.size.height - playBtnSideLength - bottomBaHeight + 5), playBtnSideLength, playBtnSideLength);
        self.activityIndicatorView.center = CGPointMake(self.playerOriginalFrame.size.width / 2, self.playerOriginalFrame.size.height / 2);
        [self updateConstraintsIfNeeded];
    }];
    [self setStatusBarHidden:NO];
}

- (void)setStatusBarOrientation:(UIInterfaceOrientation)orientation{
    if ([[UIDevice currentDevice] respondsToSelector:@selector(setOrientation:)]) {
        SEL selector  = NSSelectorFromString(@"setOrientation:");
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[UIDevice instanceMethodSignatureForSelector:selector]];
        [invocation setSelector:selector];
        [invocation setTarget:[UIDevice currentDevice]];
        // 从2开始是因为前两个参数已经被selector和target占用
        [invocation setArgument:&orientation atIndex:2];
        [invocation invoke];
    }
}

#pragma mark - app notif

- (void)appDidEnterBackground:(NSNotification*)note {
    
    NSLog(@"appDidEnterBackground");
}

- (void)appWillEnterForeground:(NSNotification*)note {
    NSLog(@"appWillEnterForeground");
}

- (void)appwillResignActive:(NSNotification *)note {
    NSLog(@"appwillResignActive");
    _isPlayingBeforeResignActive = (self.player.state == SGPlayerStatePlaying);
    if(_isPlayingBeforeResignActive) {
        [self playOrPause:self.playOrPauseBtn];
    }
}

- (void)appBecomeActive:(NSNotification *)note {
    NSLog(@"appBecomeActive");
    
    if(_isPlayingBeforeResignActive) {
        [self playOrPause:self.playOrPauseBtn];
    }
}

#pragma mark - Reachability
- (BOOL)afNetworkingReachabilityDidChange:(NSNotification *)notification {
    
    AFNetworkReachabilityStatus status = [notification.userInfo[AFNetworkingReachabilityNotificationStatusItem] integerValue];
    if(self.player.state == SGPlayerStateFinished && status == AFNetworkReachabilityStatusReachableViaWWAN
       && !self.isLocalFilePlay && !isPresentAlert) {
        
        isPresentAlert = YES;
        self.playOrPauseBtn.selected = NO;
        [self.player pause];
        [self showReachabilityStatusAlert];
        
        return YES;
    }
    return NO;
}

- (BOOL)afNetworkingReachabilityViaWWANAlert {
    
    BOOL isReachableViaWWAN = [AFNetworkReachabilityManager sharedManager].isReachableViaWWAN;
    if(isReachableViaWWAN && !self.isLocalFilePlay && !isPresentAlert) {
        
        isPresentAlert = YES;
        self.playOrPauseBtn.selected = NO;
        [self.player pause];
        [self showReachabilityStatusAlert];
        
        return YES;
    }
    return NO;
}

#pragma mark - alert dialog

- (void)showReachabilityStatusAlert {
    
    UIAlertController *vc = [UIAlertController alertControllerWithTitle:@"当前处在非wifi环境，注意流量消耗哦！" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [vc addAction:[UIAlertAction actionWithTitle:@"停止播放" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        isPresentAlert = NO;
        [self destroyPlayer];
    }]];
    [vc addAction:[UIAlertAction actionWithTitle:@"继续播放" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        self.playOrPauseBtn.selected = YES;
        [self.player play];
        isPresentAlert = NO;
    }]];
    [UIApplication.sharedApplication.keyWindow.rootViewController presentViewController:vc animated:YES completion:^(void){}];
}

#pragma mark - button action

- (void)playOrPause:(UIButton *)btn {
    if(self.player.state == SGPlayerStateSuspend){      //pause
        if([self afNetworkingReachabilityViaWWANAlert]) {
            ; //弹出正在使用移动网络，继续播放将消耗流量
        }
        else {
            btn.selected = YES;
            [self.player play];
        }
    }else if(self.player.state == SGPlayerStatePlaying){    //playing
        [self.player pause];
        btn.selected = NO;
    }else if (self.player.state == SGPlayerStateFinished) { //finish and playback
        self.slider.value = 0.0f;
        btn.selected = YES;
        [self.player play];
        [self show];
    }
}

- (void)showOrHidenBar {
    if (self.barHiden) {
        [self show];
    }else {
        [self hiden];
    }
}

- (void)show {
    [UIView animateWithDuration:barAnimateSpeed animations:^{
        
        self.topBar.layer.opacity = opacity;
        self.bottomBar.layer.opacity = opacity;
        self.playOrPauseBtn.layer.opacity = opacity;
    } completion:^(BOOL finished) {
        if (finished) {
            self.barHiden = !self.barHiden;
            [self performBlock:^{
                if (!self.barHiden && !self.inOperation) {
                    [self hiden];
                }
            } afterDelay:barShowDuration];
        }
    }];
}

- (void)hiden {
    self.inOperation = NO;
    [UIView animateWithDuration:barAnimateSpeed animations:^{
        if ([UIApplication sharedApplication].statusBarOrientation == UIInterfaceOrientationPortrait) {
            self.topBar.layer.opacity = opacity;
        }else {
            self.topBar.layer.opacity = 0.0f;
        }
        self.bottomBar.layer.opacity = 0.0f;
        self.playOrPauseBtn.layer.opacity = 0.0f;
    } completion:^(BOOL finished){
        if (finished) {
            self.barHiden = !self.barHiden;
        }
    }];
}

#pragma mark - UISlider
- (IBAction)didSliderValueChanged:(UISlider *)sender {
    
    self.progressLabel.text = [self timeFormatted:sender.value * self.player.duration];
    
    self.inOperation = YES;
    [self.player pause];
    
    if (self.loadingProgress.progress) {
        [self.player seekToTime:self.player.duration * sender.value completeHandler:^(BOOL finished) {
            [self.player play];
            self.playOrPauseBtn.selected = YES;
            self.activityIndicatorView.hidden = YES;
            self.inOperation = NO;
        }];
    }
}

- (IBAction)didSliderTaped:(UITapGestureRecognizer *)recognizer {
    
    CGPoint location = [recognizer locationInView:recognizer.view];
    CGFloat value = location.x / CGRectGetWidth(recognizer.view.frame);
    [(UISlider *)recognizer.view setValue:value animated:YES];
    
    self.inOperation = YES;
    [self.player pause];
    
    if (self.loadingProgress.progress) {
        [self.player seekToTime:self.player.duration * self.slider.value completeHandler:^(BOOL finished) {
            [self.player play];
            self.playOrPauseBtn.selected = YES;
            self.activityIndicatorView.hidden = YES;
            self.inOperation = NO;
        }];
    }
}

- (void)performBlock:(void (^)(void))block afterDelay:(NSTimeInterval)delay {
    [self performSelector:@selector(callBlockAfterDelay:) withObject:block afterDelay:delay];
}

- (void)callBlockAfterDelay:(void (^)(void))block {
    block();
}

#pragma mark - monitor video playing course
- (void)stateAction:(NSNotification *)notification
{
    SGState * state = [SGState stateFromUserInfo:notification.userInfo];
    
    switch (state.current) {
        case SGPlayerStateNone:
            break;
        case SGPlayerStateBuffering:
        {
            self.activityIndicatorView.hidden = NO;
            [self.activityIndicatorView startAnimating];
            self.playOrPauseBtn.layer.opacity = 0.0f;
            [self hiden];
            break;
        }
        case SGPlayerStateReadyToPlay:
        {
            self.totalDurationLabel.text = [self timeFormatted:self.player.duration];
            self.playOrPauseBtn.selected = YES;
            [self show];
            [self.player play];
            break;
        }
        case SGPlayerStatePlaying:
        {
            [self.activityIndicatorView stopAnimating];
            self.activityIndicatorView.hidden = YES;
        }
            break;
        case SGPlayerStateSuspend:
            break;
        case SGPlayerStateFinished:
        {
            if (self.isFullScreen) {
                [self smallScreen];
            }
            if (self.completedPlayingBlock) {
                [self setStatusBarHidden:NO];
                self.completedPlayingBlock(self);
            }
            else {//finish and loop playback
                self.playOrPauseBtn.selected = NO;
                [self show];
            }
        }
            break;
        case SGPlayerStateFailed:
            break;
    }
}

- (void)progressAction:(NSNotification *)notification
{
    SGProgress * progress = [SGProgress progressFromUserInfo:notification.userInfo];
    float current = progress.current;
    self.progressLabel.text = [self timeFormatted:current];
    if (current) {
        if (!self.inOperation) {
            self.slider.value = progress.percent;
        }
    }
}

- (void)playableAction:(NSNotification *)notification
{
    SGPlayable * playable = [SGPlayable playableFromUserInfo:notification.userInfo];
    self.loadingProgress.progress = playable.current;
}

- (void)errorAction:(NSNotification *)notification
{
    SGError * error = [SGError errorFromUserInfo:notification.userInfo];
    NSLog(@"player did error : %@", error.error);
}

#pragma mark - timeFormat

- (NSString *)timeFormatted:(int)totalSeconds {
    int seconds = totalSeconds % 60;
    int minutes = (totalSeconds / 60) % 60;
    return [NSString stringWithFormat:@"%02d:%02d", minutes, seconds];
}

#pragma mark - animation smallWindowPlay

- (void)smallWindowPlay {
    if ([self.superview isKindOfClass:[UIWindow class]]) return;
    self.smallWinPlaying = YES;
    self.playOrPauseBtn.hidden = YES;
    self.topBar.hidden = YES;
    self.bottomBar.hidden = YES;
    
    CGRect tableViewframe = [self.bindTableView convertRect:self.bindTableView.bounds toView:self.keyWindow];
    self.frame = [self convertRect:self.frame toView:self.keyWindow];
    [self.keyWindow addSubview:self];
    
    [UIView animateWithDuration:0.3 animations:^{
        
        CGFloat w = self.playerOriginalFrame.size.width * 1/4;
        CGFloat h = w * 9/16.0;
        CGRect smallFrame = CGRectMake(tableViewframe.origin.x + tableViewframe.size.width - w, tableViewframe.origin.y + tableViewframe.size.height - h, w, h);
        self.frame = smallFrame;
        self.player.view.frame = self.bounds;
        self.activityIndicatorView.center = CGPointMake(w / 2.0, h / 2.0);
    }];
}

- (void)returnToOriginView {
    if (![self.superview isKindOfClass:[UIWindow class]]) return;
    self.smallWinPlaying = NO;
    self.playOrPauseBtn.hidden = NO;
    self.topBar.hidden = NO;
    self.bottomBar.hidden = NO;
    
    [UIView animateWithDuration:0.3 animations:^{
        
        self.frame = CGRectMake(self.currentPlayCellRect.origin.x, self.currentPlayCellRect.origin.y, self.playerOriginalFrame.size.width, self.playerOriginalFrame.size.height);
        self.player.view.frame = self.bounds;
        self.activityIndicatorView.center = CGPointMake(self.playerOriginalFrame.size.width / 2, self.playerOriginalFrame.size.height / 2);
    } completion:^(BOOL finished) {
        self.frame = self.playerOriginalFrame;
        UITableViewCell *cell = [self.bindTableView cellForRowAtIndexPath:self.currentIndexPath];
        [cell.contentView addSubview:self];
    }];
}

#pragma mark - lazy loading

- (SGPlayer *)player{
    if (!_player) {
        
        // 解决8.1系统播放无声音问题，8.0、9.0以上未发现此问题
        AVAudioSession * session = [AVAudioSession sharedInstance];
        [session setCategory:AVAudioSessionCategoryPlayback error:nil];
        [session setActive:YES error:nil];
        
        _player = [SGPlayer player];
        [_player registerPlayerNotificationTarget:self
                                      stateAction:@selector(stateAction:)
                                   progressAction:@selector(progressAction:)
                                   playableAction:@selector(playableAction:)
                                      errorAction:@selector(errorAction:)];
        __weak typeof(self) weakSelf = self;
        [_player setViewTapAction:^(SGPlayer * _Nonnull player, SGPLFView * _Nonnull view) {
            [weakSelf showOrHidenBar];
        }];
    }
    return _player;
}

- (UIActivityIndicatorView *)activityIndicatorView {
    if (!_activityIndicatorView) {
        _activityIndicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        [self insertSubview:_activityIndicatorView aboveSubview:self.playOrPauseBtn];
        
    }
    return _activityIndicatorView;
}

- (UIView *)topBar {
    
    if(!_topBar) {
        
        _topBar = [[UIView alloc] init];
        _topBar.backgroundColor = [UIColor clearColor];
        _topBar.layer.opacity = opacity;
        
        //返回或关闭
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
        closeBtn.backgroundColor = [UIColor clearColor];
        closeBtn.hidden = YES;//self.closeHidden;
        [closeBtn setImage:[UIImage imageNamed:@"ImageResources.bundle/close.png"] forState:UIControlStateNormal];
        [closeBtn addTarget:self action:@selector(actionClose) forControlEvents:UIControlEventTouchUpInside];
        [_topBar addSubview:closeBtn];
        self.closeBtn = closeBtn;
        
        NSLayoutConstraint *closeBtnLeft = [NSLayoutConstraint constraintWithItem:closeBtn attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:_topBar attribute:NSLayoutAttributeLeft multiplier:1.0f constant:0];
        NSLayoutConstraint *closeBtnTop = [NSLayoutConstraint constraintWithItem:closeBtn attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:_topBar attribute:NSLayoutAttributeTop multiplier:1.0f constant:0];
        NSLayoutConstraint *closeBtnBottom = [NSLayoutConstraint constraintWithItem:closeBtn attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:_topBar attribute:NSLayoutAttributeBottom multiplier:1.0f constant:0];
        NSLayoutConstraint *closeBtnWidth = [NSLayoutConstraint constraintWithItem:closeBtn attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeWidth multiplier:1.0f constant:60.0f];
        [_topBar addConstraints:@[closeBtnLeft, closeBtnTop, closeBtnBottom, closeBtnWidth]];
    }
    return _topBar;
}

- (UIView *)bottomBar {
    if (!_bottomBar) {
        _bottomBar = [[UIView alloc] init];
        _bottomBar.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
        _bottomBar.layer.opacity = 0.0f;
        
        UILabel *label1 = [[UILabel alloc] init];
        label1.translatesAutoresizingMaskIntoConstraints = NO;
        label1.textAlignment = NSTextAlignmentCenter;
        label1.text = @"00:00";
        label1.font = [UIFont systemFontOfSize:13.0f];
        label1.textColor = [UIColor whiteColor];
        [_bottomBar addSubview:label1];
        self.progressLabel = label1;
        
        UIButton *fullScreenBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        fullScreenBtn.translatesAutoresizingMaskIntoConstraints = NO;
        fullScreenBtn.contentMode = UIViewContentModeCenter;
        [fullScreenBtn setImage:[UIImage imageNamed:@"ImageResources.bundle/btn_zoom_out"] forState:UIControlStateNormal];
        [fullScreenBtn setImage:[UIImage imageNamed:@"ImageResources.bundle/btn_zoom_in"] forState:UIControlStateSelected];
        [fullScreenBtn addTarget:self action:@selector(actionFullScreen) forControlEvents:UIControlEventTouchDown];
        [_bottomBar addSubview:fullScreenBtn];
        self.zoomScreenBtn = fullScreenBtn;
        
        UILabel *label2 = [[UILabel alloc] init];
        label2.translatesAutoresizingMaskIntoConstraints = NO;
        label2.textAlignment = NSTextAlignmentCenter;
        label2.text = @"00:00";
        label2.font = [UIFont systemFontOfSize:13.0f];
        label2.textColor = [UIColor whiteColor];
        [_bottomBar addSubview:label2];
        self.totalDurationLabel = label2;
        
        UIProgressView *loadingProgress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        loadingProgress.translatesAutoresizingMaskIntoConstraints = NO;
        loadingProgress.backgroundColor = [UIColor clearColor];
        loadingProgress.trackTintColor = [UIColor whiteColor];
        loadingProgress.progressTintColor = [UIColor lightGrayColor];
        [_bottomBar addSubview:loadingProgress];
        self.loadingProgress = loadingProgress;
        
        UISlider *slider = [[UISlider alloc] init];
        slider.translatesAutoresizingMaskIntoConstraints = NO;
        slider.continuous = NO;
        slider.backgroundColor = [UIColor clearColor];
        slider.maximumTrackTintColor = [UIColor clearColor];
        slider.minimumTrackTintColor = [UIColor redColor];
        [slider setThumbImage:[UIImage imageNamed:@"SGVideoPlayer.bundle/video_slide"] forState:UIControlStateNormal];
        [slider setThumbImage:[UIImage imageNamed:@"SGVideoPlayer.bundle/video_slide"] forState:UIControlStateHighlighted];
        [slider addTarget:self action:@selector(didSliderValueChanged:) forControlEvents:UIControlEventValueChanged];
        UITapGestureRecognizer *recognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didSliderTaped:)];
        slider.userInteractionEnabled = YES;
        [slider addGestureRecognizer:recognizer];
        [_bottomBar addSubview:slider];
        self.slider = slider;
        
        [_bottomBar addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-0@700-[_progressLabel(50.0)]-0-[_slider]-0-[_totalDurationLabel(50.0)]-0-[_zoomScreenBtn(40.0)]-0-|"
                                                                           options:NSLayoutFormatAlignAllCenterY
                                                                           metrics:nil
                                                                             views:NSDictionaryOfVariableBindings(_progressLabel, _slider, _totalDurationLabel, _zoomScreenBtn)]];
        
        [_bottomBar addConstraints:
         [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-0-[_progressLabel]-0-|"
                                                 options:0
                                                 metrics:nil
                                                   views:NSDictionaryOfVariableBindings(_progressLabel)]];
        
        [_bottomBar addConstraints:
         [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-0-[_zoomScreenBtn]-0-|"
                                                 options:0
                                                 metrics:nil
                                                   views:NSDictionaryOfVariableBindings(_zoomScreenBtn)]];
        
        [_bottomBar addConstraints:
         [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-0-[_totalDurationLabel]-0-|"
                                                 options:0
                                                 metrics:nil
                                                   views:NSDictionaryOfVariableBindings(_totalDurationLabel)]];
        [_bottomBar addConstraints:
         [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-0-[_slider]-0-|"
                                                 options:0
                                                 metrics:nil
                                                   views:NSDictionaryOfVariableBindings(_slider)]];
        [_bottomBar addConstraints:
         [NSLayoutConstraint constraintsWithVisualFormat:@"H:[_progressLabel]-0-[_loadingProgress]-0-[_totalDurationLabel]"
                                                 options:0
                                                 metrics:nil
                                                   views:NSDictionaryOfVariableBindings(_progressLabel, _loadingProgress, _totalDurationLabel)]];
        
        [_bottomBar addConstraint:
         [NSLayoutConstraint constraintWithItem:_loadingProgress
                                      attribute:NSLayoutAttributeCenterY
                                      relatedBy:NSLayoutRelationEqual
                                         toItem:_slider
                                      attribute:NSLayoutAttributeCenterY
                                     multiplier:1.0f
                                       constant:1]];
        
        [self updateConstraintsIfNeeded];
    }
    return _bottomBar;
}

- (UIButton *)playOrPauseBtn {
    if (!_playOrPauseBtn) {
        _playOrPauseBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        _playOrPauseBtn.layer.opacity = 0.0f;
        _playOrPauseBtn.contentMode = UIViewContentModeCenter;
        [_playOrPauseBtn setBackgroundImage:[UIImage imageNamed:@"ImageResources.bundle/play"] forState:UIControlStateNormal];
        [_playOrPauseBtn setBackgroundImage:[UIImage imageNamed:@"ImageResources.bundle/pause"] forState:UIControlStateSelected];
        [_playOrPauseBtn addTarget:self action:@selector(playOrPause:) forControlEvents:UIControlEventTouchDown];
    }
    return _playOrPauseBtn;
}

#pragma mark - dealloc

- (void)dealloc {
    [self.player removePlayerNotificationTarget:self];
    
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceOrientationDidChangeNotification object:[UIDevice currentDevice]];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AFNetworkingReachabilityDidChangeNotification object:nil];
    NSLog(@"video player - dealloc");
}

@end
