#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const LumiCatalogDidUpdateNotification;

@interface LumiCatalogStore : NSObject

+ (instancetype)sharedStore;

@property (nonatomic, copy, readonly) NSArray<NSDictionary *> *characters;
@property (nonatomic, copy, readonly) NSArray<NSDictionary *> *stories;
@property (nonatomic, copy, readonly) NSArray<NSString *> *characterTags;
@property (nonatomic, copy, readonly) NSArray<NSString *> *storyTags;

@property (nonatomic, assign, readonly) BOOL isSyncing;
@property (nonatomic, assign, readonly) NSUInteger syncedCharacterCount;
@property (nonatomic, assign, readonly) NSUInteger totalCharacterCount;
@property (nonatomic, copy, readonly, nullable) NSString *syncStatus;

/// Ordered genre chips (Все first, then popular genres).
+ (NSArray<NSString *> *)characterGenres;
+ (NSArray<NSString *> *)storyGenres;

/// Loads the on-disk cache and starts a sync when it is missing or stale.
- (void)startIfNeeded;
- (void)forceRefresh;
- (void)refreshInBackgroundIfStale;

- (NSArray<NSDictionary *> *)charactersMatchingQuery:(nullable NSString *)query tag:(nullable NSString *)tag;
- (NSArray<NSDictionary *> *)storiesMatchingQuery:(nullable NSString *)query tag:(nullable NSString *)tag;

- (nullable NSDictionary *)characterWithID:(nullable NSString *)identifier;
- (nullable NSDictionary *)storyWithID:(nullable NSString *)identifier;

@end

NS_ASSUME_NONNULL_END
