#import "PersistentStartup.h"

@interface FakeStartup : PersistentStartup
@property BOOL running;
@property int bootstrapFailure;
@property int stopFailure;
@property NSUInteger bootstraps;
@end
@implementation FakeStartup
- (int)command:(NSArray<NSString *> *)args {
    NSString *verb = args[0];
    if ([verb isEqual:@"print"]) return self.running ? 0 : 113;
    if ([verb isEqual:@"bootout"]) { if (self.stopFailure) return self.stopFailure; self.running = NO; return 0; }
    if ([verb isEqual:@"enable"]) return 0;
    NSCAssert([verb isEqual:@"bootstrap"], @"Unexpected command");
    self.bootstraps++;
    if (self.bootstrapFailure) return self.bootstrapFailure;
    NSCAssert([NSFileManager.defaultManager fileExistsAtPath:args[2]], @"Plist must be saved before bootstrap");
    self.running = YES;
    return 0;
}
@end

int main(void) {
    @autoreleasepool {
        FakeStartup *s = [FakeStartup new];
        s.label = @"test.startup";
        s.directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        s.appPath = @"/Applications/A & B <Reader>.app";
        NSError *error = nil;
        NSCAssert([s setEnabled:YES error:&error], @"Fresh install failed");
        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:s.path];
        NSCAssert(([plist[@"ProgramArguments"] isEqual:@[@"/usr/bin/open", @"-g", @"-W", s.appPath]]), @"Path escaping or wait flags lost");
        NSCAssert([plist[@"RunAtLoad"] boolValue] && [plist[@"KeepAlive"] boolValue], @"Startup/restart missing");
        NSCAssert([plist[@"ThrottleInterval"] intValue] >= 30, @"Restart storm protection missing");
        NSCAssert([s setEnabled:YES error:&error] && s.bootstraps == 1, @"Normal relaunch must not restart its own supervisor");
        NSCAssert([s pause:&error] && !s.running, @"Update pause failed");
        NSCAssert([NSFileManager.defaultManager fileExistsAtPath:s.path], @"Pause must preserve next-login configuration");
        NSCAssert([s setEnabled:YES error:&error] && s.bootstraps == 2, @"Resume after update failed");
        s.appPath = @"/Applications/Moved.app";
        NSCAssert([s setEnabled:YES error:&error] && s.bootstraps == 3, @"Moved app must replace registration");
        NSCAssert([[[NSDictionary dictionaryWithContentsOfFile:s.path] objectForKey:@"ProgramArguments"] containsObject:s.appPath], @"Old app path retained");
        s.stopFailure = 5;
        NSCAssert(![s setEnabled:NO error:&error] && error != nil && s.running, @"Stop failure must be reported");
        NSCAssert([NSFileManager.defaultManager fileExistsAtPath:s.path], @"Do not delete config when unload fails");
        s.stopFailure = 0;
        NSCAssert([s setEnabled:NO error:&error] && !s.running, @"Opt-out failed");
        NSCAssert(![NSFileManager.defaultManager fileExistsAtPath:s.path], @"Opt-out must remove next-login configuration");
        NSCAssert([s setEnabled:NO error:&error], @"Repeated opt-out failed");
        s.bootstrapFailure = 5; error = nil;
        NSCAssert(![s setEnabled:YES error:&error] && error != nil && !s.loaded, @"Failed bootstrap must not report enabled");
        s.bootstrapFailure = 0;
        NSCAssert([s setEnabled:YES error:&error] && s.loaded, @"Retry failed");
        NSCAssert([s setEnabled:NO error:&error], @"Final cleanup failed");
        [NSFileManager.defaultManager removeItemAtPath:s.directory error:nil];
        puts("Startup lifecycle tests passed");
    }
    return 0;
}
