//
//  SLCoreDataStack.m
//
//  The MIT License (MIT)
//  Copyright (c) 2013 Oliver Letterer, Sparrow-Labs
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import "SLCoreDataStack.h"
#import <objc/runtime.h>



NSString *const SLCoreDataStackErrorDomain = @"SLCoreDataStackErrorDomain";



@interface SLCoreDataStack ()

@property (nonatomic, readonly) NSURL *_dataStoreRootURL;
@property (nonatomic, readonly) BOOL requiresMigration;

@property (nonatomic, readonly) NSURL *dataStoreURL;

@end


@implementation SLCoreDataStack
@synthesize mainThreadManagedObjectContext = _mainThreadManagedObjectContext, backgroundThreadManagedObjectContext = _backgroundThreadManagedObjectContext;

#pragma mark - setters and getters

- (NSString *)managedObjectModelName
{
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (NSURL *)databaseRootURL
{
    return [[NSFileManager defaultManager] URLsForDirectory:NSLibraryDirectory
                                                  inDomains:NSUserDomainMask].lastObject;
}

- (NSURL *)dataStoreURL
{
    NSURL *dataStoreRootURL = self._dataStoreRootURL;
    NSString *dataStoreFileName = [NSString stringWithFormat:@"%@.sqlite", self.managedObjectModelName];
    
    return [dataStoreRootURL URLByAppendingPathComponent:dataStoreFileName];
}

- (NSURL *)_dataStoreRootURL
{
    NSURL *dataStoreRootURL = self.databaseRootURL;
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:dataStoreRootURL.relativePath isDirectory:NULL]) {
        NSError *error = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:dataStoreRootURL.relativePath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&error];
        
        NSAssert(error == nil, @"error while creating dataStoreRootURL '%@':\n\nerror: \"%@\"", dataStoreRootURL, error);
    }
    
    return dataStoreRootURL;
}

- (NSBundle *)bundle
{
    return [NSBundle bundleForClass:self.class];
}

- (BOOL)requiresMigration
{
    NSPersistentStoreCoordinator *persistentStoreCoordinator = nil;
    
    NSURL *storeURL = self.dataStoreURL;
    NSManagedObjectModel *managedObjectModel = self.managedObjectModel;
    
    NSError *error = nil;
    persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:managedObjectModel];
    if (![persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error]) {
        
        return error.code == NSPersistentStoreIncompatibleVersionHashError;
    }
    
    return NO;
}

+ (instancetype)sharedInstance
{
    @synchronized(self) {
        static NSMutableDictionary *_sharedDataStoreManagers = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            _sharedDataStoreManagers = [NSMutableDictionary dictionary];
        });
        
        NSString *uniqueKey = NSStringFromClass(self.class);
        SLCoreDataStack *instance = _sharedDataStoreManagers[uniqueKey];
        
        if (!instance) {
            instance = [[super allocWithZone:NULL] init];
            _sharedDataStoreManagers[uniqueKey] = instance;
        }
        
        return instance;
    }
}

#pragma mark - Initialization

- (id)init
{
    if (self = [super init]) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_automaticallySaveDataStore)
                                                     name:UIApplicationWillTerminateNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_automaticallySaveDataStore)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
    }
    return self;
}

#pragma mark - Class methods

+ (BOOL)subclassesRequireMigration
{
    __block BOOL subclassesRequireMigration = NO;
    
    for (NSString *className in [self _concreteSubclasses]) {
        Class class = NSClassFromString(className);
        
        SLCoreDataStack *manager = [class sharedInstance];
        if (manager.requiresMigration) {
            subclassesRequireMigration = YES;
        }
    }
    
    return subclassesRequireMigration;
}

+ (void)registerConcreteSubclass:(Class)subclass
{
    NSParameterAssert(subclass);
    NSAssert([subclass isSubclassOfClass:[SLCoreDataStack class]], @"%@ needs to be a concrete subclass of SLCoreDataStack", subclass);
    NSAssert(subclass != [SLCoreDataStack class], @"%@ needs to be a concrete subclass of SLCoreDataStack", subclass);
    
    [[self _concreteSubclasses] addObject:NSStringFromClass(subclass)];
}

+ (NSMutableSet *)_concreteSubclasses
{
    static NSMutableSet *set = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        set = [NSMutableSet set];
    });
    
    return set;
}

+ (void)migrateSubclassesWithProgressHandler:(void(^)(SLCoreDataStack *currentMigratingSubclass))progressHandler
                           completionHandler:(dispatch_block_t)completionHandler
{
    static dispatch_queue_t queue = NULL;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("de.ebf.SLCoreDataStack.migration-queue", DISPATCH_QUEUE_CONCURRENT);
    });
    
    NSMutableArray *requiresSubclasses = [NSMutableArray array];
    
    for (NSString *className in [self _concreteSubclasses]) {
        Class class = NSClassFromString(className);
        
        SLCoreDataStack *manager = [class sharedInstance];
        if (manager.requiresMigration) {
            [requiresSubclasses addObject:manager];
        }
    }
    
    NSUInteger count = requiresSubclasses.count;
    [requiresSubclasses enumerateObjectsUsingBlock:^(SLCoreDataStack *manager, NSUInteger idx, BOOL *stop) {
        dispatch_async(queue, ^{
            if (progressHandler) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    progressHandler(manager);
                });
            }
            
            // automatically triggers migration if available
            [manager mainThreadManagedObjectContext];
            
            if (idx + 1 == count) {
                if (completionHandler) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completionHandler();
                    });
                }
            }
        });
    }];
}

#pragma mark - CoreData

- (NSManagedObjectModel *)managedObjectModel
{
    if (!_managedObjectModel) {
        NSString *managedObjectModelName = self.managedObjectModelName;
        NSURL *modelURL = [self.bundle URLForResource:managedObjectModelName withExtension:@"momd"];
        
        _managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    }
    
    return _managedObjectModel;
}

- (NSManagedObjectContext *)mainThreadManagedObjectContext
{
    if (!_mainThreadManagedObjectContext) {
        _mainThreadManagedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        _mainThreadManagedObjectContext.persistentStoreCoordinator = self.persistentStoreCoordinator;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_managedObjectContextDidSaveNotificationCallback:) name:NSManagedObjectContextDidSaveNotification object:_mainThreadManagedObjectContext];
    }
    
    return _mainThreadManagedObjectContext;
}

- (void)setMainThreadManagedObjectContext:(NSManagedObjectContext *)mainThreadManagedObjectContext
{
    if (mainThreadManagedObjectContext != _mainThreadManagedObjectContext) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextDidSaveNotification object:_mainThreadManagedObjectContext];
        
        _mainThreadManagedObjectContext = mainThreadManagedObjectContext;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_managedObjectContextDidSaveNotificationCallback:) name:NSManagedObjectContextDidSaveNotification object:_mainThreadManagedObjectContext];
    }
}

- (NSManagedObjectContext *)backgroundThreadManagedObjectContext
{
    if (!_backgroundThreadManagedObjectContext) {
        _backgroundThreadManagedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        _backgroundThreadManagedObjectContext.persistentStoreCoordinator = self.persistentStoreCoordinator;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_managedObjectContextDidSaveNotificationCallback:) name:NSManagedObjectContextDidSaveNotification object:_backgroundThreadManagedObjectContext];
    }
    
    return _backgroundThreadManagedObjectContext;
}

- (void)setBackgroundThreadManagedObjectContext:(NSManagedObjectContext *)backgroundThreadManagedObjectContext
{
    if (backgroundThreadManagedObjectContext != _backgroundThreadManagedObjectContext) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextDidSaveNotification object:_backgroundThreadManagedObjectContext];
        
        _backgroundThreadManagedObjectContext = backgroundThreadManagedObjectContext;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_managedObjectContextDidSaveNotificationCallback:) name:NSManagedObjectContextDidSaveNotification object:_backgroundThreadManagedObjectContext];
    }
}

- (NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
    if (!_persistentStoreCoordinator) {
        NSURL *storeURL = self.dataStoreURL;
        NSManagedObjectModel *managedObjectModel = self.managedObjectModel;
        
        NSDictionary *options = @{
                                  NSMigratePersistentStoresAutomaticallyOption: @YES,
                                  NSInferMappingModelAutomaticallyOption: @YES
                                  };
        
        NSError *error = nil;
        _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:managedObjectModel];
        if (![_persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:options error:&error]) {
            error = nil;
            // first try to migrate to the new store
            if (![self _performMigrationFromDataStoreAtURL:storeURL toDestinationModel:managedObjectModel error:&error]) {
                // migration was not successful => delete database and continue
                [[NSFileManager defaultManager] removeItemAtURL:storeURL error:NULL];
                
                if (![_persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error]) {
                    NSAssert(NO, @"Could not add persistent store: %@", error);
                }
            } else {
                // migration was successful, just add the store
                if (![_persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error]) {
                    // unable to add store, fail
                    NSAssert(NO, @"Could not add persistent store: %@", error);
                }
            }
        }
    }
    
    return _persistentStoreCoordinator;
}

#pragma mark - private implementation ()

- (BOOL)_performMigrationFromDataStoreAtURL:(NSURL *)dataStoreURL
                         toDestinationModel:(NSManagedObjectModel *)destinationModel
                                      error:(NSError **)error
{
    NSAssert(error != nil, @"Error pointer cannot be nil");
    
    NSString *type = NSSQLiteStoreType;
    NSDictionary *sourceStoreMetadata = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:type
                                                                                                   URL:dataStoreURL
                                                                                                 error:error];
    
    if (!sourceStoreMetadata) {
        return NO;
    }
    
    if ([destinationModel isConfiguration:nil compatibleWithStoreMetadata:sourceStoreMetadata]) {
        *error = nil;
        return YES;
    }
    
    NSArray *bundles = @[ self.bundle ];
    NSManagedObjectModel *sourceModel = [NSManagedObjectModel mergedModelFromBundles:bundles
                                                                    forStoreMetadata:sourceStoreMetadata];
    
    if (!sourceModel) {
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Unable to find NSManagedObjectModel for store metadata %@", sourceStoreMetadata]
                                                             forKey:NSLocalizedDescriptionKey];
        *error = [NSError errorWithDomain:SLCoreDataStackErrorDomain code:SLCoreDataStackManagedObjectModelNotFound userInfo:userInfo];
        return NO;
    }
    
    NSMutableArray *objectModelPaths = [NSMutableArray array];
    NSArray *allManagedObjectModels = [self.bundle pathsForResourcesOfType:@"momd"
                                                               inDirectory:nil];
    
    for (NSString *managedObjectModelPath in allManagedObjectModels) {
        NSArray *array = [self.bundle pathsForResourcesOfType:@"mom"
                                                  inDirectory:managedObjectModelPath.lastPathComponent];
        
        [objectModelPaths addObjectsFromArray:array];
    }
    
    NSArray *otherModels = [self.bundle pathsForResourcesOfType:@"mom" inDirectory:nil];
    [objectModelPaths addObjectsFromArray:otherModels];
    
    if (objectModelPaths.count == 0) {
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"No NSManagedObjectModel found in bundle %@", self.bundle]
                                                             forKey:NSLocalizedDescriptionKey];
        *error = [NSError errorWithDomain:SLCoreDataStackErrorDomain code:SLCoreDataStackManagedObjectModelNotFound userInfo:userInfo];
        return NO;
    }
    
    NSMappingModel *mappingModel = nil;
    NSManagedObjectModel *targetModel = nil;
    NSString *modelPath = nil;
    
    for (modelPath in objectModelPaths) {
        NSURL *modelURL = [NSURL fileURLWithPath:modelPath];
        targetModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
        mappingModel = [NSMappingModel mappingModelFromBundles:bundles
                                                forSourceModel:sourceModel
                                              destinationModel:targetModel];
        
        if (mappingModel) {
            break;
        }
    }
    
    if (!mappingModel) {
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Unable to find NSMappingModel for store at URL %@", dataStoreURL]
                                                             forKey:NSLocalizedDescriptionKey];
        *error = [NSError errorWithDomain:SLCoreDataStackErrorDomain code:SLCoreDataStackMappingModelNotFound userInfo:userInfo];
        return NO;
    }
    
    NSMigrationManager *migrationManager = [[NSMigrationManager alloc] initWithSourceModel:sourceModel
                                                                          destinationModel:targetModel];
    
    NSString *modelName = modelPath.lastPathComponent.stringByDeletingPathExtension;
    NSString *storeExtension = dataStoreURL.path.pathExtension;
    
    NSString *storePath = dataStoreURL.path.stringByDeletingPathExtension;
    
    NSString *destinationPath = [NSString stringWithFormat:@"%@.%@.%@", storePath, modelName, storeExtension];
    NSURL *destinationURL = [NSURL fileURLWithPath:destinationPath];
    
    if (![migrationManager migrateStoreFromURL:dataStoreURL type:type options:nil withMappingModel:mappingModel toDestinationURL:destinationURL destinationType:type destinationOptions:nil error:error]) {
        return NO;
    }
    
    if (![[NSFileManager defaultManager] removeItemAtURL:dataStoreURL error:error]) {
        return NO;
    }
    
    if (![[NSFileManager defaultManager] moveItemAtURL:destinationURL toURL:dataStoreURL error:error]) {
        return NO;
    }
    
    return [self _performMigrationFromDataStoreAtURL:dataStoreURL
                                  toDestinationModel:destinationModel
                                               error:error];
}

- (void)_managedObjectContextDidSaveNotificationCallback:(NSNotification *)notification
{
    NSManagedObjectContext *changedContext = notification.object;
    
    for (NSManagedObjectContext *otherContext in @[ self.mainThreadManagedObjectContext, self.backgroundThreadManagedObjectContext ]) {
        if (changedContext.persistentStoreCoordinator == otherContext.persistentStoreCoordinator && otherContext != changedContext) {
            [otherContext performBlock:^{
                [otherContext mergeChangesFromContextDidSaveNotification:notification];
            }];
        }
    }
}

- (void)_automaticallySaveDataStore
{
    for (NSManagedObjectContext *context in @[ self.mainThreadManagedObjectContext, self.backgroundThreadManagedObjectContext ]) {
        if (!context.hasChanges) {
            continue;
        }
        
        [context performBlock:^{
            NSError *error = nil;
            if (![context save:&error]) {
                NSLog(@"WARNING: Error while automatically saving changes of data store of class %@: %@", self, error);
            }
        }];
    }
}

@end
