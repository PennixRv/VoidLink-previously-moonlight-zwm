//
//  Logger.m
//  Moonlight
//
//  Created by Diego Waxemberg on 2/10/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "Logger.h"

#import <Foundation/Foundation.h>
#import <fcntl.h>
#import <pthread.h>
#import <unistd.h>

#if defined(NDEBUG)
static LogLevel LoggerLogLevel = LOG_I;
#else
// Debug is too spammy during discovery
// static LogLevel LoggerLogLevel = LOG_D;
static LogLevel LoggerLogLevel = LOG_I;
#endif

static int s_fileLogFd = -1;
static NSString* s_fileLogPath = nil;
static dispatch_once_t s_fileLogOnceToken;
static pthread_mutex_t s_fileLogMutex = PTHREAD_MUTEX_INITIALIZER;

static void LoggerWriteLineToFile(NSString* line) {
    if (s_fileLogFd < 0 || line == nil) {
        return;
    }

    @autoreleasepool {
        // Write whole line in a single write() call to avoid interleaving across threads.
        NSString* withNewline = [line hasSuffix:@"\n"] ? line : [line stringByAppendingString:@"\n"];
        NSData* data = [withNewline dataUsingEncoding:NSUTF8StringEncoding];
        if (data.length == 0) {
            return;
        }

        pthread_mutex_lock(&s_fileLogMutex);
        (void)write(s_fileLogFd, data.bytes, data.length);
        pthread_mutex_unlock(&s_fileLogMutex);
    }
}

NSString* LoggerGetLogFilePath(void) {
    return s_fileLogPath;
}

void LoggerInitFileLogging(void) {
#if defined(DEBUG)
    dispatch_once(&s_fileLogOnceToken, ^{
        @autoreleasepool {
            NSArray* paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
            NSString* cacheDir = paths.firstObject ?: NSTemporaryDirectory();
            NSString* logDir = [cacheDir stringByAppendingPathComponent:@"VoidLinkLogs"];

            [[NSFileManager defaultManager] createDirectoryAtPath:logDir
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:nil];

            NSString* logPath = [logDir stringByAppendingPathComponent:@"voidlink-debug.log"];
            NSString* prevPath = [logDir stringByAppendingPathComponent:@"voidlink-debug.prev.log"];

            // Rotate the previous log (best-effort).
            [[NSFileManager defaultManager] removeItemAtPath:prevPath error:nil];
            if ([[NSFileManager defaultManager] fileExistsAtPath:logPath]) {
                [[NSFileManager defaultManager] moveItemAtPath:logPath toPath:prevPath error:nil];
            }

            const char* fsPath = [logPath fileSystemRepresentation];
            int fd = open(fsPath, O_CREAT | O_WRONLY | O_TRUNC | O_APPEND, 0644);
            if (fd < 0) {
                return;
            }

            s_fileLogFd = fd;
            s_fileLogPath = logPath;

            NSString* header = [NSString stringWithFormat:@"=== VoidLink debug log start: %@ ===",
                                [NSDate date]];
            LoggerWriteLineToFile(header);
        }
    });
#endif
}

void LogTagv(LogLevel level, NSString* tag, NSString* fmt, va_list args) {
    NSString* levelPrefix = @"";

    if (level < LoggerLogLevel) {
        return;
    }

    switch(level) {
        case LOG_D:
            levelPrefix = PRFX_DEBUG;
            break;
        case LOG_I:
            levelPrefix = PRFX_INFO;
            break;
        case LOG_W:
            levelPrefix = PRFX_WARN;
            break;
        case LOG_E:
            levelPrefix = PRFX_ERROR;
            break;
        default:
            levelPrefix = @"";
            assert(false);
            break;
    }
    NSString* prefixedString;
    if (tag) {
        prefixedString = [NSString stringWithFormat:@"%@ (%@) %@", levelPrefix, tag, fmt];
    } else {
        prefixedString = [NSString stringWithFormat:@"%@ %@", levelPrefix, fmt];
    }

    // If file logging is enabled, format once and write the fully-rendered line.
    // Avoid any allocation work if file logging hasn't been initialized.
    if (s_fileLogFd >= 0) {
        va_list argsCopy;
        va_copy(argsCopy, args);
        NSString* rendered = [[NSString alloc] initWithFormat:prefixedString arguments:argsCopy];
        va_end(argsCopy);
        LoggerWriteLineToFile(rendered);
    }

    NSLogv(prefixedString, args);
}

void LogTag(LogLevel level, NSString* tag, NSString* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    LogTagv(level, tag, fmt, args);
    va_end(args);
}
