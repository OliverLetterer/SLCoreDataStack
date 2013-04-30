# SLCoreDataStack

`SLCoreDataStack` provides a CoreData stack managing two `NSManagedObjectContext`'s for you:

* `-[SLCoreDataStack backgroundThreadManagedObjectContext]` with `NSPrivateQueueConcurrencyType`: Perform any changes to any CoreData model you are making here with the `-[NSManagedObjectContext performBlock:]` API.
* `-[SLCoreDataStack mainThreadManagedObjectContext]` with `NSMainQueueConcurrencyType`: Use this context for displaying models to the UI.
* `SLCoreDataStack` keeps these contexts is sync by automatically merging changes between them.
* `SLCoreDataStack` supports automatic database migrations. For example: If you have three different model versions, then you can provide one migration from version 1 to version 2 and one migration from version 2 to version 3. `SLCoreDataStack` will find and detect available migrations and migrate an existing database under the hood for you.

Check out [this blog post](http://floriankugler.com/blog/2013/4/29/concurrent-core-data-stack-performance-shootout) on why we chose this `NSManagedObjectContext` concept.

## Getting started

Subclass `SLCoreDataStack` and implement `managedObjectModelName`:

```
@interface GHDataStoreManager : SLCoreDataStack

@end

@implementation GHDataStoreManager

- (NSString *)managedObjectModelName
{
    return @"GithubAPI";
}

@end
```

You are good to go now :)

## License

MIT
