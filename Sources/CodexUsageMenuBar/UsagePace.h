#import <Foundation/Foundation.h>
#import <math.h>

static inline double CodexOnPacePercentLeft(NSTimeInterval resetAt,
                                             NSTimeInterval now,
                                             double windowDurationMinutes) {
    if (!isfinite(resetAt) || !isfinite(now) ||
        !isfinite(windowDurationMinutes) || windowDurationMinutes <= 0.0) {
        return NAN;
    }

    double windowSeconds = windowDurationMinutes * 60.0;
    double remainingSeconds = resetAt - now;
    return MAX(0.0, MIN(100.0, (remainingSeconds / windowSeconds) * 100.0));
}
