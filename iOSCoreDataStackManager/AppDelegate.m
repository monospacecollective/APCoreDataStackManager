//
//  AppDelegate.m
//  iOSCoreDataStackManager

#import "AppDelegate.h"
#import "MasterViewController.h"
#import "DetailViewController.h"
#import "APCoreDataStackManager.h"

#define ACTIVATETITLE @"Activate iCloud Storage"
#define DEACTIVATETITLE @"Deactivate iCloud Storage"
#define USERDEFAULTSUSEICLOUDSTORAGE @"UseICloud"

@interface AppDelegate () <APCoreDataStackManagerDelegate, UIActionSheetDelegate> {
    // Observers
    id ap_iCloudDocumentStorageAvailabilityObserver;
    
    void (^ap_persistentStoreCompletionHandler)();
    
    // Alert views
    UIAlertView * ap_ubiquitousStoreUnavailableAlertView;
    UIAlertView * ap_couldNotOpenUbiquitousStoreAlertView;
    UIAlertView * ap_noUbiquitousPersistentStoreFoundAlertView;
    
    // Action sheets
    UIActionSheet * ap_replaceExistingStoreInCloudActionSheet;
    UIActionSheet * ap_moveStoreToCloudActionSheet;
    UIActionSheet * ap_moveStoreToLocalActionSheet;
}

@property (nonatomic, strong) APCoreDataStackManager * coreDataStackManager;
@property (strong) MasterViewController * masterViewController;
@property (strong) UIBarButtonItem * iCloudButton;

// Persistent Store Management

- (void)ap_openUbiquitousStore;
- (void)ap_openLocalStore;
- (void)ap_replaceUbiquitousStoreByLocalStore;

@end

@implementation AppDelegate

// Private properties
@synthesize coreDataStackManager = ap_coreDataStackManager;
@synthesize masterViewController = ap_masterViewController;
@synthesize iCloudButton = ap_iCloudButton;

@synthesize window = ap_window;
@synthesize managedObjectContext = ap_managedObjectContext;
@synthesize navigationController = ap_navigationController;
@synthesize splitViewController = ap_splitViewController;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    UIWindow * window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    [self setWindow:window];
    
    MasterViewController * masterViewController = nil;
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        masterViewController = [[MasterViewController alloc] initWithNibName:@"MasterViewController_iPhone" bundle:nil];
        
        UINavigationController * navigationController = [[UINavigationController alloc] initWithRootViewController:masterViewController];
        [navigationController setToolbarHidden:NO];
        [self setNavigationController:navigationController];
        [window setRootViewController:navigationController];
    } else {
        masterViewController = [[MasterViewController alloc] initWithNibName:@"MasterViewController_iPad" bundle:nil];
        UINavigationController * masterNavigationController = [[UINavigationController alloc] initWithRootViewController:masterViewController];
        [masterNavigationController setToolbarHidden:NO];
        
        DetailViewController * detailViewController = [[DetailViewController alloc] initWithNibName:@"DetailViewController_iPad" bundle:nil];
        UINavigationController * detailNavigationController = [[UINavigationController alloc] initWithRootViewController:detailViewController];
        [masterViewController setDetailViewController:detailViewController];
        
        UISplitViewController * splitViewController = [[UISplitViewController alloc] init];
        [self setSplitViewController:splitViewController];
        [splitViewController setDelegate:detailViewController];
        [splitViewController setViewControllers:[NSArray arrayWithObjects:masterNavigationController, detailNavigationController, nil]];
        [window setRootViewController:splitViewController];
    }
    
    // iCloud buttons
    UIBarButtonItem * iCloudButton = [[UIBarButtonItem alloc] initWithTitle:@"Toggle iCloud"
                                                                      style:UIBarButtonItemStyleBordered
                                                                     target:self
                                                                     action:@selector(toggleICloudStorage:)];
    [self setICloudButton:iCloudButton];
    UIBarButtonItem * saveButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(saveContext)];
    UIBarItem * flexibleSpaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    [masterViewController setToolbarItems:[NSArray arrayWithObjects:iCloudButton, flexibleSpaceItem, saveButton, nil]];
    [self setMasterViewController:masterViewController];
    [window makeKeyAndVisible];
    
    NSNotificationCenter * center = [NSNotificationCenter defaultCenter];
    
    APCoreDataStackManager * coreDataStackManager = [self coreDataStackManager];
    
    [self setICloudButtonEnabled:NO];
    
    __weak id wself = self;
    
    ap_persistentStoreCompletionHandler = ^(NSManagedObjectContext * context, NSError * error){
        id sself = wself;
        if(context) {
            [sself setManagedObjectContext:context];
            MasterViewController * masterViewController = [sself masterViewController];
            [masterViewController setManagedObjectContext:context];
            [masterViewController setFetchedResultsController:nil];
            UITableView * tableView = (UITableView *)[[sself masterViewController] view];
            if([tableView isKindOfClass:[UITableView class]]) {
                [tableView reloadData];
            }
        }
        else if(error) {NSInteger errorCode = [error code];
            if(errorCode == APCoreDataStackManagerErrorDocumentStorageAvailabilityTimeOut) {
                // Attempt to open ubiquitous store failed
                if(!ap_ubiquitousStoreUnavailableAlertView) {
                    ap_ubiquitousStoreUnavailableAlertView = [[UIAlertView alloc] initWithTitle:@"iCloud is unavailable"
                                                                                        message:@"iCloud document storage availability could not be dermined in time."
                                                                                       delegate:sself
                                                                              cancelButtonTitle:@"Use local database"
                                                                              otherButtonTitles:@"Retry", nil];
                }
                [ap_ubiquitousStoreUnavailableAlertView show];
                return;
            }
            else if(errorCode == APCoreDataStackManagerErrorDocumentStorageUnavailable) {
                // Attempt to open ubiquitous store failed
                if(!ap_couldNotOpenUbiquitousStoreAlertView) {
                    NSString * deviceName = [[UIDevice currentDevice] model];
                    ap_couldNotOpenUbiquitousStoreAlertView = [[UIAlertView alloc] initWithTitle:@"You are not using iCloud"
                                                                                         message:[NSString stringWithFormat:@"Your database has been deleted from this %@ but will stay on iCloud.", deviceName]
                                                                                        delegate:sself
                                                                               cancelButtonTitle:nil
                                                                               otherButtonTitles:@"OK", nil];
                }
                [ap_couldNotOpenUbiquitousStoreAlertView show];
            }
            else if(errorCode == APCoreDataStackManagerErrorNoUbiquitousPersistentStoreFound) {
                if(!ap_noUbiquitousPersistentStoreFoundAlertView) {
                    NSString * deviceName = [[UIDevice currentDevice] model];
                    ap_noUbiquitousPersistentStoreFoundAlertView = [[UIAlertView alloc] initWithTitle:@"Database unavailable"
                                                                                              message:[NSString stringWithFormat:@"Your database has been deleted from iCloud. The app will roll back to a previous version stored on your %@.", deviceName]
                                                                                             delegate:sself
                                                                                    cancelButtonTitle:nil
                                                                                    otherButtonTitles:@"OK", nil];
                }
                [ap_noUbiquitousPersistentStoreFoundAlertView show];
            }
            else {
                NSLog(@"%@", error);
            }
        }
        
        // Set the toggle iCloud storage button's title accordingly
        BOOL isStoreCurrentlyUbiquitous = [[sself coreDataStackManager] isPersistentStoreUbiquitous];
        [sself setICloudButtonTitle:isStoreCurrentlyUbiquitous?DEACTIVATETITLE:ACTIVATETITLE];
    };
    [coreDataStackManager resetStackWithAppropriatePersistentStore:ap_persistentStoreCompletionHandler];
    
    // Observe the availability of the iCloud document storage
    ap_iCloudDocumentStorageAvailabilityObserver = [center addObserverForName:APUBIQUITOUSSTORAGEAVAILABILITYDIDCHANGENOTIFICATION
                                                                       object:nil
                                                                        queue:nil
                                                                   usingBlock:^(NSNotification *note) {
                                                                       BOOL available = [[[note userInfo] valueForKey:@"ubiquitousStorageAvailable"] boolValue];
                                                                       [self setICloudDocumentStorageAvailable:available];
                                                                       
                                                                       // Enable buttons to seed initial content and toggle iCloud storage
                                                                       [self setICloudButtonEnabled:available];
                                                                       
                                                                       // Set the toggle iCloud storage button's title accordingly
                                                                       BOOL isStoreCurrentlyUbiquitous = [[self coreDataStackManager] isPersistentStoreUbiquitous];
                                                                       [self setICloudButtonTitle:isStoreCurrentlyUbiquitous?DEACTIVATETITLE:ACTIVATETITLE];
                                                                   }];
    
    [center addObserver:self
               selector:@selector(ap_mergeChangesFrom_iCloud:)
                   name:NSPersistentStoreDidImportUbiquitousContentChangesNotification
                 object:nil];
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    APCoreDataStackManager * coreDataStackManager = [self coreDataStackManager];
    
    [coreDataStackManager checkUbiquitousStorageAvailability];
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // Saves changes in the application's managed object context before the application terminates.
    [self saveContext];
}

- (void)saveContext {
    NSError * error = nil;
    NSManagedObjectContext * managedObjectContext = [self managedObjectContext];
    if (managedObjectContext != nil) {
        if ([managedObjectContext hasChanges] && ![managedObjectContext save:&error]) {
            // Replace this implementation with code to handle the error appropriately.
            // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development. 
            NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
            abort();
        } 
    }
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if(alertView == ap_ubiquitousStoreUnavailableAlertView) {
        if(buttonIndex == 1) {
            // Use local store
            [self ap_openLocalStore];
        }
        else {
            // Retry
            [self ap_openUbiquitousStore];
        }
    }
    else if(alertView == ap_couldNotOpenUbiquitousStoreAlertView) {
        [self ap_openLocalStore];
    }
    else if(alertView == ap_noUbiquitousPersistentStoreFoundAlertView) {
        [self ap_openLocalStore];
    }
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if(actionSheet == ap_moveStoreToCloudActionSheet) {
        switch (buttonIndex) {
            case 0:
                // Move database to iCloud
                [self ap_replaceUbiquitousStoreByLocalStore];
                break;
            default:
                [[NSUserDefaults standardUserDefaults] setBool:NO forKey:USERDEFAULTSUSEICLOUDSTORAGE];
                break;
        }
    }
    else if(actionSheet == ap_replaceExistingStoreInCloudActionSheet) {
        switch (buttonIndex) {
            case 0:
                // Replace database in iCloud
                [self ap_replaceUbiquitousStoreByLocalStore];
                break;
            case 1:
                // Use existing database
                [self ap_openUbiquitousStore];
                break;
            default:
                [[NSUserDefaults standardUserDefaults] setBool:NO forKey:USERDEFAULTSUSEICLOUDSTORAGE];
                break;
        }
    }
    else if(actionSheet == ap_moveStoreToLocalActionSheet) {
        switch (buttonIndex) {
            case 0:
                // Use local database
                [self ap_openLocalStore];
                break;
            default:
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:USERDEFAULTSUSEICLOUDSTORAGE];
                break;
        }
    }
}

#pragma mark - Persistent Store Management

- (void)ap_openUbiquitousStore {
    [self setICloudButtonEnabled:NO];
    APCoreDataStackManager * coreDataStackManager = [self coreDataStackManager];
    [coreDataStackManager resetStackToBeUbiquitousWithCompletionHandler:^(NSManagedObjectContext * context, NSError * error) {
        ap_persistentStoreCompletionHandler(context, error);
        if(context) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:USERDEFAULTSUSEICLOUDSTORAGE];
            [self setICloudButtonTitle:DEACTIVATETITLE];
        }
        [self setICloudButtonEnabled:YES];
    }];
}

- (void)ap_openLocalStore {
    [self setICloudButtonEnabled:NO];
    APCoreDataStackManager * manager = [self coreDataStackManager];
    
    [manager resetStackToBeLocalWithCompletionHandler:^(NSManagedObjectContext * context, NSError * error) {
        ap_persistentStoreCompletionHandler(context, error);
        if(context) {
            [[NSUserDefaults standardUserDefaults] setBool:NO forKey:USERDEFAULTSUSEICLOUDSTORAGE];  
            [self setICloudButtonTitle:ACTIVATETITLE];
        }
        [self setICloudButtonEnabled:YES];
    }];
}

- (void)ap_replaceUbiquitousStoreByLocalStore {
    [self setICloudButtonEnabled:NO];
    APCoreDataStackManager * manager = [self coreDataStackManager];
    [manager replaceCloudStoreWithStoreAtURL:[manager localStoreURL] completionHandler:^(NSManagedObjectContext * context, NSError * error) {
        ap_persistentStoreCompletionHandler(context, error);
        if(context) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:USERDEFAULTSUSEICLOUDSTORAGE];
            [self setICloudButtonTitle:DEACTIVATETITLE];
        }
        else {
            NSLog(@"%@", error);
        }
        [self setICloudButtonEnabled:YES];
    }];
}

- (void)setICloudButtonEnabled:(BOOL)iCloudButtonEnabled {
    [[self iCloudButton] setEnabled:iCloudButtonEnabled];
}

- (void)setICloudButtonTitle:(NSString *)iCloudButtonTitle {
    [[self iCloudButton] setTitle:iCloudButtonTitle];
}

#pragma mark - Actions

- (BOOL)ap_isStoreExistingLocally {
    return [[NSFileManager defaultManager] fileExistsAtPath:[[[self coreDataStackManager] localStoreURL] path]];
}

- (BOOL)ap_isStoreExistingRemotely {
    return ([[self coreDataStackManager] ubiquitousStoreURL] != nil);
}

- (IBAction)toggleICloudStorage:(id)sender {
    APCoreDataStackManager * coreDataStackManager = [self coreDataStackManager];
    BOOL storeIsLocal = ![coreDataStackManager isPersistentStoreUbiquitous];
    BOOL existingStore = storeIsLocal?[self ap_isStoreExistingRemotely]:[self ap_isStoreExistingLocally];
    if(storeIsLocal) {
        if(existingStore) {
            // Replace existing store in the cloud?
            NSString * title = @"Would you like to replace the existing iCloud database?";
            ap_replaceExistingStoreInCloudActionSheet = [[UIActionSheet alloc] initWithTitle:title
                                                                                    delegate:self
                                                                           cancelButtonTitle:@"Cancel"
                                                                      destructiveButtonTitle:@"Replace"
                                                                           otherButtonTitles:@"Use existing database", nil];
            [ap_replaceExistingStoreInCloudActionSheet showInView:[self window]];
        }
        else {
            // Move store to the cloud?
            NSString * title = @"Would you like to store your database in iCloud?";
            ap_moveStoreToCloudActionSheet = [[UIActionSheet alloc] initWithTitle:title
                                                                         delegate:self
                                                                cancelButtonTitle:@"Cancel"
                                                           destructiveButtonTitle:nil
                                                                otherButtonTitles:@"Store in iCloud", nil];
            [ap_moveStoreToCloudActionSheet showInView:[self window]];
        }
    }
    else {
        // Stop using database in the cloud?
        NSString * title = [NSString stringWithFormat:@"The database stored in iCloud will be deleted from this %@.", [[UIDevice currentDevice] localizedModel]];
        ap_moveStoreToLocalActionSheet = [[UIActionSheet alloc] initWithTitle:title
                                                                     delegate:self
                                                            cancelButtonTitle:@"Cancel"
                                                       destructiveButtonTitle:@"Deactivate"
                                                            otherButtonTitles:nil];
        [ap_moveStoreToLocalActionSheet showInView:[self window]];
    }
}

#pragma mark
#pragma mark APCoreDataStackManagerDelegate

// Requests the delegate to refresh the stack using the local store
- (void)coreDataStackManagerRequestLocalStoreRefresh:(APCoreDataStackManager *)manager {
    [manager resetStackToBeLocalWithCompletionHandler:^(NSManagedObjectContext * context, NSError * error) {
        ap_persistentStoreCompletionHandler(context, error);
        if(context) {
            [[NSUserDefaults standardUserDefaults] setBool:NO forKey:USERDEFAULTSUSEICLOUDSTORAGE];
        }
    }];
}

// Requests the delegate to refresh the stack using the ubiquitous store
- (void)coreDataStackManagerRequestUbiquitousStoreRefresh:(APCoreDataStackManager *)manager {
    [manager resetStackToBeUbiquitousWithCompletionHandler:^(NSManagedObjectContext * context, NSError * error) {
        ap_persistentStoreCompletionHandler(context, error);
        if(context) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:USERDEFAULTSUSEICLOUDSTORAGE];
        }
    }];
}

- (BOOL)coreDataStackManagerShouldUseUbiquitousStore:(APCoreDataStackManager *)manager {
    return [[NSUserDefaults standardUserDefaults] boolForKey:USERDEFAULTSUSEICLOUDSTORAGE];
}

#pragma mark - Synthesized properties

+ (NSSet *)keyPathsForValuesAffectingICloudDocumentStorageStatus {
    return [NSSet setWithObject:@"iCloudDocumentStorageAvailable"];
}

- (NSString *)iCloudDocumentStorageStatus {
    return [self iCloudDocumentStorageAvailable]?@"iCloud Document Storage is available":@"iCloud Document Storage is not available";
}

- (APCoreDataStackManager *)coreDataStackManager {
    if(!ap_coreDataStackManager) {
        NSURL * modelURL = [[NSBundle mainBundle] URLForResource:@"iOSCoreDataStackManager" withExtension:@"momd"];
        NSString * ubiquityIdentifier = nil;
        APCoreDataStackManager * coreDataStackManager = [[APCoreDataStackManager alloc] initWithUbiquityIdentifier:ubiquityIdentifier
                                                                                           persistentStoreFileName:nil
                                                                                                          modelURL:modelURL];
        [coreDataStackManager setDelegate:self];
        [self setCoreDataStackManager:coreDataStackManager];
    }
    return ap_coreDataStackManager;
}

#pragma mark - iCloud

- (void)ap_mergeChangesFrom_iCloud:(NSNotification *)info {
    NSManagedObjectContext * context = [self managedObjectContext];
    [context performBlock:^{
        NSUndoManager * undoManager = [context undoManager];
        [undoManager disableUndoRegistration];
        [context mergeChangesFromContextDidSaveNotification:info];
        [context processPendingChanges];
        [undoManager enableUndoRegistration];
    }];
}

@end
