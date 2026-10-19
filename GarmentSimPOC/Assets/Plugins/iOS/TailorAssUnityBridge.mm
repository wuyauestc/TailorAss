#import <Foundation/Foundation.h>

static NSString * const kTailorAssUnityResultNotification = @"TailorAssUnityResultNotification";
static NSString * const kTailorAssUnityCloseNotification = @"TailorAssUnityCloseNotification";

extern "C" void TailorAssUnityDidComplete(const char *resultJson)
{
    NSString *json = resultJson ? [NSString stringWithUTF8String:resultJson] : @"{}";
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:kTailorAssUnityResultNotification
                          object:nil
                        userInfo:@{ @"json": json }];
    });
}

extern "C" void TailorAssUnityDidRequestClose(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:kTailorAssUnityCloseNotification object:nil];
    });
}
