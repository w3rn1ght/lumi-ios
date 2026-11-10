#import "LumiCatalogStore.h"
#import "LumiAPI.h"

NSString *const LumiCatalogDidUpdateNotification = @"LumiCatalogDidUpdateNotification";

static NSString *const kCatalogFileName = @"catalog-v2.json";
static const NSTimeInterval kCatalogMaxAge = 12 * 60 * 60;
static const NSUInteger kDetailConcurrency = 6;

@interface LumiCatalogStore ()
@property (nonatomic, copy, readwrite) NSArray<NSDictionary *> *characters;
@property (nonatomic, copy, readwrite) NSArray<NSDictionary *> *stories;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *characterTags;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *storyTags;
@property (nonatomic, assign, readwrite) BOOL isSyncing;
@property (nonatomic, assign, readwrite) NSUInteger syncedCharacterCount;
@property (nonatomic, assign, readwrite) NSUInteger totalCharacterCount;
@property (nonatomic, copy, readwrite, nullable) NSString *syncStatus;
@property (nonatomic, strong) LumiAPI *api;
@property (nonatomic, strong, nullable) NSDate *savedAt;
@property (nonatomic, strong) dispatch_queue_t stateQueue;
@property (nonatomic, assign) BOOL started;
@property (nonatomic, assign) NSUInteger pendingCharacterDetailCount;
@end

@implementation LumiCatalogStore

+ (instancetype)sharedStore {
    static LumiCatalogStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[LumiCatalogStore alloc] init];
    });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _api = [LumiAPI sharedClient];
        _characters = @[];
        _stories = @[];
        _characterTags = @[];
        _storyTags = @[];
        _stateQueue = dispatch_queue_create("com.w3rn1ght.lumi.catalog", DISPATCH_QUEUE_SERIAL);
        _syncStatus = nil;
    }
    return self;
}

+ (NSArray<NSString *> *)characterGenres {
    return @[@"Все", @"Романтика", @"Аниме", @"Школа/Универ", @"Фэнтези", @"Драма",
             @"Юмор", @"Мистика", @"Хоррор", @"Приключения", @"Экшен", @"Детектив",
             @"Фантастика", @"Постапокалипсис", @"Девушка", @"Мужчина", @"Фандом"];
}

+ (NSArray<NSString *> *)storyGenres {
    return @[@"Все", @"Романтика", @"Фэнтези", @"Драма", @"Детектив", @"Приключения",
             @"Мистика", @"Хоррор", @"Аниме", @"Школа/Универ", @"Фантастика",
             @"Постапокалипсис", @"Экшен", @"Юмор"];
}

#pragma mark - Cache

- (NSString *)cachePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *base = [paths firstObject] ?: NSTemporaryDirectory();
    NSString *directory = [base stringByAppendingPathComponent:@"Lumi"];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return [directory stringByAppendingPathComponent:kCatalogFileName];
}

- (void)loadCache {
    NSData *data = [NSData dataWithContentsOfFile:[self cachePath]];
    if (!data.length) {
        return;
    }
    NSDictionary *dictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSArray *characters = dictionary[@"characters"];
    NSArray *stories = dictionary[@"stories"];
    if ([characters isKindOfClass:[NSArray class]]) {
        self.characters = characters;
    }
    if ([stories isKindOfClass:[NSArray class]]) {
        self.stories = stories;
    }
    NSArray *characterTags = dictionary[@"character_tags"];
    NSArray *storyTags = dictionary[@"story_tags"];
    if ([characterTags isKindOfClass:[NSArray class]]) {
        self.characterTags = characterTags;
    }
    if ([storyTags isKindOfClass:[NSArray class]]) {
        self.storyTags = storyTags;
    }
    NSNumber *timestamp = dictionary[@"saved_at"];
    if ([timestamp isKindOfClass:[NSNumber class]]) {
        self.savedAt = [NSDate dateWithTimeIntervalSince1970:timestamp.doubleValue];
    }
    NSLog(@"[Lumi] catalog cache loaded: %lu characters, %lu stories",
          (unsigned long)self.characters.count, (unsigned long)self.stories.count);
}

- (void)saveCache {
    NSDictionary *dictionary = @{
        @"saved_at": @([[NSDate date] timeIntervalSince1970]),
        @"characters": self.characters ?: @[],
        @"stories": self.stories ?: @[],
        @"character_tags": self.characterTags ?: @[],
        @"story_tags": self.storyTags ?: @[],
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:NULL];
    if (data) {
        [data writeToFile:[self cachePath] atomically:YES];
        self.savedAt = [NSDate date];
    }
}

- (BOOL)isStale {
    if (!self.savedAt) {
        return YES;
    }
    return -[self.savedAt timeIntervalSinceNow] > kCatalogMaxAge;
}

- (void)notifyUpdate {
    [[NSNotificationCenter defaultCenter] postNotificationName:LumiCatalogDidUpdateNotification object:self];
}

#pragma mark - Sync

- (void)startIfNeeded {
    if (self.started) {
        return;
    }
    self.started = YES;
    [self loadCache];
    [self notifyUpdate];
    if (self.isStale || self.characters.count < 100) {
        [self forceRefresh];
    }
}

- (void)refreshInBackgroundIfStale {
    if (self.isStale && !self.isSyncing) {
        [self forceRefresh];
    }
}

- (void)forceRefresh {
    if (self.isSyncing) {
        return;
    }
    self.isSyncing = YES;
    self.syncStatus = @"Загрузка каталога…";
    self.syncedCharacterCount = 0;
    self.totalCharacterCount = 0;
    [self notifyUpdate];
    [self syncTags];
    [self syncCharacterIDs];
}

- (void)syncTags {
    [self.api fetchTagsWithCompletion:^(id result, NSError *error) {
        if ([result isKindOfClass:[NSDictionary class]]) {
            NSArray *characterTags = result[@"character_tags"];
            NSArray *storyTags = result[@"story_tags"];
            if ([characterTags isKindOfClass:[NSArray class]]) {
                self.characterTags = characterTags;
            }
            if ([storyTags isKindOfClass:[NSArray class]]) {
                self.storyTags = storyTags;
            }
            [self notifyUpdate];
        }
    }];
}

- (void)syncCharacterIDs {
    [self.api fetchCharacterIDsWithCompletion:^(id result, NSError *error) {
        if (![result isKindOfClass:[NSArray class]]) {
            self.isSyncing = NO;
            self.syncStatus = error.localizedDescription ?: @"Не удалось загрузить каталог";
            [self notifyUpdate];
            return;
        }
        NSArray<NSDictionary *> *items = result;
        NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:items.count];
        for (NSDictionary *item in items) {
            id identifier = item[@"id"];
            if ([identifier isKindOfClass:[NSString class]]) {
                [ids addObject:identifier];
            }
        }
        self.totalCharacterCount = ids.count;
        NSMutableDictionary *known = [NSMutableDictionary dictionary];
        for (NSDictionary *character in self.characters) {
            id identifier = character[@"id"];
            if ([identifier isKindOfClass:[NSString class]] && character[@"name"]) {
                known[identifier] = character;
            }
        }
        NSMutableArray<NSString *> *missing = [NSMutableArray array];
        for (NSString *identifier in ids) {
            if (!known[identifier]) {
                [missing addObject:identifier];
            }
        }
        NSLog(@"[Lumi] catalog: %lu ids, %lu missing details", (unsigned long)ids.count, (unsigned long)missing.count);
        NSMutableArray *merged = [NSMutableArray array];
        for (NSString *identifier in ids) {
            NSDictionary *existing = known[identifier];
            if (existing) {
                [merged addObject:existing];
            }
        }
        if (merged.count) {
            self.characters = [self sortedCharacters:merged];
        }
        [self notifyUpdate];

        if (!missing.count) {
            [self syncStoryIDs];
            return;
        }
        __block NSUInteger completed = 0;
        NSUInteger total = missing.count;
        dispatch_group_t group = dispatch_group_create();
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(kDetailConcurrency);
        __weak typeof(self) weakSelf = self;
        for (NSString *identifier in missing) {
            dispatch_group_enter(group);
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
                [weakSelf.api fetchCharacterWithID:identifier completion:^(id result, NSError *error) {
                    if ([result isKindOfClass:[NSDictionary class]]) {
                        [weakSelf addCharacterDetail:result];
                    }
                    dispatch_semaphore_signal(semaphore);
                    completed++;
                    if (completed % 25 == 0 || completed == total) {
                        weakSelf.syncedCharacterCount = completed;
                        weakSelf.syncStatus = [NSString stringWithFormat:@"Загрузка персонажей… %lu из %lu",
                                               (unsigned long)completed, (unsigned long)total];
                        [weakSelf notifyUpdate];
                        if (completed % 150 == 0) {
                            [weakSelf saveCache];
                        }
                    }
                    dispatch_group_leave(group);
                }];
            });
        }
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            weakSelf.syncedCharacterCount = total;
            [weakSelf saveCache];
            [weakSelf syncStoryIDs];
        });
    }];
}

- (void)syncStoryIDs {
    self.syncStatus = @"Загрузка историй…";
    [self notifyUpdate];
    [self.api fetchStoryIDsWithCompletion:^(id result, NSError *error) {
        if (![result isKindOfClass:[NSArray class]]) {
            self.isSyncing = NO;
            self.syncStatus = nil;
            [self saveCache];
            [self notifyUpdate];
            return;
        }
        NSArray<NSDictionary *> *items = result;
        NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:items.count];
        for (NSDictionary *item in items) {
            id identifier = item[@"id"];
            if ([identifier isKindOfClass:[NSString class]]) {
                [ids addObject:identifier];
            }
        }
        NSMutableDictionary *known = [NSMutableDictionary dictionary];
        for (NSDictionary *story in self.stories) {
            id identifier = story[@"id"];
            if ([identifier isKindOfClass:[NSString class]] && story[@"title"]) {
                known[identifier] = story;
            }
        }
        NSMutableArray<NSString *> *missing = [NSMutableArray array];
        NSMutableArray *merged = [NSMutableArray array];
        for (NSString *identifier in ids) {
            if (known[identifier]) {
                [merged addObject:known[identifier]];
            } else {
                [missing addObject:identifier];
            }
        }
        self.stories = [self sortedStories:merged];
        [self notifyUpdate];

        if (!missing.count) {
            self.isSyncing = NO;
            self.syncStatus = nil;
            [self saveCache];
            [self notifyUpdate];
            return;
        }

        __block NSUInteger completed = 0;
        NSUInteger total = missing.count;
        dispatch_group_t group = dispatch_group_create();
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(kDetailConcurrency);
        __weak typeof(self) weakSelf = self;
        for (NSString *identifier in missing) {
            dispatch_group_enter(group);
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
                [weakSelf.api fetchStoryWithID:identifier completion:^(id result, NSError *error) {
                    if ([result isKindOfClass:[NSDictionary class]]) {
                        [weakSelf addStoryDetail:result];
                    }
                    dispatch_semaphore_signal(semaphore);
                    completed++;
                    if (completed % 20 == 0 || completed == total) {
                        weakSelf.syncStatus = [NSString stringWithFormat:@"Загрузка историй… %lu из %lu",
                                               (unsigned long)completed, (unsigned long)total];
                        [weakSelf notifyUpdate];
                        if (completed % 100 == 0) {
                            [weakSelf saveCache];
                        }
                    }
                    dispatch_group_leave(group);
                }];
            });
        }
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            weakSelf.isSyncing = NO;
            weakSelf.syncStatus = nil;
            [weakSelf saveCache];
            [weakSelf notifyUpdate];
            NSLog(@"[Lumi] catalog sync finished: %lu characters, %lu stories",
                  (unsigned long)weakSelf.characters.count, (unsigned long)weakSelf.stories.count);
        });
    }];
}

#pragma mark - Detail handling

- (void)addCharacterDetail:(NSDictionary *)detail {
    NSString *identifier = detail[@"id"];
    if (![identifier isKindOfClass:[NSString class]]) {
        return;
    }
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    entry[@"id"] = identifier;
    entry[@"name"] = detail[@"name"] ?: @"Персонаж";
    if (detail[@"avatar_url"]) {
        entry[@"avatar_url"] = detail[@"avatar_url"];
    }
    if (detail[@"tagline"]) {
        entry[@"tagline"] = detail[@"tagline"];
    }
    if ([detail[@"tags"] isKindOfClass:[NSArray class]]) {
        entry[@"tags"] = detail[@"tags"];
    }
    if ([detail[@"message_count"] isKindOfClass:[NSNumber class]]) {
        entry[@"message_count"] = detail[@"message_count"];
    }
    if (detail[@"owner"][@"username"]) {
        entry[@"owner"] = @{@"username": detail[@"owner"][@"username"]};
    }
    dispatch_sync(self.stateQueue, ^{
        NSMutableArray *characters = [self.characters mutableCopy] ?: [NSMutableArray array];
        NSUInteger existingIndex = NSNotFound;
        for (NSUInteger index = 0; index < characters.count; index++) {
            if ([characters[index][@"id"] isEqual:identifier]) {
                existingIndex = index;
                break;
            }
        }
        if (existingIndex != NSNotFound) {
            [characters replaceObjectAtIndex:existingIndex withObject:entry];
        } else {
            [characters addObject:entry];
        }
        self.characters = characters;
    });
}

- (void)addStoryDetail:(NSDictionary *)detail {
    NSString *identifier = detail[@"id"];
    if (![identifier isKindOfClass:[NSString class]]) {
        return;
    }
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    entry[@"id"] = identifier;
    entry[@"title"] = detail[@"title"] ?: @"История";
    if (detail[@"avatar_url"]) {
        entry[@"avatar_url"] = detail[@"avatar_url"];
    }
    NSString *description = detail[@"description"];
    if ([description isKindOfClass:[NSString class]] && description.length > 400) {
        description = [[description substringToIndex:400] stringByAppendingString:@"…"];
    }
    if (description.length) {
        entry[@"description"] = description;
    }
    if ([detail[@"tags"] isKindOfClass:[NSArray class]]) {
        entry[@"tags"] = detail[@"tags"];
    }
    if ([detail[@"message_count"] isKindOfClass:[NSNumber class]]) {
        entry[@"message_count"] = detail[@"message_count"];
    }
    if ([detail[@"cast_members"] isKindOfClass:[NSArray class]]) {
        NSMutableArray *cast = [NSMutableArray array];
        for (NSDictionary *member in detail[@"cast_members"]) {
            if (![member isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSMutableDictionary *cleaned = [NSMutableDictionary dictionary];
            if (member[@"id"]) {
                cleaned[@"id"] = member[@"id"];
            }
            if (member[@"name"]) {
                cleaned[@"name"] = member[@"name"];
            }
            if (member[@"avatar_url"]) {
                cleaned[@"avatar_url"] = member[@"avatar_url"];
            }
            if (cleaned.count) {
                [cast addObject:cleaned];
            }
        }
        entry[@"cast"] = cast;
    }
    if ([detail[@"owner"] isKindOfClass:[NSDictionary class]] && detail[@"owner"][@"username"]) {
        entry[@"owner"] = @{@"username": detail[@"owner"][@"username"]};
    }
    dispatch_sync(self.stateQueue, ^{
        NSMutableArray *stories = [self.stories mutableCopy] ?: [NSMutableArray array];
        NSUInteger existingIndex = NSNotFound;
        for (NSUInteger index = 0; index < stories.count; index++) {
            if ([stories[index][@"id"] isEqual:identifier]) {
                existingIndex = index;
                break;
            }
        }
        if (existingIndex != NSNotFound) {
            [stories replaceObjectAtIndex:existingIndex withObject:entry];
        } else {
            [stories addObject:entry];
        }
        self.stories = stories;
    });
}

- (NSArray *)sortedCharacters:(NSArray *)characters {
    return [characters sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        NSInteger leftCount = [left[@"message_count"] integerValue];
        NSInteger rightCount = [right[@"message_count"] integerValue];
        if (leftCount != rightCount) {
            return leftCount > rightCount ? NSOrderedAscending : NSOrderedDescending;
        }
        return [(NSString *)left[@"name"] compare:(NSString *)right[@"name"] ?: @""];
    }];
}

- (NSArray *)sortedStories:(NSArray *)stories {
    return [self sortedCharacters:stories];
}

#pragma mark - Queries

- (NSArray<NSDictionary *> *)filterItems:(NSArray<NSDictionary *> *)items
                                   query:(NSString *)query
                                     tag:(NSString *)tag
                          primaryKeyName:(NSString *)primaryKey
                       secondaryKeyName:(NSString *)secondaryKey {
    NSArray *sorted = [self sortedCharacters:items];
    BOOL filterTag = tag.length && ![tag isEqualToString:@"Все"];
    NSString *trimmed = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *lowercaseQuery = trimmed.lowercaseString;

    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *item in sorted) {
        if (filterTag) {
            NSArray *tags = item[@"tags"];
            if (![tags isKindOfClass:[NSArray class]] || ![tags containsObject:tag]) {
                continue;
            }
        }
        if (lowercaseQuery.length) {
            BOOL matched = NO;
            for (NSString *key in @[primaryKey, secondaryKey]) {
                id value = item[key];
                if ([value isKindOfClass:[NSString class]]) {
                    if ([[value lowercaseString] rangeOfString:lowercaseQuery].location != NSNotFound) {
                        matched = YES;
                        break;
                    }
                }
            }
            if (!matched) {
                NSArray *tags = item[@"tags"];
                if ([tags isKindOfClass:[NSArray class]]) {
                    for (NSString *value in tags) {
                        if ([value isKindOfClass:[NSString class]] &&
                            [[value lowercaseString] rangeOfString:lowercaseQuery].location != NSNotFound) {
                            matched = YES;
                            break;
                        }
                    }
                }
            }
            if (!matched && [item[@"owner"][@"username"] isKindOfClass:[NSString class]]) {
                NSString *owner = [item[@"owner"][@"username"] lowercaseString];
                matched = [owner rangeOfString:lowercaseQuery].location != NSNotFound;
            }
            if (!matched) {
                continue;
            }
        }
        [result addObject:item];
    }
    return result;
}

- (NSArray<NSDictionary *> *)charactersMatchingQuery:(NSString *)query tag:(NSString *)tag {
    return [self filterItems:self.characters query:query tag:tag primaryKeyName:@"name" secondaryKeyName:@"tagline"];
}

- (NSArray<NSDictionary *> *)storiesMatchingQuery:(NSString *)query tag:(NSString *)tag {
    return [self filterItems:self.stories query:query tag:tag primaryKeyName:@"title" secondaryKeyName:@"description"];
}

- (NSDictionary *)characterWithID:(NSString *)identifier {
    if (!identifier.length) {
        return nil;
    }
    for (NSDictionary *character in self.characters) {
        if ([character[@"id"] isEqual:identifier]) {
            return character;
        }
    }
    return nil;
}

- (NSDictionary *)storyWithID:(NSString *)identifier {
    if (!identifier.length) {
        return nil;
    }
    for (NSDictionary *story in self.stories) {
        if ([story[@"id"] isEqual:identifier]) {
            return story;
        }
    }
    return nil;
}

@end
