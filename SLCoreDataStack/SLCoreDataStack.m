//
//  The MIT License (MIT)
//  Copyright (c) 2013-2015 Oliver Letterer, Sparrow-Labs
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
#import <objc/message.h>
#import <libkern/OSAtomic.h>

static void class_swizzleSelector(Class class, SEL originalSelector, SEL newSelector)
{
    Method origMethod = class_getInstanceMethod(class, originalSelector);
    Method newMethod = class_getInstanceMethod(class, newSelector);
    if(class_addMethod(class, originalSelector, method_getImplementation(newMethod), method_getTypeEncoding(newMethod))) {
        class_replaceMethod(class, newSelector, method_getImplementation(origMethod), method_getTypeEncoding(origMethod));
    } else {
        method_exchangeImplementations(origMethod, newMethod);
    }
}



NSString *const SLCoreDataStackErrorDomain = @"SLCoreDataStackErrorDomain";

@interface NSManagedObjectContext (SLCoreDataStackInternal)

@property (nonatomic, strong) NSMutableArray *SLCoreDataStack_deallocationHandlers;
- (void)SLCoreDataStack_addDeallocationHandler:(void(^)(__unsafe_unretained NSManagedObjectContext *context))handler;

@end

@implementation NSManagedObjectContext (SLCoreDataStackInternal)

#pragma mark - setters and getters

- (NSMutableArray *)SLCoreDataStack_deallocationHandlers
{
    return objc_getAssociatedObject(self, @selector(SLCoreDataStack_deallocationHandlers));
}

- (void)setSLCoreDataStack_deallocationHandlers:(NSMutableArray *)SLCoreDataStack_deallocationHandlers
{
    objc_setAssociatedObject(self, @selector(SLCoreDataStack_deallocationHandlers), SLCoreDataStack_deallocationHandlers, OBJC_ASSOCIATION_RETAIN);
}

#pragma mark - instance methods

- (void)SLCoreDataStack_addDeallocationHandler:(void(^)(__unsafe_unretained NSManagedObjectContext *context))handler
{
    [self.SLCoreDataStack_deallocationHandlers addObject:handler];
}

#pragma mark - Hooked implementations

+ (void)load
{
    class_swizzleSelector(self, @selector(initWithConcurrencyType:), @selector(__SLCoreDataStackInitWithConcurrencyType:));
    class_swizzleSelector(self, NSSelectorFromString(@"dealloc"), @selector(__SLCoreDataStackDealloc));
}

- (id)__SLCoreDataStackInitWithConcurrencyType:(NSManagedObjectContextConcurrencyType)ct __attribute__((objc_method_family(init)))
{
    if ((self = [self __SLCoreDataStackInitWithConcurrencyType:ct])) {
        self.SLCoreDataStack_deallocationHandlers = [NSMutableArray array];
    }

    return self;
}

- (void)__SLCoreDataStackDealloc
{
    for (id uncastedHandler in self.SLCoreDataStack_deallocationHandlers) {
        void(^handler)(__unsafe_unretained NSManagedObjectContext *context) = uncastedHandler;
        handler(self);
    }

    [self __SLCoreDataStackDealloc];
}

@end



@interface SLCoreDataStack ()

@property (nonatomic, strong) NSPointerArray *observingManagedObjectContexts;

@end


@implementation SLCoreDataStack
@synthesize mainThreadManagedObjectContext = _mainThreadManagedObjectContext, backgroundThreadManagedObjectContext = _backgroundThreadManagedObjectContext, managedObjectModel = _managedObjectModel, persistentStoreCoordinator = _persistentStoreCoordinator;

#pragma mark - setters and getters

- (id)mainThreadMergePolicy
{
    return NSMergeByPropertyObjectTrumpMergePolicy;
}

- (id)backgroundThreadMergePolicy
{
    return NSMergeByPropertyObjectTrumpMergePolicy;
}

#pragma mark - Initialization

+ (instancetype)newConvenientSQLiteStackWithModel:(NSString *)model inBundle:(NSBundle *)bundle
{
    NSURL *momURL = [bundle URLForResource:model withExtension:@"mom"];
    NSURL *momdURL = [bundle URLForResource:model withExtension:@"momd"];

    if (momURL && momdURL) {
        NSDate *momCreationDate = [[NSFileManager defaultManager] attributesOfItemAtPath:momURL.path error:NULL].fileCreationDate;
        NSDate *momdCreationDate = [[NSFileManager defaultManager] attributesOfItemAtPath:momdURL.path error:NULL].fileCreationDate;

        if (momCreationDate.timeIntervalSince1970 > momdCreationDate.timeIntervalSince1970) {
            NSLog(@"Found mom and momd model, will be using mom because fileCreationDate is newer");
            momdURL = nil;
        } else {
            NSLog(@"Found mom and momd model, will be using momd because fileCreationDate is newer");
            momURL = nil;
        }
    }

    NSAssert(momURL != nil || momdURL != nil, @"Neither %@.mom nor %@.momd could be found in bundle %@", model, model, bundle);
    NSURL *libraryDirectory = [[NSFileManager defaultManager] URLsForDirectory:NSLibraryDirectory
                                                                     inDomains:NSUserDomainMask].lastObject;

    NSURL *location = [libraryDirectory URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.sqlite", model]];
    return [[self alloc] initWithType:NSSQLiteStoreType location:location model:momURL ?: momdURL inBundle:bundle];
}

- (instancetype)init
{
    return [super init];
}

- (instancetype)initWithType:(NSString *)storeType location:(NSURL *)storeLocation model:(NSURL *)modelURL inBundle:(NSBundle *)bundle
{
    if (self = [super init]) {
        _storeLocation = storeLocation;
        _storeType = storeType;
        _managedObjectModelURL = modelURL;
        _bundle = bundle;

        _observingManagedObjectContexts = [NSPointerArray pointerArrayWithOptions:NSPointerFunctionsWeakMemory];

        NSString *parentDirectory = storeLocation.URLByDeletingLastPathComponent.path;
        if (![[NSFileManager defaultManager] fileExistsAtPath:parentDirectory isDirectory:NULL]) {
            NSError *error = nil;
            [[NSFileManager defaultManager] createDirectoryAtPath:parentDirectory
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&error];

            NSAssert(error == nil, @"error while creating parentDirectory '%@':\n\nerror: \"%@\"", parentDirectory, error);
        }

#if TARGET_OS_IOS
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_automaticallySaveDataStore)
                                                   name:UIApplicationWillTerminateNotification
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_automaticallySaveDataStore)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
#elif TARGET_OS_WATCH
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_automaticallySaveDataStore)
                                                   name:NSExtensionHostDidEnterBackgroundNotification
                                                   object:nil];
#endif
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - CoreData

- (NSManagedObjectModel *)managedObjectModel
{
    if (!_managedObjectModel) {
        _managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:self.managedObjectModelURL];
        NSParameterAssert(_managedObjectModel);
    }

    return _managedObjectModel;
}

- (NSManagedObjectContext *)mainThreadManagedObjectContext
{
    if (!_mainThreadManagedObjectContext) {
        _mainThreadManagedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        _mainThreadManagedObjectContext.persistentStoreCoordinator = self.persistentStoreCoordinator;
        _mainThreadManagedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_managedObjectContextDidSaveNotificationCallback:) name:NSManagedObjectContextDidSaveNotification object:_mainThreadManagedObjectContext];
    }

    return _mainThreadManagedObjectContext;
}

- (NSManagedObjectContext *)backgroundThreadManagedObjectContext
{
    if (!_backgroundThreadManagedObjectContext) {
        _backgroundThreadManagedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        _backgroundThreadManagedObjectContext.persistentStoreCoordinator = self.persistentStoreCoordinator;
        _backgroundThreadManagedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_managedObjectContextDidSaveNotificationCallback:) name:NSManagedObjectContextDidSaveNotification object:_backgroundThreadManagedObjectContext];
    }

    return _backgroundThreadManagedObjectContext;
}

- (NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
    if (!_persistentStoreCoordinator) {
        NSURL *storeURL = self.storeLocation;
        NSManagedObjectModel *managedObjectModel = self.managedObjectModel;

        if (self.requiresMigration) {
            NSError *error = nil;
            if (![self migrateDataStore:&error]) {
                NSLog(@"[SLCoreDataStack] migrating data store failed: %@", error);
            }
        }

        NSDictionary *options = @{
                                  NSMigratePersistentStoresAutomaticallyOption: @YES,
                                  NSInferMappingModelAutomaticallyOption: @YES
                                  };

        NSError *error = nil;
        _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:managedObjectModel];

        if (![_persistentStoreCoordinator addPersistentStoreWithType:self.storeType configuration:nil URL:storeURL options:options error:&error]) {
            NSLog(@"[SLCoreDataStack] could not add persistent store: %@", error);
            NSLog(@"[SLCoreDataStack] deleting old data store");

            [[NSFileManager defaultManager] removeItemAtURL:storeURL error:NULL];
            error = nil;

            if (![_persistentStoreCoordinator addPersistentStoreWithType:self.storeType configuration:nil URL:storeURL options:options error:&error]) {
                NSLog(@"[SLCoreDataStack] could not add persistent store: %@", error);
                abort();
            }
        }
    }

#ifdef DEBUG
    [self _enableCoreDataThreadDebugging];
#endif

    return _persistentStoreCoordinator;
}

- (NSManagedObjectContext *)newManagedObjectContextWithConcurrencyType:(NSManagedObjectContextConcurrencyType)concurrencyType
{
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:concurrencyType];
    context.persistentStoreCoordinator = self.persistentStoreCoordinator;
    context.mergePolicy = self.backgroundThreadMergePolicy;

    [self.observingManagedObjectContexts addPointer:(__bridge void *)context];

    __weak typeof(self) weakSelf = self;
    [context SLCoreDataStack_addDeallocationHandler:^(NSManagedObjectContext *__unsafe_unretained context) {
        __strong typeof(weakSelf) strongSelf = weakSelf;

        NSUInteger index = NSNotFound;

        for (NSUInteger i = 0; i < strongSelf.observingManagedObjectContexts.count; i++) {
            void *pointer = [strongSelf.observingManagedObjectContexts pointerAtIndex:i];

            if (pointer == (__bridge void *)context) {
                index = i;
                break;
            }
        }

        if (index != NSNotFound) {
            [strongSelf.observingManagedObjectContexts removePointerAtIndex:index];
        }

        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextDidSaveNotification object:context];
    }];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_managedObjectContextDidSaveNotificationCallback:) name:NSManagedObjectContextDidSaveNotification object:context];

    return context;
}

#pragma mark - private implementation ()

- (NSArray *)_observingManagedObjectsContexts
{
    NSMutableArray *observingManagedObjectsContexts = [NSMutableArray array];

    NSManagedObjectContext *mainThreadManagedObjectContext = self.mainThreadManagedObjectContext;
    if (mainThreadManagedObjectContext) {
        [observingManagedObjectsContexts addObject:mainThreadManagedObjectContext];
    }

    NSManagedObjectContext *backgroundThreadManagedObjectContext = self.backgroundThreadManagedObjectContext;
    if (backgroundThreadManagedObjectContext) {
        [observingManagedObjectsContexts addObject:backgroundThreadManagedObjectContext];
    }

    for (NSManagedObjectContext *context in self.observingManagedObjectContexts) {
        if (context) {
            [observingManagedObjectsContexts addObject:context];
        }
    }

    return observingManagedObjectsContexts;
}

- (void)_managedObjectContextDidSaveNotificationCallback:(NSNotification *)notification
{
    NSManagedObjectContext *changedContext = notification.object;

    for (NSManagedObjectContext *otherContext in [self _observingManagedObjectsContexts]) {
        if (changedContext.persistentStoreCoordinator == otherContext.persistentStoreCoordinator && otherContext != changedContext) {
            if (changedContext == self.backgroundThreadManagedObjectContext) {
                [otherContext performBlockAndWait:^{
                    [otherContext mergeChangesFromContextDidSaveNotification:notification];
                }];
            } else {
                [otherContext performBlock:^{
                    [otherContext mergeChangesFromContextDidSaveNotification:notification];
                }];
            }
        }
    }
}

- (void)_automaticallySaveDataStore
{
    for (NSManagedObjectContext *context in [self _observingManagedObjectsContexts]) {
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

- (void)_enableCoreDataThreadDebugging
{
    @synchronized(self) {
        NSManagedObjectModel *model = _persistentStoreCoordinator.managedObjectModel;

        for (NSEntityDescription *entity in model.entities) {
            Class class = NSClassFromString(entity.managedObjectClassName);

            if (!class || objc_getAssociatedObject(class, _cmd)) {
                continue;
            }

            IMP implementation = imp_implementationWithBlock(^(id _self, NSString *key) {
                struct objc_super super = {
                    .receiver = _self,
                    .super_class = [class superclass]
                };
                ((void(*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&super, @selector(willAccessValueForKey:), key);
            });
            class_addMethod(class, @selector(willAccessValueForKey:), implementation, "v@:@");

            implementation = imp_implementationWithBlock(^(id _self, NSString *key) {
                struct objc_super super = {
                    .receiver = _self,
                    .super_class = [class superclass]
                };
                ((void(*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&super, @selector(willChangeValueForKey:), key);
            });
            class_addMethod(class, @selector(willChangeValueForKey:), implementation, "v@:@");

            objc_setAssociatedObject(class, _cmd, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

@end



@implementation SLCoreDataStack (Singleton)

+ (instancetype)sharedInstance
{
    return nil;
}

@end



@implementation SLCoreDataStack (Migration)

- (BOOL)requiresMigration
{
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 90000
    NSDictionary *options = @{
                              NSMigratePersistentStoresAutomaticallyOption: @YES,
                              NSInferMappingModelAutomaticallyOption: @YES
                              };

    NSDictionary *sourceStoreMetadata = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:self.storeType URL:self.storeLocation options:options error:NULL];
#else
    NSDictionary *sourceStoreMetadata = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:self.storeType URL:self.storeLocation error:NULL];
#endif

    if (!sourceStoreMetadata) {
        return NO;
    }

    return ![self.managedObjectModel isConfiguration:nil compatibleWithStoreMetadata:sourceStoreMetadata];
}

- (BOOL)migrateDataStore:(NSError **)error
{
    static OSSpinLock lock = OS_SPINLOCK_INIT;

    OSSpinLockLock(&lock);
    BOOL success = [self _performMigrationFromDataStoreAtURL:self.storeLocation toDestinationModel:self.managedObjectModel error:error];
    OSSpinLockUnlock(&lock);

    return success;
}

- (BOOL)_performMigrationFromDataStoreAtURL:(NSURL *)dataStoreURL
                         toDestinationModel:(NSManagedObjectModel *)destinationModel
                                      error:(NSError **)error
{
    BOOL(^updateError)(NSInteger errorCode, NSString *description) = ^BOOL(NSInteger errorCode, NSString *description) {
        if (!error) {
            return NO;
        }

        NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: description };
        *error = [NSError errorWithDomain:SLCoreDataStackErrorDomain code:errorCode userInfo:userInfo];

        return NO;
    };

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 90000
    NSDictionary *options = @{
                              NSMigratePersistentStoresAutomaticallyOption: @YES,
                              NSInferMappingModelAutomaticallyOption: @YES
                              };

    NSDictionary *sourceStoreMetadata = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:self.storeType URL:dataStoreURL options:options error:error];
#else
    NSDictionary *sourceStoreMetadata = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:self.storeType URL:dataStoreURL error:error];
#endif

    if (!sourceStoreMetadata) {
        return NO;
    }

    if ([destinationModel isConfiguration:nil compatibleWithStoreMetadata:sourceStoreMetadata]) {
        return YES;
    }

    NSArray *bundles = @[ self.bundle ];
    NSManagedObjectModel *sourceModel = [NSManagedObjectModel mergedModelFromBundles:bundles
                                                                    forStoreMetadata:sourceStoreMetadata];

    if (!sourceModel) {
        return updateError(SLCoreDataStackManagedObjectModelNotFound, [NSString stringWithFormat:@"Unable to find NSManagedObjectModel for store metadata %@", sourceStoreMetadata]);
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
        return updateError(SLCoreDataStackManagedObjectModelNotFound, [NSString stringWithFormat:@"No NSManagedObjectModel found in bundle %@", self.bundle]);
    }

    NSMappingModel *mappingModel = nil;
    NSManagedObjectModel *targetModel = nil;
    NSString *modelPath = nil;

    for (modelPath in objectModelPaths.reverseObjectEnumerator) {
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
        return updateError(SLCoreDataStackMappingModelNotFound, [NSString stringWithFormat:@"Unable to find NSMappingModel for store at URL %@", dataStoreURL]);
    }

    NSMigrationManager *migrationManager = [[NSMigrationManager alloc] initWithSourceModel:sourceModel
                                                                          destinationModel:targetModel];

    NSString *modelName = modelPath.lastPathComponent.stringByDeletingPathExtension;
    NSString *storeExtension = dataStoreURL.path.pathExtension;

    NSString *storePath = dataStoreURL.path.stringByDeletingPathExtension;

    NSString *destinationPath = [NSString stringWithFormat:@"%@.%@.%@", storePath, modelName, storeExtension];
    NSURL *destinationURL = [NSURL fileURLWithPath:destinationPath];

    if (![migrationManager migrateStoreFromURL:dataStoreURL type:self.storeType options:nil withMappingModel:mappingModel toDestinationURL:destinationURL destinationType:self.storeType destinationOptions:nil error:error]) {
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

@end



#ifdef DEBUG
@implementation NSManagedObject (SLCoreDataStackCoreDataThreadDebugging)

+ (void)load
{
    class_swizzleSelector(self, @selector(willChangeValueForKey:), @selector(__SLCoreDataStackCoreDataThreadDebuggingWillChangeValueForKey:));
    class_swizzleSelector(self, @selector(willAccessValueForKey:), @selector(__SLCoreDataStackCoreDataThreadDebuggingWillAccessValueForKey:));
}

- (void)__SLCoreDataStackCoreDataThreadDebuggingWillAccessValueForKey:(NSString *)key
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSManagedObjectContext *context = self.managedObjectContext;

    if (context && context.concurrencyType != NSConfinementConcurrencyType) {
        __block dispatch_queue_t queue = NULL;
        [context performBlockAndWait:^{
            queue = dispatch_get_current_queue();
        }];

        NSAssert(queue == dispatch_get_current_queue(), @"wrong queue buddy");
    }

#pragma clang diagnostic pop

    [self __SLCoreDataStackCoreDataThreadDebuggingWillAccessValueForKey:key];
}

- (void)__SLCoreDataStackCoreDataThreadDebuggingWillChangeValueForKey:(NSString *)key
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSManagedObjectContext *context = self.managedObjectContext;

    if (context) {
        __block dispatch_queue_t queue = NULL;
        [context performBlockAndWait:^{
            queue = dispatch_get_current_queue();
        }];

        NSAssert(queue == dispatch_get_current_queue(), @"wrong queue buddy");
    }

#pragma clang diagnostic pop

    [self __SLCoreDataStackCoreDataThreadDebuggingWillChangeValueForKey:key];
}

@end
#endif
