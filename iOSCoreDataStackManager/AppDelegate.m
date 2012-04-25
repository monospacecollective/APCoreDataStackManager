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

@interface AppDelegate () <APCoreDataStackManagerDelegate> {
    // Observers
    id ap_iCloudDocumentStorageAvailabilityObserver;
    
    void (^ap_persistentStoreCompletionHandler)();
}

@property (nonatomic, strong) APCoreDataStackManager * coreDataStackManager;
@property (strong) MasterViewController * masterViewController;
@property (strong) UIBarButtonItem * iCloudButton;
@property (strong) UIBarButtonItem * seedButton;

- (void)ap_resetStackToBeLocal;

@end

@implementation AppDelegate

// Private properties
@synthesize coreDataStackManager = ap_coreDataStackManager;
@synthesize masterViewController = ap_masterViewController;
@synthesize iCloudButton = ap_iCloudButton;
@synthesize seedButton = ap_seedButton;

@synthesize window = ap_window;
@synthesize managedObjectContext = ap_managedObjectContext;
@synthesize navigationController = ap_navigationController;
@synthesize splitViewController = ap_splitViewController;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // iCloud uttons
    UIBarButtonItem * iCloudButton = [[UIBarButtonItem alloc] initWithTitle:@"Toggle iCloud"
                                                                      style:UIBarButtonItemStyleBordered
                                                                     target:self
                                                                     action:@selector(toggleICloudStorage:)];
    [self setICloudButton:iCloudButton];
    UIBarButtonItem * seedButton = [[UIBarButtonItem alloc] initWithTitle:@"Seed"
                                                                    style:UIBarButtonItemStyleBordered
                                                                   target:self
                                                                   action:@selector(seedInitalContent:)];
    [self setSeedButton:seedButton];
    
    UIWindow * window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    [self setWindow:window];
    
    NSNotificationCenter * center = [NSNotificationCenter defaultCenter];
    
    APCoreDataStackManager * coreDataStackManager = [self coreDataStackManager];
    
    [self setICloudButtonEnabled:NO];
    
    __weak id wself = self;

    ap_persistentStoreCompletionHandler = ^(NSManagedObjectContext * context, NSError * error){
        id sself = wself;
        if(context) {
            [sself setManagedObjectContext:context];
            [sself setICloudButtonTitle:[coreDataStackManager isPersistentStoreUbiquitous]?DEACTIVATETITLE:ACTIVATETITLE];
            [sself setICloudButtonEnabled:YES];
            
            MasterViewController * masterViewController = nil;
            // Override point for customization after application launch.
            if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
                masterViewController = [[MasterViewController alloc] initWithNibName:@"MasterViewController_iPhone" bundle:nil];
                
                UINavigationController * navigationController = [[UINavigationController alloc] initWithRootViewController:masterViewController];
                [navigationController setToolbarHidden:NO];
                [sself setNavigationController:navigationController];
                [window setRootViewController:navigationController];
            } else {
                masterViewController = [[MasterViewController alloc] initWithNibName:@"MasterViewController_iPad" bundle:nil];
                UINavigationController * masterNavigationController = [[UINavigationController alloc] initWithRootViewController:masterViewController];
                [masterNavigationController setToolbarHidden:NO];
                
                DetailViewController * detailViewController = [[DetailViewController alloc] initWithNibName:@"DetailViewController_iPad" bundle:nil];
                UINavigationController * detailNavigationController = [[UINavigationController alloc] initWithRootViewController:detailViewController];
                [masterViewController setDetailViewController:detailViewController];
                
                UISplitViewController * splitViewController = [[UISplitViewController alloc] init];
                [sself setSplitViewController:splitViewController];
                [splitViewController setDelegate:detailViewController];
                [splitViewController setViewControllers:[NSArray arrayWithObjects:masterNavigationController, detailNavigationController, nil]];
                [window setRootViewController:splitViewController];
            }
            UIBarButtonItem * saveButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:sself action:@selector(saveContext)];
            UIBarItem * flexibleSpaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
            [masterViewController setToolbarItems:[NSArray arrayWithObjects:iCloudButton, seedButton, flexibleSpaceItem, saveButton, nil]];
            [masterViewController setManagedObjectContext:context];
            [sself setMasterViewController:masterViewController];
            [window makeKeyAndVisible];
        }
        else if(error) {
            if([[error domain] isEqualToString:CORE_DATA_STACK_MANAGER_ERROR_DOMAIN]) {
                // Handle the error appropriately. Most of the time, errors are issued because the stack cannot be set up with a ubiquitous store
                // You can fall back to using the local ubiquitous store with resetStackToBeLocalWithCompletionHandler:
                // or you can retry again if you get a APCoreDataStackManagerErrorDocumentStorageAvailabilityTimeOut error
                [sself ap_resetStackToBeLocal];
            }
        }
    };
    [coreDataStackManager resetStackWithAppropriatePersistentStore:ap_persistentStoreCompletionHandler];
    
    ap_iCloudDocumentStorageAvailabilityObserver = [center addObserverForName:APUBIQUITOUSSTORAGEAVAILABILITYDIDCHANGENOTIFICATION
                                                                       object:nil
                                                                        queue:nil
                                                                   usingBlock:^(NSNotification *note) {
                                                                       BOOL available = [[[note userInfo] valueForKey:@"ubiquitousStorageAvailable"] boolValue];
                                                                       [self setICloudDocumentStorageAvailable:available];
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

- (void)ap_resetStackToBeLocal {
    [[self coreDataStackManager] resetStackToBeLocalWithCompletionHandler:ap_persistentStoreCompletionHandler];
}

- (void)setICloudButtonEnabled:(BOOL)iCloudButtonEnabled {
    [[self iCloudButton] setEnabled:iCloudButtonEnabled];
    [[self seedButton] setEnabled:iCloudButtonEnabled];
}

- (void)setICloudButtonTitle:(NSString *)iCloudButtonTitle {
    [[self iCloudButton] setTitle:iCloudButtonTitle];
}

#pragma mark
#pragma mark Actions

- (IBAction)toggleICloudStorage:(id)sender {
    APCoreDataStackManager * coreDataStackManager = [self coreDataStackManager];
    BOOL storeIsLocal = ![coreDataStackManager isPersistentStoreUbiquitous];
    
    [self setICloudButtonEnabled:NO];
    if(storeIsLocal) {
        // If coreDataStackManager returns nil for ubiquitousStoreURL, no initial store has been seeded.
        if([coreDataStackManager ubiquitousStoreURL]) {
            // Switch to the ubiquitous persistent store
            [coreDataStackManager resetStackToBeUbiquitousWithCompletionHandler:^(NSManagedObjectContext * context, NSError * error) {
                [self setManagedObjectContext:context];
                [[self masterViewController] setManagedObjectContext:context];
                [[self masterViewController] setFetchedResultsController:nil];
                UITableView * tableView = (UITableView *)[[self masterViewController] view];
                [tableView reloadData];
                [self setICloudButtonTitle:DEACTIVATETITLE];
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:USERDEFAULTSUSEICLOUDSTORAGE];
                [self setICloudButtonEnabled:YES];
            }];
        }
        else {
            // Seed initial content for the ubiquitous persistent store
            [coreDataStackManager replaceCloudStoreWithStoreAtURL:[coreDataStackManager localStoreURL]
                                                completionHandler:^(NSManagedObjectContext * context, NSError * error) {
                                                    if(context) {
                                                        [self setManagedObjectContext:context];
                                                        [[self masterViewController] setManagedObjectContext:context];
                                                        [[self masterViewController] setFetchedResultsController:nil];
                                                        UITableView * tableView = (UITableView *)[[self masterViewController] view];
                                                        [tableView reloadData];
                                                        
                                                        [self setICloudButtonTitle:DEACTIVATETITLE];
                                                        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:USERDEFAULTSUSEICLOUDSTORAGE];
                                                        [self setICloudButtonEnabled:YES];
                                                    }
                                                    else {
                                                        NSLog(@"%@", error);
                                                    }
                                                }];
        }
    }
    else {
        [coreDataStackManager resetStackToBeLocalWithCompletionHandler:^(NSManagedObjectContext * context, NSError * error) {
            [self setManagedObjectContext:context];
            [[self masterViewController] setManagedObjectContext:context];
            [[self masterViewController] setFetchedResultsController:nil];
            UITableView * tableView = (UITableView *)[[self masterViewController] view];
            [tableView reloadData];
            [self setICloudButtonTitle:ACTIVATETITLE];
            [[NSUserDefaults standardUserDefaults] setBool:NO forKey:USERDEFAULTSUSEICLOUDSTORAGE];
            [self setICloudButtonEnabled:YES];
        }];
    }
}

- (IBAction)seedInitalContent:(id)sender {
    // Seeds the local persistent store file as the initial content for the ubiquitous persistent store
    APCoreDataStackManager * coreDataStackManager = [self coreDataStackManager];
    
    [self setICloudButtonEnabled:NO];
    [coreDataStackManager replaceCloudStoreWithStoreAtURL:[coreDataStackManager localStoreURL]
                                        completionHandler:^(NSManagedObjectContext * context, NSError * error) {
                                            [self setManagedObjectContext:context];
                                            [[self masterViewController] setManagedObjectContext:context];
                                            [[self masterViewController] setFetchedResultsController:nil];
                                            [self setICloudButtonTitle:DEACTIVATETITLE];
                                            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:USERDEFAULTSUSEICLOUDSTORAGE];
                                            [self setICloudButtonEnabled:YES];
                                        }];
}

#pragma mark
#pragma mark APCoreDataStackManagerDelegate

// Requests the delegate to refresh the stack using the local store
- (void)coreDataStackManagerRequestLocalStoreRefresh:(APCoreDataStackManager *)manager {
    [manager resetStackToBeLocalWithCompletionHandler:^(NSManagedObjectContext * context, NSError * error) {
        [self setManagedObjectContext:context];
        [[self masterViewController] setManagedObjectContext:context];
        [[self masterViewController] setFetchedResultsController:nil];
    }];
}

// Requests the delegate to refresh the stack using the ubiquitous store
- (void)coreDataStackManagerRequestUbiquitousStoreRefresh:(APCoreDataStackManager *)manager {
    [manager resetStackToBeUbiquitousWithCompletionHandler:^(NSManagedObjectContext * context, NSError * error) {
        [self setManagedObjectContext:context];
        [[self masterViewController] setManagedObjectContext:context];
        [[self masterViewController] setFetchedResultsController:nil];
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
