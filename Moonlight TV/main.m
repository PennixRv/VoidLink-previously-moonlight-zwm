//
//  main.m
//  Moonlight TV
//
//  Created by Diego Waxemberg on 8/25/18.
//  Copyright © 2018 Moonlight Game Streaming Project. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import "Logger.h"

#define SDL_MAIN_HANDLED
#import <SDL.h>

static NSString* const kVoidLinkTVLaunchInProgressKey = @"VoidLinkTVLaunchInProgress";
static NSString* const kVoidLinkTVLaunchTimestampKey = @"VoidLinkTVLaunchTimestamp";
static NSString* const kVoidLinkTVCrashCountKey = @"VoidLinkTVCrashCount";
static NSString* const kVoidLinkTVSafeModeKey = @"VoidLinkTVSafeMode";
static NSString* const kVoidLinkTVSafeModeReasonKey = @"VoidLinkTVSafeModeReason";

static void VoidLinkTVApplySafeModeDefaults(NSUserDefaults* defaults) {
    // Keep these defaults conservative and known-good to help escape crash loops.
    // Resolution values follow Settings.bundle mapping:
    // 0=720p, 1=1080p, 2=4K, 3=1440p
    [defaults setInteger:0 forKey:@"streamPreset"]; // Custom (don't let presets override Safe Mode)
    [defaults setInteger:1 forKey:@"streamResolution"]; // 1080p
    [defaults setInteger:60 forKey:@"framerate"];
    [defaults setInteger:20000 forKey:@"bitrate"];
    [defaults setInteger:2 forKey:@"audioConfig"]; // stereo

    // Video safety: disable experimental paths.
    [defaults setInteger:0 forKey:@"preferredCodec"]; // Auto
    [defaults setInteger:0 forKey:@"useFramePacing"]; // Lowest latency
    [defaults setBool:NO forKey:@"enableHdr"];
    [defaults setInteger:0 forKey:@"renderingBackend"]; // AVSampleBuffer
    [defaults setInteger:1 forKey:@"frameQueueSize"];
    [defaults setBool:NO forKey:@"enableYUV444"];
    [defaults setBool:NO forKey:@"fullRange"];

    // Diagnostics: keep graphs off, but turn on stats overlay to aid verification.
    [defaults setBool:NO forKey:@"enableGraphs"];
    [defaults setInteger:50 forKey:@"graphOpacity"];
    [defaults setBool:YES forKey:@"statsOverlay"];
}

static void VoidLinkTVHandleLaunchCrashLoopIfNeeded(void) {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;

    BOOL lastInProgress = [defaults boolForKey:kVoidLinkTVLaunchInProgressKey];
    NSTimeInterval lastTs = [defaults doubleForKey:kVoidLinkTVLaunchTimestampKey];
    NSInteger crashCount = [defaults integerForKey:kVoidLinkTVCrashCountKey];

    // If the previous launch died before clearing the "in progress" marker, we assume a crash loop.
    // Use a small time window to avoid false positives (power loss, force-quit, long suspends).
    const NSTimeInterval kCrashLoopWindowSeconds = 120.0;
    if (lastInProgress && lastTs > 0 && (now - lastTs) < kCrashLoopWindowSeconds) {
        crashCount = MIN(crashCount + 1, 50);
        [defaults setInteger:crashCount forKey:kVoidLinkTVCrashCountKey];
        [defaults setBool:YES forKey:kVoidLinkTVSafeModeKey];
        [defaults setObject:[NSString stringWithFormat:@"Previous launch crashed before reaching Hosts (within %.0fs).", kCrashLoopWindowSeconds]
                     forKey:kVoidLinkTVSafeModeReasonKey];

        VoidLinkTVApplySafeModeDefaults(defaults);
    }

    // Mark this launch as "in progress" until MainFrameViewController clears it after startup.
    [defaults setBool:YES forKey:kVoidLinkTVLaunchInProgressKey];
    [defaults setDouble:now forKey:kVoidLinkTVLaunchTimestampKey];
    [defaults synchronize];
}

static void VoidLinkUncaughtExceptionHandler(NSException* exception) {
    Log(LOG_E, @"Uncaught exception: %@\nCall stack: %@", exception, exception.callStackSymbols);
}

int main(int argc, char * argv[]) {
    @autoreleasepool {
        SDL_SetMainReady();
        LoggerInitFileLogging();
        NSSetUncaughtExceptionHandler(&VoidLinkUncaughtExceptionHandler);
        VoidLinkTVHandleLaunchCrashLoopIfNeeded();
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
