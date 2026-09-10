#import "UsagePace.h"

int main(void) {
    @autoreleasepool {
        NSTimeInterval now = 1000000.0;
        double weeklyMinutes = 7.0 * 24.0 * 60.0;

        NSCAssert(fabs(CodexOnPacePercentLeft(now + 168.0 * 3600.0, now, weeklyMinutes) - 100.0) < 0.001,
                  @"168 hours left should be 100%% on pace");
        NSCAssert(fabs(CodexOnPacePercentLeft(now + 126.0 * 3600.0, now, weeklyMinutes) - 75.0) < 0.001,
                  @"126 hours left should be 75%% on pace");
        NSCAssert(fabs(CodexOnPacePercentLeft(now + 100.0 * 3600.0, now, weeklyMinutes) - 59.5238) < 0.001,
                  @"100 hours left should be about 60%% on pace");
        NSCAssert(fabs(CodexOnPacePercentLeft(now + 84.0 * 3600.0, now, weeklyMinutes) - 50.0) < 0.001,
                  @"84 hours left should be 50%% on pace");
        NSCAssert(CodexOnPacePercentLeft(now - 1.0, now, weeklyMinutes) == 0.0,
                  @"Expired windows should clamp to 0%%");
        NSCAssert(CodexOnPacePercentLeft(now + 200.0 * 3600.0, now, weeklyMinutes) == 100.0,
                  @"Unexpected future resets should clamp to 100%%");
        NSCAssert(isnan(CodexOnPacePercentLeft(now, now, 0.0)),
                  @"Missing window duration should not produce a marker");
        puts("Usage pace tests passed");
    }
    return 0;
}
