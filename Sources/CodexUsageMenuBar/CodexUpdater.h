#ifndef CodexUpdater_h
#define CodexUpdater_h

#import <Foundation/Foundation.h>

static NSString * const CodexDefaultGitRemote = @"https://github.com/diegocp01/top_bar_codex_credits.git";
static NSString * const CodexSourceRepoPathKey = @"sourceRepoPath";

static NSString *CodexTrimGitSHA(NSString *sha) {
    return [sha isKindOfClass:NSString.class]
        ? [[sha stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString]
        : @"";
}

static BOOL CodexGitSHAsEqual(NSString *left, NSString *right) {
    NSString *a = CodexTrimGitSHA(left), *b = CodexTrimGitSHA(right);
    if (a.length == 0 || b.length == 0) return NO;
    NSUInteger length = MIN(a.length, b.length);
    return length < 7 ? [a isEqualToString:b] : [[a substringToIndex:length] isEqualToString:[b substringToIndex:length]];
}

static NSString *CodexShortGitSHA(NSString *sha) {
    NSString *value = CodexTrimGitSHA(sha);
    return value.length >= 7 ? [value substringToIndex:7] : value;
}

static NSDictionary<NSString *, NSString *> *CodexGitHubRepoFromRemote(NSString *remote) {
    NSString *value = remote.length > 0 ? remote : CodexDefaultGitRemote;
    value = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([value hasSuffix:@".git"]) value = [value substringToIndex:value.length - 4];
    value = [value stringByReplacingOccurrencesOfString:@"git@github.com:" withString:@"https://github.com/"];
    value = [value stringByReplacingOccurrencesOfString:@"ssh://git@github.com/" withString:@"https://github.com/"];
    NSArray<NSString *> *parts = [NSURL URLWithString:value].path.pathComponents;
    if (parts.count < 3) return @{ @"owner": @"diegocp01", @"name": @"top_bar_codex_credits" };
    return @{ @"owner": parts[parts.count - 2], @"name": parts.lastObject };
}

static BOOL CodexRemotePointsAtAppRepo(NSString *remote) {
    return [CodexGitHubRepoFromRemote(remote)[@"name"] isEqualToString:@"top_bar_codex_credits"];
}

static NSString *CodexFirstLine(NSString *text) {
    for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length > 0) return trimmed;
    }
    return @"";
}

static NSArray<NSString *> *CodexCommitSummariesFromGitHub(id commits) {
    NSMutableArray *items = [NSMutableArray array];
    if (![commits isKindOfClass:NSArray.class]) return items;
    for (id value in commits) {
        if (![value isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *commit = value;
        id inner = commit[@"commit"];
        NSString *message = [inner isKindOfClass:NSDictionary.class] ? inner[@"message"] : commit[@"message"];
        NSString *line = CodexFirstLine(message);
        if (line.length > 0) [items addObject:line];
    }
    return items;
}

static NSDictionary *CodexParseGitHubUpdatePayload(id json, NSString *currentSHA) {
    if (![json isKindOfClass:NSDictionary.class]) return @{ @"ok": @NO, @"error": @"GitHub returned invalid JSON" };
    NSDictionary *payload = json;
    NSString *remoteSHA = [payload[@"sha"] isKindOfClass:NSString.class] ? payload[@"sha"] : nil;
    NSInteger ahead = [payload[@"ahead_by"] respondsToSelector:@selector(integerValue)] ? MAX(0, [payload[@"ahead_by"] integerValue]) : 0;
    NSArray *summaries = remoteSHA ? CodexCommitSummariesFromGitHub(payload[@"commit"] ? @[payload] : @[]) : @[];
    if ([payload[@"commits"] isKindOfClass:NSArray.class]) {
        summaries = CodexCommitSummariesFromGitHub(payload[@"commits"]);
        NSDictionary *last = [payload[@"commits"] lastObject];
        if ([last[@"sha"] isKindOfClass:NSString.class]) remoteSHA = last[@"sha"];
    }
    NSString *status = [payload[@"status"] isKindOfClass:NSString.class] ? payload[@"status"] : nil;
    if ([status isEqualToString:@"identical"] || ([status isEqualToString:@"behind"] && ahead == 0)) {
        ahead = 0;
        if (remoteSHA.length == 0) remoteSHA = currentSHA;
    }
    if (remoteSHA.length == 0 && ahead == 0 && currentSHA.length > 0) remoteSHA = currentSHA;
    if (remoteSHA.length == 0) return @{ @"ok": @NO, @"error": @"GitHub response had no commit SHA" };
    BOOL same = CodexGitSHAsEqual(currentSHA, remoteSHA);
    if (same) ahead = 0; else if (ahead <= 0) ahead = MAX(1, (NSInteger)summaries.count);
    return @{ @"ok": @YES, @"updateAvailable": @(ahead > 0 && !same), @"aheadBy": @(ahead),
              @"currentSHA": currentSHA ?: @"", @"remoteSHA": remoteSHA, @"commits": summaries };
}

static NSString *CodexUpdatePromptText(NSDictionary *update) {
    NSInteger ahead = [update[@"aheadBy"] integerValue];
    NSArray *commits = [update[@"commits"] isKindOfClass:NSArray.class] ? update[@"commits"] : @[];
    NSMutableArray *lines = [NSMutableArray array];
    for (NSUInteger i = 0; i < MIN(commits.count, (NSUInteger)8); i++) [lines addObject:[@"• " stringByAppendingString:commits[i]]];
    if (commits.count > 8) [lines addObject:[NSString stringWithFormat:@"• … %lu more", commits.count - 8]];
    NSString *count = ahead == 1 ? @"1 new commit" : [NSString stringWithFormat:@"%ld new commits", (long)ahead];
    NSString *body = lines.count ? [lines componentsJoinedByString:@"\n"] : @"New commits, including merged PRs, are on main.";
    return [NSString stringWithFormat:@"%@ on GitHub main.\n\n%@\n\nPull, rebuild, and restart now?", count, body];
}

static NSString *CodexRunProcess(NSString *path, NSArray<NSString *> *arguments, NSString *directory, NSInteger *status) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:path];
    task.arguments = arguments;
    if (directory.length) task.currentDirectoryURL = [NSURL fileURLWithPath:directory];
    NSPipe *pipe = NSPipe.pipe;
    task.standardOutput = pipe;
    task.standardError = pipe;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) { if (status) *status = -1; return error.localizedDescription ?: @"Could not start process"; }
    [task waitUntilExit];
    if (status) *status = task.terminationStatus;
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *CodexGit(NSString *repo, NSArray<NSString *> *arguments, NSInteger *status) {
    NSMutableArray *args = [@[@"-C", repo] mutableCopy];
    [args addObjectsFromArray:arguments];
    return CodexRunProcess(@"/usr/bin/git", args, nil, status);
}

static NSString *CodexOriginURL(NSString *repo) {
    NSInteger status = 0; NSString *url = CodexGit(repo, @[@"remote", @"get-url", @"origin"], &status);
    return status == 0 ? url : nil;
}

static BOOL CodexDirectoryHasGit(NSString *path) {
    return path.length > 0 && [NSFileManager.defaultManager fileExistsAtPath:[path stringByAppendingPathComponent:@".git"]];
}

static NSString *CodexBundledGitCommit(void) {
    return CodexTrimGitSHA(NSBundle.mainBundle.infoDictionary[@"CodexGitCommit"]);
}

static NSString *CodexBundledGitRemote(void) {
    NSString *remote = NSBundle.mainBundle.infoDictionary[@"CodexGitRemote"];
    return remote.length ? remote : CodexDefaultGitRemote;
}

static NSString *CodexManagedClonePath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Codex Usage Menu Bar/src"];
}

static NSString *CodexFindSourceRepo(void) {
    NSMutableArray *candidates = [NSMutableArray array];
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:CodexSourceRepoPathKey];
    if (saved) [candidates addObject:saved];
    NSString *path = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
    while (path.length > 1) { [candidates addObject:path]; NSString *parent = path.stringByDeletingLastPathComponent; if ([parent isEqual:path]) break; path = parent; }
    NSString *home = NSHomeDirectory();
    [candidates addObjectsFromArray:@[
        [home stringByAppendingPathComponent:@"Documents/code_projects/menu_bar_widgets/top_bar_codex_credits"],
        [home stringByAppendingPathComponent:@"Documents/top_bar_codex_credits"],
        [home stringByAppendingPathComponent:@"src/top_bar_codex_credits"], CodexManagedClonePath()
    ]];
    for (NSString *candidate in candidates) {
        if (CodexDirectoryHasGit(candidate) && CodexRemotePointsAtAppRepo(CodexOriginURL(candidate))) return candidate.stringByStandardizingPath;
    }
    return nil;
}

static NSString *CodexEnsureSourceRepo(NSError **error) {
    NSString *repo = CodexFindSourceRepo();
    if (repo.length) { [NSUserDefaults.standardUserDefaults setObject:repo forKey:CodexSourceRepoPathKey]; return repo; }
    NSString *destination = CodexManagedClonePath();
    [NSFileManager.defaultManager createDirectoryAtPath:destination.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error];
    NSInteger status = 0;
    NSString *output = CodexRunProcess(@"/usr/bin/git", @[@"clone", @"--branch", @"main", CodexBundledGitRemote(), destination], nil, &status);
    if (status != 0) { if (error) *error = [NSError errorWithDomain:@"CodexUpdater" code:1 userInfo:@{NSLocalizedDescriptionKey: output.length ? output : @"git clone failed"}]; return nil; }
    [NSUserDefaults.standardUserDefaults setObject:destination forKey:CodexSourceRepoPathKey];
    return destination;
}

static NSDictionary *CodexGitHubRequest(NSString *url) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"CodexUsageMenuBar/0.1" forHTTPHeaderField:@"User-Agent"];
    NSHTTPURLResponse *response = nil; NSError *error = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
#pragma clang diagnostic pop
    if (!data || response.statusCode < 200 || response.statusCode >= 300) return @{ @"ok": @NO, @"status": @(response.statusCode), @"error": error.localizedDescription ?: [NSString stringWithFormat:@"GitHub HTTP %ld", response.statusCode] };
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    return json ?: @{ @"ok": @NO, @"error": error.localizedDescription ?: @"Invalid GitHub response" };
}

static NSDictionary *CodexCheckForUpdates(void) {
    NSString *repo = CodexFindSourceRepo();
    NSString *current = CodexBundledGitCommit();
    if (current.length < 7 && repo.length) { NSInteger status = 0; current = CodexGit(repo, @[@"rev-parse", @"HEAD"], &status); }
    NSDictionary *details = CodexGitHubRepoFromRemote(CodexBundledGitRemote());
    NSString *base = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@", details[@"owner"], details[@"name"]];
    NSString *url = current.length >= 7 ? [NSString stringWithFormat:@"%@/compare/%@...main", base, current] : [base stringByAppendingString:@"/commits/main"];
    NSDictionary *json = CodexGitHubRequest(url);
    if ([json[@"status"] integerValue] == 404 && current.length >= 7) json = CodexGitHubRequest([base stringByAppendingString:@"/commits/main"]);
    if ([json[@"ok"] isEqual:@NO]) return json;
    NSMutableDictionary *result = [CodexParseGitHubUpdatePayload(json, current) mutableCopy];
    if (repo.length) result[@"repoPath"] = repo;
    return result;
}

static NSDictionary *CodexApplyGitPullAndRebuild(NSString *installPath, NSError **error) {
    NSString *repo = CodexEnsureSourceRepo(error);
    if (!repo.length) return @{ @"ok": @NO, @"error": (*error).localizedDescription ?: @"Could not find the source repository" };
    NSInteger status = 0;
    NSString *output = CodexGit(repo, @[@"fetch", @"origin", @"main"], &status);
    if (status != 0) return @{ @"ok": @NO, @"error": output.length ? output : @"git fetch failed" };
    output = CodexGit(repo, @[@"pull", @"--ff-only", @"origin", @"main"], &status);
    if (status != 0) return @{ @"ok": @NO, @"error": output.length ? output : @"git pull --ff-only failed" };
    NSString *buildDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"codex-usage-update-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    NSTask *build = [NSTask new];
    build.executableURL = [NSURL fileURLWithPath:@"/bin/bash"];
    build.arguments = @[[repo stringByAppendingPathComponent:@"scripts/build.sh"]];
    build.currentDirectoryURL = [NSURL fileURLWithPath:repo];
    NSMutableDictionary *environment = NSProcessInfo.processInfo.environment.mutableCopy; environment[@"OUT_DIR"] = buildDir; build.environment = environment;
    NSPipe *pipe = NSPipe.pipe; build.standardOutput = pipe; build.standardError = pipe;
    if (![build launchAndReturnError:error]) return @{ @"ok": @NO, @"error": (*error).localizedDescription ?: @"Could not start build" };
    [build waitUntilExit];
    NSString *log = [[NSString alloc] initWithData:[pipe.fileHandleForReading readDataToEndOfFile] encoding:NSUTF8StringEncoding] ?: @"";
    if (build.terminationStatus != 0) return @{ @"ok": @NO, @"error": [@"Build failed:\n" stringByAppendingString:log.length > 800 ? [log substringFromIndex:log.length - 800] : log] };
    NSString *builtApp = [buildDir stringByAppendingPathComponent:@"Codex Usage Menu Bar.app"];
    if (![NSFileManager.defaultManager fileExistsAtPath:builtApp]) return @{ @"ok": @NO, @"error": @"Build finished but the app is missing" };
    NSString *destination = [installPath.pathExtension isEqual:@"app"] ? installPath : [NSHomeDirectory() stringByAppendingPathComponent:@"Applications/Codex Usage Menu Bar.app"];
    [NSFileManager.defaultManager createDirectoryAtPath:destination.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    output = CodexRunProcess(@"/usr/bin/ditto", @[@"--noqtn", builtApp, destination], nil, &status);
    if (status != 0) return @{ @"ok": @NO, @"error": output.length ? output : @"Could not replace the app" };
    CodexRunProcess(@"/usr/bin/xattr", @[@"-cr", destination], nil, &status);
    CodexRunProcess(@"/usr/bin/codesign", @[@"--force", @"--sign", @"-", @"--options", @"runtime", destination], nil, &status);
    [NSFileManager.defaultManager removeItemAtPath:buildDir error:nil];
    return @{ @"ok": @YES, @"appPath": destination };
}

#endif
