#import "LumiCatalogStore.h"
#import "LumiAPI.h"
#import "LumiSafe.h"
#import "LumiDiagnostics.h"

NSString *const LumiCatalogDidUpdateNotification = @"LumiCatalogDidUpdateNotification";

static NSString *const kCatalogFileName = @"catalog-v2.json";
static const NSTimeInterval kCatalogMaxAge = 12 * 60 * 60;
static const NSUInteger kDetailConcurrency = 14;
static const NSUInteger kDetailInitialWorkers = 10;
static const NSUInteger kDetailMinimumWorkers = 3;

typedef NS_ENUM(NSInteger, LumiCatalogSyncKind) {
    LumiCatalogSyncKindCharacter = 0,
    LumiCatalogSyncKindStory = 1,
};

@interface LumiCatalogStore ()
// Deliberately atomic: they are reassigned on the serial state queue while the
// chat list / catalog screens read them on the main thread. A nonatomic getter
// racing a setter can over-release the array and kill the app.
@property (copy, readwrite) NSArray<NSDictionary *> *characters;
@property (copy, readwrite) NSArray<NSDictionary *> *stories;
@property (copy, readwrite) NSArray<NSString *> *characterTags;
@property (copy, readwrite) NSArray<NSString *> *storyTags;
@property (nonatomic, assign, readwrite) BOOL isSyncing;
@property (nonatomic, assign, readwrite) NSUInteger syncedCharacterCount;
@property (nonatomic, assign, readwrite) NSUInteger totalCharacterCount;
@property (nonatomic, copy, readwrite, nullable) NSString *syncStatus;
@property (nonatomic, copy, readwrite, nullable) NSString *syncPhase;
@property (nonatomic, assign, readwrite) double syncProgress;
@property (nonatomic, assign, readwrite) NSUInteger syncCompletedCount;
@property (nonatomic, assign, readwrite) NSUInteger syncTotalCount;
@property (nonatomic, assign, readwrite) NSUInteger phaseCompletedCount;
@property (nonatomic, assign, readwrite) NSUInteger phaseTotalCount;
@property (nonatomic, assign, readwrite) NSUInteger syncFailedCount;
@property (nonatomic, assign, readwrite) BOOL syncRateLimited;
@property (nonatomic, assign) NSUInteger totalStoryCount;
@property (nonatomic, assign) NSUInteger syncedStoryCount;
@property (nonatomic, strong) LumiAPI *api;
@property (nonatomic, strong, nullable) NSDate *savedAt;
@property (nonatomic, assign) BOOL started;
@property (nonatomic, strong) dispatch_queue_t stateQueue;
@property (nonatomic, strong) dispatch_queue_t cacheQueue;
@property (nonatomic, assign) BOOL notifyScheduled;
@property (nonatomic, assign) NSTimeInterval lastNotifyTime;
@property (nonatomic, assign) NSUInteger characterRetryRounds;
@property (nonatomic, assign) BOOL pendingCharacterRetry;
/// YES when the cache was built from the authenticated cursor-paged endpoints,
/// which return the full catalog instead of the public 1000-item preview.
@property (nonatomic, assign) BOOL catalogFromAuthenticatedSource;
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
        _syncStatus = nil;
        _syncPhase = nil;
        _syncProgress = 0.0;
    }
    return self;
}

#pragma mark - Progress helpers

- (BOOL)isShowingSyncError {
    return !self.isSyncing && self.syncStatus.length > 0;
}

- (NSString *)syncPercentString {    if (self.syncTotalCount == 0) {
        return self.isSyncing ? @"0%" : @"100%";
    }
    double ratio = (double)self.syncCompletedCount / (double)self.syncTotalCount;
    if (ratio > 1.0) {
        ratio = 1.0;
    }
    if (ratio < 0.0) {
        ratio = 0.0;
    }
    return [NSString stringWithFormat:@"%d%%", (int)floor(ratio * 100.0 + 0.5)];
}

- (NSString *)phasePercentString {
    if (self.phaseTotalCount == 0) {
        return self.isSyncing ? @"0%" : @"100%";
    }
    double ratio = (double)self.phaseCompletedCount / (double)self.phaseTotalCount;
    if (ratio > 1.0) {
        ratio = 1.0;
    }
    if (ratio < 0.0) {
        ratio = 0.0;
    }
    return [NSString stringWithFormat:@"%d%%", (int)floor(ratio * 100.0 + 0.5)];
}

- (NSString *)syncDetailedDescription {
    if (!self.isSyncing) {
        if (self.syncStatus.length) {
            return self.syncStatus;
        }
        return [NSString stringWithFormat:@"Каталог загружен · %lu персонажей · %lu историй",
                (unsigned long)self.characters.count, (unsigned long)self.stories.count];
    }
    NSString *phase = self.syncPhase.length ? self.syncPhase : @"Подготовка";
    if (self.phaseTotalCount == 0) {
        return [NSString stringWithFormat:@"%@ · получение списка…", phase];
    }
    NSString *base = [NSString stringWithFormat:@"%@ · %@ · %lu / %lu",
                      phase, [self phasePercentString],
                      (unsigned long)self.phaseCompletedCount, (unsigned long)self.phaseTotalCount];
    if (self.syncRateLimited) {
        base = [base stringByAppendingString:@"  ·  сервер ограничивает запросы, ждём…"];
    } else if (self.syncFailedCount > 0) {
        base = [base stringByAppendingFormat:@"  ·  ошибок: %lu", (unsigned long)self.syncFailedCount];
    }
    return base;
}

- (double)phaseProgress {
    if (self.phaseTotalCount == 0) {
        return 0.0;
    }
    double ratio = (double)self.phaseCompletedCount / (double)self.phaseTotalCount;
    if (ratio > 1.0) {
        ratio = 1.0;
    }
    if (ratio < 0.0) {
        ratio = 0.0;
    }
    return ratio;
}

- (void)updateProgressWithPhase:(NSString *)phase
                    phaseDone:(NSUInteger)phaseDone
                   phaseTotal:(NSUInteger)phaseTotal {
    self.syncPhase = phase;
    self.phaseCompletedCount = phaseDone;
    self.phaseTotalCount = phaseTotal;
    self.syncStatus = [self syncDetailedDescription];
}

- (void)recalculateProgress {
    NSUInteger charactersTotal = self.totalCharacterCount;
    NSUInteger storiesTotal = MAX(self.totalStoryCount, self.stories.count);
    if (storiesTotal == 0 && self.syncPhase && [self.syncPhase isEqualToString:@"Истории"]) {
        storiesTotal = self.phaseTotalCount;
    }
    self.syncTotalCount = charactersTotal + storiesTotal;
    self.syncCompletedCount = MIN(self.syncedCharacterCount, charactersTotal) +
                              MIN(self.syncedStoryCount, storiesTotal);
    self.syncProgress = self.syncTotalCount > 0
        ? (double)self.syncCompletedCount / (double)self.syncTotalCount
        : 0.0;
    self.syncStatus = [self syncDetailedDescription];
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

#pragma mark - State serialization

/// Mutations run on a private serial queue; UI components read `characters` /
/// `stories` from the main thread (assigning an immutable array is safe).
- (void)performState:(dispatch_block_t)block {
    if (!self.stateQueue) {
        self.stateQueue = dispatch_queue_create("com.w3rn1ght.lumi.catalog.state", DISPATCH_QUEUE_SERIAL);
    }
    dispatch_async(self.stateQueue, block);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self notifyUpdate];
    });
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
    // Snapshot on the caller's thread (the arrays are immutable copies), then
    // serialise ~9 MB of JSON off the main thread. Doing this on the main queue
    // froze the interface for seconds at a time.
    NSDictionary *dictionary = @{
        @"saved_at": @([[NSDate date] timeIntervalSince1970]),
        @"characters": self.characters ?: @[],
        @"stories": self.stories ?: @[],
        @"character_tags": self.characterTags ?: @[],
        @"story_tags": self.storyTags ?: @[],
    };
    self.savedAt = [NSDate date];
    if (!self.cacheQueue) {
        self.cacheQueue = dispatch_queue_create("com.w3rn1ght.lumi.catalog.cache", DISPATCH_QUEUE_SERIAL);
    }
    NSString *path = [self cachePath];
    dispatch_async(self.cacheQueue, ^{
        NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:NULL];
        if (data) {
            [data writeToFile:path atomically:YES];
        }
    });
}

- (BOOL)isStale {
    if (!self.savedAt) {
        return YES;
    }
    return -[self.savedAt timeIntervalSinceNow] > kCatalogMaxAge;
}

/// Crowds of catalog events must not flood the main queue: each notification
/// makes the catalog list re-filter and re-sort 1000+ entries. Posting at most
/// four times per second keeps the UI (and the progress bar) alive while the
/// ~1400 detail requests are still streaming in.
- (void)notifyUpdate {
    @synchronized (self) {
        if (self.notifyScheduled) {
            return;
        }
        self.notifyScheduled = YES;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        @synchronized (self) {
            self.notifyScheduled = NO;
            self.lastNotifyTime = [NSDate timeIntervalSinceReferenceDate];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:LumiCatalogDidUpdateNotification
                                                            object:self];
    });
}

/// Immediate variant used for terminal states (finished / failed).
- (void)notifyUpdateNow {
    @synchronized (self) {
        self.notifyScheduled = NO;
    }
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
    [LumiDiagnostics log:@"каталог: кэш %lu персонажей / %lu историй, устарел: %d",
     (unsigned long)self.characters.count, (unsigned long)self.stories.count, self.isStale];
    if (self.isStale || self.characters.count < 100) {
        [self forceRefresh];
    }
}

- (void)refreshInBackgroundIfStale {
    if (self.isStale && !self.isSyncing) {
        [self forceRefresh];
    }
}

- (void)retryFailedCharacterDetails {
    if (self.isSyncing) {
        return;
    }
    // Must re-read the ID list: characters that never loaded are not part of
    // `self.characters`, so `syncCharacterDetailsOnly` cannot see them.
    self.isSyncing = YES;
    self.syncPhase = @"Персонажи";
    self.syncStatus = nil;
    [self notifyUpdateNow];
    [self syncCharacterIDs];
}

- (void)forceRefresh {
    if (self.isSyncing) {
        return;
    }
    self.characterRetryRounds = 0;
    self.pendingCharacterRetry = NO;
    [self startSyncWithPhase:@"Подготовка"];
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

- (NSArray<NSString *> *)identifiersFromItems:(NSArray *)items {
    NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:items.count];
    for (NSDictionary *item in items) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        id identifier = item[@"id"];
        if ([identifier isKindOfClass:[NSString class]]) {
            [ids addObject:identifier];
        }
    }
    return ids;
}

- (void)failSyncWithError:(NSError *)error fallback:(NSString *)fallback {
    self.isSyncing = NO;
    self.syncPhase = nil;
    NSString *message = error.localizedDescription.length ? error.localizedDescription : fallback;
    self.syncStatus = message;
    self.syncFailedCount = 1;
    NSLog(@"[Lumi] catalog sync failed: %@", message);
    [LumiDiagnostics log:@"каталог: ошибка — %@", message];
    [self saveCache];
    [self notifyUpdateNow];
}

- (void)startSyncWithPhase:(NSString *)phase {
    self.isSyncing = YES;
    self.started = YES;
    self.syncPhase = phase;
    self.syncStatus = nil;
    self.syncFailedCount = 0;
    self.syncRateLimited = NO;
    self.syncCompletedCount = 0;
    self.syncTotalCount = 0;
    self.phaseCompletedCount = 0;
    self.phaseTotalCount = 0;
    self.totalCharacterCount = 0;
    self.totalStoryCount = 0;
    self.syncedCharacterCount = 0;
    self.syncedStoryCount = 0;
    self.syncProgress = 0.0;
    [self notifyUpdateNow];
}

- (NSArray<NSDictionary *> *)currentCharacterIDs {
    NSMutableArray *ids = [NSMutableArray array];
    for (NSDictionary *character in self.characters) {
        if (character[@"id"]) {
            [ids addObject:character[@"id"]];
        }
    }
    return ids;
}

- (void)syncCharacterDetailsOnly {
    [self startSyncWithPhase:@"Персонажи"];
    NSMutableDictionary *known = [NSMutableDictionary dictionary];
    for (NSDictionary *character in self.characters) {
        id identifier = character[@"id"];
        if ([identifier isKindOfClass:[NSString class]] && character[@"name"]) {
            known[identifier] = character;
        }
    }
    NSArray *ids = [self currentCharacterIDs];
    NSMutableArray<NSString *> *missing = [NSMutableArray arrayWithCapacity:ids.count];
    for (NSString *identifier in ids) {
        if (!known[identifier]) {
            [missing addObject:identifier];
        }
    }
    NSLog(@"[Lumi] catalog: %lu characters, %lu missing details", (unsigned long)ids.count, (unsigned long)missing.count);
    [self updateProgressWithPhase:@"Персонажи" phaseDone:known.count phaseTotal:ids.count];
    [self recalculateProgress];
    [self notifyUpdate];
    if (!missing.count) {
        [self finishSync];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self syncDetailsForIDs:missing
                       kind:LumiCatalogSyncKindCharacter
                alreadyDone:known.count
               overallTotal:ids.count
                 completion:^(NSUInteger failed) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (failed > 0) {
            [LumiDiagnostics log:@"каталог: не загрузилось %lu из %lu, повторю позже",
             (unsigned long)failed, (unsigned long)missing.count];
        }
        strongSelf.syncedCharacterCount = ids.count;
        [strongSelf updateProgressWithPhase:@"Персонажи" phaseDone:ids.count phaseTotal:ids.count];
        [strongSelf recalculateProgress];
        [strongSelf saveCache];
        if (missing.count > 0 && failed == missing.count) {
            [strongSelf failSyncWithError:nil fallback:@"Не удалось загрузить карточки персонажей. Проверьте соединение."];
            return;
        }
        if (failed > 0) {
            [strongSelf scheduleCharacterRetry];
        }
        [strongSelf finishSync];
    }];
}

/// Partial failure is not a dead end: keep everything that was downloaded and
/// silently fetch the leftovers in the background once the current sync ends
/// (bounded, so a permanently broken card cannot spin forever).
- (void)scheduleCharacterRetry {
    if (self.characterRetryRounds >= 3) {
        return;
    }
    self.pendingCharacterRetry = YES;
}

- (void)handleCharacterSyncCompletionWithFailed:(NSUInteger)failed
                                        missing:(NSArray<NSString *> *)missing
                                     overallIDs:(NSArray<NSString *> *)ids {
    if (failed > 0) {
        NSLog(@"[Lumi] %lu character details failed", (unsigned long)failed);
        [LumiDiagnostics log:@"каталог: не загрузилось %lu из %lu, повторю позже",
         (unsigned long)failed, (unsigned long)missing.count];
    }
    if (missing.count > 0 && failed == missing.count) {
        [self failSyncWithError:nil fallback:@"Не удалось загрузить карточки персонажей. Проверьте соединение."];
        return;
    }
    self.syncedCharacterCount = ids.count;
    [self updateProgressWithPhase:@"Персонажи" phaseDone:ids.count phaseTotal:ids.count];
    [self recalculateProgress];
    [self notifyUpdate];
    [self saveCache];
    if (failed > 0) {
        [self scheduleCharacterRetry];
    }
    [self syncStoryIDs];
}

- (void)syncCharacterIDs {
    [self.api fetchCharacterIDsWithCompletion:^(id result, NSError *error) {
        if (![result isKindOfClass:[NSArray class]]) {
            [self failSyncWithError:error fallback:@"Не удалось загрузить список персонажей"];
            return;
        }
        NSArray<NSString *> *ids = [self identifiersFromItems:result];
        self.totalCharacterCount = ids.count;
        NSMutableDictionary *known = [NSMutableDictionary dictionary];
        for (NSDictionary *character in self.characters) {
            id identifier = character[@"id"];
            if ([identifier isKindOfClass:[NSString class]] && character[@"name"]) {
                known[identifier] = character;
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
        if (merged.count) {
            self.characters = [self sortedCharacters:merged];
        }
        self.syncedCharacterCount = known.count;
        [self updateProgressWithPhase:@"Персонажи" phaseDone:known.count phaseTotal:ids.count];
        [self recalculateProgress];
        [self notifyUpdate];
        NSLog(@"[Lumi] catalog: %lu ids, %lu missing details", (unsigned long)ids.count, (unsigned long)missing.count);
        [LumiDiagnostics log:@"каталог: %lu персонажей, загрузить %lu",
         (unsigned long)ids.count, (unsigned long)missing.count];

        if (!missing.count) {
            [self syncStoryIDs];
            return;
        }
        __weak typeof(self) weakSelf = self;
        [self syncDetailsForIDs:missing
                           kind:LumiCatalogSyncKindCharacter
                    alreadyDone:known.count
                   overallTotal:ids.count
                     completion:^(NSUInteger failed) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            [strongSelf handleCharacterSyncCompletionWithFailed:failed
                                                        missing:missing
                                                     overallIDs:ids];
        }];
    }];
}

- (void)syncStoryIDs {
    [self updateProgressWithPhase:@"Истории" phaseDone:0 phaseTotal:0];
    [self recalculateProgress];
    [self notifyUpdate];
    [self.api fetchStoryIDsWithCompletion:^(id result, NSError *error) {
        if (![result isKindOfClass:[NSArray class]]) {
            self.isSyncing = NO;
            self.syncPhase = nil;
            self.syncStatus = nil;
            [self saveCache];
            [self notifyUpdate];
            return;
        }
        NSArray<NSString *> *ids = [self identifiersFromItems:result];
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
        self.totalStoryCount = ids.count;
        self.syncedStoryCount = known.count;
        [self updateProgressWithPhase:@"Истории" phaseDone:known.count phaseTotal:ids.count];
        [self recalculateProgress];
        [self notifyUpdate];

        if (!missing.count) {
            [self finishSync];
            return;
        }
        __weak typeof(self) weakSelf = self;
        [self syncDetailsForIDs:missing
                           kind:LumiCatalogSyncKindStory
                    alreadyDone:known.count
                   overallTotal:ids.count
                     completion:^(NSUInteger failed) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            strongSelf.syncedStoryCount = ids.count;
            [strongSelf updateProgressWithPhase:@"Истории" phaseDone:ids.count phaseTotal:ids.count];
            [strongSelf recalculateProgress];
            [strongSelf saveCache];
            if (failed > 0) {
                [LumiDiagnostics log:@"каталог: не загрузилось %lu историй из %lu",
                 (unsigned long)failed, (unsigned long)missing.count];
            }
            if (missing.count > 0 && failed == missing.count) {
                [strongSelf failSyncWithError:nil fallback:@"Не удалось загрузить истории. Проверьте соединение."];
                return;
            }
            [strongSelf finishSync];
        }];
    }];
}

- (void)finishSync {
    self.isSyncing = NO;
    self.syncPhase = nil;
    self.syncStatus = nil;
    [self saveCache];
    NSLog(@"[Lumi] catalog sync finished: %lu characters, %lu stories",
          (unsigned long)self.characters.count, (unsigned long)self.stories.count);
    [LumiDiagnostics log:@"каталог: готово — %lu персонажей / %lu историй",
     (unsigned long)self.characters.count, (unsigned long)self.stories.count];
    [self notifyUpdateNow];

    if (self.pendingCharacterRetry) {
        self.pendingCharacterRetry = NO;
        if (self.characterRetryRounds < 3) {
            self.characterRetryRounds += 1;
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [weakSelf retryFailedCharacterDetails];
            });
        }
    }
}

/// Downloads details with a fixed worker pool (no thread blocking). A single
/// dead TLS handshake must not end the whole catalog: failed IDs are retried in
/// up to three passes, and the API itself cancels hung requests after 9 s.
- (void)syncDetailsForIDs:(NSArray<NSString *> *)identifiers
                     kind:(LumiCatalogSyncKind)kind
              alreadyDone:(NSUInteger)alreadyDone
             overallTotal:(NSUInteger)overallTotal
               completion:(void (^)(NSUInteger failed))completion {
    NSArray<NSString *> *ids = [identifiers copy];
    if (!ids.count) {
        completion(0);
        return;
    }

    LumiAPI *api = self.api;
    dispatch_queue_t scheduler = dispatch_queue_create("com.w3rn1ght.lumi.catalog.workers", DISPATCH_QUEUE_SERIAL);
    NSString *phase = kind == LumiCatalogSyncKindCharacter ? @"Персонажи" : @"Истории";
    NSString *kindSlug = kind == LumiCatalogSyncKindCharacter ? @"characters" : @"stories";
    NSUInteger reportEvery = kind == LumiCatalogSyncKindCharacter ? 10 : 8;
    NSUInteger saveEvery = kind == LumiCatalogSyncKindCharacter ? 20 : 16;
    NSUInteger totalIDs = ids.count;
    __weak typeof(self) weakSelf = self;
    __block BOOL finished = NO;
    __block NSUInteger succeeded = 0;
    __block NSUInteger activity = 0;
    // Both blocks are held STRONG. The previous version kept `runPass`/`pump`
    // as weak self-references, which silently killed the whole download: a
    // `__block` variable that is not captured by any escaping block keeps its
    // storage on the stack, so when `runPass` returned the block was released
    // and `weakPump` became nil. The pool then started exactly `workers`
    // requests (8 of 897) and never fetched another card again — which is
    // precisely what the log showed. Cycles are broken by nil-ing both blocks
    // on every terminal path.
    __block void (^runPass)(NSArray<NSString *> *, NSUInteger);
    __block void (^pump)(void);

    dispatch_async(dispatch_get_main_queue(), ^{
        weakSelf.syncFailedCount = 0;
        weakSelf.syncRateLimited = NO;
    });

    runPass = ^(NSArray<NSString *> *passIDs, NSUInteger passIndex) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || finished) {
            return;
        }
        NSUInteger total = passIDs.count;
        if (total == 0) {
            finished = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(0);
            });
            return;
        }

        __block NSUInteger nextIndex = 0;
        __block NSUInteger completed = 0;
        __block NSUInteger inFlight = 0;
        __block NSUInteger rateLimited = 0;
        __block NSUInteger errorLogs = 0;
        __block NSUInteger failedCount = 0;
        __block BOOL loggedFirstCard = NO;
        const NSUInteger workers = 8;
        NSMutableArray<NSString *> *failedIDs = [NSMutableArray array];
        NSTimeInterval passStartedAt = [NSDate timeIntervalSinceReferenceDate];
        [LumiDiagnostics log:@"каталог: старт %@ — %lu карточек, %lu воркеров",
         phase, (unsigned long)total, (unsigned long)workers];

        // Heartbeat: proves workers are alive even when no card completes for a
        // while (e.g. every connection hangs). It runs on its own queue so a
        // wedged worker scheduler still shows up in the log as a silent one.
        dispatch_queue_t pulseQueue = dispatch_queue_create("com.w3rn1ght.lumi.catalog.pulse", DISPATCH_QUEUE_SERIAL);
        __block void (^heartbeat)(void);
        __block __weak void (^weakHeartbeat)(void);
        heartbeat = ^{
            if (finished || completed >= total) {
                return;
            }
            [LumiDiagnostics log:@"каталог: пульс — %lu/%lu, в работе %lu, ошибок %lu, %.0f с",
             (unsigned long)completed, (unsigned long)total, (unsigned long)inFlight,
             (unsigned long)failedCount,
             [NSDate timeIntervalSinceReferenceDate] - passStartedAt];
            // Self-healing: if the pool somehow lost its pump, restart it
            // instead of sitting at "в работе 0" forever.
            if (inFlight == 0 && completed < total) {
                dispatch_async(scheduler, ^{
                    if (!finished && pump && inFlight == 0 && completed < total) {
                        [LumiDiagnostics log:@"каталог: воркеры простаивают, перезапускаю с %lu",
                         (unsigned long)completed];
                        pump();
                    }
                });
            }
            void (^next)(void) = weakHeartbeat;
            if (next) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                               pulseQueue, next);
            }
        };
        weakHeartbeat = heartbeat;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                       pulseQueue, heartbeat);

        pump = ^{
            if (finished) {
                return;
            }
            while (inFlight < workers && nextIndex < total) {
                NSString *identifier = passIDs[nextIndex];
                nextIndex += 1;
                inFlight += 1;
                [api fetchCatalogDetailWithKind:kindSlug
                                     identifier:identifier
                          includeFailureStatus:YES
                                     completion:^(id result, NSError *error) {
                    BOOL ok = !error && [result isKindOfClass:[NSDictionary class]];
                    if (ok) {
                        if (kind == LumiCatalogSyncKindCharacter) {
                            [strongSelf addCharacterDetail:result];
                        } else {
                            [strongSelf addStoryDetail:result];
                        }
                    }
                    dispatch_async(scheduler, ^{
                        if (finished) {
                            return;
                        }
                        activity += 1;
                        completed += 1;
                        inFlight -= 1;
                        if (ok) {
                            succeeded += 1;
                            if (!loggedFirstCard) {
                                loggedFirstCard = YES;
                                [LumiDiagnostics log:@"каталог: первая карточка за %.1f с",
                                 [NSDate timeIntervalSinceReferenceDate] - passStartedAt];
                            }
                        } else {
                            failedCount += 1;
                            [failedIDs addObject:identifier];
                            if (error.code == 429) {
                                rateLimited += 1;
                            }
                            if (errorLogs < 5) {
                                errorLogs += 1;
                                [LumiDiagnostics log:@"каталог: карточка %@ — %@",
                                 [identifier substringToIndex:MIN((NSUInteger)8, identifier.length)],
                                 error.localizedDescription ?: @"нет ответа"];
                            }
                        }

                        if (completed % reportEvery == 0 || completed == total) {
                            NSUInteger doneSnapshot = MIN(alreadyDone + succeeded, overallTotal);
                            NSUInteger failedSnapshot = failedIDs.count;
                            BOOL limitedSnapshot = rateLimited > 0;
                            dispatch_async(dispatch_get_main_queue(), ^{
                                if (kind == LumiCatalogSyncKindCharacter) {
                                    strongSelf.syncedCharacterCount = doneSnapshot;
                                } else {
                                    strongSelf.syncedStoryCount = doneSnapshot;
                                }
                                strongSelf.syncFailedCount = failedSnapshot;
                                strongSelf.syncRateLimited = limitedSnapshot;
                                [strongSelf updateProgressWithPhase:phase
                                                          phaseDone:doneSnapshot
                                                         phaseTotal:overallTotal];
                                [strongSelf recalculateProgress];
                                [strongSelf notifyUpdate];
                            });
                            if (completed % saveEvery == 0) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [strongSelf saveCache];
                                });
                            }
                            if (completed % 25 == 0) {
                                NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - passStartedAt;
                                [LumiDiagnostics log:@"каталог: %lu/%lu за %.0f с, ошибок %lu",
                                 (unsigned long)completed, (unsigned long)total, elapsed,
                                 (unsigned long)failedCount];
                            }
                        }

                        if (completed == total) {
                            if (failedIDs.count > 0 && passIndex < 2) {
                                NSArray<NSString *> *retryIDs = [failedIDs copy];
                                NSUInteger nextPass = passIndex + 1;
                                NSLog(@"[Lumi] catalog: pass %lu failed %lu of %lu, retrying",
                                      (unsigned long)(passIndex + 1),
                                      (unsigned long)retryIDs.count,
                                      (unsigned long)total);
                                [LumiDiagnostics log:@"каталог: повтор %lu — осталось %lu из %lu",
                                 (unsigned long)nextPass, (unsigned long)retryIDs.count,
                                 (unsigned long)total];
                                // Drop this pass's pool before the next one
                                // starts so the blocks do not pile up.
                                pump = nil;
                                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                                               scheduler, ^{
                                    void (^next)(NSArray<NSString *> *, NSUInteger) = runPass;
                                    if (next) {
                                        next(retryIDs, nextPass);
                                    }
                                });
                            } else {
                                finished = YES;
                                NSUInteger failedFinal = failedIDs.count;
                                pump = nil;
                                runPass = nil;
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    completion(failedFinal);
                                });
                            }
                            return;
                        }

                        pump();
                    });
                }];
            }
        };
        pump();
    };

    dispatch_async(scheduler, ^{
        runPass(ids, 0);
    });

    // Last-resort watchdog. With per-request cancellation this should never
    // fire; it only protects against a framework-level hang.
    // Extended to 30 seconds to allow retries for failed requests (up to 3 passes).
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30.0 * NSEC_PER_SEC)),
                   scheduler, ^{
        __block NSUInteger lastActivity = activity;
        __block NSUInteger stallTicks = 0;
        __block void (^watchdog)(void);
        __block __weak void (^weakWatchdog)(void);
        watchdog = ^{
            if (finished) {
                return;
            }
            if (activity != lastActivity) {
                lastActivity = activity;
                stallTicks = 0;
            } else {
                stallTicks += 1;
            }
            if (stallTicks >= 60) {
                finished = YES;
                pump = nil;
                runPass = nil;
                NSUInteger missing = totalIDs > succeeded ? totalIDs - succeeded : 0;
                NSLog(@"[Lumi] catalog watchdog: %lu of %lu details unfinished",
                      (unsigned long)missing, (unsigned long)totalIDs);
                [LumiDiagnostics log:@"каталог: сторож остановил загрузку, не хватает %lu из %lu",
                 (unsigned long)missing, (unsigned long)totalIDs];
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(missing);
                });
                return;
            }
            void (^nextWatchdog)(void) = weakWatchdog;
            if (nextWatchdog) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.0 * NSEC_PER_SEC)),
                               scheduler, nextWatchdog);
            }
        };
        weakWatchdog = watchdog;
        watchdog();
    });
}

#pragma mark - Detail handling

- (void)addCharacterDetail:(NSDictionary *)detail {
    if (![detail isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSString *identifier = LumiAsString(LumiValue(detail, @"id"));
    if (!identifier.length) {
        return;
    }
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    entry[@"id"] = identifier;
    entry[@"name"] = LumiAsString(LumiValue(detail, @"name")) ?: @"Персонаж";
    NSString *avatar = LumiAsString(LumiValue(detail, @"avatar_url"));
    if (avatar.length) {
        entry[@"avatar_url"] = avatar;
    }
    NSString *tagline = LumiAsString(LumiValue(detail, @"tagline"));
    if (tagline.length) {
        entry[@"tagline"] = tagline;
    }
    NSArray *tags = LumiAsArray(LumiValue(detail, @"tags"));
    if (tags.count) {
        entry[@"tags"] = tags;
    }
    NSNumber *messageCount = LumiAsNumber(LumiValue(detail, @"message_count"));
    if (messageCount) {
        entry[@"message_count"] = messageCount;
    }
    NSString *ownerName = LumiNestedString(detail, @"owner", @"username");
    if (ownerName.length) {
        entry[@"owner"] = @{@"username": ownerName};
    }
    [self performState:^{
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
    }];
}

- (void)addStoryDetail:(NSDictionary *)detail {
    if (![detail isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSString *identifier = LumiAsString(LumiValue(detail, @"id"));
    if (!identifier.length) {
        return;
    }
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    entry[@"id"] = identifier;
    entry[@"title"] = LumiAsString(LumiValue(detail, @"title")) ?: @"История";
    NSString *avatar = LumiAsString(LumiValue(detail, @"avatar_url"));
    if (avatar.length) {
        entry[@"avatar_url"] = avatar;
    }
    NSString *description = LumiAsString(LumiValue(detail, @"description"));
    if (description.length > 400) {
        description = [[description substringToIndex:400] stringByAppendingString:@"…"];
    }
    if (description.length) {
        entry[@"description"] = description;
    }
    NSArray *tags = LumiAsArray(LumiValue(detail, @"tags"));
    if (tags.count) {
        entry[@"tags"] = tags;
    }
    NSNumber *messageCount = LumiAsNumber(LumiValue(detail, @"message_count"));
    if (messageCount) {
        entry[@"message_count"] = messageCount;
    }
    NSArray *castMembers = LumiAsArray(LumiValue(detail, @"cast_members"));
    if (castMembers) {
        NSMutableArray *cast = [NSMutableArray array];
        for (id memberObject in castMembers) {
            NSDictionary *member = LumiAsDictionary(memberObject);
            if (!member) {
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
    NSString *ownerName = LumiNestedString(detail, @"owner", @"username");
    if (ownerName.length) {
        entry[@"owner"] = @{@"username": ownerName};
    }
    [self performState:^{
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
    }];
}

- (NSArray *)sortedCharacters:(NSArray *)characters {
    return [characters sortedArrayUsingComparator:^NSComparisonResult(id leftObject, id rightObject) {
        NSDictionary *left = LumiAsDictionary(leftObject);
        NSDictionary *right = LumiAsDictionary(rightObject);
        if (!left || !right) {
            return NSOrderedSame;
        }
        NSInteger leftCount = [LumiAsNumber(LumiValue(left, @"message_count")) integerValue];
        NSInteger rightCount = [LumiAsNumber(LumiValue(right, @"message_count")) integerValue];
        if (leftCount != rightCount) {
            return leftCount > rightCount ? NSOrderedAscending : NSOrderedDescending;
        }
        NSString *leftName = LumiAsString(LumiValue(left, @"name"))
            ?: LumiAsString(LumiValue(left, @"title")) ?: @"";
        NSString *rightName = LumiAsString(LumiValue(right, @"name"))
            ?: LumiAsString(LumiValue(right, @"title")) ?: @"";
        return [leftName localizedCaseInsensitiveCompare:rightName];
    }];
}

- (NSArray *)sortedStories:(NSArray *)stories {
    return [self sortedCharacters:stories];
}

#pragma mark - Queries

- (NSArray<NSDictionary *> *)filterItems:(NSArray<NSDictionary *> *)items
                                   query:(NSString *)query
                                    tags:(NSArray<NSString *> *)tags
                         primaryKeyName:(NSString *)primaryKey
                       secondaryKeyName:(NSString *)secondaryKey {
    NSArray *sorted = [self sortedCharacters:items];
    NSMutableSet<NSString *> *wantedTags = [NSMutableSet set];
    for (NSString *tag in tags) {
        if ([tag isKindOfClass:[NSString class]] && tag.length && ![tag isEqualToString:@"Все"]) {
            [wantedTags addObject:tag];
        }
    }
    BOOL filterTags = wantedTags.count > 0;
    NSString *trimmed = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *lowercaseQuery = trimmed.lowercaseString;

    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *item in sorted) {
        if (filterTags) {
            NSArray *itemTags = LumiAsArray(LumiValue(item, @"tags"));
            BOOL matchedTag = NO;
            for (id tag in itemTags) {
                if ([tag isKindOfClass:[NSString class]] && [wantedTags containsObject:tag]) {
                    matchedTag = YES;
                    break;
                }
            }
            if (!matchedTag) {
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
            if (!matched) {
                NSString *owner = LumiNestedString(item, @"owner", @"username");
                if (owner.length) {
                    matched = [[owner lowercaseString] rangeOfString:lowercaseQuery].location != NSNotFound;
                }
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
    return [self charactersMatchingQuery:query tags:(tag.length ? @[tag] : nil)];
}

- (NSArray<NSDictionary *> *)storiesMatchingQuery:(NSString *)query tag:(NSString *)tag {
    return [self storiesMatchingQuery:query tags:(tag.length ? @[tag] : nil)];
}

- (NSArray<NSDictionary *> *)charactersMatchingQuery:(NSString *)query tags:(NSArray<NSString *> *)tags {
    return [self filterItems:self.characters
                       query:query
                        tags:tags ?: @[]
             primaryKeyName:@"name"
           secondaryKeyName:@"tagline"];
}

- (NSArray<NSDictionary *> *)storiesMatchingQuery:(NSString *)query tags:(NSArray<NSString *> *)tags {
    return [self filterItems:self.stories
                       query:query
                        tags:tags ?: @[]
             primaryKeyName:@"title"
           secondaryKeyName:@"description"];
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
