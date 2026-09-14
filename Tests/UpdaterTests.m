#import "CodexUpdater.h"

int main(void) {
    @autoreleasepool {
        NSCAssert(CodexGitSHAsEqual(@"217185e", @"217185ef00aabb"), @"Short SHA matches long SHA");
        NSCAssert(!CodexGitSHAsEqual(@"217185e", @"deadbeef"), @"Different SHAs differ");
        NSCAssert([CodexShortGitSHA(@"217185ef00") isEqual:@"217185e"], @"Short SHA");

        NSDictionary *repo = CodexGitHubRepoFromRemote(@"https://github.com/diegocp01/top_bar_codex_credits.git");
        NSCAssert([repo[@"owner"] isEqual:@"diegocp01"], @"HTTPS owner");
        NSCAssert([repo[@"name"] isEqual:@"top_bar_codex_credits"], @"HTTPS name");
        repo = CodexGitHubRepoFromRemote(@"git@github.com:diegocp01/top_bar_codex_credits.git");
        NSCAssert([repo[@"owner"] isEqual:@"diegocp01"] && [repo[@"name"] isEqual:@"top_bar_codex_credits"], @"SSH remote");
        NSCAssert(CodexRemotePointsAtAppRepo(@"https://github.com/diegocp01/top_bar_codex_credits.git"), @"Repo match");
        NSCAssert(!CodexRemotePointsAtAppRepo(@"https://github.com/diegocp01/grok_menu_bar.git"), @"Other repo");

        NSDictionary *identical = CodexParseGitHubUpdatePayload(@{ @"status": @"identical", @"ahead_by": @0, @"commits": @[] }, @"217185eadd");
        NSCAssert([identical[@"ok"] boolValue] && ![identical[@"updateAvailable"] boolValue], @"Identical compare");

        NSDictionary *ahead = CodexParseGitHubUpdatePayload(@{
            @"status": @"ahead", @"ahead_by": @2,
            @"commits": @[
                @{ @"sha": @"aaa1111", @"commit": @{ @"message": @"Fix parsing\n\nDetails" } },
                @{ @"sha": @"bbb2222deadbeef", @"commit": @{ @"message": @"Merge pull request #9" } }
            ]
        }, @"217185eadd");
        NSCAssert([ahead[@"updateAvailable"] boolValue], @"Ahead is an update");
        NSCAssert([ahead[@"aheadBy"] integerValue] == 2, @"Ahead count");
        NSCAssert([ahead[@"commits"] count] == 2, @"Commit summaries");
        NSCAssert([CodexUpdatePromptText(ahead) containsString:@"Merge pull request #9"], @"Prompt summaries");

        NSDictionary *tip = CodexParseGitHubUpdatePayload(@{ @"sha": @"217185eaddffff", @"commit": @{ @"message": @"Current" } }, @"217185eaddffff");
        NSCAssert(![tip[@"updateAvailable"] boolValue], @"Same tip is current");
        puts("Updater tests passed");
    }
    return 0;
}
