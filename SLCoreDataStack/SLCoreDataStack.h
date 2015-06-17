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

#import <CoreData/CoreData.h>
#import <Foundation/Foundation.h>
#import <SLCoreDataStack/NSManagedObjectContext+SLCoreDataStack.h>

extern NSString *const SLCoreDataStackErrorDomain;

enum {
    SLCoreDataStackMappingModelNotFound = 1,
    SLCoreDataStackManagedObjectModelNotFound
};



@interface SLCoreDataStack : NSObject

@property (nonatomic, readonly) NSBundle *bundle;

@property (nonatomic, readonly) NSString *storeType;
@property (nonatomic, readonly) NSURL *storeLocation;

@property (nonatomic, readonly) NSURL *managedObjectModelURL;
@property (nonatomic, readonly) NSManagedObjectModel *managedObjectModel;
@property (nonatomic, readonly) NSPersistentStoreCoordinator *persistentStoreCoordinator;

@property (nonatomic, readonly) NSManagedObjectContext *mainThreadManagedObjectContext;
@property (nonatomic, readonly) NSManagedObjectContext *backgroundThreadManagedObjectContext;

- (instancetype)init NS_DESIGNATED_INITIALIZER NS_UNAVAILABLE;
- (instancetype)initWithType:(NSString *)storeType location:(NSURL *)storeLocation model:(NSURL *)modelURL inBundle:(NSBundle *)bundle NS_DESIGNATED_INITIALIZER;

+ (instancetype)newConvenientSQLiteStackWithModel:(NSString *)model inBundle:(NSBundle *)bundle;

@end



@interface SLCoreDataStack (Singleton)

+ (instancetype)sharedInstance NS_UNAVAILABLE;

@end


@interface SLCoreDataStack (Migration)

@property (nonatomic, readonly) BOOL requiresMigration;
- (BOOL)migrateDataStore:(NSError **)error;

@end
