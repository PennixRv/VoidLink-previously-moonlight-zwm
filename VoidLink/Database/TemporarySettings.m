//
//  TemporarySettings.m
//  Moonlight
//
//  Created by Cameron Gutman on 12/1/15.
//  Copyright © 2015 Moonlight Stream. All rights reserved.
//
//  Modified by True砖家 since 2024.6.1
//  Copyright © 2024 True砖家 @ Bilibili. All rights reserved.
//

#import "TemporarySettings.h"

@implementation TemporarySettings

- (id) initFromSettings:(Settings*)settings {
    self = [self init];
    
    self.parent = settings;
    
#if TARGET_OS_TV
    // Apply default values from our Root.plist
    NSString* settingsBundle = [[NSBundle mainBundle] pathForResource:@"Settings" ofType:@"bundle"];
    NSDictionary* settingsData = [NSDictionary dictionaryWithContentsOfFile:[settingsBundle stringByAppendingPathComponent:@"Root.plist"]];
    NSArray* preferences = [settingsData objectForKey:@"PreferenceSpecifiers"];
    NSMutableDictionary* defaultsToRegister = [[NSMutableDictionary alloc] initWithCapacity:[preferences count]];
    for (NSDictionary* prefSpecification in preferences) {
        NSString* key = [prefSpecification objectForKey:@"Key"];
        if (key != nil) {
            [defaultsToRegister setObject:[prefSpecification objectForKey:@"DefaultValue"] forKey:key];
        }
    }
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaultsToRegister];
    
	    // These values are user-editable via Settings.bundle, so they must never hard-crash the app.
	    // Also note: Settings.bundle values are often stored as NSStrings (e.g., "60"), so we read
	    // via objectForKey + integerValue to avoid relying on numeric-only accessors.
	    NSInteger streamPreset = [[[NSUserDefaults standardUserDefaults] objectForKey:@"streamPreset"] integerValue];

	    NSInteger bitrateKbps = [[[NSUserDefaults standardUserDefaults] objectForKey:@"bitrate"] integerValue];
	    if (bitrateKbps <= 0) {
	        bitrateKbps = 20000;
	    }
	    self.bitrate = @(bitrateKbps);

    NSInteger fps = [[[NSUserDefaults standardUserDefaults] objectForKey:@"framerate"] integerValue];
    if (fps <= 0) {
        fps = 60;
    }
    self.framerate = @(fps);

    NSInteger audioConfig = [[[NSUserDefaults standardUserDefaults] objectForKey:@"audioConfig"] integerValue];
    // Expected: 2, 6, 8 (Stereo, 5.1, 7.1). Fall back to stereo on invalid data.
    if (!(audioConfig == 2 || audioConfig == 6 || audioConfig == 8)) {
        audioConfig = 2;
    }
    self.audioConfig = @(audioConfig);

    NSInteger preferredCodec = [[[NSUserDefaults standardUserDefaults] objectForKey:@"preferredCodec"] integerValue];
    if (preferredCodec < 0 || preferredCodec > 3) {
        preferredCodec = 0;
    }
    self.preferredCodec = (typeof(self.preferredCodec))preferredCodec;
    self.enableYUV444 = [[NSUserDefaults standardUserDefaults] boolForKey:@"enableYUV444"];
    self.enablePIP = [[NSUserDefaults standardUserDefaults] boolForKey:@"enablePIP"];
    self.fullColorRange = [[NSUserDefaults standardUserDefaults] boolForKey:@"fullRange"];
    NSInteger frameQueueSize = [[[NSUserDefaults standardUserDefaults] objectForKey:@"frameQueueSize"] integerValue];
    if (frameQueueSize < 0 || frameQueueSize > 5) {
        frameQueueSize = 1;
    }
    self.frameQueueSize = @(frameQueueSize);
    self.playAudioOnPC = [[NSUserDefaults standardUserDefaults] boolForKey:@"audioOnPC"];
    self.enableHdr = [[NSUserDefaults standardUserDefaults] boolForKey:@"enableHdr"];
    self.optimizeGames = [[NSUserDefaults standardUserDefaults] boolForKey:@"optimizeGames"];
    self.multiController = [[NSUserDefaults standardUserDefaults] boolForKey:@"multipleControllers"];
    self.swapABXYButtons = [[NSUserDefaults standardUserDefaults] boolForKey:@"swapABXYButtons"];
    self.btMouseSupport = [[NSUserDefaults standardUserDefaults] boolForKey:@"btMouseSupport"];
    self.statsOverlayEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"statsOverlay"];
    self.enableGraphs = [[NSUserDefaults standardUserDefaults] boolForKey:@"enableGraphs"];
    NSInteger graphOpacity = [[[NSUserDefaults standardUserDefaults] objectForKey:@"graphOpacity"] integerValue];
    if (graphOpacity < 0 || graphOpacity > 100) {
        graphOpacity = 50;
    }
    self.graphOpacity = @(graphOpacity);

    NSInteger renderingBackend = [[[NSUserDefaults standardUserDefaults] objectForKey:@"renderingBackend"] integerValue];
    if (renderingBackend < 0 || renderingBackend > 1) {
        renderingBackend = 0;
    }
    self.renderingBackend = @(renderingBackend);

    // tvOS settings use a simplified "useFramePacing" preference:
    // - 0: Lowest Latency
    // - 1: Smoothest Video
    //
    // Internally, the renderer expects FramePacingMode values (see DataManager.h):
    // 0 = Off, 1 = Legacy, 2 = Queue.
    //
    // Keep backwards-compatibility with an older "framePacingMode" key if present.
    NSNumber* rawFramePacingMode = [[NSUserDefaults standardUserDefaults] objectForKey:@"framePacingMode"];
    if (rawFramePacingMode != nil) {
        self.framePacingMode = @([rawFramePacingMode integerValue]);
    } else {
        NSInteger useFramePacingPreference = [[NSUserDefaults standardUserDefaults] integerForKey:@"useFramePacing"];
        const NSInteger kFramePacingModeOff = 0;
        const NSInteger kFramePacingModeQueue = 2;
        self.framePacingMode = @(useFramePacingPreference ? kFramePacingModeQueue : kFramePacingModeOff);
    }

	    NSInteger screenSize = [[[NSUserDefaults standardUserDefaults] objectForKey:@"streamResolution"] integerValue];
	    switch (screenSize) {
	        case 0:
	            self.height = [NSNumber numberWithInteger:720];
	            self.width = [NSNumber numberWithInteger:1280];
            break;
        case 1:
            self.height = [NSNumber numberWithInteger:1080];
            self.width = [NSNumber numberWithInteger:1920];
            break;
        case 2:
            self.height = [NSNumber numberWithInteger:2160];
            self.width = [NSNumber numberWithInteger:3840];
            break;
        case 3:
            self.height = [NSNumber numberWithInteger:1440];
            self.width = [NSNumber numberWithInteger:2560];
            break;
        default:
            // Unknown value, fall back to 1080p.
            self.height = [NSNumber numberWithInteger:1080];
	            self.width = [NSNumber numberWithInteger:1920];
	            break;
	    }

	    // Convenience presets for tvOS, to make "4K60" and "2K120" real modes, not just independent toggles.
	    // Selecting a preset intentionally overrides the corresponding individual settings.
	    if (streamPreset == 1) {
	        // 4K60
	        self.width = @3840;
	        self.height = @2160;
	        self.framerate = @60;
	        self.bitrate = @(MAX(self.bitrate.integerValue, 80000)); // 80 Mbps baseline
	        self.preferredCodec = CODEC_PREF_HEVC;

	        // Favor smooth video at this quality level.
	        self.framePacingMode = @2; // FramePacingModeQueue
	        self.frameQueueSize = @2;
	    }
	    else if (streamPreset == 2) {
	        // 2K120 (1440p @ 120)
	        self.width = @2560;
	        self.height = @1440;
	        self.framerate = @120;
	        self.bitrate = @(MAX(self.bitrate.integerValue, 100000)); // 100 Mbps baseline
	        self.preferredCodec = CODEC_PREF_HEVC;

	        // Favor latency at high FPS.
	        self.framePacingMode = @0; // FramePacingModeOff
	        self.frameQueueSize = @1;
	    }

	    // tvOS has no touchscreen. Keep OSC disabled even if CoreData has stale values.
	    // OnScreenControlsLevelOff is 0, but we intentionally avoid importing the OSC headers here.
	    self.onscreenControls = @(0);
#else
    self.settingsMenuMode = settings.settingsMenuMode;
    self.settingsMenuWidth = settings.settingsMenuWidth;
    self.bitrate = settings.bitrate;
    self.framerate = settings.framerate;
    self.height = settings.height;
    self.width = settings.width;
    self.audioConfig = settings.audioConfig;
    self.preferredCodec = settings.preferredCodec;
    self.enableYUV444 = settings.enableYUV444;
    self.sdrPerformanceWorkaround = settings.sdrPerformanceWorkaround;
    self.enablePIP = settings.enablePIP;
    self.fullColorRange = settings.fullColorRange;
    self.frameQueueSize = settings.frameQueueSize;
    self.enableFrameTimebase  = settings.enableFrameTimebase;
    self.asyncFrameDequeue = settings.asyncFrameDequeue;
    self.playAudioOnPC = settings.playAudioOnPC;
    self.redirectMic = settings.redirectMic;
    self.useBuiltinMic = settings.useBuiltinMic;
    self.enableHdr = settings.enableHdr;
    self.optimizeGames = settings.optimizeGames;
    self.multiController = settings.multiController;
    self.buttonVisualFeedback = settings.buttonVisualFeedback;
    self.touchPointTracking = settings.touchPointTracking;
    self.swapABXYButtons = settings.swapABXYButtons;
    self.onscreenControls = settings.onscreenControls;
    self.gyroMode = settings.gyroMode;
    self.emulatedControllerType = settings.emulatedControllerType;
    self.reverseMouseWheelDirection = settings.reverseMouseWheelDirection;
    self.asyncNativeTouchPriority = settings.asyncNativeTouchPriority;
    self.btMouseSupport = settings.btMouseSupport;
    // self.absoluteTouchMode = settings.absoluteTouchMode;
    self.touchMode = settings.touchMode;
    self.statsOverlayLevel = settings.statsOverlayLevel;
    self.statsOverlayEnabled = settings.statsOverlayEnabled;
    self.keyboardToggleFingers = settings.keyboardToggleFingers;
    self.oscLayoutToolFingers = settings.oscLayoutToolFingers;
    self.slideToSettingsScreenEdge = settings.slideToSettingsScreenEdge;
    self.slideToSettingsDistance = settings.slideToSettingsDistance;
    self.liftStreamViewForKeyboard = settings.liftStreamViewForKeyboard;
    self.showKeyboardToolbar = settings.showKeyboardToolbar;
    self.touchMoveEventInterval = settings.touchMoveEventInterval;
    self.touchPointerVelocityFactor = settings.touchPointerVelocityFactor;
    self.mousePointerVelocityFactor = settings.mousePointerVelocityFactor;
    self.gyroSensitivity = settings.gyroSensitivity;
    self.localVolume = settings.localVolume;
    self.micVolume = settings.micVolume;
    self.pointerVelocityModeDivider = settings.pointerVelocityModeDivider;
    self.unlockDisplayOrientation = settings.unlockDisplayOrientation;
    self.resolutionSelected = settings.resolutionSelected;
    self.externalDisplayMode = settings.externalDisplayMode;
    self.localMousePointerMode = settings.localMousePointerMode;
    self.enableGraphs = settings.enableGraphs;
    self.graphOpacity = settings.graphOpacity;
    self.renderingBackend = settings.renderingBackend;
    self.framePacingMode = settings.framePacingMode;
    self.sendDummyEvent = settings.sendDummyEvent;
    self.rememberFoldState = settings.rememberFoldState;
    self.gyroBiasX = settings.gyroBiasX;
    self.gyroBiasY = settings.gyroBiasY;
    self.gyroBiasZ = settings.gyroBiasZ;
    self.singleTapSensitivity = settings.singleTapSensitivity;
    self.backgroundSessionTimer = settings.backroundSessionTimer;
    self.edgeSlidingSensitivity = settings.edgeSlidingSensitivity;
    self.appTheme = settings.appTheme;
    self.hapticEngine = settings.hapticEngine;
    self.uniqueId = settings.uniqueId;
    self.audioEngine = settings.audioEngine;
    self.delayLeftClick = settings.delayLeftClick;
    self.duckOtherApps = settings.duckOtherApps;
    self.muteInBackground = settings.muteInBackground;
    self.relativeTouchSlideThreshold = settings.relativeTouchSlideThreshold;
    self.enablePinch = settings.enablePinch;
    self.scrollSensitivity = settings.scrollSensitivity;
    self.pinchSensitivity = settings.pinchSensitivity;
    self.leftClickDelayMs = settings.leftClickDelayMs;
    self.ctrlDownForPinch = settings.ctrlDownForPinch;
    self.settingsMenuOffset = settings.settingsMenuOffset;
    self.passthroughGestures = settings.passthroughGestures;
    self.mapControllerToMouse = settings.mapControllerToMouse;
    self.controllerMouseLeftButton = settings.controllerMouseLeftButton;
    self.controllerMouseRightButton = settings.controllerMouseRightButton;
    self.controllerMouseSwitch = settings.controllerMouseSwitch;
    self.controllerMouseStick = settings.controllerMouseStick;
    self.controllerMousePointerVelocity = settings.controllerMousePointerVelocity;
    self.controllerMouseExpo = settings.controllerMouseExpo;
    
    
    // Pencil settings:
    self.pencilTickMode = settings.pencilTickMode;
    self.pencilTickIntervalUs = settings.pencilTickIntervalUs;

#endif
    
    return self;
}

@end
