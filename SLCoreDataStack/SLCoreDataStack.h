//
//  SLCoreDataStack.h
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

#import <CoreData/CoreData.h>
#import <Foundation/Foundation.h>
#import <NSManagedObjectContext+SLCoreDataStack.h>

extern NSString *const SLCoreDataStackErrorDomain;

enum {
    SLCoreDataStackMappingModelNotFound = 1,
    SLCoreDataStackManagedObjectModelNotFound
};



@interface SLCoreDataStack : NSObject

@property (nonatomic, strong) NSManagedObjectModel *managedObjectModel;
@property (nonatomic, strong) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (nonatomic, readonly) NSString *storeType;

@property (nonatomic, strong) NSManagedObjectContext *mainThreadManagedObjectContext;
@property (nonatomic, strong) NSManagedObjectContext *backgroundThreadManagedObjectContext;

/**
 returns a new NSManagedObjectContext instance which is observed by this CoreData stack and automatically merges changes between all other observing contexts. Observation ends iff the NSManagedObjectContext gets dealloced.
 */
- (NSManagedObjectContext *)newManagedObjectContextWithConcurrencyType:(NSManagedObjectContextConcurrencyType)concurrencyType;

/**
 Merge policies which will be applied to mainThreadManagedObjectContext and backgroundThreadManagedObjectContext.
 */
@property (nonatomic, readonly) id mainThreadMergePolicy;
@property (nonatomic, readonly) id backgroundThreadMergePolicy;

/**
 Return the name for your CoreData model here.

 @warning Must be overwritten.
 */
@property (nonatomic, readonly) NSString *managedObjectModelName;

/**
 The root URL in which the database will be stored. Default is NSLibraryDirectory.
 */
@property (nonatomic, readonly) NSURL *databaseRootURL;

/**
 The bundle, in with the momd file and migrations are stored.
 */
@property (nonatomic, readonly) NSBundle *bundle;

/**
 Return YES if you want to assert cases where you access NSManagedObjects on the wrong thread. Defaults to NO and can only be used if DEBUG is defined.
 */
+ (BOOL)coreDataThreadDebuggingEnabled;

@end



@interface SLCoreDataStack (Singleton)

+ (instancetype)sharedInstance;

@end


@interface SLCoreDataStack (Migration)

@property (nonatomic, readonly) BOOL requiresMigration;
- (BOOL)migrateDataStore:(NSError **)error;

@end
