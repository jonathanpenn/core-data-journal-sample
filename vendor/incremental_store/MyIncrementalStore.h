#import <CoreData/CoreData.h>

@interface MyIncrementalStore : NSIncrementalStore

@property (nonatomic, weak) NSManagedObjectContext *rootContext;

+ (NSString *)type;

@end
