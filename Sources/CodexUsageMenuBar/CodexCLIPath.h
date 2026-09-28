#import <Foundation/Foundation.h>

static inline NSString *CodexCLIExecutablePath(NSString *override,
                                                NSString *home,
                                                NSArray<NSString *> *resourceDirectories,
                                                NSFileManager *files) {
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    if (override.length > 0) [candidates addObject:override];

    // The standalone CLI is updated independently of the desktop app.
    [candidates addObject:[home stringByAppendingPathComponent:@".local/bin/codex"]];
    [candidates addObject:[home stringByAppendingPathComponent:@".codex/packages/standalone/current/bin/codex"]];

    for (NSString *directory in resourceDirectories) {
        [candidates addObject:[directory stringByAppendingPathComponent:@"codex-cli/bin/codex"]];
        [candidates addObject:[directory stringByAppendingPathComponent:@"codex-cli/CodexCLI.app/Contents/MacOS/codex"]];
        [candidates addObject:[directory stringByAppendingPathComponent:@"codex"]];
    }
    [candidates addObjectsFromArray:@[@"/opt/homebrew/bin/codex", @"/usr/local/bin/codex"]];

    for (NSString *path in candidates) {
        if ([files isExecutableFileAtPath:path]) return path;
    }
    return nil;
}
