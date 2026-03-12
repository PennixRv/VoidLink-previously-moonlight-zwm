//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

#include <Limelight.h>
#include <TargetConditionals.h>

// Keep tvOS builds clean: avoid importing iOS-only OSC/widget headers into the Swift bridging
// header. The tvOS target should not compile/link those implementations.
#if !TARGET_OS_TV
#import "OnScreenControls.h"
#import "OnScreenButtonState.h"
#import "OSCProfile.h"
#import "OSCProfilesManager.h"
#endif

#import "opus.h"
#import "opus_defines.h"
// #import "RelativeTouchHandler.h"
