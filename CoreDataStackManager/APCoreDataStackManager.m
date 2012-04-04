//
//  APCoreDataStackManager.m
//  APCoreDataStackManager
//
//  Created by Axel Péju on 14/11/11.
//  Copyright (c) 2011 Axel Péju.
//

#import "APCoreDataStackManager.h"

#define UBIQUITYCONFIGURATIONFILENAME @"Configuration.plist"
#define UBIQUITYCONFIGURATIONCONTENTNAMEKEY @"storeUbiquitousContentName"

@interface APCoreDataStackManager () <NSFilePresenter> {
@private
    NSString                      * ap_ubiquityIdentifier;
    NSString                      * ap_storeName;
    NSURL                         * ap_modelURL;
    
    id                            ap_managedObjectContextObjectsDidChangeObserver;
    
    dispatch_queue_t              ap_persistentStoreQueue;
    dispatch_queue_t              ap_ubiquitousStorageCheckQueue;
    
    // Ubiquity container URL
    NSURL                         * ap_ubiquityContainerURL;
    
    // Content name of the store currently added
    NSString                      * ap_currentStoreUbiquitousContentName;
    
    // Content names    
    // Configuration file presenter
    NSOperationQueue              * ap_filePresenterQueue;
    NSURL                         * ap_filePresenterURL;
}

// Core Data stack
@property (nonatomic, strong) NSManagedObjectModel          * managedObjectModel;
@property (nonatomic, strong) NSPersistentStoreCoordinator  * persistentStoreCoordinator;
@property (nonatomic, strong) NSManagedObjectContext        * rootManagedObjectContext;

// Ubiquitous content name
@property (nonatomic, strong) NSString * ubiquitousContentName;

// Persistent store URLs
@property (strong) NSURL * ubiquitousPersistentStoreURL; // If Document storage is active, this contains the URL of the local copy of the persistent store file
@property (strong) NSURL * currentPersistentStoreURL; // Contains the URL of the current persistent store

- (void)ap_checkUbiquitousDocumentStorageAvailabilityWithTimeOutDelay:(NSTimeInterval)delay completionHandler:(void (^)(BOOL, BOOL, NSURL *, NSURL *, NSString *))completionHandler;

// Database URL
- (NSURL *)ap_ubiquitousStoreURLWithContentName:(NSString *)contentName;

// Ubiquitous content name
- (BOOL)ap_readContentNameFromUbiquityContainerURL:(NSURL *)containerURL intoString:(NSString **)string;
- (BOOL)ap_readContentNameFromCloudIntoString:(NSString **)string;
- (NSString *)ap_newStoreUbiquitousContentName;
- (void)ap_configureCloudForStoreUbiquitousContentName:(NSString *)contentName;

// Persistent store management
- (NSPersistentStore *)ap_addUbiquitousPersistentStoreWithError:(NSError **)error;
- (NSPersistentStore *)ap_addLocalPersistentStoreWithError:(NSError **)error;

// Migration
- (BOOL)ap_migrationNeededForStoreAtURL:(NSURL *)storeURL error:(NSError **)error;
- (void)ap_migrateStoreAtURL:(NSURL *)storeURL completionHandler:(void (^)(BOOL, NSError *))completionHandler;

// Core Data stack
- (void)ap_resetCoreDataStack;

// Application's data directory
- (NSURL *)ap_applicationDocumentsDirectory;
- (void)ap_createUbiquitousDirectoryIfNeeded;
- (BOOL)ap_createApplicationDirectoryIfNeededWithError:(NSError **)error;
- (BOOL)ap_deleteCloudDataWithError:(NSError **)error;

@end

@implementation APCoreDataStackManager

// Core Data stack
@synthesize managedObjectModel = ap_managedObjectModel;
@synthesize persistentStoreCoordinator = ap_persistentStoreCoordinator;
@synthesize rootManagedObjectContext = ap_rootManagedObjectContext;

// Delegate
@synthesize delegate;

@synthesize ubiquitousContentName = ap_ubiquitousContentName;

// Persistent store URLs
@synthesize ubiquitousPersistentStoreURL = ap_ubiquitousPersistentStoreURL;
@synthesize currentPersistentStoreURL = ap_currentPersistentStoreURL;

- (id)initWithUbiquityIdentifier:(NSString *)ubiquityIdentifier persistentStoreFileName:(NSString *)storeFileName modelURL:(NSURL *)modelURL {
    self = [super init];
    if (self) {
        ap_ubiquityIdentifier = ubiquityIdentifier;
        if(!storeFileName || [storeFileName length] == 0) {
            storeFileName = @"Database.sqlite";
        }
        ap_storeName = storeFileName;
        ap_modelURL = modelURL;
        NSString * persistentStoreQueueIdentifier = [[[NSBundle mainBundle] bundleIdentifier] stringByAppendingString:@".persistentStoreQueue"];
        ap_persistentStoreQueue = dispatch_queue_create([persistentStoreQueueIdentifier UTF8String], DISPATCH_QUEUE_SERIAL);
        ap_ubiquitousStorageCheckQueue = dispatch_queue_create("ubiquitousStorageCheckQueue", DISPATCH_QUEUE_SERIAL);
        
        // File coordination
        ap_filePresenterQueue = [[NSOperationQueue alloc] init];
    }
    return self;
}

- (void)dealloc {
    if([[NSFileCoordinator filePresenters] containsObject:self]) {
        [NSFileCoordinator removeFilePresenter:self];
    }
    dispatch_release(ap_persistentStoreQueue);
}

- (void)ap_checkUbiquitousDocumentStorageAvailabilityWithTimeOutDelay:(NSTimeInterval)delay completionHandler:(void (^)(BOOL, BOOL, NSURL *, NSURL *, NSString *))completionHandler {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        __block BOOL ubiquitousDocumentStorageAvailable = NO;
        __block NSURL * ubiquityContainerURL = nil;
        __block NSString * ubiquitousContentName = nil;
        
        dispatch_group_t group = dispatch_group_create();
        dispatch_group_async(group, ap_ubiquitousStorageCheckQueue, ^{
            // Get ubiquity container URL
            NSFileManager   * fileManager = [NSFileManager defaultManager]; 
            ubiquityContainerURL = [fileManager URLForUbiquityContainerIdentifier:ap_ubiquityIdentifier];
            ap_ubiquityContainerURL = ubiquityContainerURL;
            
            NSURL * ubiquitousPersistentStoreURL = nil;
            if(ubiquityContainerURL) {
                // Try to get the content name
                ubiquitousDocumentStorageAvailable = [self ap_readContentNameFromUbiquityContainerURL:ubiquityContainerURL intoString:&ubiquitousContentName];
                if(ubiquitousDocumentStorageAvailable) {
                    ubiquitousPersistentStoreURL = [self ap_ubiquitousStoreURLWithContentName:ubiquitousContentName];
                }
            }
            
            ap_ubiquitousPersistentStoreURL = ubiquitousPersistentStoreURL;
        });
        
        BOOL timeOut = NO;
        if(dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC*delay)) != 0) {
            timeOut = YES;
        }
        if(completionHandler) {
            completionHandler(timeOut, ubiquitousDocumentStorageAvailable, ubiquityContainerURL, ap_ubiquitousPersistentStoreURL, ubiquitousContentName);
        }
    });
}

- (void)checkUbiquitousStorageAvailability {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSFileManager   * fileManager = [NSFileManager defaultManager];
        __block NSURL * ubiquityContainerURL = nil;
        dispatch_sync(ap_ubiquitousStorageCheckQueue, ^{
            ubiquityContainerURL = [fileManager URLForUbiquityContainerIdentifier:ap_ubiquityIdentifier]; 
        });
        ap_ubiquityContainerURL = ubiquityContainerURL;
        
        BOOL available = (ap_ubiquityContainerURL != nil);
        NSString * ubiquitousContentName = nil;
        if(available) {
            // Check if we can read the configuration file
            available = [self ap_readContentNameFromUbiquityContainerURL:ap_ubiquityContainerURL intoString:&ubiquitousContentName];
        }

        ap_ubiquitousPersistentStoreURL = available?[self ap_ubiquitousStoreURLWithContentName:ubiquitousContentName]:nil;
        
        // Notify that we have determined if the ubiquitous storage was available
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:APUBIQUITOUSSTORAGEAVAILABILITYDIDCHANGENOTIFICATION
                                                                object:self
                                                              userInfo:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:available] forKey:@"ubiquitousStorageAvailable"]]; 
        });
    });
}

#pragma mark
#pragma mark Persistent store state

+ (NSSet *)keyPathsForValuesAffectingPersistentStoreUbiquitous {
    return [NSSet setWithObjects:@"ubiquitousPersistentStoreURL", @"currentPersistentStoreURL", nil];
}

- (BOOL)isPersistentStoreUbiquitous {
    return [[self ubiquitousStoreURL] isEqual:[self currentStoreURL]];
}

#pragma mark
#pragma mark Persistent stores URLs

- (NSURL *)currentStoreURL {
    return ap_currentPersistentStoreURL;
}

- (NSURL *)ubiquitousStoreURL {
    return ap_ubiquitousPersistentStoreURL;
}

- (NSURL *)localStoreURL {
    return [[self ap_applicationDocumentsDirectory] URLByAppendingPathComponent:ap_storeName];
}

- (NSURL *)ap_ubiquitousStoreURLWithContentName:(NSString *)contentName {
    if(!ap_ubiquityContainerURL || !contentName) {
        return nil;
    }
    
    NSURL    * persistentStoreContentURL = [ap_ubiquityContainerURL URLByAppendingPathComponent:@"Documents/LocalData.nosync" isDirectory:YES];
    NSString * storeFileName = [contentName stringByAppendingPathExtension:[ap_storeName pathExtension]];
    return [persistentStoreContentURL URLByAppendingPathComponent:storeFileName];
}

#pragma mark
#pragma mark Ubiquitous content name

- (BOOL)ap_readContentNameFromUbiquityContainerURL:(NSURL *)containerURL intoString:(NSString **)string {
    if(!containerURL) {
        return NO;
    }
    
    // Perform a coordinated reading of the configuration file
    NSFileCoordinator   * fileCoordinator = [[NSFileCoordinator alloc] initWithFilePresenter:self];
    
    __block NSString    * contentName = nil;
    NSURL               * ubiquityConfigurationURL = [containerURL URLByAppendingPathComponent:UBIQUITYCONFIGURATIONFILENAME];
    NSError             * outError = nil;
    [fileCoordinator coordinateReadingItemAtURL:ubiquityConfigurationURL
                                        options:0
                                          error:&outError
                                     byAccessor:^(NSURL *newURL) {
                                         NSData * ubiquityConfigurationData = [NSData dataWithContentsOfURL:ubiquityConfigurationURL];
                                         if(ubiquityConfigurationData) {
                                             NSDictionary * dictionary = [NSPropertyListSerialization propertyListWithData:ubiquityConfigurationData
                                                                                                                   options:NSPropertyListImmutable
                                                                                                                    format:NULL
                                                                                                                     error:nil];
                                             contentName = [dictionary valueForKey:UBIQUITYCONFIGURATIONCONTENTNAMEKEY];
                                         }
                                         
                                         ap_filePresenterURL = newURL;
                                     }];
    if(string) {
        * string = contentName;
    }
    
    // Observe Configuration.plist file
    if(ap_filePresenterURL) {
        [NSFileCoordinator addFilePresenter:self];
    }
    else {
        [NSFileCoordinator removeFilePresenter:self];        
    }
    
    return !outError;
}

- (BOOL)ap_readContentNameFromCloudIntoString:(NSString **)string {
    if(!ap_ubiquityContainerURL) {
        return NO;
    }
    
    // Perform a coordinated reading of the configuration file
    NSFileCoordinator   * fileCoordinator = [[NSFileCoordinator alloc] initWithFilePresenter:self];
    
    __block NSString    * contentName = nil;
    NSURL               * ubiquityConfigurationURL = [ap_ubiquityContainerURL URLByAppendingPathComponent:UBIQUITYCONFIGURATIONFILENAME];
    NSError             * outError = nil;
    [fileCoordinator coordinateReadingItemAtURL:ubiquityConfigurationURL
                                        options:0
                                          error:&outError
                                     byAccessor:^(NSURL *newURL) {
                                         NSData * ubiquityConfigurationData = [NSData dataWithContentsOfURL:ubiquityConfigurationURL];
                                         if(ubiquityConfigurationData) {
                                             NSDictionary * dictionary = [NSPropertyListSerialization propertyListWithData:ubiquityConfigurationData
                                                                                                                   options:NSPropertyListImmutable
                                                                                                                    format:NULL
                                                                                                                     error:nil];
                                             contentName = [dictionary valueForKey:UBIQUITYCONFIGURATIONCONTENTNAMEKEY];
                                         }
                                         
                                         ap_filePresenterURL = newURL;
                                     }];
    * string = contentName;
    
    // Observe Configuration.plist file
    if(ap_filePresenterURL) {
        [NSFileCoordinator addFilePresenter:self];
    }
    else {
        [NSFileCoordinator removeFilePresenter:self];        
    }

    return !outError;
}

- (NSString *)ap_newStoreUbiquitousContentName {
    CFUUIDRef uuidRef = CFUUIDCreate(kCFAllocatorDefault);
    CFStringRef uuidStringRef = CFUUIDCreateString(kCFAllocatorDefault, uuidRef);
    CFRelease(uuidRef);
    NSString * contentName = (__bridge NSString *)uuidStringRef;
    return contentName;
}

- (void)ap_configureCloudForStoreUbiquitousContentName:(NSString *)contentName {
    if(!ap_ubiquityContainerURL) {
        return;
    }
    
    // Perform a coordinated write on the configuration file
    NSFileCoordinator * fileCoordinator = [[NSFileCoordinator alloc] initWithFilePresenter:self];    
    
    NSURL           * ubiquityConfigurationURL = [ap_ubiquityContainerURL URLByAppendingPathComponent:UBIQUITYCONFIGURATIONFILENAME];
    
    // Write it to the configuration file
    NSDictionary * dictionary = [NSDictionary dictionaryWithObject:contentName forKey:UBIQUITYCONFIGURATIONCONTENTNAMEKEY];
    NSData * ubiquityConfigurationData = [NSPropertyListSerialization dataWithPropertyList:dictionary
                                                                                    format:NSPropertyListXMLFormat_v1_0
                                                                                   options:0
                                                                                     error:nil];
    
    [fileCoordinator coordinateWritingItemAtURL:ubiquityConfigurationURL
                                        options:0
                                          error:nil
                                     byAccessor:^(NSURL *newURL) {
                                         [ubiquityConfigurationData writeToURL:newURL atomically:YES];
                                     }];
}

#pragma mark
#pragma mark Persistent store management

- (void)resetStackWithAppropriatePersistentStore:(void (^)(NSManagedObjectContext *, NSError *))completionHandler {
    // Reset the stack
    [self ap_resetCoreDataStack];
    
    // Check if we should attempt to use a ubiquitous persistent store
    BOOL useUbiquitousStore = NO;
    if(delegate && [delegate respondsToSelector:@selector(coreDataStackManagerShouldUseUbiquitousStore:)]) {
        useUbiquitousStore = [delegate coreDataStackManagerShouldUseUbiquitousStore:self];
    }
    
    if(useUbiquitousStore) {
        [self resetStackToBeUbiquitousWithCompletionHandler:completionHandler];
    }
    else {
        [self resetStackToBeLocalWithCompletionHandler:completionHandler];
    }
}

// Adds the ubiquitous store only if it exists
- (NSPersistentStore *)ap_addUbiquitousPersistentStoreWithError:(NSError **)error {
    NSString * storeUbiquitousContentName = [self ubiquitousContentName];
    if(!storeUbiquitousContentName) {
        return nil;
    }
    
    NSError * pscError = nil;
    NSPersistentStoreCoordinator * persistentStoreCoordinator = [self persistentStoreCoordinator];
    
    // Inform the delegate that a ubiquitous store will be added
    if(delegate && [delegate respondsToSelector:@selector(coreDataStackManagerWillAddUbiquitousStore:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate coreDataStackManagerWillAddUbiquitousStore:self];
        });
    }
    
    [self ap_createUbiquitousDirectoryIfNeeded];
    
    // Set up the ubiquitous options
    NSURL * ubiquitousContentURL = [ap_ubiquityContainerURL URLByAppendingPathComponent:@"UbiquitousContent"];
    
    NSDictionary * options = [NSDictionary dictionaryWithObjectsAndKeys:
                              storeUbiquitousContentName, NSPersistentStoreUbiquitousContentNameKey,
                              ubiquitousContentURL, NSPersistentStoreUbiquitousContentURLKey,
                              [NSNumber numberWithBool:YES], NSMigratePersistentStoresAutomaticallyOption,
                              [NSNumber numberWithBool:YES], NSInferMappingModelAutomaticallyOption,
                              nil];
    
    NSURL * storeURL = [self ap_ubiquitousStoreURLWithContentName:storeUbiquitousContentName];

    [persistentStoreCoordinator lock];
    NSPersistentStore * store = [persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType
                                                                         configuration:nil
                                                                                   URL:storeURL
                                                                               options:options
                                                                                 error:&pscError];
    [persistentStoreCoordinator unlock];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        ap_currentStoreUbiquitousContentName = storeUbiquitousContentName;
        [self setCurrentPersistentStoreURL:storeURL];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:APPERSISTENTSTOREDIDCHANGENOTIFICATION
                                                            object:nil
                                                          userInfo:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:@"PersistentStoreIsUbiquitous"]];
        
        if(delegate && [delegate respondsToSelector:@selector(coreDataStackManagerDidAddUbiquitousStore:)]) {
            [delegate coreDataStackManagerDidAddUbiquitousStore:self];
        }
    });
    * error = pscError;
    return store;
}

- (NSPersistentStore *)ap_addLocalPersistentStoreWithError:(NSError **)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if(delegate && [delegate respondsToSelector:@selector(coreDataStackManagerWillAddLocalStore:)]) {
            [delegate coreDataStackManagerWillAddLocalStore:self];
        }
    });
    NSError * pscError = nil;
    
    [self ap_createApplicationDirectoryIfNeededWithError:&pscError];
    
    NSURL * localStoreURL = [self localStoreURL];
    NSPersistentStoreCoordinator * persistentStoreCoordinator = [self persistentStoreCoordinator];
    
    NSDictionary * options = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithBool:YES], NSMigratePersistentStoresAutomaticallyOption,
                              [NSNumber numberWithBool:YES], NSInferMappingModelAutomaticallyOption,
                              nil];
    
    NSPersistentStore * store = [persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType
                                                                         configuration:nil
                                                                                   URL:localStoreURL
                                                                               options:options
                                                                                 error:&pscError];
    ap_currentStoreUbiquitousContentName = nil;
    [self setCurrentPersistentStoreURL:localStoreURL];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:APPERSISTENTSTOREDIDCHANGENOTIFICATION
                                                            object:nil
                                                          userInfo:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:NO] forKey:@"PersistentStoreIsUbiquitous"]];
        
        if(delegate && [delegate respondsToSelector:@selector(coreDataStackManagerDidAddLocalStore:)]) {
            [delegate coreDataStackManagerDidAddLocalStore:self];
        }
    });
    * error = pscError;
    return store;
}


- (void)resetStackToBeLocalWithCompletionHandler:(void (^)(NSManagedObjectContext *, NSError *))completionHandler {
    dispatch_async(ap_persistentStoreQueue, ^{
        // Block the queue until we are finished
        dispatch_suspend(ap_persistentStoreQueue);
        
        [self ap_resetCoreDataStack];
        
        // Reset the stack to be local
        void(^addLocalPersistentStoreBlock)() = ^(){
            NSError * error = nil;
            NSPersistentStore * store = [self ap_addLocalPersistentStoreWithError:&error];
            
            // Send the completion handler at the end of the run loop
            if(completionHandler) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completionHandler(store?[self rootManagedObjectContext]:nil, error);
                    });
                });
            }
            // Resume the queue for pending persistent store operations
            dispatch_resume(ap_persistentStoreQueue);
        };
        
        // Check if migration is needed
        NSError * error = nil;
        NSURL * storeUrl = [self localStoreURL];
        if([self ap_migrationNeededForStoreAtURL:storeUrl error:&error]) {
            // Migration needed, perform it
            [self ap_migrateStoreAtURL:storeUrl completionHandler:^(BOOL migrationSuccess, NSError * migrationError) {
                if(migrationSuccess) {    
                    addLocalPersistentStoreBlock();
                }
                else {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completionHandler(nil, migrationError);
                    });
                    dispatch_resume(ap_persistentStoreQueue);
                }
            }];
        }
        else {
            if(error) {
                // We shouldn't migrate but there has been an error, stop there
                if(completionHandler) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completionHandler(nil, error);
                    });
                }
                dispatch_resume(ap_persistentStoreQueue);
            }
            else {
                // We don't need to migrate and we can continue
                addLocalPersistentStoreBlock();
            }
        }
    });
}

- (void)resetStackToBeUbiquitousWithCompletionHandler:(void (^)(NSManagedObjectContext *, NSError *))completionHandler {
    [self ap_checkUbiquitousDocumentStorageAvailabilityWithTimeOutDelay:10
                                                      completionHandler:^(BOOL timeOut, BOOL available, NSURL * ubiquityContainerURL, NSURL * persistentStoreURL, NSString * contentName) {
                                                          if(timeOut) {
                                                              // The availability of ubiquitous document storage could not be determined in time
                                                              if(completionHandler) {
                                                                  dispatch_async(dispatch_get_main_queue(), ^{
                                                                      NSError * error = [NSError errorWithDomain:CORE_DATA_STACK_MANAGER_ERROR_DOMAIN
                                                                                                            code:APCoreDataStackManagerErrorDocumentStorageAvailabilityTimeOut
                                                                                                        userInfo:nil];
                                                                      completionHandler(nil, error);
                                                                  });
                                                              }
                                                          }
                                                          else {
                                                              if(available) {
                                                                  dispatch_async(ap_persistentStoreQueue, ^{        
                                                                      // Block the queue until we are finished
                                                                      dispatch_suspend(ap_persistentStoreQueue);
                                                                      
                                                                      [self ap_resetCoreDataStack];
                                                                      
                                                                      ap_ubiquityContainerURL = ubiquityContainerURL;
                                                                      [self setUbiquitousContentName:contentName];
                                                                      [self setUbiquitousPersistentStoreURL:persistentStoreURL];
                                                                      
                                                                      NSError * error = nil;
                                                                      NSPersistentStore * store = [self ap_addUbiquitousPersistentStoreWithError:&error];
                                                                      
                                                                      dispatch_resume(ap_persistentStoreQueue);
                                                                      
                                                                      dispatch_async(dispatch_get_main_queue(), ^{
                                                                          if(store) {
                                                                              if(completionHandler) {
                                                                                  NSManagedObjectContext * context = nil;
                                                                                  if(store) {
                                                                                      context = [self rootManagedObjectContext];
                                                                                  }
                                                                                  completionHandler(context, error);
                                                                              }
                                                                          }
                                                                          else {
                                                                              if(completionHandler) {
                                                                                  completionHandler(nil, error);
                                                                              }
                                                                          }   
                                                                      });
                                                                  });
                                                              }
                                                              else {
                                                                  // Document storage is not available
                                                                  if(completionHandler) {
                                                                      dispatch_async(dispatch_get_main_queue(), ^{
                                                                          NSError * error = [NSError errorWithDomain:CORE_DATA_STACK_MANAGER_ERROR_DOMAIN
                                                                                                                code:APCoreDataStackManagerErrorDocumentStorageUnavailable
                                                                                                            userInfo:nil];
                                                                          completionHandler(nil, error);
                                                                      });
                                                                  }
                                                              }
                                                          }
                                                      }];
}

- (void)replaceLocalPersistentStoreWithStoreAtURL:(NSURL *)originStoreURL completionHandler:(void(^)(NSManagedObjectContext *, NSError *))completionHandler {
    NSURL * localStoreURL = [self localStoreURL];
    if(!localStoreURL) {
        if(completionHandler) {
            completionHandler(nil, [NSError errorWithDomain:CORE_DATA_STACK_MANAGER_ERROR_DOMAIN
                                                       code:APCoreDataStackManagerErrorLocalStoreURLUnavailable
                                                   userInfo:nil]);
        }
        return;
    }
    
    dispatch_async(ap_persistentStoreQueue, ^{
        // Block the queue until we are finished
        dispatch_suspend(ap_persistentStoreQueue);
        
        [self ap_resetCoreDataStack];
        
        NSFileManager   * fileManager = [NSFileManager defaultManager];
        
        __block NSError * pscError = nil;
        
        NSPersistentStoreCoordinator * psc = [self persistentStoreCoordinator];
        
        // Delete the file of the current persistent store
        if([localStoreURL checkResourceIsReachableAndReturnError:nil]) {
            if(![fileManager removeItemAtURL:localStoreURL error:&pscError]) {
                if(completionHandler) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completionHandler(nil, pscError);
                    });
                }
                dispatch_resume(ap_persistentStoreQueue);
                return;
            }
        }
        
        NSDictionary * options = [NSDictionary dictionaryWithObjectsAndKeys:
                                  [NSNumber numberWithBool:YES], NSMigratePersistentStoresAutomaticallyOption,
                                  [NSNumber numberWithBool:YES], NSInferMappingModelAutomaticallyOption,
                                  nil];
        
        // Add the new store
        NSPersistentStore * newStore = [psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:originStoreURL options:options error:&pscError];
        if(!newStore) {
            if(completionHandler) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completionHandler(nil, pscError);
                });
            }
            dispatch_resume(ap_persistentStoreQueue);
            return;
        }
        
        // Migrate the store to the new location
        NSPersistentStore * store = [psc migratePersistentStore:newStore toURL:localStoreURL options:nil withType:NSSQLiteStoreType error:&pscError];
        
        [self setCurrentPersistentStoreURL:localStoreURL];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if(completionHandler) {
                completionHandler(store?[self rootManagedObjectContext]: nil, pscError);
            }
        });
        dispatch_resume(ap_persistentStoreQueue);
    });
}

- (void)replaceCloudStoreWithStoreAtURL:(NSURL *)originStoreURL completionHandler:(void (^)(NSManagedObjectContext *, NSError *))completionHandler {
    if(!ap_ubiquityContainerURL) {
        if(completionHandler) {
            completionHandler(nil, [NSError errorWithDomain:CORE_DATA_STACK_MANAGER_ERROR_DOMAIN
                                                       code:APCoreDataStackManagerErrorDocumentStorageUnavailable
                                                   userInfo:nil]);
        }
        return;
    }
    
    dispatch_async(ap_persistentStoreQueue, ^{
        // Block the queue until we are finished
        dispatch_suspend(ap_persistentStoreQueue);
        
        [self ap_resetCoreDataStack];
        
        NSError * localError = nil;  
        // Delete the data on the cloud
        if(![self ap_deleteCloudDataWithError:&localError]) {
            if(completionHandler) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completionHandler(nil, localError);
                });
                dispatch_resume(ap_persistentStoreQueue);
            }
            return;
        }
        
        [self ap_createUbiquitousDirectoryIfNeeded];
        
        NSDate * startingDate = [NSDate date];
        
        // Notify the delegate that the cloud store will be replaced
        dispatch_async(dispatch_get_main_queue(), ^{
            if(delegate && [delegate respondsToSelector:@selector(coreDataStackManagerWillReplaceUbiquitousStore:)]) {
                [delegate coreDataStackManagerWillReplaceUbiquitousStore:self];
            }
        });
        
        __block NSError * pscError = nil;
        NSPersistentStoreCoordinator * psc = [self persistentStoreCoordinator];
        
        NSDictionary * options = [NSDictionary dictionaryWithObjectsAndKeys:
                                  [NSNumber numberWithBool:YES], NSMigratePersistentStoresAutomaticallyOption,
                                  [NSNumber numberWithBool:YES], NSInferMappingModelAutomaticallyOption,
                                  nil];
        
        // Add the store to migrate
        NSPersistentStore * storeToMigrate = [psc addPersistentStoreWithType:NSSQLiteStoreType
                                                               configuration:nil
                                                                         URL:originStoreURL
                                                                     options:options
                                                                       error:&pscError];
        if(!storeToMigrate) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if(completionHandler) {
                    completionHandler(nil, pscError);
                }
                if(delegate && [delegate respondsToSelector:@selector(coreDataStackManagerDidReplaceUbiquitousStore:)]) {
                    [delegate coreDataStackManagerDidReplaceUbiquitousStore:self];
                }
            });
            dispatch_resume(ap_persistentStoreQueue);
            return;
        }
        
        // Migrate the store
        NSString        * storeUbiquitousContentName = [self ap_newStoreUbiquitousContentName];
        NSURL           * ubiquitousContentURL = [ap_ubiquityContainerURL URLByAppendingPathComponent:@"UbiquitousContent"];
        
        NSDictionary * migrationOptions = [NSDictionary dictionaryWithObjectsAndKeys:
                                           storeUbiquitousContentName, NSPersistentStoreUbiquitousContentNameKey,
                                           ubiquitousContentURL, NSPersistentStoreUbiquitousContentURLKey,
                                           nil];

        NSURL * ubiquitousStoreURL = [self ap_ubiquitousStoreURLWithContentName:storeUbiquitousContentName];
        
        NSPersistentStore * migratedStore = [psc migratePersistentStore:storeToMigrate 
                                                                  toURL:ubiquitousStoreURL
                                                                options:migrationOptions
                                                               withType:NSSQLiteStoreType
                                                                  error:&pscError];
        
        ap_currentStoreUbiquitousContentName = storeUbiquitousContentName;
        [self setCurrentPersistentStoreURL:ubiquitousStoreURL];
        [self ap_configureCloudForStoreUbiquitousContentName:storeUbiquitousContentName];
        
        // If the migration took less than 2 seconds, keep the window displayed for 2 more seconds
        if(fabs([startingDate timeIntervalSinceNow]) < 2) {
            [NSThread sleepForTimeInterval:2];   
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if(delegate && [delegate respondsToSelector:@selector(coreDataStackManagerDidReplaceUbiquitousStore:)]) {
                [delegate coreDataStackManagerDidReplaceUbiquitousStore:self];
            }
            
            if(completionHandler) {
                completionHandler(migratedStore?[self rootManagedObjectContext]:nil, pscError);
            }
        });
        dispatch_resume(ap_persistentStoreQueue);
    });
}

- (BOOL)ap_deleteCloudDataWithError:(NSError **)error {
    if(!ap_ubiquityContainerURL) {
        return NO;
    }
    __block BOOL success = YES;
    NSFileCoordinator * fileCoordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    NSURL           * ubiquitousContentURL = [ap_ubiquityContainerURL URLByAppendingPathComponent:@"UbiquitousContent"];
    [fileCoordinator coordinateWritingItemAtURL:ubiquitousContentURL
                                        options:0
                                          error:nil
                                     byAccessor:^(NSURL * newURL) {
                                         NSFileManager  * fileManager = [NSFileManager defaultManager];
                                         NSError        * fileManagerError = nil;
                                         if([newURL checkResourceIsReachableAndReturnError:nil]) {
                                             success = [fileManager removeItemAtURL:newURL error:&fileManagerError];
                                             if(error) {
                                                 * error = fileManagerError;
                                             }
                                         }
                                     }];
    return success;
}

#pragma mark
#pragma mark Migration

- (BOOL)ap_migrationNeededForStoreAtURL:(NSURL *)storeURL error:(NSError **)error {
    // If no file is there, no migration needed
    if(![storeURL checkResourceIsReachableAndReturnError:nil]) {
        return NO;
    }
    
    // Get the meta data of the store    
    NSError         * metadataError = nil;
    NSDictionary    * metadata = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:NSSQLiteStoreType
                                                                                            URL:storeURL
                                                                                          error:&metadataError];
    if (!metadata) {
        * error = metadataError;
        return NO;
    }
    return (![[self managedObjectModel] isConfiguration:nil compatibleWithStoreMetadata:metadata]);
}

- (void)ap_migrateStoreAtURL:(NSURL *)storeURL completionHandler:(void (^)(BOOL, NSError *))completionHandler {
    if(delegate && [delegate conformsToProtocol:@protocol(APCoreDataStackManagerDelegate)]) {
        [delegate coreDataStackManager:self
                     migrateStoreAtURL:storeURL
     withDestinationManagedObjectModel:[self managedObjectModel]
                     completionHandler:completionHandler];
    }
}

#pragma mark
#pragma mark Database data

- (NSData *)persistentStoreData {
    // Save the changes
    NSManagedObjectContext * context = ap_rootManagedObjectContext;
    if ([context hasChanges]) {
        [context performBlockAndWait:^{
            NSError *error = nil;
            if (![context save:&error]) {
                NSLog(@"%@", error);
            }
        }];
    }
    
    return [NSData dataWithContentsOfURL:[self currentStoreURL]];
}

#pragma mark
#pragma mark Application's data directory

- (NSURL *)ap_applicationDocumentsDirectory {
    NSURL * applicationDocumentsDirectory = nil;
    if([delegate respondsToSelector:@selector(coreDataStackManagerApplicationDocumentsDirectory:)]) {
        applicationDocumentsDirectory = [delegate coreDataStackManagerApplicationDocumentsDirectory:self];
    }
    if(!applicationDocumentsDirectory) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSURL * appSupportURL = [[fileManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject];
        applicationDocumentsDirectory = [appSupportURL URLByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier]];
    }
    return applicationDocumentsDirectory;
}

- (void)ap_createUbiquitousDirectoryIfNeeded {
    if(!ap_ubiquityContainerURL) {
        return;
    }
    
    NSURL           * localDataURL = [ap_ubiquityContainerURL URLByAppendingPathComponent:@"Documents" isDirectory:YES];
    localDataURL = [localDataURL URLByAppendingPathComponent:@"LocalData.nosync" isDirectory:YES];
    BOOL            localDataURLIsDirectory;
    NSFileManager * fileManager = [NSFileManager defaultManager];
    if([fileManager fileExistsAtPath:[localDataURL path] isDirectory:&localDataURLIsDirectory]) {
        if(!localDataURLIsDirectory) {
            // There is a file at this URL!
            [fileManager removeItemAtURL:localDataURL error:nil];
            [fileManager createDirectoryAtURL:localDataURL withIntermediateDirectories:YES attributes:nil error:nil];
        }
    }
    else {
        // There is nothing at this URL
        [fileManager createDirectoryAtURL:localDataURL withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

- (BOOL)ap_createApplicationDirectoryIfNeededWithError:(NSError **)error {
    NSURL * applicationDocumentsDirectory = [self ap_applicationDocumentsDirectory];
    
    NSError * directoryCreationError = nil;
    
    BOOL success = NO;
    NSDictionary * properties = [applicationDocumentsDirectory resourceValuesForKeys:[NSArray arrayWithObject:NSURLIsDirectoryKey] error:&directoryCreationError];
    if (!properties) {
        if ([directoryCreationError code] == NSFileReadNoSuchFileError) {
            NSFileManager * fileManager = [NSFileManager defaultManager];
            success = [fileManager createDirectoryAtPath:[applicationDocumentsDirectory path] withIntermediateDirectories:YES attributes:nil error:&directoryCreationError];
        }
    }
    else {
        if ([[properties objectForKey:NSURLIsDirectoryKey] boolValue] != YES) {
            directoryCreationError = [NSError errorWithDomain:CORE_DATA_STACK_MANAGER_ERROR_DOMAIN
                                                         code:APCoreDataStackManagerErrorFileFoundAtApplicationDirectoryURL
                                                     userInfo:nil];
        }
    }
    * error = directoryCreationError;
    return success;
}

#pragma mark
#pragma mark NSFilePresenter

- (NSURL *)presentedItemURL {
    return ap_filePresenterURL;
}

- (NSOperationQueue *)presentedItemOperationQueue {
    return ap_filePresenterQueue;
}

- (void)relinquishPresentedItemToReader:(void (^)(void (^reacquirer)(void)))reader {
    reader(^{});
}

- (void)presentedItemDidChange {
    // Read the content name
    NSString * contentName = nil;
    [self ap_readContentNameFromCloudIntoString:&contentName];
    
    if(![ap_currentStoreUbiquitousContentName isEqual:contentName]) {
        BOOL iCloudEnabled = NO;
        if(delegate && [delegate respondsToSelector:@selector(coreDataStackManagerShouldUseUbiquitousStore:)]) {
            iCloudEnabled = [delegate coreDataStackManagerShouldUseUbiquitousStore:self];
        }
        if(iCloudEnabled) {
            if(contentName && (NSNull *)contentName != [NSNull null]) {
                // A new store has been seeded to iCloud
                if(delegate && [delegate respondsToSelector:@selector(coreDataStackManagerRequestUbiquitousStoreRefresh:)]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [delegate coreDataStackManagerRequestUbiquitousStoreRefresh:self];
                    });
                }
            }
            else {
                // Data from the cloud was deleted
                if(delegate && [delegate respondsToSelector:@selector(coreDataStackManagerRequestLocalStoreRefresh:)]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [delegate coreDataStackManagerRequestLocalStoreRefresh:self];
                    });
                }
            }
        }
    }

}

#pragma mark
#pragma mark Core Data Stack

- (NSManagedObjectModel *)managedObjectModel {
    if (!ap_managedObjectModel) {
        NSManagedObjectModel    * model = [[NSManagedObjectModel alloc] initWithContentsOfURL:ap_modelURL];
        [self setManagedObjectModel:model];
    }
    return ap_managedObjectModel;
}

- (NSPersistentStoreCoordinator *)persistentStoreCoordinator {
    if (!ap_persistentStoreCoordinator) {
        NSManagedObjectModel * managedObjectModel = [self managedObjectModel];
        if (!managedObjectModel) {
            NSLog(@"%@:%@ No model to generate a store from", [self class], NSStringFromSelector(_cmd));
            return nil;
        }
        
        NSPersistentStoreCoordinator * persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:managedObjectModel];
        [self setPersistentStoreCoordinator:persistentStoreCoordinator];
    }
    return ap_persistentStoreCoordinator;
}

- (NSManagedObjectContext *)rootManagedObjectContext {
    if (!ap_rootManagedObjectContext) {
        NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
        
        NSManagedObjectContext * managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        [managedObjectContext performBlockAndWait:^{
            [managedObjectContext setPersistentStoreCoordinator:coordinator];
            [managedObjectContext setMergePolicy:NSMergeByPropertyObjectTrumpMergePolicy];
        }];
        [self setRootManagedObjectContext:managedObjectContext];
    }
    
    return ap_rootManagedObjectContext;
}

- (void)ap_resetCoreDataStack {
    [[NSNotificationCenter defaultCenter] removeObserver:ap_managedObjectContextObjectsDidChangeObserver];
     
    // Save the changes
    NSManagedObjectContext * context = ap_rootManagedObjectContext;
    [context processPendingChanges];
    if ([context hasChanges]) {
        [context performBlockAndWait:^{
            NSError *error = nil;
            if (![context save:&error]) {
                NSLog(@"%@", error);
            }
        }];
    }
    
    [self setCurrentPersistentStoreURL:nil];
    [self setManagedObjectModel:nil];
    [self setPersistentStoreCoordinator:nil];
    [self setRootManagedObjectContext:nil];
}

@end
