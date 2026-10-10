#import <Cocoa/Cocoa.h>
#import <signal.h>
#import <unistd.h>

// Style only this launched scrcpy process's Cocoa window. SDL retains full
// ownership of rendering, mouse/keyboard input, fullscreen and close behavior.
__attribute__((constructor)) static void installWindowStyle(void) {
    @autoreleasepool {
        [NSProcessInfo processInfo].processName = @"That Mirroring";
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserverForName:NSWindowDidBecomeKeyNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            NSWindow *window = note.object;
            if (![window isKindOfClass:NSWindow.class] || ![window.title hasPrefix:@"That Mirroring"]) return;
            window.titleVisibility = NSWindowTitleHidden;
            window.titlebarAppearsTransparent = YES;
            window.styleMask |= NSWindowStyleMaskFullSizeContentView;
            window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
            window.backgroundColor = NSColor.blackColor;
            window.collectionBehavior |= NSWindowCollectionBehaviorFullScreenPrimary;
            NSString *icons = NSProcessInfo.processInfo.environment[@"SCRCPY_ICON_PATH"];
            if (icons) NSApp.applicationIconImage = [[NSImage alloc] initWithContentsOfFile:[icons stringByAppendingPathComponent:@"scrcpy.png"]];
        }];
        // If the host crashes or is force-quit, leave no orphan mirror window.
        pid_t parent = (pid_t)[NSProcessInfo.processInfo.environment[@"THATMIRRORING_PARENT_PID"] intValue];
        if (parent > 1) {
            dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
            dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, NSEC_PER_SEC / 10);
            dispatch_source_set_event_handler(timer, ^{
                if (getppid() != parent) {
                    dispatch_source_cancel(timer);
                    raise(SIGTERM);
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ _exit(0); });
                }
            });
            dispatch_resume(timer);
        }
    }
}
