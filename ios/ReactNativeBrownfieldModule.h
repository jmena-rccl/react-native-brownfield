#ifdef __cplusplus

#import <React/RCTBridgeModule.h>

#if RCT_NEW_ARCH_ENABLED
@protocol NativeReactNativeBrownfieldModuleSpec;
@interface ReactNativeBrownfieldModule : NSObject <NativeReactNativeBrownfieldModuleSpec>
#else
@interface ReactNativeBrownfieldModule : NSObject <RCTBridgeModule>
#endif

@end

#endif
