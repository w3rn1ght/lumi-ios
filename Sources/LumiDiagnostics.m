#import "LumiDiagnostics.h"
#import <signal.h>
#import <unistd.h>
#import <fcntl.h>
#import <string.h>

static NSString *gLumiLogPath = nil;
static int gLumiLogFD = -1;
static dispatch_queue_t gLumiLogQueue = nil;

static void LumiWriteCrashLine(const char *bytes) {
    if (!bytes || gLumiLogFD < 0) {
        return;
    }
    size_t length = strlen(bytes);
    if (length) {
        write(gLumiLogFD, bytes, length);
    }
}

static void LumiUncaughtExceptionHandler(NSException *exception) {
    NSMutableString *report = [NSMutableString string];
    [report appendString:@"\n===== UNCAUGHT EXCEPTION =====\n"];
    [report appendFormat:@"name: %@\n", exception.name ?: @"?"];
    [report appendFormat:@"reason: %@\n", exception.reason ?: @"?"];
    [report appendString:@"stack:\n"];
    for (NSDictionary *frame in exception.callStackSymbols ?: @[]) {
        [report appendFormat:@"  %@\n", frame];
    }
    NSString *text = [report copy];
    LumiWriteCrashLine(text.UTF8String);
#if DEBUG
    NSLog(@"%@", text);
#endif
}

static void LumiFatalSignalHandler(int signalNumber) {
    NSMutableString *report = [NSMutableString string];
    [report appendFormat:@"\n===== FATAL SIGNAL %d =====\n", signalNumber];
    for (NSDictionary *frame in [NSThread callStackSymbols] ?: @[]) {
        [report appendFormat:@"  %@\n", frame];
    }
    LumiWriteCrashLine(report.UTF8String);
    signal(signalNumber, SIG_DFL);
    raise(signalNumber);
}

@implementation LumiDiagnostics

+ (void)install {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gLumiLogQueue = dispatch_queue_create("com.w3rn1ght.lumi.log", DISPATCH_QUEUE_SERIAL);

        NSString *path = @"/var/mobile/Documents/Lumi.log";
        gLumiLogFD = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (gLumiLogFD < 0) {
            NSString *documents = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            path = [documents stringByAppendingPathComponent:@"Lumi.log"];
            gLumiLogFD = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0644);
        }
        gLumiLogPath = [path copy];

        NSSetUncaughtExceptionHandler(&LumiUncaughtExceptionHandler);
        signal(SIGABRT, LumiFatalSignalHandler);
        signal(SIGSEGV, LumiFatalSignalHandler);
        signal(SIGBUS, LumiFatalSignalHandler);
        signal(SIGILL, LumiFatalSignalHandler);
        signal(SIGFPE, LumiFatalSignalHandler);

        NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
        NSString *version = info[@"CFBundleShortVersionString"] ?: @"?";
        NSString *build = info[@"CFBundleVersion"] ?: @"?";
        [self log:@"──── Lumi запущен · v%@ (build %@) · %@ ────",
         version, build, [NSDate date]];
    });
}

+ (void)log:(NSString *)format, ... {
    if (!format) {
        return;
    }
    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);

    if (!gLumiLogQueue) {
        NSLog(@"%@", message);
        return;
    }
    dispatch_async(gLumiLogQueue, ^{
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n",
                          [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                         dateStyle:NSDateFormatterNoStyle
                                                         timeStyle:NSDateFormatterMediumStyle],
                          message];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (gLumiLogFD >= 0 && data.length) {
            write(gLumiLogFD, data.bytes, data.length);
        }
        NSLog(@"[Lumi] %@", message);
    });
}

+ (NSString *)logPath {
    return gLumiLogPath ?: @"";
}

+ (NSString *)logContents {
    if (!gLumiLogPath.length) {
        return @"Журнал ещё не создан.";
    }
    NSString *contents = [NSString stringWithContentsOfFile:gLumiLogPath
                                                   encoding:NSUTF8StringEncoding
                                                      error:NULL];
    if (!contents.length) {
        return @"Журнал пуст.";
    }
    // Keep the tail: an uncaught exception report sits at the end of the file.
    NSUInteger limit = 24000;
    if (contents.length > limit) {
        contents = [contents substringFromIndex:contents.length - limit];
        contents = [@"…\n" stringByAppendingString:contents];
    }
    return contents;
}

+ (void)clearLog {
    if (!gLumiLogPath.length) {
        return;
    }
    truncate(gLumiLogPath.fileSystemRepresentation, 0);
    [self log:@"Журнал очищен"];
}

@end
