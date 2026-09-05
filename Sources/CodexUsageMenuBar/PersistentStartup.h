#import <Foundation/Foundation.h>
#import <ServiceManagement/ServiceManagement.h>
#import <unistd.h>

// A LaunchServices wrapper keeps the app's normal bundle identity and permissions.
// Tests override command: and use a temporary directory; no real jobs are touched.
@interface PersistentStartup : NSObject
@property(nonatomic, copy) NSString *label;
@property(nonatomic, copy) NSString *appPath;
@property(nonatomic, copy) NSString *directory;
- (int)command:(NSArray<NSString *> *)arguments;
- (NSString *)path;
- (BOOL)loaded;
- (BOOL)pause:(NSError **)error;
- (BOOL)setEnabled:(BOOL)enabled error:(NSError **)error;
@end

@implementation PersistentStartup
- (NSString *)path { return [self.directory stringByAppendingPathComponent:[self.label stringByAppendingString:@".plist"]]; }
- (NSString *)domain { return [NSString stringWithFormat:@"gui/%u", getuid()]; }
- (NSString *)service { return [[self domain] stringByAppendingFormat:@"/%@", self.label]; }
- (int)command:(NSArray<NSString *> *)arguments {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/launchctl"];
    task.arguments = arguments;
    task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) return -1;
    [task waitUntilExit];
    return task.terminationStatus;
}
- (BOOL)fail:(NSString *)message code:(int)code error:(NSError **)error {
    if (error) *error = [NSError errorWithDomain:@"PersistentStartup" code:code userInfo:@{NSLocalizedDescriptionKey: message}];
    return NO;
}
- (BOOL)loaded { return [self command:@[@"print", self.service]] == 0; }
- (BOOL)pause:(NSError **)error {
    if (!self.loaded) return YES;
    int result = [self command:@[@"bootout", self.service]];
    return result == 0 || [self fail:@"Could not stop automatic restart; try again before quitting or updating." code:result error:error];
}
- (BOOL)setEnabled:(BOOL)enabled error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    if (!enabled) {
        if (![self pause:error]) return NO;
        return ![fm fileExistsAtPath:self.path] || [fm removeItemAtPath:self.path error:error];
    }
    NSDictionary *job = @{
        @"Label": self.label,
        @"ProgramArguments": @[@"/usr/bin/open", @"-g", @"-W", self.appPath],
        @"RunAtLoad": @YES, @"KeepAlive": @YES, @"ThrottleInterval": @30,
        @"LimitLoadToSessionType": @"Aqua", @"ProcessType": @"Background"
    };
    BOOL unchanged = [[NSDictionary dictionaryWithContentsOfFile:self.path] isEqualToDictionary:job];
    if (unchanged && self.loaded) return YES;
    if (![self pause:error]) return NO;
    if (![fm createDirectoryAtPath:self.directory withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:job format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
    if (!data || ![data writeToFile:self.path options:NSDataWritingAtomic error:error]) return NO;
    int result = [self command:@[@"enable", self.service]];
    if (result == 0) result = [self command:@[@"bootstrap", self.domain, self.path]];
    if (result != 0) return [self fail:@"Automatic startup could not be activated. Check System Settings > General > Login Items, then retry the menu option." code:result error:error];
    return YES;
}
@end

static PersistentStartup *StartupController(NSString *label) {
    PersistentStartup *startup = [PersistentStartup new];
    startup.label = label;
    startup.appPath = NSBundle.mainBundle.bundlePath;
    startup.directory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents"];
    return startup;
}

static BOOL RemoveNativeLoginItem(NSError **error) {
    if (@available(macOS 13.0, *)) {
        SMAppService *service = SMAppService.mainAppService;
        if (service.status == SMAppServiceStatusEnabled || service.status == SMAppServiceStatusRequiresApproval) {
            return [service unregisterAndReturnError:error];
        }
    }
    return YES;
}
