//
//  StreamManager.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//
//  Modified by True砖家 since 2024.7.9
//  Copyright © 2024 True砖家 @ Bilibili. All rights reserved.
//

#import "StreamManager.h"
#import "CryptoManager.h"
#import "HttpManager.h"
#import "Plot.h"
#import "Utils.h"
#import "DataManager.h"

#import "StreamView.h"
#import "ServerInfoResponse.h"
#import "HttpResponse.h"
#import "HttpRequest.h"
#import "IdManager.h"
#import "LocalizationHelper.h"

#include <Limelight.h>

#import <UIKit/UIKit.h>

@implementation StreamManager {
    StreamConfiguration* _config;

    UIView* _renderView;
    id<ConnectionCallbacks> _callbacks;
    Connection* _connection;
    VideoDecoderRenderer* _videoRenderer;
}

- (id) initWithConfig:(StreamConfiguration*)config renderView:(UIView*)view connectionCallbacks:(id<ConnectionCallbacks>)callbacks {
    self = [super init];
    _config = config;
    _renderView = view;
    _callbacks = callbacks;
    _config.riKey = [Utils randomBytes:16];
    _config.riKeyId = arc4random();
    return self;
}

- (void)main {
    [CryptoManager generateKeyPairUsingSSL];
    
    HttpManager* hMan = [[HttpManager alloc] initWithAddress:_config.host httpsPort:_config.httpsPort
                                                     serverCert:_config.serverCert];
    
    ServerInfoResponse* serverInfoResp = [[ServerInfoResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:serverInfoResp withUrlRequest:[hMan newServerInfoRequest:false]
                                       fallbackError:401 fallbackRequest:[hMan newHttpServerInfoRequest]]];
    NSString* pairStatus = [serverInfoResp getStringTag:@"PairStatus"];
    NSString* appversion = [serverInfoResp getStringTag:@"appversion"];
    NSString* gfeVersion = [serverInfoResp getStringTag:@"GfeVersion"];
    NSString* serverState = [serverInfoResp getStringTag:@"state"];
    if (![serverInfoResp isStatusOk]) {
        [_callbacks launchFailed:serverInfoResp.statusMessage];
        return;
    }
    else if (pairStatus == NULL || appversion == NULL || serverState == NULL) {
        [_callbacks launchFailed:@"Failed to connect to PC"];
        return;
    }
    
    if (![pairStatus isEqualToString:@"1"]) {
        // Not paired
        [_callbacks launchFailed:@"Device not paired to PC"];
        return;
    }
    
    // Only perform this check on GFE (as indicated by MJOLNIR in state value)
    if ((_config.width > 4096 || _config.height > 4096) && [serverState containsString:@"MJOLNIR"]) {
        // Pascal added support for 8K HEVC encoding support. Maxwell 2 could encode HEVC but only up to 4K.
        // We can't directly identify Pascal, but we can look for HEVC Main10 which was added in the same generation.
        NSString* codecSupport = [serverInfoResp getStringTag:@"ServerCodecModeSupport"];
        if (codecSupport == nil || !([codecSupport intValue] & 0x200)) {
            [_callbacks launchFailed:@"Your host PC's GPU doesn't support streaming video resolutions over 4K."];
            return;
        }
    }
    
    // Populate the config's version fields from serverinfo
    _config.appVersion = appversion;
    _config.gfeVersion = gfeVersion;
    
    // resumeApp and launchApp handle calling launchFailed
    NSString* sessionUrl;
    if ([serverState hasSuffix:@"_SERVER_BUSY"]) {
        // App already running, resume it
        if (![self resumeApp:hMan receiveSessionUrl:&sessionUrl]) {
            return;
        }
    } else {
        // Start app
        if (![self launchApp:hMan receiveSessionUrl:&sessionUrl]) {
            return;
        }
    }
    
    // Populate RTSP session URL from launch/resume response
    _config.rtspSessionUrl = sessionUrl;
    
    // Initializing the renderer must be done on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_videoRenderer = [[VideoDecoderRenderer alloc] initWithView:self->_renderView callbacks:self->_callbacks streamAspectRatio:(float)self->_config.width / (float)self->_config.height];

        self->_connection = [[Connection alloc] initWithConfig:self->_config renderer:self->_videoRenderer connectionCallbacks:self->_callbacks];
        NSOperationQueue* opQueue = [[NSOperationQueue alloc] init];
        [opQueue addOperation:self->_connection];
    });
}

- (void) setNeedRequeuing:(bool)needRequeuing{
    if (_videoRenderer.queueSize==0) return;
    [_videoRenderer.frameQueue clear];
    _videoRenderer.needRequeuing = needRequeuing;
}

- (void) stopStream
{
    [_connection terminate];
    _callbacks = nil;
}

- (BOOL) launchApp:(HttpManager*)hMan receiveSessionUrl:(NSString**)sessionUrl {
    HttpResponse* launchResp = [[HttpResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:launchResp withUrlRequest:[hMan newLaunchOrResumeRequest:@"launch" config:_config]]];
    NSString *gameSession = [launchResp getStringTag:@"gamesession"];
    if (![launchResp isStatusOk]) {
        [_callbacks launchFailed:launchResp.statusMessage];
        Log(LOG_E, @"Failed Launch Response: %@", launchResp.statusMessage);
        return FALSE;
    } else if (gameSession == NULL || [gameSession isEqualToString:@"0"]) {
        [_callbacks launchFailed:@"Failed to launch app"];
        Log(LOG_E, @"Failed to parse game session");
        return FALSE;
    }
    
    *sessionUrl = [launchResp getStringTag:@"sessionUrl0"];
    return TRUE;
}

- (BOOL) resumeApp:(HttpManager*)hMan receiveSessionUrl:(NSString**)sessionUrl {
    HttpResponse* resumeResp = [[HttpResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:resumeResp withUrlRequest:[hMan newLaunchOrResumeRequest:@"resume" config:_config]]];
    NSString* resume = [resumeResp getStringTag:@"resume"];
    if (![resumeResp isStatusOk]) {
        [_callbacks launchFailed:resumeResp.statusMessage];
        Log(LOG_E, @"Failed Resume Response: %@", resumeResp.statusMessage);
        return FALSE;
    } else if (resume == NULL || [resume isEqualToString:@"0"]) {
        [_callbacks launchFailed:@"Failed to resume app"];
        Log(LOG_E, @"Failed to parse resume response");
        return FALSE;
    }
    
    *sessionUrl = [resumeResp getStringTag:@"sessionUrl0"];
    return TRUE;
}

- (NSString*) getStatsOverlayText: (uint16_t) overlayLevel {
    video_stats_t stats;

    if (!_connection) {
        return nil;
    }
    
    if (![_connection getVideoStats:&stats]) {
        return nil;
    }
    
    uint32_t rtt, variance;
    NSString* latencyString;
    if (LiGetEstimatedRttInfo(&rtt, &variance)) {
        latencyString = [LocalizationHelper localizedStringForKey:@"%3u ms (var: %3u ms)", rtt, variance];
    }
    else {
        latencyString = @"N/A";
    }
    
    NSString* hostProcessingString;
    if (stats.framesWithHostProcessingLatency != 0) {
        hostProcessingString = [LocalizationHelper localizedStringForKey:@"Host processing latency min/max/avg: %.1f/%.1f/%.1f ms\n",
                                stats.minHostProcessingLatency / 10.f,
                                stats.maxHostProcessingLatency / 10.f,
                                (float)stats.totalHostProcessingLatency / stats.framesWithHostProcessingLatency / 10.f];
    }
    else {
        // If all frames are duplicates this can happen, but let's avoid having the whole stats area change height
        hostProcessingString = @"Host processing latency min/max/avg: -/-/- ms\n";
    }
    
    float interval = stats.endTime - stats.startTime;
    
    // Get frame pacing mode
    DataManager* dataMan = [[DataManager alloc] init];
    FramePacingMode framePacingMode = [[dataMan getSettings].framePacingMode integerValue];

    // Calculate FPS differently based on pacing mode
    float fps;
    if (framePacingMode == FramePacingModeLegacy || framePacingMode == FramePacingModeOff) {
        fps = stats.totalFrames / interval;
    } else {
        float scalePlotMetrics = stats.frameDropMetrics.nsamples > 0 ? ((float)stats.frameDropMetrics.nsamples / stats.totalFrames) : 1.0f;
        fps = (stats.totalFrames - stats.networkDroppedFrames - (stats.frameDropMetrics.total / scalePlotMetrics)) / interval;
    }

    double avgVideoMbps = [_connection getBwTracker].averageMbps;
    double peakVideoMbps = [_connection getBwTracker].peakMbps;

    NSString* colorRange = _config.fullColorRange ? @"Full" : @"Limited";

    NSString* outputInfo = nil;
#if TARGET_OS_TV
    // Help validate 4K60 / 1440p120 modes: show the current HDMI output mode we're running under.
    // Note: maximumFramesPerSecond reflects the current display mode, which should change when
    // AVDisplayManager.preferredDisplayCriteria is applied at stream start.
    UIScreen* screen = [UIScreen mainScreen];
    NSInteger maxHz = screen.maximumFramesPerSecond;
    CGSize nativeSize = CGSizeZero;
    if ([screen respondsToSelector:@selector(nativeBounds)]) {
        nativeSize = screen.nativeBounds.size;
    } else {
        // Fallback: approximate using points * scale.
        nativeSize = CGSizeMake(screen.bounds.size.width * screen.scale, screen.bounds.size.height * screen.scale);
    }

    NSString* hostType = _config.isNvidiaServerSoftware ? @"GFE/GameStream" : @"Sunshine";
    NSString* fpsSuffix = (_config.requestedFrameRate > 0 && _config.requestedFrameRate != _config.frameRate)
        ? [NSString stringWithFormat:@" (requested %d)", _config.requestedFrameRate]
        : @"";
    NSString* bitrateSuffix = (_config.requestedBitRate > 0 && _config.requestedBitRate != _config.bitRate)
        ? [NSString stringWithFormat:@" (requested %d)", _config.requestedBitRate]
        : @"";
    float configuredMbps = _config.bitRate / 1000.0f;

    if (nativeSize.width > 0 && nativeSize.height > 0) {
        outputInfo = [LocalizationHelper localizedStringForKey:
                      @"Output: %.0fx%.0f @ %ld Hz (host: %@)\n"
                      @"Stream: %dx%d@%d%@, bitrate: %.1f Mbps%@\n",
                      nativeSize.width, nativeSize.height, (long)maxHz, hostType,
                      _config.width, _config.height, _config.frameRate, fpsSuffix,
                      configuredMbps, bitrateSuffix];
    } else {
        outputInfo = [LocalizationHelper localizedStringForKey:
                      @"Output: %ld Hz (host: %@)\n"
                      @"Stream: %dx%d@%d%@, bitrate: %.1f Mbps%@\n",
                      (long)maxHz, hostType,
                      _config.width, _config.height, _config.frameRate, fpsSuffix,
                      configuredMbps, bitrateSuffix];
    }
#endif

    if(overlayLevel == 1) {
        NSString* base = [LocalizationHelper localizedStringForKey:@"simplifiedOsdText",
                          fps,
                          stats.networkDroppedFrames / interval,
                          avgVideoMbps,
                          latencyString];
        return outputInfo != nil ? [outputInfo stringByAppendingString:base] : base;
    }
    else {
        if (framePacingMode == FramePacingModeLegacy || framePacingMode == FramePacingModeOff) {
            NSString* rendererWithPacing = stats.renderingBackendString;
            if ([stats.renderingBackendString isEqualToString:@"AVSampleBuffer"]) {
                if (framePacingMode == FramePacingModeOff) {
                    rendererWithPacing = @"AVSampleBuffer (No Pacing)";
                } else {
                    rendererWithPacing = @"AVSampleBuffer (Legacy Pacing)";
                }
            }
            
            NSString* base = [LocalizationHelper localizedStringForKey:@"Video stream: %dx%d %.2f FPS (Codec: %@, %@)\n"
                              "Bitrate: %.1f Mbps, Peak: %.1f\n"
                              "%@"
                              "Renderer: %@\n"
                              "Frames dropped by network: %.1f%%\n"
                              "Average network latency: %@",
                              _config.width,
                              _config.height,
                              fps,
                              [_connection getActiveCodecName],
                              colorRange,
                              avgVideoMbps, peakVideoMbps,
                              hostProcessingString,
                              rendererWithPacing,
                              (stats.networkDroppedFrames / stats.totalFrames) * 100.0,
                              latencyString];
            return outputInfo != nil ? [outputInfo stringByAppendingString:base] : base;
        } else {
            NSString* rendererWithPacing = stats.renderingBackendString;
            if ([stats.renderingBackendString isEqualToString:@"AVSampleBuffer"]) {
                rendererWithPacing = @"AVSampleBuffer (Queue Pacing)";
            }
            
            NSString* base = [LocalizationHelper localizedStringForKey:@"Video stream: %dx%d %.2f FPS (Codec: %@, %@)\n"
                              "Bitrate: %.1f Mbps, Peak: %.1f, Frames buffered: %.1f\n"
                              "%@"
                              "Renderer: %@\n"
                              "Frames dropped by network/pacing jitter: %.1f%% / %.1f%%\n"
                              "Average network latency: %@\n"
                              "Decode time: %.2f/%.2f/%.2f ms",
                              _config.width,
                              _config.height,
                              fps,
                              [_connection getActiveCodecName],
                              colorRange,
                              avgVideoMbps, peakVideoMbps, stats.frameQueueMetrics.avg,
                              hostProcessingString,
                              rendererWithPacing,
                              (stats.networkDroppedFrames / stats.totalFrames) * 100.0,
                              stats.frameDropMetrics.nsamples > 0 ? (stats.frameDropMetrics.total / stats.frameDropMetrics.nsamples) * 100.0 : 0.0f,
                              latencyString,
                              stats.decodeMetrics.min, stats.decodeMetrics.max, stats.decodeMetrics.avg];
            return outputInfo != nil ? [outputInfo stringByAppendingString:base] : base;
        }
    }
}

@end
