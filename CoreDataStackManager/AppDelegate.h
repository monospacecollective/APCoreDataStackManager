//
//  AppDelegate.h
//  CoreDataStackManager
//

#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>

// Outlets
@property (assign) IBOutlet NSWindow *window;
@property (weak) IBOutlet NSTableView *tableView;
@property (weak) IBOutlet NSArrayController *arrayController;

// Actions
- (IBAction)toggleICloudStorage:(id)sender;
- (IBAction)seedInitalContent:(id)sender;
- (IBAction)save:(id)sender;

@property (strong) NSManagedObjectContext * managedObjectContext;
@property BOOL iCloudDocumentStorageAvailable;
@property (nonatomic, readonly) NSString * iCloudDocumentStorageStatus;
@property (strong) NSString * iCloudButtonTitle;
@property BOOL iCloudButtonEnabled;

@end
