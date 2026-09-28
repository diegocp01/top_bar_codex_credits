#import "CodexCLIPath.h"

static NSString *MakeExecutable(NSString *path) {
    NSFileManager *files = NSFileManager.defaultManager;
    [files createDirectoryAtPath:path.stringByDeletingLastPathComponent
     withIntermediateDirectories:YES attributes:nil error:nil];
    NSCAssert([files createFileAtPath:path contents:[NSData data] attributes:@{NSFilePosixPermissions: @0755}],
              @"Could not create test executable");
    return path;
}

int main(void) {
    @autoreleasepool {
        NSFileManager *files = NSFileManager.defaultManager;
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString *home = [root stringByAppendingPathComponent:@"home"];
        NSString *resources = [root stringByAppendingPathComponent:@"ChatGPT.app/Contents/Resources"];
        NSArray *dirs = @[resources];
        NSString *bundled = MakeExecutable([resources stringByAppendingPathComponent:@"codex-cli/bin/codex"]);
        NSCAssert([CodexCLIExecutablePath(nil, home, dirs, files) isEqualToString:bundled],
                  @"Current desktop bundle layout should work");

        NSString *standalone = MakeExecutable([home stringByAppendingPathComponent:@".local/bin/codex"]);
        NSCAssert([CodexCLIExecutablePath(nil, home, dirs, files) isEqualToString:standalone],
                  @"Updated standalone CLI should take priority");

        NSString *override = MakeExecutable([root stringByAppendingPathComponent:@"custom/codex"]);
        NSCAssert([CodexCLIExecutablePath(override, home, dirs, files) isEqualToString:override],
                  @"Valid explicit override should take priority");
        NSCAssert([CodexCLIExecutablePath(@"/missing/codex", home, dirs, files) isEqualToString:standalone],
                  @"Broken override should not prevent a live refresh");

        [files removeItemAtPath:root error:nil];
        puts("Codex CLI path tests passed");
    }
    return 0;
}
