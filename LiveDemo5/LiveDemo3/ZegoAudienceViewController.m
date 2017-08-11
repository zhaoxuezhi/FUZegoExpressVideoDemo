//
//  ZegoAudienceViewController.m
//  LiveDemo3
//
//  Created by Strong on 16/6/27.
//  Copyright © 2016年 ZEGO. All rights reserved.
//

#import "ZegoAudienceViewController.h"
#import "ZegoAVKitManager.h"
#import "ZegoSettings.h"
#import "ZegoLiveToolViewController.h"


@interface ZegoAudienceViewController () <ZegoRoomDelegate, ZegoLivePlayerDelegate, ZegoIMDelegate, ZegoLiveToolViewControllerDelegate>

@property (weak, nonatomic) IBOutlet UIView *playViewContainer;

@property (nonatomic, weak) ZegoLiveToolViewController *toolViewController;

@property (weak, nonatomic) UIButton *publishButton;
@property (weak, nonatomic) UIButton *optionButton;
@property (weak, nonatomic) UIButton *mutedButton;
@property (weak, nonatomic) UIButton *fullscreenButton;
@property (nonatomic, weak) UIButton *sharedButton;

@property (nonatomic, strong) NSMutableArray<ZegoStream *> *streamList;
@property (nonatomic, strong) NSMutableArray<ZegoStream *> *originStreamList;   // 直播秒开流列表

@property (nonatomic, assign) BOOL loginRoomSuccess;

@property (nonatomic, strong) UIColor *defaultButtonColor;

@property (nonatomic, strong) NSMutableDictionary *viewContainersDict;
@property (nonatomic, strong) NSMutableDictionary *streamID2SizeDict;
@property (nonatomic, strong) NSMutableDictionary *videoSizeDict;

@property (nonatomic, copy) NSString *sharedHls;
@property (nonatomic, copy) NSString *sharedRtmp;

@end

@implementation ZegoAudienceViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    for (UIViewController *viewController in self.childViewControllers)
    {
        if ([viewController isKindOfClass:[ZegoLiveToolViewController class]])
        {
            self.toolViewController = (ZegoLiveToolViewController *)viewController;
            self.toolViewController.delegate = self;
            self.toolViewController.isAudience = YES;
            break;
        }
    }
    
    self.optionButton = self.toolViewController.joinLiveOptionButton;
    self.publishButton = self.toolViewController.joinLiveButton;
    self.mutedButton = self.toolViewController.playMutedButton;
    self.fullscreenButton = self.toolViewController.fullScreenButton;
    self.sharedButton = self.toolViewController.shareButton;
    
    _streamList = [[NSMutableArray alloc] initWithCapacity:self.maxStreamCount];
    _viewContainersDict = [[NSMutableDictionary alloc] initWithCapacity:self.maxStreamCount];
    _videoSizeDict = [[NSMutableDictionary alloc] initWithCapacity:self.maxStreamCount];
    _streamID2SizeDict = [[NSMutableDictionary alloc] initWithCapacity:self.maxStreamCount];
    _originStreamList = [[NSMutableArray alloc] initWithCapacity:self.maxStreamCount];
    
    [self setupLiveKit];
    [self loginRoom];
    
    UIImage *backgroundImage = [[ZegoSettings sharedInstance] getBackgroundImage:self.view.bounds.size withText:NSLocalizedString(@"加载中", nil)];
    [self setBackgroundImage:backgroundImage playerView:self.playViewContainer];
    
    [self setButtonHidden:YES];
    
    self.publishButton.enabled = NO;
    self.optionButton.enabled = NO;
    self.sharedButton.enabled = NO;
    
    self.fullscreenButton.hidden = YES;
    
    [self playStreamEnteringRoom];
    
    if ([ZegoDemoHelper recordTime])
    {
        [self.toolViewController startTimeRecord];
    }
}

- (void)setButtonHidden:(BOOL)hidden
{
    if (hidden)
    {
        self.mutedButton.enabled = NO;
    }
    else
    {
        self.mutedButton.enabled = YES;
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)setBackgroundImage:(UIImage *)image playerView:(UIView *)playerView
{
    playerView.backgroundColor = [UIColor colorWithPatternImage:image];
}

#pragma mark - ZegoLiveRoom
- (void)setupLiveKit
{
    [[ZegoDemoHelper api] setRoomDelegate:self];
    [[ZegoDemoHelper api] setPlayerDelegate:self];
    [[ZegoDemoHelper api] setIMDelegate:self];
}

- (void)loginRoom
{
    [[ZegoDemoHelper api] loginRoom:self.roomID role:ZEGO_AUDIENCE withCompletionBlock:^(int errorCode, NSArray<ZegoStream *> *streamList) {
        NSLog(@"%s, error: %d", __func__, errorCode);
        if (errorCode == 0)
        {
            NSString *logString = [NSString stringWithFormat:NSLocalizedString(@"登录房间成功. roomID: %@", nil), self.roomID];
            [self addLogString:logString];
            
            self.loginRoomSuccess = YES;
            
            ZegoStream *stream = [streamList firstObject];
            if (stream.extraInfo.length != 0)
            {
                NSDictionary *dict = [self decodeJSONToDictionary:stream.extraInfo];
                if (dict)
                {
                    self.sharedHls = dict[kHlsKey];
                    self.sharedRtmp = dict[kRtmpKey];
                    
                    if (self.sharedRtmp && self.sharedHls)
                        self.sharedButton.enabled = YES;
                }
            }
            
//            if (streamList.count != 0)
//                [self onStreamUpdateForAdd:streamList];
            
            // 更新流播放列表，包括新增流、删除流
            NSMutableArray *newStreamList = [streamList mutableCopy];
            for (int i = (int)newStreamList.count - 1; i >= 0; i--) {
                for (int j = (int)self.originStreamList.count - 1; j >= 0; j--) {
                    ZegoStream *new = newStreamList[i];
                    ZegoStream *old = self.originStreamList[j];
                    if ([new.streamID isEqualToString:old.streamID]) {
                        [newStreamList removeObject:new];
                        break;
                    }
                }
            }
            if (newStreamList.count) {
                for (ZegoStream *stream in newStreamList) {
                    NSString *logString = [NSString stringWithFormat:NSLocalizedString(@"登录成功后新增流. 流ID: %@", nil), stream.streamID];
                    [self addLogString:logString];
                }
                [self onStreamUpdateForAdd:newStreamList];
            } else {
                NSString *logString = [NSString stringWithFormat:NSLocalizedString(@"登录成功后没有新增的流", nil)];
                [self addLogString:logString];
            }
            
            for (int i = (int)self.originStreamList.count - 1; i >= 0; i--) {
                for (int j = (int)streamList.count - 1; j >= 0; j--) {
                    ZegoStream *new = streamList[j];
                    ZegoStream *old = self.originStreamList[i];
                    if ([new.streamID isEqualToString:old.streamID]) {
                        [self.originStreamList removeObject:old];
                        break;
                    }
                }
            }
            if (self.originStreamList.count) {
                for (ZegoStream *stream in self.originStreamList) {
                    NSString *logString = [NSString stringWithFormat:NSLocalizedString(@"登录成功后删除流. 流ID: %@", nil), stream.streamID];
                    [self addLogString:logString];
                }
                [self onStreamUpdateForDelete:self.originStreamList];
            } else {
                NSString *logString = [NSString stringWithFormat:NSLocalizedString(@"登录成功后没有删除的流", nil)];
                [self addLogString:logString];
            }
        }
        else
        {
            NSString *logString = [NSString stringWithFormat:NSLocalizedString(@"登录房间失败. error: %d", nil), errorCode];
            [self addLogString:logString];
            
            self.loginRoomSuccess = NO;
            
            [self onStreamUpdateForDelete:self.originStreamList];
            [self showNoLivesAlert];
        }
    }];
    
    NSString *logString = [NSString stringWithFormat:NSLocalizedString(@"开始登录房间", nil)];
    [self addLogString:logString];
}

// 秒开播
- (void)playStreamEnteringRoom {
    for (NSString *streamId in self.streamIdList) {
        ZegoStream *stream = [[ZegoStream alloc] init];
        stream.streamID = streamId;
        NSString *logString = [NSString stringWithFormat:NSLocalizedString(@"直播观看秒开. 流ID: %@", nil), stream.streamID];
        [self addLogString:logString];
        [self.originStreamList addObject:stream];
    }
    [self onStreamUpdateForAdd:self.originStreamList];
}

#pragma mark - ZegoRoomDelegate

- (void)onDisconnect:(int)errorCode roomID:(NSString *)roomID
{
    NSString *logString = [NSString stringWithFormat:NSLocalizedString(@"连接失败, error: %d", nil), errorCode];
    [self addLogString:logString];
}

- (void)onKickOut:(int)reason roomID:(NSString *)roomID
{
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"" message:NSLocalizedString(@"被踢出房间", nil) delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil, nil];
    [alertView show];
    
    [self onCloseButton:nil];
}

- (void)onStreamUpdated:(int)type streams:(NSArray<ZegoStream *> *)streamList roomID:(NSString *)roomID
{
    if (type == ZEGO_STREAM_ADD)
        [self onStreamUpdateForAdd:streamList];
    else if (type == ZEGO_STREAM_DELETE)
        [self onStreamUpdateForDelete:streamList];
}

#pragma mark - ZegoLivePlayerDelegate

- (void)onPlayStateUpdate:(int)stateCode streamID:(NSString *)streamID
{
    NSLog(@"%s, streamID: %@", __func__, streamID);
    
    NSString *logString = nil;
    if (stateCode == 0)
    {
        logString = [NSString stringWithFormat:NSLocalizedString(@"播放流成功, 流ID:%@", nil), streamID];
    }
    else
    {
        logString = [NSString stringWithFormat:NSLocalizedString(@"播放流失败, 流ID: %@,  error: %d", nil), streamID, stateCode];
    }
    [self addLogString:logString];
}

- (void)onVideoSizeChangedTo:(CGSize)size ofStream:(NSString *)streamID
{
    NSLog(@"%s, streamID %@", __func__, streamID);
    
    NSString *logString = [NSString stringWithFormat:NSLocalizedString(@"第一帧画面, 流ID:%@", nil), streamID];
    [self addLogString:logString];
    
    [self setButtonHidden:NO];
    [self setBackgroundImage:nil playerView:self.playViewContainer];
    
    UIView *view = self.viewContainersDict[streamID];
    if (view)
        [self setBackgroundImage:nil playerView:view];
    
    if ([self isStreamIDExist:streamID] && view)
    {
        if (size.width > size.height && view.frame.size.width < view.frame.size.height)
        {
            [[ZegoDemoHelper api] setViewMode:ZegoVideoViewModeScaleAspectFit ofStream:streamID];
            
            self.videoSizeDict[streamID] = @(NO);
            
            if (CGRectEqualToRect(view.frame, self.playViewContainer.bounds))
                self.fullscreenButton.hidden = NO;
        }
        
        self.streamID2SizeDict[streamID] = [NSValue valueWithCGSize:size];
    }
}

- (void)onPlayQualityUpate:(NSString *)streamID quality:(ZegoApiPlayQuality)quality
{
    UIView *view = self.viewContainersDict[streamID];
    if (view)
        [self updateQuality:quality.quality view:view];
    
    [self addStaticsInfo:NO stream:streamID fps:quality.fps kbs:quality.kbps];
}

#pragma mark - ZegoIMDelegate

- (void)onUserUpdate:(NSArray<ZegoUserState *> *)userList updateType:(ZegoUserUpdateType)type
{
    for (ZegoUserState *state in userList)
    {
        if (state.role == ZEGO_ANCHOR && state.updateFlag == ZEGO_USER_DELETE)
        {
            NSString *logString = [NSString stringWithFormat:NSLocalizedString(@"主播已退出：%@", nil), state.userName];
            [self addLogString:logString];
            break;
        }
    }
}

- (void)onRecvRoomMessage:(NSString *)roomId messageList:(NSArray<ZegoRoomMessage *> *)messageList
{
    [self.toolViewController updateLayout:messageList];
}

#pragma mark - Stream add & delete function
- (BOOL)isStreamIDExist:(NSString *)streamID
{
    for (ZegoStream *info in self.streamList)
    {
        if ([info.streamID isEqualToString:streamID])
            return YES;
    }
    
    return NO;
}

- (void)addStreamViewContainer:(NSString *)streamID
{
    if (streamID.length == 0)
        return;
    
    if (self.viewContainersDict[streamID] != nil)
        return;
    
    UIView *bigView = [[UIView alloc] init];
    bigView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.playViewContainer addSubview:bigView];
    
    BOOL bResult = [self setContainerConstraints:bigView containerView:self.playViewContainer viewCount:self.viewContainersDict.count];
    if (bResult == NO)
    {
        [bigView removeFromSuperview];
        return;
    }
    
    UIImage *backgroundImage = [[ZegoSettings sharedInstance] getBackgroundImage:self.view.bounds.size withText:NSLocalizedString(@"加载中", nil)];
    [self setBackgroundImage:backgroundImage playerView:bigView];
    
    self.viewContainersDict[streamID] = bigView;
    bool ret = [[ZegoDemoHelper api] startPlayingStream:streamID inView:bigView];
    [[ZegoDemoHelper api] setViewMode:ZegoVideoViewModeScaleAspectFill ofStream:streamID];
    
    assert(ret);
}

- (void)removeStreamViewContainer:(NSString *)streamID
{
    if (streamID.length == 0)
        return;
    
    UIView *view = self.viewContainersDict[streamID];
    if (view == nil)
        return;
    
    [self updateContainerConstraintsForRemove:view containerView:self.playViewContainer];
    
    [self.viewContainersDict removeObjectForKey:streamID];
}

- (void)removeStreamInfo:(NSString *)streamID
{
    NSInteger index = NSNotFound;
    for (ZegoStream *info in self.streamList)
    {
        if ([info.streamID isEqualToString:streamID])
        {
            index = [self.streamList indexOfObject:info];
            break;
        }
    }
    
    if (index != NSNotFound)
        [self.streamList removeObjectAtIndex:index];
}

- (void)onStreamUpdateForAdd:(NSArray<ZegoStream *> *)streamList
{
    for (ZegoStream *stream in streamList)
    {
        if (stream.streamID.length == 0)
            continue;
        
        if ([self isStreamIDExist:stream.streamID])
            continue;
        
        [self.streamList addObject:stream];
        [self addStreamViewContainer:stream.streamID];
        
        NSString *logString = [NSString stringWithFormat:NSLocalizedString(@"新增一条流, 流ID:%@", nil), stream.streamID];
        [self addLogString:logString];
    }
}

- (void)onStreamUpdateForDelete:(NSArray<ZegoStream *> *)streamList
{
    for (ZegoStream *stream in streamList)
    {
        NSString *streamID = stream.streamID;
        if (streamID.length == 0)
            continue;
        
        if (![self isStreamIDExist:streamID])
            continue;
        [[ZegoDemoHelper api] stopPlayingStream:streamID];
        
        [self removeStreamViewContainer:streamID];
        [self removeStreamInfo:streamID];
        
        NSString *logString = [NSString stringWithFormat:NSLocalizedString(@"删除一条流, 流ID:%@", nil), streamID];
        [self addLogString:logString];
    }
}

#pragma mark Alert
- (void)showNoLivesAlert
{
    if ([self isDeviceiOS7])
    {
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"" message:NSLocalizedString(@"主播已退出", nil) delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil, nil];
        [alertView show];
    }
    else
    {
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"" message:NSLocalizedString(@"主播已退出", nil) preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
            [self onCloseButton:nil];
        }];
        
        [alertController addAction:okAction];
        
        [self presentViewController:alertController animated:YES completion:nil];
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    [self onCloseButton:nil];
}

#pragma mark close
- (void)clearAllStream
{
    for (ZegoStream *info in self.streamList)
    {
        [[ZegoDemoHelper api] stopPlayingStream:info.streamID];
        UIView *playView = self.viewContainersDict[info.streamID];
        if (playView)
        {
            [self updateContainerConstraintsForRemove:playView containerView:self.playViewContainer];
            [self.viewContainersDict removeObjectForKey:info.streamID];
        }
    }
    
    [self.viewContainersDict removeAllObjects];
}

#pragma mark ZegoLiveToolViewControllerDelegate
- (void)onCloseButton:(id)sender
{
    [self setBackgroundImage:nil playerView:self.playViewContainer];
    [self clearAllStream];
    
    if ([ZegoDemoHelper recordTime])
    {
        [self.toolViewController stopTimeRecord];
    }
    
    if (self.loginRoomSuccess)
    {
        [[ZegoDemoHelper api] logoutRoom];
    }
    
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)onMutedButton:(id)sender
{
    if (self.enableSpeaker)
    {
        self.enableSpeaker = NO;
        [self.mutedButton setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    }
    else
    {
        self.enableSpeaker = YES;
        [self.mutedButton setTitleColor:self.defaultButtonColor forState:UIControlStateNormal];
    }
}

- (void)onLogButton:(id)sender
{
    [self showLogViewController];
}

- (void)onShareButton:(id)sender
{
    if (self.streamList.count == 0)
        return;
    
    ZegoStream *stream = [self.streamList firstObject];
    if (stream.extraInfo.length != 0)
    {
        NSDictionary *dict = [self decodeJSONToDictionary:stream.extraInfo];
        if (dict)
            [self shareToQQ:dict[kHlsKey] rtmp:dict[kRtmpKey] bizToken:nil bizID:self.roomID streamID:stream.streamID];
    }
}

- (void)onEnterFullScreenButton:(id)sender
{
    UIView *view = [self getFirstViewInContainer:self.playViewContainer];
    NSString *streamID = [self getStreamIDFromView:view];
    if (streamID == nil)
        return;
    
    id info = self.videoSizeDict[streamID];
    if (info == nil)
        return;
    
    BOOL isfull = [info boolValue];
    if (isfull)
    {
        //退出全屏
        [self exitFullScreen:streamID];
        [self.fullscreenButton setTitle:NSLocalizedString(@"进入全屏", nil) forState:UIControlStateNormal];
    }
    else
    {
        //进入全屏
        [self enterFullScreen:streamID];
        [self.fullscreenButton setTitle:NSLocalizedString(@"退出全屏", nil) forState:UIControlStateNormal];
    }
}

- (void)onSendComment:(NSString *)comment
{
    bool ret = [[ZegoDemoHelper api] sendRoomMessage:comment type:ZEGO_TEXT category:ZEGO_CHAT priority:ZEGO_DEFAULT completion:nil];
    if (ret)
    {
        ZegoRoomMessage *roomMessage = [ZegoRoomMessage new];
        roomMessage.fromUserId = [ZegoSettings sharedInstance].userID;
        roomMessage.fromUserName = [ZegoSettings sharedInstance].userName;
        roomMessage.content = comment;
        roomMessage.type = ZEGO_TEXT;
        roomMessage.category = ZEGO_CHAT;
        roomMessage.priority = ZEGO_DEFAULT;
        
        [self.toolViewController updateLayout:@[roomMessage]];
    }
}

- (void)onSendLike
{
    //    [[ZegoDemoHelper api] likeAnchor:1 count:10];
    NSDictionary *likeDict = @{@"likeType": @(1), @"likeCount": @(10)};
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:likeDict options:0 error:nil];
    NSString *content = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    
    bool ret = [[ZegoDemoHelper api] sendRoomMessage:content type:ZEGO_TEXT category:ZEGO_LIKE priority:ZEGO_DEFAULT completion:nil];
    if (ret)
    {
        ZegoRoomMessage *roomMessage = [ZegoRoomMessage new];
        roomMessage.fromUserId = [ZegoSettings sharedInstance].userID;
        roomMessage.fromUserName = [ZegoSettings sharedInstance].userName;
        roomMessage.content = @"点赞了主播";
        roomMessage.type = ZEGO_TEXT;
        roomMessage.category = ZEGO_CHAT;
        roomMessage.priority = ZEGO_DEFAULT;
        
        [self.toolViewController updateLayout:@[roomMessage]];
    }
}

- (NSString *)getStreamIDFromView:(UIView *)view
{
    for (NSString *streamID in self.viewContainersDict)
    {
        if (self.viewContainersDict[streamID] == view)
            return streamID;
    }
    
    return nil;
}

#pragma mark FullScreen action
- (void)exitFullScreen:(NSString *)streamID
{
    BOOL isLandscape = UIInterfaceOrientationIsLandscape([[UIApplication sharedApplication] statusBarOrientation]);
    
    [[ZegoDemoHelper api] setViewMode:ZegoVideoViewModeScaleAspectFit ofStream:streamID];
    if (isLandscape)
    {
        [[ZegoDemoHelper api] setViewRotation:90 ofStream:streamID];
    }
    else
    {
        [[ZegoDemoHelper api] setViewRotation:0 ofStream:streamID];
    }
    self.videoSizeDict[streamID] = @(NO);
}

- (void)enterFullScreen:(NSString *)streamID
{
    BOOL isLandscape = UIInterfaceOrientationIsLandscape([[UIApplication sharedApplication] statusBarOrientation]);
    
    [[ZegoDemoHelper api] setViewMode:ZegoVideoViewModeScaleAspectFit ofStream:streamID];
    if (isLandscape)
    {
        [[ZegoDemoHelper api] setViewRotation:0 ofStream:streamID];
    }
    else
    {
        [[ZegoDemoHelper api] setViewRotation:90 ofStream:streamID];
    }
    self.videoSizeDict[streamID] = @(YES);
}

#pragma mark transition view
- (void)setRotateFromInterfaceOrientation:(UIInterfaceOrientation)orientation
{
    for (NSString *streamID in self.viewContainersDict.allKeys)
    {
        int rotate = 0;
        switch (orientation)
        {
            case UIInterfaceOrientationPortrait:
                rotate = 0;
                break;
                
            case UIInterfaceOrientationPortraitUpsideDown:
                rotate = 180;
                break;
                
            case UIInterfaceOrientationLandscapeLeft:
                rotate = 270;
                break;
                
            case UIInterfaceOrientationLandscapeRight:
                rotate = 90;
                break;
                
            default:
                return;
        }
        
        [[ZegoDemoHelper api] setViewRotation:rotate ofStream:streamID];
    }
}

- (void)changeFirstViewContent
{
    UIView *view = [self getFirstViewInContainer:self.playViewContainer];
    NSString *streamID = [self getStreamIDFromView:view];
    if (streamID == nil)
        return;
    
    id info = self.videoSizeDict[streamID];
    if (info == nil)
        return;
    
    BOOL isfull = [info boolValue];
    if (isfull)
    {
        [self exitFullScreen:streamID];
        [self onEnterFullScreenButton:nil];
    }
}


- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        
        UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
        [self setRotateFromInterfaceOrientation:orientation];
        [self changeFirstViewContent];
        
    } completion:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        
    }];
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    [super willAnimateRotationToInterfaceOrientation:toInterfaceOrientation duration:duration];
    
    [self setRotateFromInterfaceOrientation:toInterfaceOrientation];
    [self changeFirstViewContent];
}


@end
