#import "PersistentStartup.h"
#import "UsagePace.h"
#import <Cocoa/Cocoa.h>
#import <ServiceManagement/ServiceManagement.h>
#import <math.h>

static NSString * const LaunchAtLoginPreferenceKey = @"launchAtLoginPreference";
static NSString * const DisplayModeKey = @"displayMode";
static NSString * const DisplayModePercent = @"percent";
static NSString * const DisplayModeBattery = @"battery";
static NSString * const TimeModeKey = @"timeMode";
static NSString * const TimeModeClock = @"clock";
static NSString * const TimeModeCountdown = @"countdown";
static NSString * const MetricModeKey = @"metricMode";
static NSString * const MetricModeLeft = @"left";
static NSString * const MetricModeUsed = @"used";
static NSString * const WidgetWindowModeKey = @"widgetWindowMode";
static NSString * const WidgetWindowDaily = @"daily";
static NSString * const WidgetWindowWeekly = @"weekly";
static NSString * const RefreshIntervalKey = @"refreshIntervalSeconds";
static NSTimeInterval const DefaultRefreshIntervalSeconds = 300.0;

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSTimer *pollTimer;
@property(nonatomic, strong) NSTimer *displayTimer;
@property(nonatomic, strong) NSDictionary *latestState;
@property(nonatomic, strong) NSImage *codexIcon;
@property(nonatomic, copy) NSString *launchAtLoginError;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    [NSUserDefaults.standardUserDefaults registerDefaults:@{
        LaunchAtLoginPreferenceKey: @YES,
        DisplayModeKey: DisplayModePercent,
        TimeModeKey: TimeModeClock,
        MetricModeKey: MetricModeLeft,
        WidgetWindowModeKey: WidgetWindowDaily,
        RefreshIntervalKey: @(DefaultRefreshIntervalSeconds)
    }];

    [self ensureLaunchAtLoginIfPreferred];

    self.codexIcon = [self codexMenuBarIcon];
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"--";
    self.statusItem.button.image = self.codexIcon;
    self.statusItem.button.imagePosition = NSImageLeft;
    self.statusItem.button.font = [NSFont monospacedDigitSystemFontOfSize:[NSFont systemFontSize]
                                                                    weight:NSFontWeightMedium];
    self.statusItem.menu = [self menuForCurrentState];

    [self refresh];
    [self schedulePollTimer];
    self.displayTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                         target:self
                                                       selector:@selector(updateStatusItem)
                                                       userInfo:nil
                                                        repeats:YES];
}

- (NSImage *)codexMenuBarIcon {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSString *bundledIcon = [NSBundle.mainBundle pathForResource:@"CodexMenuBarIcon" ofType:@"svg"];
    if (bundledIcon.length > 0) {
        [paths addObject:bundledIcon];
    }
    NSArray<NSString *> *names = @[
        @"codexTemplate@2x.png",
        @"icon-codex-dark.png"
    ];

    for (NSString *directory in [self codexAppResourceDirectories]) {
        for (NSString *name in names) {
            [paths addObject:[directory stringByAppendingPathComponent:name]];
        }
    }

    for (NSString *path in paths) {
        NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];
        if (image != nil) {
            image.template = YES;
            image.size = NSMakeSize(18.0, 18.0);
            return image;
        }
    }

    NSImage *fallback = [NSImage imageWithSystemSymbolName:@"terminal.fill"
                                  accessibilityDescription:@"Codex"];
    fallback.template = YES;
    fallback.size = NSMakeSize(18.0, 18.0);
    return fallback;
}

- (NSArray<NSString *> *)codexAppResourceDirectories {
    NSMutableArray<NSString *> *directories = [NSMutableArray array];

    NSURL *installedAppURL = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.openai.codex"];
    if (installedAppURL.path.length > 0) {
        [directories addObject:[installedAppURL.path stringByAppendingPathComponent:@"Contents/Resources"]];
    }

    NSArray<NSString *> *knownApplications = @[
        @"/Applications/ChatGPT.app",
        @"/Applications/Codex.app",
        [[@"~/Applications/ChatGPT.app" stringByExpandingTildeInPath] stringByStandardizingPath],
        [[@"~/Applications/Codex.app" stringByExpandingTildeInPath] stringByStandardizingPath]
    ];
    for (NSString *application in knownApplications) {
        NSString *resources = [application stringByAppendingPathComponent:@"Contents/Resources"];
        if (![directories containsObject:resources]) {
            [directories addObject:resources];
        }
    }

    return directories;
}

- (NSImage *)batteryIconForPercent:(double)percent recommendedPercent:(double)recommendedPercent {
    double clamped = MAX(0.0, MIN(100.0, percent));
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(66.0, 18.0)];
    __block NSColor *foregroundColor = NSColor.blackColor;
    NSAppearance *appearance = self.statusItem.button.effectiveAppearance ?: NSApp.effectiveAppearance;
    [appearance performAsCurrentDrawingAppearance:^{
        foregroundColor = [NSColor.labelColor colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace]
            ?: NSColor.blackColor;
    }];

    [image lockFocus];

    [NSColor.blackColor set];
    if (self.codexIcon != nil) {
        [self.codexIcon drawInRect:NSMakeRect(0.0, 0.0, 18.0, 18.0)];
    }

    NSRect body = NSMakeRect(24.0, 3.0, 34.0, 12.0);
    NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:body xRadius:2.0 yRadius:2.0];
    outline.lineWidth = 1.4;
    [outline stroke];

    NSRect nub = NSMakeRect(NSMaxX(body) + 1.0, 6.5, 2.0, 5.0);
    [[NSBezierPath bezierPathWithRoundedRect:nub xRadius:0.8 yRadius:0.8] fill];

    CGFloat fillWidth = (CGFloat)((body.size.width - 4.0) * (clamped / 100.0));
    NSBezierPath *fillPath = nil;
    if (fillWidth > 0.5) {
        NSRect fillRect = NSMakeRect(body.origin.x + 2.0, body.origin.y + 2.0, fillWidth, body.size.height - 4.0);
        fillPath = [NSBezierPath bezierPathWithRoundedRect:fillRect xRadius:1.0 yRadius:1.0];
        [fillPath fill];
    }

    NSString *number = [NSString stringWithFormat:@"%.0f", clamped];
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:8.5 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: NSColor.blackColor
    };
    NSSize numberSize = [number sizeWithAttributes:attributes];
    NSPoint numberPoint = NSMakePoint(NSMidX(body) - numberSize.width / 2.0,
                                      NSMidY(body) - numberSize.height / 2.0 - 0.5);
    [number drawAtPoint:numberPoint withAttributes:attributes];

    // Template images carry opacity rather than fixed colors. Remove the part of
    // each glyph that overlaps the charge so it reveals the menu-bar background;
    // the remainder keeps the system icon tint. This gives the number opposite
    // contrast on either side of the moving fill boundary in light and dark mode.
    if (fillPath != nil) {
        [NSGraphicsContext saveGraphicsState];
        [fillPath addClip];
        NSGraphicsContext.currentContext.compositingOperation = NSCompositingOperationDestinationOut;
        [number drawAtPoint:numberPoint withAttributes:attributes];
        [NSGraphicsContext restoreGraphicsState];
    }

    // Resolve the template artwork to the current menu-bar foreground color.
    [foregroundColor setFill];
    NSRectFillUsingOperation(NSMakeRect(0.0, 0.0, image.size.width, image.size.height),
                             NSCompositingOperationSourceIn);

    if (isfinite(recommendedPercent)) {
        double pace = MAX(0.0, MIN(100.0, recommendedPercent));
        CGFloat markerX = body.origin.x + 2.0 + (body.size.width - 4.0) * (CGFloat)(pace / 100.0);
        NSRect numberBounds = NSMakeRect(numberPoint.x - 0.5,
                                         numberPoint.y,
                                         numberSize.width + 1.0,
                                         numberSize.height);
        CGFloat markerAlpha = NSPointInRect(NSMakePoint(markerX, NSMidY(numberBounds)), numberBounds)
            ? 0.45
            : 1.0;
        NSBezierPath *marker = [NSBezierPath bezierPath];
        [marker moveToPoint:NSMakePoint(markerX, body.origin.y + 1.0)];
        [marker lineToPoint:NSMakePoint(markerX, NSMaxY(body) - 1.0)];
        marker.lineWidth = 1.5;
        marker.lineCapStyle = NSLineCapStyleRound;
        [[foregroundColor colorWithAlphaComponent:markerAlpha] setStroke];
        [marker stroke];

        // Match the number's adaptive contrast: keep the foreground-colored
        // portion over empty space and cut out the portion over battery fill.
        if (fillPath != nil) {
            [NSGraphicsContext saveGraphicsState];
            [fillPath addClip];
            NSGraphicsContext.currentContext.compositingOperation = NSCompositingOperationDestinationOut;
            [marker stroke];
            [NSGraphicsContext restoreGraphicsState];
        }

        // Reapply the contrasting number mask after the marker so the pace
        // indicator can never paint over a digit when their positions overlap.
        NSDictionary *foregroundAttributes = @{
            NSFontAttributeName: attributes[NSFontAttributeName],
            NSForegroundColorAttributeName: foregroundColor
        };
        [number drawAtPoint:numberPoint withAttributes:foregroundAttributes];
        if (fillPath != nil) {
            [NSGraphicsContext saveGraphicsState];
            [fillPath addClip];
            NSGraphicsContext.currentContext.compositingOperation = NSCompositingOperationDestinationOut;
            [number drawAtPoint:numberPoint withAttributes:foregroundAttributes];
            [NSGraphicsContext restoreGraphicsState];
        }
    }

    [image unlockFocus];
    image.template = NO;
    return image;
}

- (void)menuWillOpen:(NSMenu *)menu {
    (void)menu;
    self.statusItem.menu = [self menuForCurrentState];
}

- (NSMenu *)menuForCurrentState {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Codex Usage"];
    menu.delegate = self;

    NSMenuItem *header = [[NSMenuItem alloc] initWithTitle:@"Codex Usage" action:nil keyEquivalent:@""];
    header.enabled = NO;
    [menu addItem:header];
    [menu addItem:[NSMenuItem separatorItem]];

    NSDictionary *state = self.latestState;
    [self addDisabledItem:[self detailUsageTextForState:state] toMenu:menu];
    if ([state[@"weekly_summary"] isKindOfClass:[NSString class]]) {
        [self addDisabledItem:state[@"weekly_summary"] toMenu:menu];
    }
    [self addDisabledItem:[self resetClockDetailForState:state] toMenu:menu];
    [self addDisabledItem:[self countdownDetailForState:state] toMenu:menu];

    if ([state[@"credits_summary"] isKindOfClass:[NSString class]]) {
        [self addDisabledItem:state[@"credits_summary"] toMenu:menu];
    }
    if ([state[@"reset_credits_summary"] isKindOfClass:[NSString class]]) {
        [self addDisabledItem:state[@"reset_credits_summary"] toMenu:menu];
    }
    if ([state[@"monthly_summary"] isKindOfClass:[NSString class]]) {
        [self addDisabledItem:state[@"monthly_summary"] toMenu:menu];
    }
    if ([state[@"plan_summary"] isKindOfClass:[NSString class]]) {
        [self addDisabledItem:state[@"plan_summary"] toMenu:menu];
    }
    if ([state[@"limit_summaries"] isKindOfClass:[NSArray class]]) {
        for (id summary in state[@"limit_summaries"]) {
            if ([summary isKindOfClass:[NSString class]]) {
                [self addDisabledItem:summary toMenu:menu];
            }
        }
    }
    [self addDisabledItem:state[@"updated_summary"] ?: @"Updated: unknown" toMenu:menu];

    if ([state[@"source_summary"] isKindOfClass:[NSString class]]) {
        [self addDisabledItem:state[@"source_summary"] toMenu:menu];
    }
    if (self.launchAtLoginError.length > 0) {
        [self addDisabledItem:[NSString stringWithFormat:@"Login item: %@", self.launchAtLoginError] toMenu:menu];
    }

    NSNumber *ok = state[@"ok"];
    if ([ok respondsToSelector:@selector(boolValue)] && ![ok boolValue] &&
        [state[@"error"] isKindOfClass:[NSString class]]) {
        [menu addItem:[NSMenuItem separatorItem]];
        [self addDisabledItem:[NSString stringWithFormat:@"Error: %@", state[@"error"]] toMenu:menu];
    }

    [menu addItem:[NSMenuItem separatorItem]];
    [self addChoiceWithTitle:@"Show Percentage"
                      action:@selector(usePercentDisplay)
                     checked:[[self displayMode] isEqualToString:DisplayModePercent]
                      toMenu:menu];
    [self addChoiceWithTitle:@"Show Battery"
                      action:@selector(useBatteryDisplay)
                     checked:[[self displayMode] isEqualToString:DisplayModeBattery]
                      toMenu:menu];

    [menu addItem:[NSMenuItem separatorItem]];
    [self addChoiceWithTitle:@"Show % Left"
                      action:@selector(useLeftMetric)
                     checked:[[self metricMode] isEqualToString:MetricModeLeft]
                      toMenu:menu];
    [self addChoiceWithTitle:@"Show % Used"
                      action:@selector(useUsedMetric)
                     checked:[[self metricMode] isEqualToString:MetricModeUsed]
                      toMenu:menu];

    [menu addItem:[NSMenuItem separatorItem]];
    [self addChoiceWithTitle:@"Widget: Daily"
                      action:@selector(useDailyWidgetWindow)
                     checked:[[self widgetWindowMode] isEqualToString:WidgetWindowDaily]
                      toMenu:menu];
    [self addChoiceWithTitle:@"Widget: Weekly"
                      action:@selector(useWeeklyWidgetWindow)
                     checked:[[self widgetWindowMode] isEqualToString:WidgetWindowWeekly]
                      toMenu:menu];

    [menu addItem:[NSMenuItem separatorItem]];
    [self addChoiceWithTitle:@"Show Reset Time"
                      action:@selector(useClockTime)
                     checked:[[self timeMode] isEqualToString:TimeModeClock]
                      toMenu:menu];
    [self addChoiceWithTitle:@"Show Countdown"
                      action:@selector(useCountdownTime)
                     checked:[[self timeMode] isEqualToString:TimeModeCountdown]
                      toMenu:menu];

    [menu addItem:[NSMenuItem separatorItem]];
    [self addRefreshIntervalSubmenuToMenu:menu];

    [menu addItem:[NSMenuItem separatorItem]];
    [self addChoiceWithTitle:@"Launch at Login & Keep Running"
                      action:@selector(toggleLaunchAtLogin)
                     checked:[self launchAtLoginEnabled]
                      toMenu:menu];

    [self addActionsToMenu:menu];
    return menu;
}

- (void)addActionsToMenu:(NSMenu *)menu {
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *refresh = [[NSMenuItem alloc] initWithTitle:@"Refresh Now"
                                                     action:@selector(refresh)
                                              keyEquivalent:@"r"];
    refresh.target = self;
    [menu addItem:refresh];

    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit"
                                                  action:@selector(quit)
                                           keyEquivalent:@"q"];
    quit.target = self;
    [menu addItem:quit];
}

- (void)addChoiceWithTitle:(NSString *)title action:(SEL)action checked:(BOOL)checked toMenu:(NSMenu *)menu {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    item.state = checked ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:item];
}

- (void)addRefreshIntervalSubmenuToMenu:(NSMenu *)menu {
    NSTimeInterval current = [self refreshIntervalSeconds];
    NSMenuItem *root = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Refresh Every: %@",
                                                          [self refreshIntervalLabelForSeconds:current]]
                                                  action:nil
                                           keyEquivalent:@""];
    NSMenu *submenu = [[NSMenu alloc] initWithTitle:@"Refresh Every"];
    NSArray<NSNumber *> *intervals = @[@30.0, @60.0, @180.0, @300.0];

    for (NSNumber *interval in intervals) {
        NSTimeInterval seconds = interval.doubleValue;
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[self refreshIntervalLabelForSeconds:seconds]
                                                      action:@selector(useRefreshInterval:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = interval;
        item.state = fabs(seconds - current) < 0.5 ? NSControlStateValueOn : NSControlStateValueOff;
        [submenu addItem:item];
    }

    root.submenu = submenu;
    [menu addItem:root];
}

- (void)addDisabledItem:(NSString *)title toMenu:(NSMenu *)menu {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title ?: @"" action:nil keyEquivalent:@""];
    item.enabled = NO;
    [menu addItem:item];
}

- (void)updateStatusItem {
    NSDictionary *state = self.latestState;
    NSNumber *ok = state[@"ok"];
    if (![ok respondsToSelector:@selector(boolValue)] || ![ok boolValue]) {
        self.statusItem.button.toolTip = nil;
        self.statusItem.button.image = self.codexIcon;
        self.statusItem.button.title = @"--";
        return;
    }

    double metric = [self displayPercentForWidgetState:state];
    NSString *timeText = [self timeTextForWidgetState:state];

    if ([[self displayMode] isEqualToString:DisplayModeBattery]) {
        double recommendedPercent = NAN;
        if ([[self metricMode] isEqualToString:MetricModeLeft]) {
            recommendedPercent = [self recommendedPercentLeftForWidgetState:state];
        }
        self.statusItem.button.image = [self batteryIconForPercent:metric recommendedPercent:recommendedPercent];
        self.statusItem.button.title = timeText;
        self.statusItem.button.toolTip = isfinite(recommendedPercent) ? @"Contrast marker: on-pace usage target" : nil;
        return;
    }

    self.statusItem.button.toolTip = nil;
    self.statusItem.button.image = self.codexIcon;
    if (isnan(metric)) {
        self.statusItem.button.title = timeText.length > 0 ? timeText : @"--";
    } else {
        NSString *metricLabel = [self metricLabel];
        if (metricLabel.length > 0) {
            self.statusItem.button.title = [NSString stringWithFormat:@"%@ | %.0f%% %@", timeText, metric, metricLabel];
        } else {
            self.statusItem.button.title = [NSString stringWithFormat:@"%@ | %.0f%%", timeText, metric];
        }
    }
}

- (NSString *)detailUsageTextForState:(NSDictionary *)state {
    double used = [self usagePercentForState:state];
    if (isnan(used)) {
        return @"Codex usage: unavailable";
    }
    double left = MAX(0.0, MIN(100.0, 100.0 - used));
    return [NSString stringWithFormat:@"Codex: %.0f%% left, %.0f%% used", left, used];
}

- (NSString *)resetClockDetailForState:(NSDictionary *)state {
    NSString *clock = [self resetClockTextForState:state];
    if (clock.length == 0) {
        return @"Reset time: unknown";
    }
    return [NSString stringWithFormat:@"Reset time: %@", clock];
}

- (NSString *)countdownDetailForState:(NSDictionary *)state {
    NSString *countdown = [self countdownTextForState:state];
    if (countdown.length == 0) {
        return @"Countdown: unknown";
    }
    return [NSString stringWithFormat:@"Countdown: %@", countdown];
}

- (double)usagePercentForState:(NSDictionary *)state {
    id value = state[@"primary_used_percent"];
    if ([value respondsToSelector:@selector(doubleValue)]) {
        return MAX(0.0, MIN(100.0, [value doubleValue]));
    }
    return NAN;
}

- (double)displayPercentForState:(NSDictionary *)state {
    double used = [self usagePercentForState:state];
    if (isnan(used)) {
        return NAN;
    }
    if ([[self metricMode] isEqualToString:MetricModeUsed]) {
        return used;
    }
    return MAX(0.0, MIN(100.0, 100.0 - used));
}

- (double)displayPercentForWidgetState:(NSDictionary *)state {
    double used = [self widgetUsagePercentForState:state];
    if (isnan(used)) {
        return NAN;
    }
    if ([[self metricMode] isEqualToString:MetricModeUsed]) {
        return used;
    }
    return MAX(0.0, MIN(100.0, 100.0 - used));
}

- (double)widgetUsagePercentForState:(NSDictionary *)state {
    id value = [[self widgetWindowMode] isEqualToString:WidgetWindowWeekly] ? state[@"secondary_used_percent"] : state[@"primary_used_percent"];
    if (![value respondsToSelector:@selector(doubleValue)] && [[self widgetWindowMode] isEqualToString:WidgetWindowWeekly]) {
        value = state[@"primary_used_percent"];
    }
    if ([value respondsToSelector:@selector(doubleValue)]) {
        return MAX(0.0, MIN(100.0, [value doubleValue]));
    }
    return NAN;
}

- (NSString *)metricLabel {
    if ([[self metricMode] isEqualToString:MetricModeUsed]) {
        return @"used";
    }
    return @"";
}

- (NSNumber *)resetSecondsForState:(NSDictionary *)state {
    id value = state[@"primary_resets_at"];
    if ([value respondsToSelector:@selector(doubleValue)]) {
        return @([value doubleValue]);
    }
    return nil;
}

- (NSNumber *)widgetResetSecondsForState:(NSDictionary *)state {
    id value = [[self widgetWindowMode] isEqualToString:WidgetWindowWeekly] ? state[@"secondary_resets_at"] : state[@"primary_resets_at"];
    if (![value respondsToSelector:@selector(doubleValue)] && [[self widgetWindowMode] isEqualToString:WidgetWindowWeekly]) {
        value = state[@"primary_resets_at"];
    }
    if ([value respondsToSelector:@selector(doubleValue)]) {
        return @([value doubleValue]);
    }
    return nil;
}

- (NSNumber *)widgetWindowDurationMinutesForState:(NSDictionary *)state {
    BOOL weekly = [[self widgetWindowMode] isEqualToString:WidgetWindowWeekly];
    id value = state[@"primary_window_minutes"];
    if (weekly && [state[@"secondary_resets_at"] respondsToSelector:@selector(doubleValue)]) {
        value = state[@"secondary_window_minutes"];
        if (![value respondsToSelector:@selector(doubleValue)]) {
            // The weekly selector has an explicit seven-day meaning even when
            // a legacy usage event omits the window-duration field.
            return @(7.0 * 24.0 * 60.0);
        }
    }
    if ([value respondsToSelector:@selector(doubleValue)] && [value doubleValue] > 0.0) {
        return @([value doubleValue]);
    }
    return nil;
}

- (double)recommendedPercentLeftForWidgetState:(NSDictionary *)state {
    NSNumber *reset = [self widgetResetSecondsForState:state];
    NSNumber *durationMinutes = [self widgetWindowDurationMinutesForState:state];
    if (reset == nil || durationMinutes == nil) {
        return NAN;
    }
    return CodexOnPacePercentLeft(reset.doubleValue,
                                  NSDate.date.timeIntervalSince1970,
                                  durationMinutes.doubleValue);
}

- (NSString *)timeTextForState:(NSDictionary *)state {
    if ([[self timeMode] isEqualToString:TimeModeCountdown]) {
        return [self countdownTextForState:state] ?: @"--:--";
    }
    return [self resetClockTextForState:state] ?: @"--";
}

- (NSString *)timeTextForWidgetState:(NSDictionary *)state {
    if ([[self timeMode] isEqualToString:TimeModeCountdown]) {
        return [self countdownTextForWidgetState:state] ?: @"--:--";
    }
    return [self resetClockTextForWidgetState:state] ?: @"--";
}

- (NSString *)resetClockTextForState:(NSDictionary *)state {
    NSNumber *seconds = [self resetSecondsForState:state];
    if (seconds == nil) {
        return nil;
    }

    NSDate *date = [NSDate dateWithTimeIntervalSince1970:seconds.doubleValue];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterNoStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    return [formatter stringFromDate:date];
}

- (NSString *)resetClockTextForWidgetState:(NSDictionary *)state {
    NSNumber *seconds = [self widgetResetSecondsForState:state];
    if (seconds == nil) {
        return nil;
    }

    NSDate *date = [NSDate dateWithTimeIntervalSince1970:seconds.doubleValue];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterNoStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    return [formatter stringFromDate:date];
}

- (NSString *)countdownTextForState:(NSDictionary *)state {
    NSNumber *seconds = [self resetSecondsForState:state];
    if (seconds == nil) {
        return nil;
    }

    NSInteger remaining = MAX(0, (NSInteger)llround(seconds.doubleValue - [NSDate date].timeIntervalSince1970));
    NSInteger hours = remaining / 3600;
    NSInteger minutes = (remaining % 3600) / 60;
    NSInteger secs = remaining % 60;
    return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)minutes, (long)secs];
}

- (NSString *)countdownTextForWidgetState:(NSDictionary *)state {
    NSNumber *seconds = [self widgetResetSecondsForState:state];
    if (seconds == nil) {
        return nil;
    }

    NSInteger remaining = MAX(0, (NSInteger)llround(seconds.doubleValue - [NSDate date].timeIntervalSince1970));
    NSInteger hours = remaining / 3600;
    NSInteger minutes = (remaining % 3600) / 60;
    NSInteger secs = remaining % 60;
    return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)minutes, (long)secs];
}

- (NSString *)displayMode {
    NSString *mode = [NSUserDefaults.standardUserDefaults stringForKey:DisplayModeKey];
    return mode.length > 0 ? mode : DisplayModePercent;
}

- (NSString *)timeMode {
    NSString *mode = [NSUserDefaults.standardUserDefaults stringForKey:TimeModeKey];
    return mode.length > 0 ? mode : TimeModeClock;
}

- (NSString *)metricMode {
    NSString *mode = [NSUserDefaults.standardUserDefaults stringForKey:MetricModeKey];
    return mode.length > 0 ? mode : MetricModeLeft;
}

- (NSString *)widgetWindowMode {
    NSString *mode = [NSUserDefaults.standardUserDefaults stringForKey:WidgetWindowModeKey];
    if ([mode isEqualToString:WidgetWindowWeekly]) {
        return WidgetWindowWeekly;
    }
    return WidgetWindowDaily;
}

- (NSTimeInterval)refreshIntervalSeconds {
    NSTimeInterval seconds = [NSUserDefaults.standardUserDefaults doubleForKey:RefreshIntervalKey];
    NSArray<NSNumber *> *allowed = @[@30.0, @60.0, @180.0, @300.0];
    for (NSNumber *interval in allowed) {
        if (fabs(seconds - interval.doubleValue) < 0.5) {
            return interval.doubleValue;
        }
    }
    return DefaultRefreshIntervalSeconds;
}

- (NSString *)refreshIntervalLabelForSeconds:(NSTimeInterval)seconds {
    if (fabs(seconds - 30.0) < 0.5) {
        return @"30 sec";
    }
    NSInteger minutes = (NSInteger)llround(seconds / 60.0);
    return [NSString stringWithFormat:@"%ld min", (long)minutes];
}

- (void)usePercentDisplay {
    [NSUserDefaults.standardUserDefaults setObject:DisplayModePercent forKey:DisplayModeKey];
    [self updateStatusItem];
    self.statusItem.menu = [self menuForCurrentState];
}

- (void)useBatteryDisplay {
    [NSUserDefaults.standardUserDefaults setObject:DisplayModeBattery forKey:DisplayModeKey];
    [self updateStatusItem];
    self.statusItem.menu = [self menuForCurrentState];
}

- (void)useClockTime {
    [NSUserDefaults.standardUserDefaults setObject:TimeModeClock forKey:TimeModeKey];
    [self updateStatusItem];
    self.statusItem.menu = [self menuForCurrentState];
}

- (void)useCountdownTime {
    [NSUserDefaults.standardUserDefaults setObject:TimeModeCountdown forKey:TimeModeKey];
    [self updateStatusItem];
    self.statusItem.menu = [self menuForCurrentState];
}

- (void)useLeftMetric {
    [NSUserDefaults.standardUserDefaults setObject:MetricModeLeft forKey:MetricModeKey];
    [self updateStatusItem];
    self.statusItem.menu = [self menuForCurrentState];
}

- (void)useUsedMetric {
    [NSUserDefaults.standardUserDefaults setObject:MetricModeUsed forKey:MetricModeKey];
    [self updateStatusItem];
    self.statusItem.menu = [self menuForCurrentState];
}

- (void)useDailyWidgetWindow {
    [NSUserDefaults.standardUserDefaults setObject:WidgetWindowDaily forKey:WidgetWindowModeKey];
    [self updateStatusItem];
    self.statusItem.menu = [self menuForCurrentState];
}

- (void)useWeeklyWidgetWindow {
    [NSUserDefaults.standardUserDefaults setObject:WidgetWindowWeekly forKey:WidgetWindowModeKey];
    [self updateStatusItem];
    self.statusItem.menu = [self menuForCurrentState];
}

- (void)useRefreshInterval:(NSMenuItem *)sender {
    NSNumber *interval = sender.representedObject;
    if (![interval respondsToSelector:@selector(doubleValue)]) {
        return;
    }

    [NSUserDefaults.standardUserDefaults setDouble:interval.doubleValue forKey:RefreshIntervalKey];
    [self schedulePollTimer];
    self.statusItem.menu = [self menuForCurrentState];
}

- (void)schedulePollTimer {
    [self.pollTimer invalidate];
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:[self refreshIntervalSeconds]
                                                      target:self
                                                    selector:@selector(refresh)
                                                    userInfo:nil
                                                     repeats:YES];
}

- (void)refresh {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *state = [self loadUsageState];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.latestState = state;
            [self updateStatusItem];
            self.statusItem.menu = [self menuForCurrentState];
        });
    });
}

- (NSDictionary *)loadUsageState {
    NSDictionary *liveState = [self loadUsageStateFromAppServer];
    NSNumber *liveOk = liveState[@"ok"];
    if ([liveOk respondsToSelector:@selector(boolValue)] && [liveOk boolValue]) {
        return liveState;
    }

    NSDictionary *offlineState = [self loadUsageStateFromJSONL];
    NSNumber *offlineOk = offlineState[@"ok"];
    if ([offlineOk respondsToSelector:@selector(boolValue)] && [offlineOk boolValue]) {
        NSMutableDictionary *state = [offlineState mutableCopy];
        NSString *liveError = liveState[@"error"];
        if ([liveError isKindOfClass:[NSString class]] && liveError.length > 0) {
            state[@"live_error"] = liveError;
        }
        return state;
    }

    NSString *liveError = [liveState[@"error"] isKindOfClass:[NSString class]] ? liveState[@"error"] : @"Codex app-server unavailable";
    NSString *offlineError = [offlineState[@"error"] isKindOfClass:[NSString class]] ? offlineState[@"error"] : @"No offline usage event found";
    return @{
        @"ok": @NO,
        @"menu_title": @"--",
        @"primary_summary": @"Codex usage: unavailable",
        @"updated_summary": @"Updated: unavailable",
        @"source_summary": @"Source: unavailable",
        @"error": [NSString stringWithFormat:@"Live: %@; offline: %@", liveError, offlineError]
    };
}

- (NSDictionary *)loadUsageStateFromAppServer {
    NSString *codexPath = [self codexCLIPath];
    if (codexPath.length == 0) {
        return @{@"ok": @NO, @"error": @"Codex CLI not found"};
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:codexPath];
    task.arguments = @[@"app-server", @"--stdio"];

    NSPipe *stdinPipe = [NSPipe pipe];
    NSPipe *stdoutPipe = [NSPipe pipe];
    NSPipe *stderrPipe = [NSPipe pipe];
    task.standardInput = stdinPipe;
    task.standardOutput = stdoutPipe;
    task.standardError = stderrPipe;

    NSMutableData *outputData = [NSMutableData data];
    NSMutableData *errorData = [NSMutableData data];
    dispatch_semaphore_t initializeReady = dispatch_semaphore_create(0);
    dispatch_semaphore_t responseReady = dispatch_semaphore_create(0);

    stdoutPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *chunk = [handle availableData];
        if (chunk.length == 0) {
            return;
        }
        @synchronized (outputData) {
            [outputData appendData:chunk];
            if ([self jsonRPCResponseWithId:@"codex-usage-menu-bar-init" fromData:outputData] != nil) {
                dispatch_semaphore_signal(initializeReady);
            }
            if ([self jsonRPCResponseWithId:@"codex-usage-menu-bar" fromData:outputData] != nil) {
                dispatch_semaphore_signal(responseReady);
            }
        }
    };
    stderrPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *chunk = [handle availableData];
        if (chunk.length == 0) {
            return;
        }
        @synchronized (errorData) {
            [errorData appendData:chunk];
        }
    };

    @try {
        [task launch];
        NSDictionary *initialize = @{
            @"id": @"codex-usage-menu-bar-init",
            @"method": @"initialize",
            @"params": @{
                @"clientInfo": @{
                    @"name": @"codex-usage-menu-bar",
                    @"version": NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"0.1.0"
                },
                @"capabilities": @{
                    @"experimentalApi": @YES
                }
            }
        };
        NSData *initializeData = [NSJSONSerialization dataWithJSONObject:initialize options:0 error:nil];
        if (initializeData != nil) {
            [[stdinPipe fileHandleForWriting] writeData:initializeData];
            [[stdinPipe fileHandleForWriting] writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
        }
    } @catch (NSException *exception) {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil;
        stderrPipe.fileHandleForReading.readabilityHandler = nil;
        return @{
            @"ok": @NO,
            @"error": [NSString stringWithFormat:@"Could not start Codex app-server: %@", exception.reason ?: @"unknown"]
        };
    }

    long initializeWaitResult = dispatch_semaphore_wait(initializeReady, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)));
    if (initializeWaitResult != 0) {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil;
        stderrPipe.fileHandleForReading.readabilityHandler = nil;
        [[stdinPipe fileHandleForWriting] closeFile];
        if (task.isRunning) {
            [task terminate];
            [task waitUntilExit];
        }
        return @{@"ok": @NO, @"error": @"Codex app-server initialization timed out"};
    }

    @try {
        NSDictionary *initialized = @{
            @"method": @"initialized",
            @"params": @{}
        };
        NSDictionary *request = @{
            @"id": @"codex-usage-menu-bar",
            @"method": @"account/rateLimits/read",
            @"params": [NSNull null]
        };
        for (NSDictionary *message in @[initialized, request]) {
            NSData *messageData = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
            if (messageData != nil) {
                [[stdinPipe fileHandleForWriting] writeData:messageData];
                [[stdinPipe fileHandleForWriting] writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
            }
        }
    } @catch (NSException *exception) {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil;
        stderrPipe.fileHandleForReading.readabilityHandler = nil;
        [[stdinPipe fileHandleForWriting] closeFile];
        if (task.isRunning) {
            [task terminate];
            [task waitUntilExit];
        }
        return @{
            @"ok": @NO,
            @"error": [NSString stringWithFormat:@"Could not query Codex app-server: %@", exception.reason ?: @"unknown"]
        };
    }

    long waitResult = dispatch_semaphore_wait(responseReady, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)));
    stdoutPipe.fileHandleForReading.readabilityHandler = nil;
    stderrPipe.fileHandleForReading.readabilityHandler = nil;

    [[stdinPipe fileHandleForWriting] closeFile];
    if (task.isRunning) {
        [task terminate];
        [task waitUntilExit];
    }

    if (waitResult != 0) {
        return @{@"ok": @NO, @"error": @"Codex app-server request timed out"};
    }

    NSData *data = nil;
    @synchronized (outputData) {
        data = [outputData copy];
    }
    NSDictionary *response = [self jsonRPCResponseWithId:@"codex-usage-menu-bar" fromData:data];
    NSDictionary *result = [response[@"result"] isKindOfClass:[NSDictionary class]] ? response[@"result"] : nil;
    if (result != nil) {
        NSDictionary *state = [self buildStateFromRateLimitsResult:result
                                                        sourceText:@"Codex app-server"
                                                         timestamp:[NSDate date]];
        if (state != nil) {
            return state;
        }
    }

    NSData *capturedErrorData = nil;
    @synchronized (errorData) {
        capturedErrorData = [errorData copy];
    }
    NSString *stderrText = [[NSString alloc] initWithData:capturedErrorData encoding:NSUTF8StringEncoding];
    NSString *message = stderrText.length > 0 ? [stderrText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"Codex app-server returned invalid JSON";

    return @{
        @"ok": @NO,
        @"error": message
    };
}

- (NSString *)codexCLIPath {
    NSString *override = NSProcessInfo.processInfo.environment[@"CODEX_CLI"];
    if (override.length > 0) {
        return override;
    }

    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    for (NSString *directory in [self codexAppResourceDirectories]) {
        [candidates addObject:[directory stringByAppendingPathComponent:@"codex"]];
    }
    [candidates addObjectsFromArray:@[
        @"/opt/homebrew/bin/codex",
        @"/usr/local/bin/codex"
    ]];
    for (NSString *path in candidates) {
        if ([NSFileManager.defaultManager isExecutableFileAtPath:path]) {
            return path;
        }
    }
    return nil;
}

- (NSDictionary *)jsonRPCResponseWithId:(NSString *)requestId fromData:(NSData *)data {
    if (data.length == 0) {
        return nil;
    }

    id whole = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if ([whole isKindOfClass:[NSDictionary class]] && [whole[@"id"] isEqual:requestId]) {
        return whole;
    }

    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if (line.length == 0) {
            continue;
        }
        NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];
        id object = [NSJSONSerialization JSONObjectWithData:lineData options:0 error:nil];
        if ([object isKindOfClass:[NSDictionary class]] && [object[@"id"] isEqual:requestId]) {
            return object;
        }
    }
    return nil;
}

- (NSDictionary *)loadUsageStateFromJSONL {
    NSDictionary *event = [self latestOfflineUsageEvent];
    if (event == nil) {
        return @{
            @"ok": @NO,
            @"menu_title": @"--",
            @"primary_summary": @"Codex usage: unavailable",
            @"updated_summary": @"Updated: no local token-count event found",
            @"error": @"No Codex usage event found under ~/.codex/sessions"
        };
    }

    NSDictionary *rateLimits = [event[@"rate_limits"] isKindOfClass:[NSDictionary class]] ? event[@"rate_limits"] : nil;
    if (rateLimits == nil) {
        return @{@"ok": @NO, @"error": @"Offline usage event has no rate limit snapshot"};
    }

    NSDate *timestamp = [self dateFromISOString:event[@"timestamp"]];
    return [self buildStateFromLegacySnapshot:rateLimits
                                   sourceText:[NSString stringWithFormat:@"Offline JSONL (%@)", [event[@"source_path"] lastPathComponent]]
                                    timestamp:timestamp];
}

- (NSDictionary *)latestOfflineUsageEvent {
    NSArray<NSURL *> *files = [self recentUsageFiles];
    NSDictionary *latest = nil;

    for (NSURL *fileURL in files) {
        NSArray<NSData *> *lines = [self candidateOfflineLinesFromFile:fileURL];
        for (NSData *line in lines) {
            id json = [NSJSONSerialization JSONObjectWithData:line options:0 error:nil];
            if (![json isKindOfClass:[NSDictionary class]]) {
                continue;
            }

            NSDictionary *payload = [json[@"payload"] isKindOfClass:[NSDictionary class]] ? json[@"payload"] : nil;
            if (![payload[@"type"] isEqualToString:@"token_count"] ||
                ![payload[@"rate_limits"] isKindOfClass:[NSDictionary class]]) {
                continue;
            }

            NSMutableDictionary *event = [@{
                @"timestamp": json[@"timestamp"] ?: @"",
                @"rate_limits": payload[@"rate_limits"],
                @"source_path": fileURL.path ?: @""
            } mutableCopy];
            if (latest == nil || [event[@"timestamp"] compare:(latest[@"timestamp"] ?: @"")] == NSOrderedDescending) {
                latest = event;
            }
            break;
        }
    }

    return latest;
}

- (NSArray<NSURL *> *)recentUsageFiles {
    NSString *codexHome = NSProcessInfo.processInfo.environment[@"CODEX_HOME"];
    if (codexHome.length == 0) {
        codexHome = [@"~/.codex" stringByExpandingTildeInPath];
    }
    NSURL *sessionsURL = [NSURL fileURLWithPath:[codexHome stringByAppendingPathComponent:@"sessions"]];

    NSDirectoryEnumerator<NSURL *> *enumerator = [NSFileManager.defaultManager enumeratorAtURL:sessionsURL
                                                                    includingPropertiesForKeys:@[NSURLContentModificationDateKey]
                                                                                       options:0
                                                                                  errorHandler:nil];
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    for (NSURL *url in enumerator) {
        if (![url.pathExtension isEqualToString:@"jsonl"]) {
            continue;
        }
        NSDate *date = nil;
        [url getResourceValue:&date forKey:NSURLContentModificationDateKey error:nil];
        [entries addObject:@{@"url": url, @"date": date ?: NSDate.distantPast}];
    }

    [entries sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [right[@"date"] compare:left[@"date"]];
    }];

    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    NSUInteger count = MIN(entries.count, 150);
    for (NSUInteger index = 0; index < count; index++) {
        [urls addObject:entries[index][@"url"]];
    }
    return urls;
}

- (NSArray<NSData *> *)candidateOfflineLinesFromFile:(NSURL *)fileURL {
    NSData *data = [NSData dataWithContentsOfURL:fileURL options:NSDataReadingMappedIfSafe error:nil];
    if (data.length == 0) {
        return @[];
    }

    NSUInteger tailBytes = MIN(data.length, (NSUInteger)(4 * 1024 * 1024));
    NSData *tail = [data subdataWithRange:NSMakeRange(data.length - tailBytes, tailBytes)];
    NSString *text = [[NSString alloc] initWithData:tail encoding:NSUTF8StringEncoding];
    if (text.length == 0) {
        return @[];
    }

    NSArray<NSString *> *rawLines = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    NSMutableArray<NSData *> *lines = [NSMutableArray array];
    for (NSString *line in [rawLines reverseObjectEnumerator]) {
        if ([line containsString:@"token_count"] && [line containsString:@"rate_limits"]) {
            NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];
            if (lineData != nil) {
                [lines addObject:lineData];
            }
        }
    }
    return lines;
}

- (NSDictionary *)buildStateFromRateLimitsResult:(NSDictionary *)result sourceText:(NSString *)sourceText timestamp:(NSDate *)timestamp {
    NSDictionary *snapshot = [self preferredSnapshotFromResult:result];
    if (snapshot == nil) {
        return nil;
    }

    NSMutableDictionary *state = [[self buildStateFromSnapshot:snapshot
                                                    sourceText:sourceText
                                                     timestamp:timestamp
                                                  appServerKeys:YES] mutableCopy];

    NSString *resetCredits = [self resetCreditsSummary:result[@"rateLimitResetCredits"]];
    if (resetCredits.length > 0) {
        state[@"reset_credits_summary"] = resetCredits;
    }

    NSArray *summaries = [self limitSummariesFromResult:result];
    if (summaries.count > 0) {
        state[@"limit_summaries"] = summaries;
    }

    return state;
}

- (NSDictionary *)buildStateFromLegacySnapshot:(NSDictionary *)snapshot sourceText:(NSString *)sourceText timestamp:(NSDate *)timestamp {
    NSMutableDictionary *state = [[self buildStateFromSnapshot:snapshot
                                                    sourceText:sourceText
                                                     timestamp:timestamp
                                                  appServerKeys:NO] mutableCopy];
    NSArray *summaries = [self summariesForSnapshot:snapshot fallbackName:[self snapshotName:snapshot appServerKeys:NO] appServerKeys:NO];
    if (summaries.count > 0) {
        state[@"limit_summaries"] = summaries;
    }
    return state;
}

- (NSDictionary *)buildStateFromSnapshot:(NSDictionary *)snapshot
                              sourceText:(NSString *)sourceText
                               timestamp:(NSDate *)timestamp
                            appServerKeys:(BOOL)appServerKeys {
    NSDictionary *primary = [self windowForSnapshot:snapshot key:@"primary"];
    NSDictionary *secondary = [self windowForSnapshot:snapshot key:@"secondary"];
    NSNumber *primaryUsed = [self numberFromDictionary:primary keys:appServerKeys ? @[@"usedPercent"] : @[@"used_percent"]];
    NSNumber *primaryReset = [self numberFromDictionary:primary keys:appServerKeys ? @[@"resetsAt"] : @[@"resets_at"]];
    NSNumber *primaryWindowMinutes = [self numberFromDictionary:primary keys:appServerKeys ? @[@"windowDurationMins"] : @[@"window_minutes"]];
    NSNumber *secondaryUsed = [self numberFromDictionary:secondary keys:appServerKeys ? @[@"usedPercent"] : @[@"used_percent"]];
    NSNumber *secondaryReset = [self numberFromDictionary:secondary keys:appServerKeys ? @[@"resetsAt"] : @[@"resets_at"]];
    NSNumber *secondaryWindowMinutes = [self numberFromDictionary:secondary keys:appServerKeys ? @[@"windowDurationMins"] : @[@"window_minutes"]];
    NSString *resetText = [self resetLabelForSeconds:primaryReset includeDate:NO];

    NSMutableDictionary *state = [@{
        @"ok": @YES,
        @"menu_title": primaryUsed != nil ? [NSString stringWithFormat:@"%@ | %.0f%%", resetText, primaryUsed.doubleValue] : @"--",
        @"primary_summary": [self rateLimitSummaryWithLabel:[self snapshotName:snapshot appServerKeys:appServerKeys]
                                                     window:primary
                                              appServerKeys:appServerKeys],
        @"updated_summary": [self updatedSummaryForDate:timestamp],
        @"source_summary": [NSString stringWithFormat:@"Source: %@", sourceText ?: @"unknown"]
    } mutableCopy];

    if (primaryUsed != nil) {
        state[@"primary_used_percent"] = primaryUsed;
    }
    if (primaryReset != nil) {
        state[@"primary_resets_at"] = primaryReset;
    }
    if (primaryWindowMinutes != nil) {
        state[@"primary_window_minutes"] = primaryWindowMinutes;
    }
    if (secondaryUsed != nil) {
        state[@"secondary_used_percent"] = secondaryUsed;
    }
    if (secondaryReset != nil) {
        state[@"secondary_resets_at"] = secondaryReset;
    }
    if (secondaryWindowMinutes != nil) {
        state[@"secondary_window_minutes"] = secondaryWindowMinutes;
    }

    NSString *weekly = [self weeklySummary:secondary appServerKeys:appServerKeys];
    if (weekly.length > 0) {
        state[@"weekly_summary"] = weekly;
    }

    NSString *credits = [self creditsSummary:[self dictionaryFromSnapshot:snapshot key:@"credits" appServerKeys:appServerKeys]];
    if (credits.length > 0) {
        state[@"credits_summary"] = credits;
    }

    NSString *plan = [self stringFromDictionary:snapshot keys:appServerKeys ? @[@"planType"] : @[@"plan_type"]];
    if (plan.length > 0) {
        state[@"plan_summary"] = [NSString stringWithFormat:@"Plan: %@", plan];
    }

    NSString *monthly = [self monthlySummary:[self dictionaryFromSnapshot:snapshot key:@"individualLimit" appServerKeys:appServerKeys]];
    if (monthly.length > 0) {
        state[@"monthly_summary"] = monthly;
    }

    return state;
}

- (NSDictionary *)preferredSnapshotFromResult:(NSDictionary *)result {
    NSDictionary *byLimitId = [result[@"rateLimitsByLimitId"] isKindOfClass:[NSDictionary class]] ? result[@"rateLimitsByLimitId"] : nil;
    NSDictionary *codex = [byLimitId[@"codex"] isKindOfClass:[NSDictionary class]] ? byLimitId[@"codex"] : nil;
    if (codex != nil) {
        return codex;
    }
    if (byLimitId.count > 0) {
        NSArray *keys = [[byLimitId allKeys] sortedArrayUsingSelector:@selector(compare:)];
        for (id key in keys) {
            if ([byLimitId[key] isKindOfClass:[NSDictionary class]]) {
                return byLimitId[key];
            }
        }
    }
    return [result[@"rateLimits"] isKindOfClass:[NSDictionary class]] ? result[@"rateLimits"] : nil;
}

- (NSArray<NSString *> *)limitSummariesFromResult:(NSDictionary *)result {
    NSDictionary *byLimitId = [result[@"rateLimitsByLimitId"] isKindOfClass:[NSDictionary class]] ? result[@"rateLimitsByLimitId"] : nil;
    if (byLimitId.count == 0) {
        NSDictionary *single = [result[@"rateLimits"] isKindOfClass:[NSDictionary class]] ? result[@"rateLimits"] : nil;
        return single != nil ? [self summariesForSnapshot:single fallbackName:@"Codex" appServerKeys:YES] : @[];
    }

    NSMutableArray<NSString *> *items = [NSMutableArray array];
    NSArray *keys = [[byLimitId allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (id key in keys) {
        NSDictionary *snapshot = [byLimitId[key] isKindOfClass:[NSDictionary class]] ? byLimitId[key] : nil;
        if (snapshot == nil) {
            continue;
        }
        [items addObjectsFromArray:[self summariesForSnapshot:snapshot fallbackName:[key description] appServerKeys:YES]];
    }
    return items;
}

- (NSArray<NSString *> *)summariesForSnapshot:(NSDictionary *)snapshot fallbackName:(NSString *)fallbackName appServerKeys:(BOOL)appServerKeys {
    NSMutableArray<NSString *> *items = [NSMutableArray array];
    NSString *name = [self snapshotName:snapshot appServerKeys:appServerKeys] ?: fallbackName ?: @"Codex";

    NSDictionary *primary = [self windowForSnapshot:snapshot key:@"primary"];
    if (primary != nil) {
        NSString *window = [self windowLabelForWindow:primary appServerKeys:appServerKeys];
        [items addObject:[self rateLimitSummaryWithLabel:[NSString stringWithFormat:@"%@ %@", name, window]
                                                  window:primary
                                           appServerKeys:appServerKeys]];
    }

    NSDictionary *secondary = [self windowForSnapshot:snapshot key:@"secondary"];
    if (secondary != nil) {
        NSString *window = [self windowLabelForWindow:secondary appServerKeys:appServerKeys];
        [items addObject:[self rateLimitSummaryWithLabel:[NSString stringWithFormat:@"%@ %@", name, window]
                                                  window:secondary
                                           appServerKeys:appServerKeys]];
    }

    return items;
}

- (NSDictionary *)windowForSnapshot:(NSDictionary *)snapshot key:(NSString *)key {
    id value = snapshot[key];
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

- (NSDictionary *)dictionaryFromSnapshot:(NSDictionary *)snapshot key:(NSString *)key appServerKeys:(BOOL)appServerKeys {
    (void)appServerKeys;
    id value = snapshot[key];
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

- (NSString *)snapshotName:(NSDictionary *)snapshot appServerKeys:(BOOL)appServerKeys {
    NSString *name = [self stringFromDictionary:snapshot keys:appServerKeys ? @[@"limitName", @"limitId"] : @[@"limit_name", @"limit_id"]];
    return name.length > 0 ? name : @"Codex";
}

- (NSString *)rateLimitSummaryWithLabel:(NSString *)label window:(NSDictionary *)window appServerKeys:(BOOL)appServerKeys {
    if (window == nil) {
        return [NSString stringWithFormat:@"%@: unavailable", label ?: @"Codex"];
    }

    NSNumber *used = [self numberFromDictionary:window keys:appServerKeys ? @[@"usedPercent"] : @[@"used_percent"]];
    NSNumber *reset = [self numberFromDictionary:window keys:appServerKeys ? @[@"resetsAt"] : @[@"resets_at"]];
    NSString *usedText = [self percentSummaryTextForUsedPercent:used];
    NSString *resetText = [self resetLabelForSeconds:reset includeDate:NO];
    return [NSString stringWithFormat:@"%@: %@, resets %@", label ?: @"Codex", usedText, resetText];
}

- (NSString *)weeklySummary:(NSDictionary *)window appServerKeys:(BOOL)appServerKeys {
    if (window == nil) {
        return nil;
    }

    NSNumber *used = [self numberFromDictionary:window keys:appServerKeys ? @[@"usedPercent"] : @[@"used_percent"]];
    NSNumber *reset = [self numberFromDictionary:window keys:appServerKeys ? @[@"resetsAt"] : @[@"resets_at"]];
    NSString *usedText = [self percentSummaryTextForUsedPercent:used];
    NSString *resetText = [self resetLabelForSeconds:reset includeDate:YES];
    return [NSString stringWithFormat:@"Weekly: %@, resets %@", usedText, resetText];
}

- (NSString *)percentSummaryTextForUsedPercent:(NSNumber *)used {
    if (used == nil) {
        return [[self metricMode] isEqualToString:MetricModeUsed] ? @"--% used" : @"--% left";
    }

    double usedValue = MAX(0.0, MIN(100.0, used.doubleValue));
    if ([[self metricMode] isEqualToString:MetricModeUsed]) {
        return [NSString stringWithFormat:@"%.0f%% used", usedValue];
    }

    double leftValue = MAX(0.0, MIN(100.0, 100.0 - usedValue));
    return [NSString stringWithFormat:@"%.0f%% left, %.0f%% used", leftValue, usedValue];
}

- (NSString *)windowLabelForWindow:(NSDictionary *)window appServerKeys:(BOOL)appServerKeys {
    NSNumber *minutes = [self numberFromDictionary:window keys:appServerKeys ? @[@"windowDurationMins"] : @[@"window_minutes"]];
    if (minutes == nil) {
        return @"window";
    }
    NSInteger value = minutes.integerValue;
    if (value > 0 && value % 1440 == 0) {
        return [NSString stringWithFormat:@"%ldd", (long)(value / 1440)];
    }
    if (value > 0 && value % 60 == 0) {
        return [NSString stringWithFormat:@"%ldh", (long)(value / 60)];
    }
    return [NSString stringWithFormat:@"%ldm", (long)value];
}

- (NSString *)creditsSummary:(NSDictionary *)credits {
    if (credits == nil) {
        return nil;
    }
    NSNumber *unlimited = [credits[@"unlimited"] respondsToSelector:@selector(boolValue)] ? credits[@"unlimited"] : nil;
    if (unlimited.boolValue) {
        return @"Credits: unlimited";
    }
    id balance = credits[@"balance"];
    if ([balance isKindOfClass:[NSString class]] && [balance length] > 0) {
        return [NSString stringWithFormat:@"Credits: %@", balance];
    }
    if ([balance respondsToSelector:@selector(doubleValue)]) {
        return [NSString stringWithFormat:@"Credits: %.2f", [balance doubleValue]];
    }
    NSNumber *hasCredits = [credits[@"hasCredits"] respondsToSelector:@selector(boolValue)] ? credits[@"hasCredits"] : nil;
    if (hasCredits != nil && !hasCredits.boolValue) {
        return @"Credits: none";
    }
    return nil;
}

- (NSString *)resetCreditsSummary:(id)resetCredits {
    if (![resetCredits isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSNumber *available = [self numberFromDictionary:resetCredits keys:@[@"availableCount"]];
    if (available == nil) {
        return nil;
    }
    return [NSString stringWithFormat:@"Usage resets: %ld available", (long)available.integerValue];
}

- (NSString *)monthlySummary:(NSDictionary *)monthly {
    if (monthly == nil) {
        return nil;
    }
    NSString *used = [self stringFromDictionary:monthly keys:@[@"used"]];
    NSString *limit = [self stringFromDictionary:monthly keys:@[@"limit"]];
    NSNumber *remaining = [self numberFromDictionary:monthly keys:@[@"remainingPercent"]];
    NSNumber *reset = [self numberFromDictionary:monthly keys:@[@"resetsAt"]];
    if (used.length == 0 && limit.length == 0 && remaining == nil) {
        return nil;
    }

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (used.length > 0 && limit.length > 0) {
        [parts addObject:[NSString stringWithFormat:@"%@ of %@", used, limit]];
    }
    if (remaining != nil) {
        [parts addObject:[NSString stringWithFormat:@"%ld%% left", (long)remaining.integerValue]];
    }
    if (reset != nil) {
        [parts addObject:[NSString stringWithFormat:@"resets %@", [self resetLabelForSeconds:reset includeDate:YES]]];
    }
    return [NSString stringWithFormat:@"Monthly: %@", [parts componentsJoinedByString:@", "]];
}

- (NSNumber *)numberFromDictionary:(NSDictionary *)dictionary keys:(NSArray<NSString *> *)keys {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    for (NSString *key in keys) {
        id value = dictionary[key];
        if ([value respondsToSelector:@selector(doubleValue)]) {
            return @([value doubleValue]);
        }
    }
    return nil;
}

- (NSString *)stringFromDictionary:(NSDictionary *)dictionary keys:(NSArray<NSString *> *)keys {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    for (NSString *key in keys) {
        id value = dictionary[key];
        if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
            return value;
        }
    }
    return nil;
}

- (NSString *)resetLabelForSeconds:(NSNumber *)seconds includeDate:(BOOL)includeDate {
    if (seconds == nil) {
        return @"unknown";
    }
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:seconds.doubleValue];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = includeDate ? NSDateFormatterMediumStyle : NSDateFormatterNoStyle;
    formatter.timeStyle = includeDate ? NSDateFormatterNoStyle : NSDateFormatterShortStyle;
    return [formatter stringFromDate:date];
}

- (NSString *)updatedSummaryForDate:(NSDate *)date {
    if (date == nil) {
        return @"Updated: unknown";
    }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterNoStyle;
    formatter.timeStyle = NSDateFormatterMediumStyle;
    return [NSString stringWithFormat:@"Updated: %@", [formatter stringFromDate:date]];
}

- (NSDate *)dateFromISOString:(id)value {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    NSDate *date = [formatter dateFromString:value];
    if (date != nil) {
        return date;
    }
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    return [formatter dateFromString:value];
}

- (PersistentStartup *)startup {
    return StartupController(@"com.local.autostart.codex-usage");
}

- (BOOL)launchAtLoginEnabled {
    return [NSFileManager.defaultManager fileExistsAtPath:self.startup.path] && self.startup.loaded;
}

- (NSString *)launchAtLoginStatusText {
    if ([self launchAtLoginEnabled]) return @"enabled";
    return [NSFileManager.defaultManager fileExistsAtPath:self.startup.path] ? @"inactive" : @"not_registered";
}

- (void)ensureLaunchAtLoginIfPreferred {
    NSError *error = nil;
    BOOL preferred = [NSUserDefaults.standardUserDefaults boolForKey:LaunchAtLoginPreferenceKey];
    // Retire the older installer-only login job before taking ownership.
    BOOL ok = [StartupController(@"com.local.codex-usage-menu-bar") setEnabled:NO error:&error]
        && RemoveNativeLoginItem(&error) && [self.startup setEnabled:preferred error:&error];
    self.launchAtLoginError = ok ? nil : error.localizedDescription;
}

- (void)toggleLaunchAtLogin {
    NSError *error = nil;
    // A pending/blocked registration can also be turned off.
    BOOL wasPreferred = [NSUserDefaults.standardUserDefaults boolForKey:LaunchAtLoginPreferenceKey];
    BOOL ok = RemoveNativeLoginItem(&error) && [self.startup setEnabled:!wasPreferred error:&error];
    if (ok) [NSUserDefaults.standardUserDefaults setBool:!wasPreferred forKey:LaunchAtLoginPreferenceKey];
    self.launchAtLoginError = ok ? nil : error.localizedDescription;
    self.statusItem.menu = [self menuForCurrentState];
}

- (void)quit {
    [NSApp terminate:nil];
}

@end

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;

    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--pause-startup") == 0) {
            NSError *error = nil;
            BOOL ok = [StartupController(@"com.local.autostart.codex-usage") pause:&error];
            if (!ok) fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
            return ok ? 0 : 1;
        }
        if (argc > 1 && strcmp(argv[1], "--launch-at-login-status") == 0) {
            printf("%s\n", [[AppDelegate new] launchAtLoginStatusText].UTF8String);
            return 0;
        }
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
