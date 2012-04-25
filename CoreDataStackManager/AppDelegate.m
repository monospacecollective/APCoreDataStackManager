//
//  AppDelegate.m
//  CoreDataStackManager
//

#import "AppDelegate.h"
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

- (void)ap_resetStackToBeLocal;

@end

@implementation AppDelegate

@synthesize managedObjectContext = ap_managedObjectContext;
@synthesize iCloudDocumentStorageAvailable = ap_iCloudDocumentStorageAvailable;
@synthesize iCloudButtonTitle = ap_iCloudButtonTitle;
@synthesize iCloudButtonEnabled = ap_iCloudButtonEnabled;

// Outlets
@synthesize window = ap_window;
@synthesize tableView;
@synthesize arrayController;

// Private properties
@synthesize coreDataStackManager = ap_coreDataStackManager;

- (void)applicationDidBecomeActive:(NSNotification *)aNotification {
    APCoreDataStackManager * coreDataStackManager = [self coreDataStackManager];
    
    [coreDataStackManager checkUbiquitousStorageAvailability];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    NSNotificationCenter * center = [NSNotificationCenter defaultCenter];
    
    APCoreDataStackManager * coreDataStackManager = [self coreDataStackManager];
    
    [self setICloudButtonEnabled:NO];
    
    __weak id wself = self;
    __weak NSArrayController * warrayController = arrayController;
    ap_persistentStoreCompletionHandler = ^(NSManagedObjectContext * context, NSError * error){
        id sself = wself;
        NSArrayController * sarrayController = warrayController;
        if(context) {
            [sself setManagedObjectContext:context];
            [sarrayController fetch:sself];
            [sself setICloudButtonTitle:[coreDataStackManager isPersistentStoreUbiquitous]?DEACTIVATETITLE:ACTIVATETITLE];
            [sself setICloudButtonEnabled:YES];
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
}

- (void)ap_resetStackToBeLocal {
    [[self coreDataStackManager] resetStackToBeLocalWithCompletionHandler:ap_persistentStoreCompletionHandler];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    // Save changes in the application's managed object context before the application terminates.
    
    __block NSApplicationTerminateReply reply = NSTerminateNow;
    
    NSManagedObjectContext * context = [self managedObjectContext];
    
    [context performBlockAndWait:^{
        if (![context commitEditing]) {
            NSLog(@"%@:%@ unable to commit editing to terminate", [self class], NSStringFromSelector(_cmd));
            reply = NSTerminateCancel;
        }
        
        if (![context hasChanges]) {
            reply = NSTerminateNow;
        }
        
        NSError *error = nil;
        if (![context save:&error]) {
            // Customize this code block to include application-specific recovery steps.              
            BOOL result = [sender presentError:error];
            if (result) {
                reply = NSTerminateCancel;
            }
            
            NSString *question = NSLocalizedString(@"Could not save changes while quitting. Quit anyway?", @"Quit without saves error question message");
            NSString *info = NSLocalizedString(@"Quitting now will lose any changes you have made since the last successful save", @"Quit without saves error question info");
            NSString *quitButton = NSLocalizedString(@"Quit anyway", @"Quit anyway button title");
            NSString *cancelButton = NSLocalizedString(@"Cancel", @"Cancel button title");
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:question];
            [alert setInformativeText:info];
            [alert addButtonWithTitle:quitButton];
            [alert addButtonWithTitle:cancelButton];
            
            NSInteger answer = [alert runModal];
            
            if (answer == NSAlertAlternateReturn) {
                reply = NSTerminateCancel;
            }
        }
    }];
    return reply;
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
                [arrayController fetch:self];
                [self setICloudButtonTitle:DEACTIVATETITLE];
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:USERDEFAULTSUSEICLOUDSTORAGE];
                [self setICloudButtonEnabled:YES];
            }];
        }
        else {
            // Seed initial content for the ubiquitous persistent store
            [coreDataStackManager replaceCloudStoreWithStoreAtURL:[coreDataStackManager localStoreURL]
                                                completionHandler:^(NSManagedObjectContext * context, NSError * error) {
                                                    [self setManagedObjectContext:context];
                                                    [arrayController fetch:self];
                                                    [self setICloudButtonTitle:DEACTIVATETITLE];
                                                    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:USERDEFAULTSUSEICLOUDSTORAGE];
                                                    [self setICloudButtonEnabled:YES];
                                                }];
        }
    }
    else {
        [coreDataStackManager resetStackToBeLocalWithCompletionHandler:^(NSManagedObjectContext * context, NSError * error) {
            [self setManagedObjectContext:context];
            [arrayController fetch:self];
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
                                            [arrayController fetch:self];
                                            [self setICloudButtonTitle:DEACTIVATETITLE];
                                            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:USERDEFAULTSUSEICLOUDSTORAGE];
                                            [self setICloudButtonEnabled:YES];
                                        }];
}

- (IBAction)save:(id)sender {
    NSManagedObjectContext * context = [self managedObjectContext];
    [context performBlock:^{
        [context save:nil];
    }];
}

#pragma mark
#pragma mark APCoreDataStackManagerDelegate

// Requests the delegate to refresh the stack using the local store
- (void)coreDataStackManagerRequestLocalStoreRefresh:(APCoreDataStackManager *)manager {
    [manager resetStackToBeLocalWithCompletionHandler:^(NSManagedObjectContext * context, NSError * error) {
        [self setManagedObjectContext:context];
        [arrayController fetch:self];
    }];
}

// Requests the delegate to refresh the stack using the ubiquitous store
- (void)coreDataStackManagerRequestUbiquitousStoreRefresh:(APCoreDataStackManager *)manager {
    [manager resetStackToBeUbiquitousWithCompletionHandler:^(NSManagedObjectContext * context, NSError * error) {
        [self setManagedObjectContext:context];
        [arrayController fetch:self];
    }];
}

- (BOOL)coreDataStackManagerShouldUseUbiquitousStore:(APCoreDataStackManager *)manager {
    return [[NSUserDefaults standardUserDefaults] boolForKey:USERDEFAULTSUSEICLOUDSTORAGE];
}

#pragma mark
#pragma mark Synthesized properties

+ (NSSet *)keyPathsForValuesAffectingICloudDocumentStorageStatus {
    return [NSSet setWithObject:@"iCloudDocumentStorageAvailable"];
}

- (NSString *)iCloudDocumentStorageStatus {
    return [self iCloudDocumentStorageAvailable]?@"iCloud Document Storage is available":@"iCloud Document Storage is not available";
}

- (APCoreDataStackManager *)coreDataStackManager {
    if(!ap_coreDataStackManager) {
        NSURL * modelURL = [[NSBundle mainBundle] URLForResource:@"CoreDataStackManager" withExtension:@"momd"];
        NSString * ubiquityIdentifier = nil;
        APCoreDataStackManager * coreDataStackManager = [[APCoreDataStackManager alloc] initWithUbiquityIdentifier:ubiquityIdentifier
                                                                                           persistentStoreFileName:nil
                                                                                                          modelURL:modelURL];
        [coreDataStackManager setDelegate:self];
        [self setCoreDataStackManager:coreDataStackManager];
    }
    return ap_coreDataStackManager;
}

#pragma mark
#pragma mark iCloud

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
