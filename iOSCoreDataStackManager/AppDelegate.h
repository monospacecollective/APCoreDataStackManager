//
//  AppDelegate.h
//  iOSCoreDataStackManager

#import <UIKit/UIKit.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

@property (strong) NSManagedObjectContext * managedObjectContext;

- (void)saveContext;
- (IBAction)toggleICloudStorage:(id)sender;

@property (strong, nonatomic) UINavigationController *navigationController;

@property (strong, nonatomic) UISplitViewController *splitViewController;

@property BOOL iCloudDocumentStorageAvailable;
@property (nonatomic, readonly) NSString * iCloudDocumentStorageStatus;
@property (nonatomic, strong) NSString * iCloudButtonTitle;
@property (nonatomic) BOOL iCloudButtonEnabled;

@end
