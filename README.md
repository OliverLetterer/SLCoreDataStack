# SLCoreDataStack

`SLCoreDataStack` provides a CoreData stack managing two `NSManagedObjectContext`'s for you:

* `SLCoreDataStack.backgroundThreadManagedObjectContext` with `NSPrivateQueueConcurrencyType`: Perform any changes to any CoreData model you are making here with the `-[NSManagedObjectContext performBlock:]` API.
* `SLCoreDataStack.mainThreadManagedObjectContext` with `NSMainQueueConcurrencyType`: Use this context for displaying models in your UI.
* `SLCoreDataStack` keeps these contexts is sync by automatically merging changes between them.
* `SLCoreDataStack` supports automatic database migrations. For example: If you have three different model versions, then you can provide one migration from version 1 to version 2 and one migration from version 2 to version 3. `SLCoreDataStack` will find and detect available migrations and migrate an existing database under the hood for you.

Check out [this blog post](http://floriankugler.com/blog/2013/4/29/concurrent-core-data-stack-performance-shootout) on why we chose this `NSManagedObjectContext` concept.

## Getting started

```objc
NSURL *location = ...; // url to database.sqlite
NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"MyModel" withExtension:@"momd"];

SLCoreDataStack *stack = [[SLCoreDataStack alloc] initWithType:NSSQLiteStoreType
    location:location
    model:modelURL
    inBundle:[NSBundle mainBundle]];
```

Store the stack somewhere and make it accessible as needed. You are ready to go :)

## License

MIT
