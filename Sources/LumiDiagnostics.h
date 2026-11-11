#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// On-device diagnostics: a persistent text log plus an uncaught-exception
/// handler. The log is shown from the Profile tab, so a crash report can be
/// copied and sent without Xcode or a cable.
@interface LumiDiagnostics : NSObject

+ (void)install;
+ (void)log:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);

+ (NSString *)logPath;
+ (NSString *)logContents;
+ (void)clearLog;

@end

NS_ASSUME_NONNULL_END
