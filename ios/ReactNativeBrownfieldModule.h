#ifdef __cplusplus

#import <React/RCTBridgeModule.h>

#if RCT_NEW_ARCH_ENABLED && __has_include(<ReactNativeBrownfieldSpec/ReactNativeBrownfieldSpec.h>)
#import <ReactNativeBrownfieldSpec/ReactNativeBrownfieldSpec.h>
@interface ReactNativeBrownfieldModule : NSObject <NativeReactNativeBrownfieldModuleSpec>
#else
@interface ReactNativeBrownfieldModule : NSObject <RCTBridgeModule>
#endif

@end

#endif
