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
                                                              userInfo:@{@"ubiquitousStorageAvailable": @(available)}]; 
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
                                         NSData * ubiquityConfigurationData = [NSData dataWithContentsOfURL:newURL];
                                         if(ubiquityConfigurationData) {
                                             NSDictionary * dictionary = [NSPropertyListSerialization propertyListWithData:ubiquityConfigurationData
                                                                                                                   options:NSPropertyListImmutable
                                                                                                                    format:NULL
                                                                                                                     error:nil];
                                             contentName = [dictionary valueForKey:UBIQUITYCONFIGURATIONCONTENTNAMEKEY];
                                         }
                                         
                                         ap_filePresenterURL = newURL;
                                         [NSFileCoordinator addFilePresenter:self];
                                     }];
    if(string) {
        * string = contentName;
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
    NSDictionary * dictionary = @{UBIQUITYCONFIGURATIONCONTENTNAMEKEY: contentName};
    NSData * ubiquityConfigurationData = [NSPropertyListSerialization dataWithPropertyList:dictionary
                                                                                    format:NSPropertyListXMLFormat_v1_0
                                                                                   options:0
                                                                                     error:nil];
    
    [fileCoordinator coordinateWritingItemAtURL:ubiquityConfigurationURL
                                        options:0
                                          error:nil
                                     byAccessor:^(NSURL *newURL) {
                                         [ubiquityConfigurationData writeToURL:newURL atomically:YES];
                                         
                                         ap_filePresenterURL = newURL;
                                         [NSFileCoordinator addFilePresenter:self];
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
    // Automatic migration options
    NSDictionary * options = @{NSPersistentStoreUbiquitousContentNameKey : storeUbiquitousContentName, NSPersistentStoreUbiquitousContentURLKey : ubiquitousContentURL, NSMigratePersistentStoresAutomaticallyOption : @YES, NSInferMappingModelAutomaticallyOption : @YES};
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
                                                          userInfo:@{@"PersistentStoreIsUbiquitous": @YES}];
        
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
    
    // Stop observing the Configuration.plist file if we were observing it
    if([[NSFileCoordinator filePresenters] containsObject:self]) {
        [NSFileCoordinator removeFilePresenter:self];
    }
    
    NSError * pscError = nil;
    
    [self ap_createApplicationDirectoryIfNeededWithError:&pscError];
    
    // Automatic migration options
    NSDictionary * options = @{NSMigratePersistentStoresAutomaticallyOption : @YES, NSInferMappingModelAutomaticallyOption : @YES };
    NSURL * localStoreURL = [self localStoreURL];
    NSPersistentStoreCoordinator * persistentStoreCoordinator = [self persistentStoreCoordinator];
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
                                                          userInfo:@{@"PersistentStoreIsUbiquitous": @NO}];
        
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
                                                                  if(persistentStoreURL) {
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
                                                                      // Document storage is available, but no persistent store could be found
                                                                      if(completionHandler) {
                                                                          dispatch_async(dispatch_get_main_queue(), ^{
                                                                              NSError * error = [NSError errorWithDomain:CORE_DATA_STACK_MANAGER_ERROR_DOMAIN
                                                                                                                    code:APCoreDataStackManagerErrorNoUbiquitousPersistentStoreFound
                                                                                                                userInfo:nil];
                                                                              completionHandler(nil, error);
                                                                          });
                                                                      }
                                                                      
                                                                  }
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
        
        // Automatic migration options
        NSDictionary * options = @{NSReadOnlyPersistentStoreOption : @YES, NSMigratePersistentStoresAutomaticallyOption : @YES, NSInferMappingModelAutomaticallyOption : @YES };
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
        
        // Automatic migration options
        NSDictionary * storeToMigrateOptions = @{NSReadOnlyPersistentStoreOption : @YES, NSMigratePersistentStoresAutomaticallyOption : @YES, NSInferMappingModelAutomaticallyOption : @YES};
        // Add the store to migrate
        NSPersistentStore * storeToMigrate = [psc addPersistentStoreWithType:NSSQLiteStoreType
                                                               configuration:nil
                                                                         URL:originStoreURL
                                                                     options:storeToMigrateOptions
                                                                       error:&pscError];
        
        // Erase keys about the iCloud metadata of the persistent store
        // Known bug in iOS 6 and OS 10.8.2 that lead in corruption of this metadata
        // and prevents the store to be succesfully migrated afterwards
        BOOL resetiCloudMetadata = NO;
        if(resetiCloudMetadata) {
            NSMutableDictionary * metadata = [NSMutableDictionary dictionaryWithDictionary:[psc metadataForPersistentStore:storeToMigrate]];
            NSSet * ubiquityKeys = [metadata keysOfEntriesPassingTest:^BOOL(id key, id obj, BOOL *stop) {
                NSRange range = [key rangeOfString:@"com.apple.coredata.ubiquity"];
                return !(range.location == NSNotFound && range.length == 0);
            }];
            [metadata removeObjectsForKeys:[ubiquityKeys allObjects]];
            [psc removePersistentStore:storeToMigrate error:NULL];
            NSError * e = nil;
            [NSPersistentStoreCoordinator setMetadata:[NSDictionary dictionaryWithDictionary:metadata]
                             forPersistentStoreOfType:NSSQLiteStoreType
                                                  URL:originStoreURL
                                                error:&e];
            storeToMigrate = [psc addPersistentStoreWithType:NSSQLiteStoreType
                                               configuration:nil
                                                         URL:originStoreURL
                                                     options:@{NSReadOnlyPersistentStoreOption : @YES}
                                                       error:&pscError];
        }
        
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
        NSDictionary    * options = @{NSPersistentStoreUbiquitousContentNameKey: storeUbiquitousContentName, NSPersistentStoreUbiquitousContentURLKey: ubiquitousContentURL};
        NSURL * ubiquitousStoreURL = [self ap_ubiquitousStoreURLWithContentName:storeUbiquitousContentName];
        
        NSPersistentStore *migratedStore = nil;
        @try {
            migratedStore = [psc migratePersistentStore:storeToMigrate
                                                  toURL:ubiquitousStoreURL
                                                options:options
                                               withType:NSSQLiteStoreType
                                                  error:&pscError];
        }
        @catch (NSException *exception) {
            
            if(completionHandler) {
                completionHandler(nil, [NSError errorWithDomain:CORE_DATA_STACK_MANAGER_ERROR_DOMAIN
                                                           code:APCoreDataStackManagerErrorDocumentStorageUnavailable
                                                       userInfo:[NSDictionary dictionaryWithObject:[exception reason] forKey:NSLocalizedDescriptionKey]]);
            }
            return;
        }
        
        ap_currentStoreUbiquitousContentName = storeUbiquitousContentName;
        ap_ubiquitousPersistentStoreURL = ubiquitousStoreURL;
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
    if(delegate && [delegate respondsToSelector:@selector(coreDataStackManager:migrateStoreAtURL:withDestinationManagedObjectModel:completionHandler:)]) {
        [delegate coreDataStackManager:self
                     migrateStoreAtURL:storeURL
     withDestinationManagedObjectModel:[self managedObjectModel]
                     completionHandler:completionHandler];
    }
    else {
        // Migrate ourselves
        NSError * error = nil;
		NSDictionary    * sourceMetadata = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:NSSQLiteStoreType
																									  URL:storeURL
																									error:&error];
		if (!sourceMetadata) {
            // Couldn't find source metadata
            if(completionHandler) {
                completionHandler(NO, error);
            }
            return;
		}
		
		NSManagedObjectModel * sourceModel = [NSManagedObjectModel mergedModelFromBundles:nil
																		 forStoreMetadata:sourceMetadata];
        NSManagedObjectModel * destinationModel = [self managedObjectModel];
		NSMigrationManager  * migrationManager = [[NSMigrationManager alloc] initWithSourceModel:sourceModel
																				destinationModel:destinationModel];
        
		// Find the mapping model between the source and the destination model
		NSMappingModel      * mappingModel = [NSMappingModel mappingModelFromBundles:nil
																	  forSourceModel:sourceModel
																	destinationModel:destinationModel];
        if(!mappingModel) {
            mappingModel = [NSMappingModel inferredMappingModelForSourceModel:sourceModel
                                                             destinationModel:destinationModel
                                                                        error:&error];
        }
        
        if(!mappingModel) {
            // Couldn't find a mapping model
            if(completionHandler) {
                completionHandler(NO, error);
            }
            return;
        }
        
        NSURL   * destinationStoreURL = [storeURL URLByAppendingPathExtension:@"new"];
        if(![migrationManager migrateStoreFromURL:storeURL
                                             type:NSSQLiteStoreType
                                          options:nil
                                 withMappingModel:mappingModel
                                 toDestinationURL:destinationStoreURL
                                  destinationType:NSSQLiteStoreType
                               destinationOptions:nil
                                            error:&error]) {
            // Couldn't migrate the store
            if(completionHandler) {
                completionHandler(NO, error);
            }
            return;
        }
        
        // Move the migrated store file to storeURL, making a backup copy
        NSString * backupStoreFileName = [[[[storeURL URLByDeletingPathExtension] lastPathComponent] stringByAppendingString:@"~"] stringByAppendingPathExtension:[storeURL pathExtension]];
        NSURL   * backupStoreURL = [[storeURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:backupStoreFileName];

        NSFileManager * fileManager = [NSFileManager defaultManager];
        [fileManager removeItemAtURL:backupStoreURL error:NULL];
        [fileManager moveItemAtURL:storeURL toURL:backupStoreURL error:NULL];
        [fileManager moveItemAtURL:destinationStoreURL toURL:storeURL error:NULL];
        
        if(completionHandler) {
            completionHandler(YES, nil);
        }
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

#pragma mark - Remaining persistent stores

- (NSArray *)previouslyUsedPersistentStoresURLs {
    NSURL * ubiquityContainerURL = ap_ubiquityContainerURL;
    if(!ubiquityContainerURL) {
        // URLs will not be fetched asynchronously
        // This method should be called once the stack is set up
        return nil;
    }
    NSURL           * persistentStoresContainer = [ap_ubiquityContainerURL URLByAppendingPathComponent:@"Documents"
                                                                                           isDirectory:YES];
    persistentStoresContainer = [persistentStoresContainer URLByAppendingPathComponent:@"LocalData.nosync"
                                                                           isDirectory:YES];
    NSFileManager * fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator * enumerator = [fileManager enumeratorAtURL:persistentStoresContainer
                                           includingPropertiesForKeys:@[NSURLNameKey, NSURLContentModificationDateKey]
                                                              options:(NSDirectoryEnumerationSkipsHiddenFiles|NSDirectoryEnumerationSkipsSubdirectoryDescendants)
                                                         errorHandler:nil];
    NSMutableArray * urls = [NSMutableArray array];
    for (NSURL * url in enumerator) {
        if(![url isEqual:[self ubiquitousPersistentStoreURL]]) {
            [urls addObject:url];
        }
    }
    return [NSArray arrayWithArray:urls];
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
    NSDictionary * properties = [applicationDocumentsDirectory resourceValuesForKeys:@[NSURLIsDirectoryKey] error:&directoryCreationError];
    if (!properties) {
        if ([directoryCreationError code] == NSFileReadNoSuchFileError) {
            NSFileManager * fileManager = [NSFileManager defaultManager];
            success = [fileManager createDirectoryAtPath:[applicationDocumentsDirectory path] withIntermediateDirectories:YES attributes:nil error:&directoryCreationError];
        }
    }
    else {
        if ([properties[NSURLIsDirectoryKey] boolValue] != YES) {
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

- (void)accommodatePresentedItemDeletionWithCompletionHandler:(void (^)(NSError *errorOrNil))completionHandler {
    BOOL isUsingUbiquitousStore = NO;
    if(delegate && [delegate respondsToSelector:@selector(coreDataStackManagerShouldUseUbiquitousStore:)]) {
        isUsingUbiquitousStore = [delegate coreDataStackManagerShouldUseUbiquitousStore:self];
    }
    if(isUsingUbiquitousStore) {
        // Data from the cloud was deleted
        if(delegate && [delegate respondsToSelector:@selector(coreDataStackManagerRequestLocalStoreRefresh:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [delegate coreDataStackManagerRequestLocalStoreRefresh:self];
            });
        }
    }
    completionHandler(nil);
}

- (void)presentedItemDidChange {
    // Read the content name
    NSString * contentName = nil;
    [self ap_readContentNameFromUbiquityContainerURL:ap_ubiquityContainerURL intoString:&contentName];
    if(![ap_currentStoreUbiquitousContentName isEqual:contentName]) {
        BOOL isUsingUbiquitousStore = NO;
        if(delegate && [delegate respondsToSelector:@selector(coreDataStackManagerShouldUseUbiquitousStore:)]) {
            isUsingUbiquitousStore = [delegate coreDataStackManagerShouldUseUbiquitousStore:self];
        }
        if(isUsingUbiquitousStore) {
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
    
    [context performBlockAndWait:^{
        [context reset];
        [context lock];
        
        NSPersistentStoreCoordinator * psc = [self persistentStoreCoordinator];
        NSArray * persistentStores = [psc persistentStores];
        NSError * error = nil;
        for(NSPersistentStore * store in persistentStores) {
            [psc removePersistentStore:store error:&error];
        }
        
        [context unlock];
    }];
    
    [self setCurrentPersistentStoreURL:nil];
    [self setManagedObjectModel:nil];
    [self setPersistentStoreCoordinator:nil];
    [self setRootManagedObjectContext:nil];
}

@end
