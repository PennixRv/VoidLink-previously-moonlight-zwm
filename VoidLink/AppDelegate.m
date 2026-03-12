//
//  AppDelegate.m
//  Moonlight
//
//  Created by Diego Waxemberg on 1/17/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//
//  Modified by True砖家 since 2024.7.12
//  Copyright © 2024 True砖家 @ Bilibili. All rights reserved.
//

#import "AppDelegate.h"
#import "MainFrameViewController.h"
#import "VoidLink-Swift.h"

#if TARGET_OS_TV
@class VoidLinkTVSafeModeViewController;
#endif

@implementation AppDelegate

@synthesize managedObjectContext = _managedObjectContext;
@synthesize managedObjectModel = _managedObjectModel;
@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;

static NSOperationQueue* mainQueue;

#if TARGET_OS_TV
static NSString* DB_NAME = @"Moonlight_tvOS.bin";
static NSString* const kVoidLinkTVLaunchInProgressKey = @"VoidLinkTVLaunchInProgress";
static NSString* const kVoidLinkTVCrashCountKey = @"VoidLinkTVCrashCount";
static NSString* const kVoidLinkTVSafeModeKey = @"VoidLinkTVSafeMode";
static NSString* const kVoidLinkTVSafeModeReasonKey = @"VoidLinkTVSafeModeReason";
#else
static NSString* DB_NAME = @"Limelight_iOS.sqlite";
#endif

#pragma mark - UISceneSession lifecycle

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options API_AVAILABLE(ios(13.0)){
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}

- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions API_AVAILABLE(ios(13.0)){
}

#if TARGET_OS_TV
- (void)tvosSwitchToMainUI
{
    UIStoryboard* storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    UIViewController* initial = [storyboard instantiateInitialViewController];
    if (initial == nil) {
        Log(LOG_E, @"Failed to instantiate Main storyboard initial view controller");
        return;
    }
    self.window.rootViewController = initial;
    [self.window makeKeyAndVisible];
}

- (void)tvosScheduleLaunchSuccessMarkerClear
{
    // Mirror the logic in MainFrameViewController, but used when we never reach it (Safe Mode splash).
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [defaults setBool:NO forKey:kVoidLinkTVLaunchInProgressKey];
        [defaults setInteger:0 forKey:kVoidLinkTVCrashCountKey];
        [defaults setBool:NO forKey:kVoidLinkTVSafeModeKey];
        [defaults removeObjectForKey:kVoidLinkTVSafeModeReasonKey];
        [defaults synchronize];
    });
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    (void)application;
    (void)launchOptions;

    // Keep command defaults consistent across platforms.
    [CommandManager presetDefaultCommands];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    BOOL safeMode = [[NSUserDefaults standardUserDefaults] boolForKey:kVoidLinkTVSafeModeKey];
    if (safeMode) {
        UIViewController* safeVC = [[VoidLinkTVSafeModeViewController alloc] init];
        UINavigationController* nav = [[UINavigationController alloc] initWithRootViewController:safeVC];
        nav.navigationBar.translucent = NO;
        nav.navigationBar.barTintColor = [UIColor blackColor];
        nav.navigationBar.titleTextAttributes = @{ NSForegroundColorAttributeName : [UIColor whiteColor] };
        self.window.rootViewController = nav;
        [self.window makeKeyAndVisible];

        // If the app stays alive long enough to show the Safe Mode UI, clear the crash-loop marker.
        [self tvosScheduleLaunchSuccessMarkerClear];
        return YES;
    }

    [self tvosSwitchToMainUI];
    return YES;
}

#endif


#if !TARGET_OS_TV

/*
// orietation limitatioin test
- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    UIViewController *topController = window.rootViewController;
    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }
    return [topController supportedInterfaceOrientations];
}
*/

/*
- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    NSLog(@"orientation limit");
        return UIInterfaceOrientationMaskLandscape;
}
*/

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for command tool customization after application launch (works only when user default is nil)
    [CommandManager presetDefaultCommands];
    
    // For iOS 12 and below, we need to manually create the window
    if (@available(iOS 13.0, *)) {
        // Scene delegate will handle window creation
    } else {
        self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
        
        NSString *storyboardName;
        if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            storyboardName = @"iPad";
        } else {
            storyboardName = @"iPhone";
        }
        
        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:storyboardName bundle:nil];
        UIViewController *initialViewController = [storyboard instantiateInitialViewController];
        
        self.window.rootViewController = initialViewController;
        [self.window makeKeyAndVisible];
    }
    
    return YES;
}


- (void)application:(UIApplication *)application performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void (^)(BOOL succeeded))completionHandler {
    _pcUuidToLoad = (NSString*)[shortcutItem.userInfo objectForKey:@"UUID"];
    _shortcutCompletionHandler = completionHandler;
}
#endif

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Saves changes in the application's managed object context before the application terminates.
    [self saveContext];
}

- (void)saveContext
{
    NSManagedObjectContext *managedObjectContext = [self managedObjectContext];
    if (managedObjectContext != nil) {
        [managedObjectContext performBlock:^{
            if (![managedObjectContext hasChanges]) {
                return;
            }
            NSError *error = nil;
            if (![managedObjectContext save:&error]) {
                Log(LOG_E, @"Critical database error: %@, %@", error, [error userInfo]);
            }
            
#if TARGET_OS_TV
            NSData* dbData = [NSData dataWithContentsOfURL:[[[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] lastObject] URLByAppendingPathComponent:DB_NAME]];
            [[NSUserDefaults standardUserDefaults] setObject:dbData forKey:DB_NAME];
#endif
        }];
    }
}

#pragma mark - Core Data stack

// Returns the managed object context for the application.
// If the context doesn't already exist, it is created and bound to the persistent store coordinator for the application.
- (NSManagedObjectContext *)managedObjectContext
{
    if (_managedObjectContext != nil) {
        return _managedObjectContext;
    }
    
    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (coordinator != nil) {
        _managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        [_managedObjectContext setPersistentStoreCoordinator:coordinator];
    }
    return _managedObjectContext;
}

// Returns the managed object model for the application.
// If the model doesn't already exist, it is created from the application's model.
- (NSManagedObjectModel *)managedObjectModel
{
    if (_managedObjectModel != nil) {
        return _managedObjectModel;
    }
    _managedObjectModel = [NSManagedObjectModel mergedModelFromBundles:nil];
    return _managedObjectModel;
}

// Returns the persistent store coordinator for the application.
// If the coordinator doesn't already exist, it is created and the application's store added to it.
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
    if (_persistentStoreCoordinator != nil) {
        return _persistentStoreCoordinator;
    }
    
    _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithBool:YES], NSMigratePersistentStoresAutomaticallyOption,
                             [NSNumber numberWithBool:YES], NSInferMappingModelAutomaticallyOption, nil];
    NSString* storeType;
    
#if TARGET_OS_TV
    // Use a binary store for tvOS since we will need exclusive access to the file
    // to serialize into NSUserDefaults.
    storeType = NSBinaryStoreType;
#else
    storeType = NSSQLiteStoreType;
#endif
    
    // We must ensure the persistent store is ready to opened
    [self preparePersistentStore];

    NSURL* storeURL = [self getStoreURL];
    NSError* error = nil;

    // Previous implementation used recursion and could loop indefinitely if the
    // persistent store could never be created (eventually stack overflowing).
    // Retry once after dropping the database, then fall back to in-memory storage.
    const int kMaxAttempts = 2;
    for (int attempt = 1; attempt <= kMaxAttempts; attempt++) {
        error = nil;
        if ([_persistentStoreCoordinator addPersistentStoreWithType:storeType
                                                     configuration:nil
                                                               URL:storeURL
                                                           options:options
                                                             error:&error]) {
            return _persistentStoreCoordinator;
        }

        Log(LOG_E, @"Critical database error (attempt %d/%d) opening %@ store at %@: %@, %@",
            attempt, kMaxAttempts, storeType, storeURL, error, [error userInfo]);

        // On failure, drop the on-disk database and try again.
        [self dropDatabase];
        [self preparePersistentStore];
    }

    // If the DB still can't be opened, continue without persistence instead of crashing.
    error = nil;
    if (![_persistentStoreCoordinator addPersistentStoreWithType:NSInMemoryStoreType
                                                 configuration:nil
                                                           URL:nil
                                                       options:options
                                                         error:&error]) {
        Log(LOG_E, @"Failed to create in-memory persistent store: %@, %@", error, [error userInfo]);
    } else {
        Log(LOG_W, @"Using in-memory persistent store. Hosts/settings will not persist across launches.");
    }

    return _persistentStoreCoordinator;
}

#pragma mark - Application's Documents directory

// Returns the URL to the application's Documents directory.
- (NSURL *)applicationDocumentsDirectory
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

- (void) dropDatabase
{
    // Delete the file on disk
    [[NSFileManager defaultManager] removeItemAtURL:[self getStoreURL] error:nil];
    
#if TARGET_OS_TV
    // Also delete the copy in the NSUserDefaults on tvOS
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:DB_NAME];
#endif
}

- (void) preparePersistentStore
{
#if TARGET_OS_TV
    // On tvOS, we may need to inflate the DB from NSUserDefaults
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cacheDirectory = [paths objectAtIndex:0];
    NSString *dbPath = [cacheDirectory stringByAppendingPathComponent:DB_NAME];
    
    // Always prefer the on disk version
    if (![[NSFileManager defaultManager] fileExistsAtPath:dbPath]) {
        // If that is unavailable, inflate it from NSUserDefaults
        NSData* data = [[NSUserDefaults standardUserDefaults] dataForKey:DB_NAME];
        if (data != nil) {
            Log(LOG_I, @"Inflating database from NSUserDefaults");
            [data writeToFile:dbPath atomically:YES];
        }
        else {
            Log(LOG_I, @"No database on disk or in NSUserDefaults");
        }
    }
    else {
        Log(LOG_I, @"Using cached database");
    }
#endif
}

- (NSURL*) getStoreURL {
#if TARGET_OS_TV
    // We use the cache folder to store our database on tvOS
    return [[[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] lastObject] URLByAppendingPathComponent:DB_NAME];
#else
    return [[self applicationDocumentsDirectory] URLByAppendingPathComponent:DB_NAME];
#endif
}

@end

#if TARGET_OS_TV

@interface AppDelegate (TVSafeMode)
- (void)tvosSwitchToMainUI;
@end

@interface VoidLinkTVSafeModeViewController : UIViewController
@end

@implementation VoidLinkTVSafeModeViewController

- (UIButton *)makePrimaryButtonWithTitle:(NSString *)title action:(SEL)action
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];

    button.titleLabel.font = [UIFont systemFontOfSize:34 weight:UIFontWeightSemibold];
    button.contentEdgeInsets = UIEdgeInsetsMake(18, 28, 18, 28);
    button.layer.cornerRadius = 14.0;
    button.clipsToBounds = YES;
    button.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

    [button addTarget:self action:action forControlEvents:UIControlEventPrimaryActionTriggered];
    return button;
}

- (UIViewController *)makeLogsViewController
{
    // Mirror MainFrameViewController's log viewer but keep it self-contained for Safe Mode.
    NSString* currentLogPath = LoggerGetLogFilePath();
    if (currentLogPath == nil) {
        LoggerInitFileLogging();
        currentLogPath = LoggerGetLogFilePath();
    }

    NSString* logDir = nil;
    if (currentLogPath != nil) {
        logDir = [currentLogPath stringByDeletingLastPathComponent];
    } else {
        NSArray* paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString* cacheDir = paths.firstObject ?: NSTemporaryDirectory();
        logDir = [cacheDir stringByAppendingPathComponent:@"VoidLinkLogs"];
        currentLogPath = [logDir stringByAppendingPathComponent:@"voidlink-debug.log"];
    }

    NSString* prevLogPath = [logDir stringByAppendingPathComponent:@"voidlink-debug.prev.log"];

    NSError* currentError = nil;
    NSString* currentContent = [NSString stringWithContentsOfFile:currentLogPath encoding:NSUTF8StringEncoding error:&currentError];
    if (currentContent == nil) {
        currentContent = [NSString stringWithFormat:@"(Failed to read current log)\npath: %@\nerror: %@\n", currentLogPath, currentError];
    }

    NSError* prevError = nil;
    NSString* prevContent = [NSString stringWithContentsOfFile:prevLogPath encoding:NSUTF8StringEncoding error:&prevError];
    if (prevContent == nil) {
        prevContent = [NSString stringWithFormat:@"(No previous log, or failed to read)\npath: %@\nerror: %@\n", prevLogPath, prevError];
    }

    NSString* content = [NSString stringWithFormat:
                         @"=== Current Log ===\npath: %@\n\n%@\n\n=== Previous Log ===\npath: %@\n\n%@\n",
                         currentLogPath,
                         currentContent,
                         prevLogPath,
                         prevContent];

    UIViewController* vc = [[UIViewController alloc] init];
    vc.title = @"Logs";
    vc.view.backgroundColor = [UIColor blackColor];

    UITextView* textView = [[UITextView alloc] initWithFrame:CGRectZero];
    textView.translatesAutoresizingMaskIntoConstraints = NO;
    textView.backgroundColor = [UIColor blackColor];
    textView.textColor = [UIColor whiteColor];
    textView.selectable = YES;
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        textView.font = [UIFont monospacedSystemFontOfSize:18 weight:UIFontWeightRegular];
    } else {
        textView.font = [UIFont systemFontOfSize:18];
    }
    textView.text = content;

    [vc.view addSubview:textView];
    UILayoutGuide* safe = vc.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [textView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [textView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [textView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [textView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
    ]];

    return vc;
}

- (void)openTvSettings:(id)sender
{
    (void)sender;
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
}

- (void)showLogs:(id)sender
{
    (void)sender;
    UIViewController* logsVC = [self makeLogsViewController];
    [self.navigationController pushViewController:logsVC animated:YES];
}

- (void)continueToApp:(id)sender
{
    (void)sender;
    AppDelegate* app = (AppDelegate*)[UIApplication sharedApplication].delegate;
    [app tvosSwitchToMainUI];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Safe Mode";
    self.view.backgroundColor = [UIColor blackColor];

    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSString* reason = [defaults stringForKey:kVoidLinkTVSafeModeReasonKey] ?: @"Detected a previous crash during launch.";
    NSInteger crashCount = [defaults integerForKey:kVoidLinkTVCrashCountKey];

    UILabel* title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"VoidLink Safe Mode";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont systemFontOfSize:54 weight:UIFontWeightBold];

    UILabel* subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.85];
    subtitle.font = [UIFont systemFontOfSize:28 weight:UIFontWeightRegular];
    subtitle.numberOfLines = 0;
    subtitle.text = [NSString stringWithFormat:@"Reason: %@\nCrash count: %ld\n\nYou can open Logs to inspect the crash, adjust settings, then Continue.", reason, (long)crashCount];

    UIButton* continueBtn = [self makePrimaryButtonWithTitle:@"Continue" action:@selector(continueToApp:)];
    UIButton* logsBtn = [self makePrimaryButtonWithTitle:@"View Logs" action:@selector(showLogs:)];
    UIButton* settingsBtn = [self makePrimaryButtonWithTitle:@"Open Settings" action:@selector(openTvSettings:)];

    UIStackView* buttons = [[UIStackView alloc] initWithArrangedSubviews:@[continueBtn, logsBtn, settingsBtn]];
    buttons.translatesAutoresizingMaskIntoConstraints = NO;
    buttons.axis = UILayoutConstraintAxisVertical;
    buttons.spacing = 22;
    buttons.alignment = UIStackViewAlignmentLeading;

    [self.view addSubview:title];
    [self.view addSubview:subtitle];
    [self.view addSubview:buttons];

    UILayoutGuide* safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:safe.topAnchor constant:40],
        [title.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:80],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:safe.trailingAnchor constant:-80],

        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:24],
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.trailingAnchor constraintLessThanOrEqualToAnchor:safe.trailingAnchor constant:-80],

        [buttons.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:44],
        [buttons.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
    ]];
}

@end

#endif
