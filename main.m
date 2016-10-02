#import <Cocoa/Cocoa.h>

#import "JenkinsNotifierAppDelegate.h"

static JenkinsNotifierAppDelegate *delegate;

int main(int argc, char *argv[])
{
    delegate = [[JenkinsNotifierAppDelegate alloc] init];
    [NSApplication sharedApplication].delegate = delegate;
    return NSApplicationMain(argc,  (const char **) argv);
}
