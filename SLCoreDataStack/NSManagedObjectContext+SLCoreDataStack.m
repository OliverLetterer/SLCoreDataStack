//
//  NSManagedObjectContext+SLRESTfulCoreData.m
//  SLRESTfulCoreData
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

#import "NSManagedObjectContext+SLCoreDataStack.h"

static id managedObjectIDCollector(id object)
{
    if ([object isKindOfClass:[NSArray class]]) {
        NSArray *array = object;
        NSMutableArray *newArray = [NSMutableArray arrayWithCapacity:array.count];

        for (id managedObject in array) {
            [newArray addObject:managedObjectIDCollector(managedObject)];
        }

        return newArray;
    } else if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = object;
        NSMutableDictionary *newDictionary = [NSMutableDictionary dictionaryWithCapacity:dictionary.count];

        for (id key in dictionary) {
            newDictionary[key] = managedObjectIDCollector(dictionary[key]);
        }

        return newDictionary;
    } else if ([object isKindOfClass:[NSManagedObject class]]) {
        return [object objectID];
    } else if ([object isKindOfClass:[NSManagedObjectID class]]) {
        return object;
    } else if (!object) {
        return nil;
    }

    NSCAssert(NO, @"%@ is unsupported by performBlock:withObject:", object);
    return nil;
}

static id managedObjectCollector(id objectIDs, NSManagedObjectContext *context, NSError **error)
{
    if ([objectIDs isKindOfClass:[NSArray class]]) {
        NSArray *array = objectIDs;
        NSMutableArray *newArray = [NSMutableArray arrayWithCapacity:array.count];

        for (id object in array) {
            NSError *localError = nil;
            id result = managedObjectCollector(object, context, &localError);

            if (localError) {
                *error = localError;
                return nil;
            }

            [newArray addObject:result];
        }

        return newArray;
    } else if ([objectIDs isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = objectIDs;
        NSMutableDictionary *newDictionary = [NSMutableDictionary dictionaryWithCapacity:dictionary.count];

        for (id key in dictionary) {
            NSError *localError = nil;
            id result = managedObjectCollector(dictionary[key], context, &localError);

            if (localError) {
                *error = localError;
                return nil;
            }

            newDictionary[key] = result;
        }

        return newDictionary;
    } else if ([objectIDs isKindOfClass:[NSManagedObjectID class]]) {
        NSError *localError = nil;
        NSManagedObject *managedObject = [context existingObjectWithID:objectIDs error:&localError];

        if (localError) {
            *error = localError;
            return nil;
        }

        return managedObject;
    } else if (!objectIDs) {
        return nil;
    }

    NSCAssert(NO, @"%@ is unsupported by performBlock:withObject:", objectIDs);
    return nil;
}



@implementation NSManagedObjectContext (SLCoreDataStack)

- (void)performBlock:(void (^)(id object, NSError *error))block withObject:(id)object
{
    id objectIDs = managedObjectIDCollector(object);

    [self performBlock:^{
        NSError *error = nil;

        if (block) {
            block(managedObjectCollector(objectIDs, self, &error), error);
        }
    }];
}

- (void)performUnsafeBlock:(void (^)(id object))block withObject:(id)object
{
    NSArray *callStackSymbols = [NSThread callStackSymbols];

    [self performBlock:^(id object, NSError *error) {
        if (error != nil) {
            [NSException raise:NSInternalInconsistencyException format:@"performUnsafeBlock raised an error: %@, call stack: %@", error, callStackSymbols];
        }

        if (block) {
            block(object);
        }
    } withObject:object];
}

@end
