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

/// Local error helper (LumiError is private to LumiAPI.m).
static NSError *LumiCatalogError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:LumiAPIErrorDomain
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey: message ?: @"Ошибка"}];
}

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

- (NSString *)syncPercentString {
    if (self.syncTotalCount == 0) {
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
    [self syncStoriesWithCursor];
}

}

- (void)syncCharacterIDs {
    [self updateProgressWithPhase:@"Персонажи" phaseDone:0 phaseTotal:0];
    [self recalculateProgress];
    [self notifyUpdate];
    
    __weak typeof(self) weakSelf = self;
    [self fetchAllCatalogCardsWithKind:@"characters"
                          completion:^(NSArray<NSDictionary *> * _Nullable allCards, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        if (error || !allCards) {
            NSLog(@"[Lumi] catalog: character fetch error — %@", error);
            [strongSelf failSyncWithError:error fallback:@"Не удалось загрузить список персонажей"];
            return;
        }
        
        strongSelf.totalCharacterCount = allCards.count;
        strongSelf.characters = [strongSelf sortedCharacters:allCards];
        strongSelf.syncedCharacterCount = allCards.count;
        [strongSelf updateProgressWithPhase:@"Персонажи" phaseDone:allCards.count phaseTotal:allCards.count];
        [strongSelf recalculateProgress];
        [strongSelf notifyUpdate];
        
        NSLog(@"[Lumi] catalog: %lu персонажей загружено", (unsigned long)allCards.count);
        [LumiDiagnostics log:@"каталог: %lu персонажей загружено", (unsigned long)allCards.count];
        
        [strongSelf syncStoryIDs];
    }];
}

- (void)fetchAllCatalogCardsWithKind:(NSString *)kind
                          completion:(void (^)(NSArray<NSDictionary *> * _Nullable allCards, NSError * _Nullable error))completion {
    NSMutableArray *allCards = [NSMutableArray array];
    __block NSString *cursor = @"";
    __weak typeof(self) weakSelf = self;
    
    __block void (^fetchPage)(void);
    __weak void (^weakFetchPage)(void) = fetchPage;
    fetchPage = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            completion(nil, LumiCatalogError(500, @"Синхронизация отменена"));
            return;
        }
        
        void (^fetchCompletion)(id, NSError *) = ^(id result, NSError *error) {
            __strong typeof(weakSelf) sSelf = weakSelf;
            if (!sSelf) {
                completion(nil, LumiCatalogError(500, @"Синхронизация отменена"));
                return;
            }
            
            if (error) {
                NSLog(@"[Lumi] catalog: %@ fetch error — %@", kind, error);
                completion(nil, error);
                return;
            }
            
            NSDictionary *dictionary = [result isKindOfClass:[NSDictionary class]] ? result : nil;
            NSArray *items = [dictionary[@"items"] isKindOfClass:[NSArray class]] ? dictionary[@"items"] : nil;
            if (!items) {
                NSLog(@"[Lumi] catalog: unexpected %@ response type: %@", kind, [result class]);
                completion(nil, LumiCatalogError(500, @"Некорректный ответ сервера"));
                return;
            }
            
            [allCards addObjectsFromArray:items];
            NSLog(@"[Lumi] catalog: fetched %@ page — items: %lu, next_cursor: %@",
                  kind, (unsigned long)items.count, dictionary[@"next_cursor"] ?: @"(null)");
            
            NSString *nextCursor = [dictionary[@"next_cursor"] isKindOfClass:[NSString class]]
                ? dictionary[@"next_cursor"] : @"";
            
            if (nextCursor.length) {
                cursor = nextCursor;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf updateProgressWithPhase:kind phaseDone:allCards.count phaseTotal:0];
                    [weakSelf notifyUpdate];
                });
                void (^strongFetchPage)(void) = weakFetchPage;
                if (strongFetchPage) strongFetchPage();
            } else {
                completion([allCards copy], nil);
            }
        };
        
        if ([kind isEqualToString:@"characters"]) {
            [strongSelf.api fetchCharacterCardsWithCursor:cursor limit:100 completion:fetchCompletion];
        } else if ([kind isEqualToString:@"stories"]) {
            [strongSelf.api fetchStoryCardsWithCursor:cursor limit:100 completion:fetchCompletion];
        } else {
            completion(nil, LumiCatalogError(500, @"Неизвестный тип каталога"));
        }
    };
    
    weakFetchPage = fetchPage;
    fetchPage();
}

- (void)syncStoryIDs {
    [self updateProgressWithPhase:@"Истории" phaseDone:0 phaseTotal:0];
    [self recalculateProgress];
    [self notifyUpdate];
    
    __weak typeof(self) weakSelf = self;
    [self fetchAllCatalogCardsWithKind:@"stories"
                          completion:^(NSArray<NSDictionary *> * _Nullable allCards, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        if (error || !allCards) {
            NSLog(@"[Lumi] catalog: story fetch error — %@", error);
            [strongSelf failSyncWithError:error fallback:@"Не удалось загрузить список историй"];
            return;
        }
        
        strongSelf.totalStoryCount = allCards.count;
        strongSelf.stories = [strongSelf sortedStories:allCards];
        strongSelf.syncedStoryCount = allCards.count;
        [strongSelf updateProgressWithPhase:@"Истории" phaseDone:allCards.count phaseTotal:allCards.count];
        [strongSelf recalculateProgress];
        [strongSelf notifyUpdate];
        
        NSLog(@"[Lumi] catalog: %lu историй загружено", (unsigned long)allCards.count);
        [LumiDiagnostics log:@"каталог: %lu историй загружено", (unsigned long)allCards.count];
        
        [strongSelf finishSync];
    }];
}

- (void)finishSync {
    self.isSyncing = NO;
    self.syncPhase = nil;
    self.syncStatus = nil;
    [self saveCache];
    [self notifyUpdateNow];
}

- (NSArray<NSDictionary *> *)sortedCharacters:(NSArray<NSDictionary *> *)characters {
    return [characters sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *obj1, NSDictionary *obj2) {
        return [obj2[@"name"] compare:obj1[@"name"]];
    }];
}

- (NSArray<NSDictionary *> *)sortedStories:(NSArray<NSDictionary *> *)stories {
    return [stories sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *obj1, NSDictionary *obj2) {
        return [obj2[@"title"] compare:obj1[@"title"]];
    }];
}

- (NSArray<NSDictionary *> *)charactersMatchingQuery:(nullable NSString *)query tag:(nullable NSString *)tag { return @[]; }
- (NSArray<NSDictionary *> *)storiesMatchingQuery:(nullable NSString *)query tag:(nullable NSString *)tag { return @[]; }
- (NSArray<NSDictionary *> *)charactersMatchingQuery:(nullable NSString *)query tags:(nullable NSArray<NSString *> *)tags { return @[]; }
- (NSArray<NSDictionary *> *)storiesMatchingQuery:(nullable NSString *)query tags:(nullable NSArray<NSString *> *)tags { return @[]; }
- (nullable NSDictionary *)characterWithID:(nullable NSString *)identifier { return nil; }

- (void)syncStoriesWithCursor {
    [self updateProgressWithPhase:@"Истории" phaseDone:0 phaseTotal:0];
    [self recalculateProgress];
    [self notifyUpdate];
