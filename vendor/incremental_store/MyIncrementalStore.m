#import "MyIncrementalStore.h"

@interface MyIncrementalStoreDirectoryCreator : NSObject
@property (nonatomic, strong) NSURL *URL;
- (instancetype)initWithURL:(NSURL *)URL;
- (BOOL)createDirectoryIfNotThereError:(NSError * __autoreleasing *)error;
@end

@interface MyIncrementalStore () <NSFilePresenter>
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@end

static dispatch_queue_t backgroundQueue = nil;

@implementation MyIncrementalStore

#pragma mark - Setup

+ (NSString *)type
{
    return NSStringFromClass([self class]);
}

- (id)initWithPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)root
                       configurationName:(NSString *)name
                                     URL:(NSURL *)url
                                 options:(NSDictionary *)options
{
    self = [super initWithPersistentStoreCoordinator:root configurationName:name URL:url options:options];
    if (self) {
        [NSFileCoordinator addFilePresenter:self];
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            backgroundQueue = dispatch_queue_create("net.cocoamanifest.file-watcher-queue", DISPATCH_QUEUE_CONCURRENT);
        });
    }
    return self;
}


#pragma mark - NSFilePresenter Methods

- (NSURL *)presentedItemURL
{
    return [self URL];
}

- (NSOperationQueue *)presentedItemOperationQueue
{
    return [NSOperationQueue mainQueue];
}

- (void)presentedSubitemDidChangeAtURL:(NSURL *)url
{
    dispatch_async(backgroundQueue, ^{
        if (![[url.path pathExtension] isEqualToString:@"txt"]) return;

        NSError *error = nil;
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:self];
        [coordinator coordinateReadingItemAtURL:url options:NSFileCoordinatorReadingResolvesSymbolicLink error:&error byAccessor:^(NSURL *newURL) {

            NSEntityDescription *entity = [NSEntityDescription entityForName:@"JournalEntry" inManagedObjectContext:self.rootContext];
            NSManagedObjectID *objectID = [self newObjectIDForEntity:entity referenceObject:[self _referenceObjectForFileURL:newURL]];

            BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:newURL.path];
            if (exists) {
                [self _tellRootContextThatObjectIDChanged:objectID];
            } else {
                [self _tellRootContextThatObjectIDDisappeared:objectID];
            }

        }];

        if (error) {
            NSLog(@"Error responding to presented subitem: %@, %@", error, [error userInfo]);
        }
    });
}

#pragma mark - Helper Methods For NSFilePresenter Stuff

- (void)_tellRootContextThatObjectIDChanged:(NSManagedObjectID *)objectID
{
    [self.rootContext performBlockAndWait:^{
        NSError *error = nil;
        NSManagedObject *object = [self.rootContext existingObjectWithID:objectID error:&error];
        if (object) {
            [self.rootContext refreshObject:object mergeChanges:NO];
        } else {
            NSLog(@"Could not refresh object: %@, %@", error, [error userInfo]);
        }
    }];
}

- (void)_tellRootContextThatObjectIDDisappeared:(NSManagedObjectID *)objectID
{
    [self.rootContext performBlockAndWait:^{
        NSError *error = nil;
        NSManagedObject *object = [self.rootContext objectWithID:objectID];
        [self.rootContext deleteObject:object];
        if (![self.rootContext save:&error]) {
            NSLog(@"Unable to update root context when removing object: %@, %@", error, [error userInfo]);
        }
    }];
}



#pragma mark - NSIncrementalStore Methods

- (BOOL)loadMetadata:(NSError *__autoreleasing *)error
{
    [self setMetadata:@{
       NSStoreUUIDKey: [[NSProcessInfo processInfo] globallyUniqueString],
       NSStoreTypeKey: NSStringFromClass([self class])
     }];
    MyIncrementalStoreDirectoryCreator *creator = [[MyIncrementalStoreDirectoryCreator alloc] initWithURL:self.URL];
    return [creator createDirectoryIfNotThereError:error];
}

- (id)executeRequest:(NSPersistentStoreRequest *)request
         withContext:(NSManagedObjectContext *)context
               error:(NSError *__autoreleasing *)error
{
    switch (request.requestType) {
        case NSFetchRequestType:
            return [self _executeFetchRequest:(NSFetchRequest *)request
                                  withContext:context
                                        error:error];
            break;

        case NSSaveRequestType:
            return [self _executeSaveRequest:(NSSaveChangesRequest *)request
                                 withContext:context
                                       error:error];
            break;

        default:
            NSLog(@"Unknown fetch request type: %d", request.requestType);
            abort();
            break;
    }
}

- (NSIncrementalStoreNode *)newValuesForObjectWithID:(NSManagedObjectID *)objectID
                                         withContext:(NSManagedObjectContext *)context
                                               error:(NSError *__autoreleasing *)error
{
    NSString *referenceObject = [self referenceObjectForObjectID:objectID];
    NSURL *url = [self _fileURLForReferenceObject:referenceObject];
    __block NSString *contents = nil;

    void (^accessor)(NSURL *newURL) = ^(NSURL *newURL) {
        contents = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:error];
    };

    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:self];
    [coordinator coordinateReadingItemAtURL:url
                                    options:NSFileCoordinatorReadingResolvesSymbolicLink
                                      error:error
                                 byAccessor:accessor];

    return [self _decodeDataString:contents forObjectID:objectID];
}

- (id)newValueForRelationship:(NSRelationshipDescription *)relationship
              forObjectWithID:(NSManagedObjectID *)objectID
                  withContext:(NSManagedObjectContext *)context
                        error:(NSError *__autoreleasing *)error
{
    NSAssert(false, @"Not Supported");
    return nil;
}

- (NSArray *)obtainPermanentIDsForObjects:(NSArray *)objects
                                    error:(NSError *__autoreleasing *)error
{
    NSMutableArray *ids = [NSMutableArray array];

    for (NSManagedObject *object in objects) {
        NSString *guid = [[NSProcessInfo processInfo] globallyUniqueString];
        NSString *name = [NSString stringWithFormat:@"%@.txt", guid];
        NSURL *url = [[self URL] URLByAppendingPathComponent:name];
        NSString *referenceObject = [self _referenceObjectForFileURL:url];
        [ids addObject:[self newObjectIDForEntity:object.entity referenceObject:referenceObject]];
    }
    return ids;
}

- (NSDateFormatter *)dateFormatter
{
    if (_dateFormatter) return _dateFormatter;

    _dateFormatter = [[NSDateFormatter alloc] init];
    [_dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];

    return _dateFormatter;
}


#pragma mark - Helper methods for NSIncrementalStore Stuff

- (id)_executeFetchRequest:(NSFetchRequest *)request
               withContext:(NSManagedObjectContext *)context
                     error:(NSError * __autoreleasing *)error
{
    NSEntityDescription *entity = [(NSFetchRequest *)request entity];
    NSMutableArray *results = [NSMutableArray array];

    void (^accessor)(NSURL *newURL) = ^(NSURL *newURL) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSDirectoryEnumerator *enumerator =
        [fileManager enumeratorAtURL:newURL
          includingPropertiesForKeys:nil
                             options:NSDirectoryEnumerationSkipsSubdirectoryDescendants | NSDirectoryEnumerationSkipsHiddenFiles
                        errorHandler:^BOOL(NSURL *url, NSError *blockError) {
                            *error = blockError;
                            return NO;
                        }];


        for (NSURL *fileURL in enumerator) {
            if (![[fileURL.path pathExtension] isEqualToString:@"txt"]) continue;

            __block NSManagedObject *managedObject = nil;
            NSManagedObjectID *objectID = [self newObjectIDForEntity:entity referenceObject:[self _referenceObjectForFileURL:fileURL]];

            if (request.resultType == NSManagedObjectIDResultType) {
                [results addObject:objectID];
            } else {
                managedObject = [context existingObjectWithID:objectID error:error];
                if (!managedObject) return;

                [results addObject:managedObject];
            }
        }
    };

    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:self];
    [coordinator coordinateReadingItemAtURL:[self URL]
                                    options:NSFileCoordinatorReadingResolvesSymbolicLink
                                      error:error
                                 byAccessor:accessor];

    if (error && *error) return nil;

    return [results sortedArrayUsingDescriptors:request.sortDescriptors];
}

- (id)_executeSaveRequest:(NSSaveChangesRequest *)request
              withContext:(NSManagedObjectContext *)context
                    error:(NSError * __autoreleasing *)error
{
    if (![self _storeObjects:((NSSaveChangesRequest *)request).insertedObjects
                 withContext:context
                       error:error] ||
        ![self _storeObjects:((NSSaveChangesRequest *)request).updatedObjects
                 withContext:context
                       error:error] ||
        ![self _removeObjects:((NSSaveChangesRequest *)request).deletedObjects
                  withContext:context
                        error:error]) {
            return nil;
        } else {
            return @[];
        }
}


- (BOOL)_storeObjects:(NSSet *)objects
          withContext:(NSManagedObjectContext *)context
                error:(NSError * __autoreleasing *)error
{
    if (objects == nil) return YES;

    for (NSManagedObject *object in objects) {
        NSString *referenceObject = [self referenceObjectForObjectID:object.objectID];
        NSURL *url = [self _fileURLForReferenceObject:referenceObject];
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:self];
        __block BOOL success = NO;
        [coordinator coordinateWritingItemAtURL:url options:NSFileCoordinatorWritingForReplacing error:error byAccessor:^(NSURL *newURL) {
            NSString *contents = [self _encodeObject:object];
            success = [contents writeToURL:newURL atomically:YES encoding:NSUTF8StringEncoding error:error];
        }];

        if (!success) return NO;
    }
    return YES;
}

- (BOOL)_removeObjects:(NSSet *)objects
           withContext:(NSManagedObjectContext *)context
                 error:(NSError * __autoreleasing *)error
{
    if (objects == nil) return YES;

    for (NSManagedObject *object in objects) {
        NSString *referenceObject = [self referenceObjectForObjectID:object.objectID];
        NSURL *url = [self _fileURLForReferenceObject:referenceObject];
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:self];
        __block BOOL success = NO;
        [coordinator coordinateWritingItemAtURL:url options:NSFileCoordinatorWritingForDeleting error:error byAccessor:^(NSURL *newURL) {
            NSFileManager *manager = [NSFileManager defaultManager];
            if ([manager fileExistsAtPath:newURL.path]) {
                success = [[NSFileManager defaultManager] removeItemAtURL:newURL error:error];
            } else {
                // If file doesn't exist, it must have vanished. Nothing to delete.
                success = YES;
            }
        }];

        if (!success) return NO;
    }
    return YES;
}

- (NSString *)_encodeObject:(NSManagedObject *)object
{
    return [@"" stringByAppendingFormat:@"%@\n%@",
            [self.dateFormatter stringFromDate:[object valueForKey:@"timestamp"]],
            [object valueForKey:@"content"]];
}

- (NSIncrementalStoreNode *)_decodeDataString:(NSString *)dataString
                                  forObjectID:(NSManagedObjectID *)objectID
{
    NSMutableDictionary *values = [NSMutableDictionary dictionary];

    NSString *referenceObject = [self referenceObjectForObjectID:objectID];
    NSURL *fileURL = [self _fileURLForReferenceObject:referenceObject];

    // Set up some defaults if there is an error trying to read from file
    values[@"timestamp"] = NSDate.date;
    values[@"content"] = [NSString stringWithFormat:@"!! bad file %@", [fileURL.path lastPathComponent]];

    NSRange firstLineRange = [dataString rangeOfString:@"\n"];
    if (firstLineRange.location != NSNotFound || [dataString length] < firstLineRange.length) {
        NSString *dateString = [dataString substringToIndex:firstLineRange.location];
        NSDate *timestamp = [self.dateFormatter dateFromString:dateString];
        if (timestamp) {
            values[@"timestamp"] = timestamp;
            NSString *content = [dataString substringFromIndex:firstLineRange.location+1];
            values[@"content"] = content;
        }
    }

    return [[NSIncrementalStoreNode alloc] initWithObjectID:objectID
                                                 withValues:values
                                                    version:0];
}

- (NSString *)_referenceObjectForFileURL:(NSURL *)fileURL
{
    return fileURL.lastPathComponent;
}

- (NSURL *)_fileURLForReferenceObject:(NSString *)referenceString
{
    return [[self URL] URLByAppendingPathComponent:referenceString];
}

@end

@implementation MyIncrementalStoreDirectoryCreator

- (instancetype)initWithURL:(NSURL *)URL
{
    self = [super init];
    if (self) {
        _URL = URL;
    }
    return self;
}

- (BOOL)createDirectoryIfNotThereError:(NSError * __autoreleasing *)error
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSFileCoordinator *existenceCoordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];

    BOOL __block URLExists = NO;
    BOOL __block URLIsDirectory = NO;

    void (^existenceAccessor)(NSURL *newURL) = ^(NSURL *newURL) {
        URLExists = [fileManager fileExistsAtPath:newURL.path
                                      isDirectory:&URLIsDirectory];
    };
    [existenceCoordinator coordinateReadingItemAtURL:self.URL
                                             options:0
                                               error:error
                                          byAccessor:existenceAccessor];

    if (*error) return NO;

    if (!URLExists) {
        return [self createDirectory:error];
    } else if (!URLIsDirectory) {
        NSString *key = [NSString stringWithFormat:@"The destination for MyIncrementalStore is not a directory (%@)", self.URL];
        NSString *localizedDescription = NSLocalizedString(key, nil);
        *error = [NSError errorWithDomain:@"MyIncrementalStore" code:1 userInfo:@{NSLocalizedDescriptionKey: localizedDescription}];
        return NO;
    }

    return YES;
}

- (BOOL)createDirectory:(NSError * __autoreleasing *)error
{
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];

    BOOL __block success = NO;

    void (^accessor)(NSURL *newURL)  = ^(NSURL *newURL) {
        success = [[NSFileManager defaultManager] createDirectoryAtURL:newURL
                                           withIntermediateDirectories:YES
                                                            attributes:nil
                                                                 error:error];
    };

    [coordinator coordinateWritingItemAtURL:self.URL
                                    options:NSFileCoordinatorWritingForReplacing
                                      error:error
                                 byAccessor:accessor];

    if (!success || *error) return NO;

    return YES;
}

@end
