//
//  APCoreDataStackManager.h
//  APCoreDataStackManager
//
//  Created by Axel Péju on 14/11/11.
//  Copyright (c) 2011 Axel Péju.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@protocol APCoreDataStackManagerDelegate;

@interface APCoreDataStackManager : NSObject

// Root managed object context
@property (nonatomic, readonly, strong) NSManagedObjectContext * rootManagedObjectContext;

// Persistent store state
@property (nonatomic, readonly, getter = isPersistentStoreUbiquitous) BOOL persistentStoreUbiquitous;

// Delegate
@property (assign) id <APCoreDataStackManagerDelegate> delegate;

// ---------------------------
// Initialization
// ---------------------------

- (id)initWithUbiquityIdentifier:(NSString *)ubiquityIdentifier persistentStoreFileName:(NSString *)storeFileName modelURL:(NSURL *)modelURL;

// ---------------------------
// iCloud availabilty
// ---------------------------

- (void)checkUbiquitousStorageAvailability;

// ---------------------------
// Persistent store management
// ---------------------------

// Resets the Core Data stack and sets it up with a local or ubiquitous persistent store depending on the delegate's result for coreDataStackManagerShouldUseUbiquitousStore:
- (void)resetStackWithAppropriatePersistentStore:(void(^)(NSManagedObjectContext *, NSError *))completionHandler;

// Switches to the local persitent store. If the current store is local, this does nothing.
// If there is no local store file, a new store is created.
- (void)resetStackToBeLocalWithCompletionHandler:(void (^)(NSManagedObjectContext *, NSError *))completionHandler;

// Resets the Core Data stack and sets it up to be ubiquitous.
// If there is no existing ubiquitous persistent store, this method does nothing.
- (void)resetStackToBeUbiquitousWithCompletionHandler:(void (^)(NSManagedObjectContext *, NSError *))completionHandler;

// Resets the Core Data stack and uses the persistent store.
- (void)replaceLocalPersistentStoreWithStoreAtURL:(NSURL *)originStoreURL completionHandler:(void(^)(NSManagedObjectContext *, NSError *))completionHandler;

// Resets the Core Data stack and seeds the store at originStoreURL as initial content
- (void)replaceCloudStoreWithStoreAtURL:(NSURL *)originStoreURL completionHandler:(void (^)(NSManagedObjectContext *, NSError *))completionHandler;


// ----------------------
// Persistent stores URLs
// ----------------------

// Returns the URL of the currently used persistent store. Returns nil if no store is currently used (during a Core Data Stack reset).
- (NSURL *)currentStoreURL;

// Returns the URL of the ubiquitous persistent store. This will return a valid URL if the ubiquitous storage is enabled, and a store has already been seeded.
- (NSURL *)ubiquitousStoreURL;

// Returns the local store URL.
- (NSURL *)localStoreURL;

// Persistent store data
- (NSData *)persistentStoreData;

// URLs of remaining persistent stores the local ubiquitous container
- (NSArray *)remainingPersistentStoresURLs;

@end

@protocol APCoreDataStackManagerDelegate <NSObject>

@required

// Requests the delegate to refresh the stack using the local store
- (void)coreDataStackManagerRequestLocalStoreRefresh:(APCoreDataStackManager *)manager;

// Requests the delegate to refresh the stack using the ubiquitous store
- (void)coreDataStackManagerRequestUbiquitousStoreRefresh:(APCoreDataStackManager *)manager;

@optional

// Request the delegate to handle the migration
- (void)coreDataStackManager:(APCoreDataStackManager *)manager
migrateStoreAtURL:(NSURL *)storeURL
withDestinationManagedObjectModel:(NSManagedObjectModel *)model
completionHandler:(void (^)(BOOL, NSError *))completionHandler;

- (BOOL)coreDataStackManagerShouldUseUbiquitousStore:(APCoreDataStackManager *)manager;
- (void)coreDataStackManagerWillAddUbiquitousStore:(APCoreDataStackManager *)manager;
- (void)coreDataStackManagerDidAddUbiquitousStore:(APCoreDataStackManager *)manager;
- (void)coreDataStackManagerWillAddLocalStore:(APCoreDataStackManager *)manager;
- (void)coreDataStackManagerDidAddLocalStore:(APCoreDataStackManager *)manager;
- (void)coreDataStackManagerWillReplaceUbiquitousStore:(APCoreDataStackManager *)manager;
- (void)coreDataStackManagerDidReplaceUbiquitousStore:(APCoreDataStackManager *)manager;

// URL of the application's documents director
- (NSURL *)coreDataStackManagerApplicationDocumentsDirectory:(APCoreDataStackManager *)manager;

@end

// Errors

#define CORE_DATA_STACK_MANAGER_ERROR_DOMAIN	@"APCoreDataStackManagerErrorDomain"

enum
{
    APCoreDataStackManagerErrorUnknown =                            -1,
    APCoreDataStackManagerErrorDocumentStorageUnavailable =         100,
    APCoreDataStackManagerErrorDocumentStorageAvailabilityTimeOut = 101,
    APCoreDataStackManagerErrorNoUbiquitousPersistentStoreFound =   102,
    APCoreDataStackManagerErrorLocalStoreURLUnavailable =           200,
    APCoreDataStackManagerErrorFileFoundAtApplicationDirectoryURL = 300,
};

// Notifications

#define APPERSISTENTSTOREDIDCHANGENOTIFICATION	@"APPersistentStoreDidChangeNotification"
#define APUBIQUITOUSSTORAGEAVAILABILITYDIDCHANGENOTIFICATION @"APUbiquitousStorageAvailablityDidChangeNotification"
