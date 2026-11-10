#import "LumiCatalogStore.h"
#import "LumiAPI.h"

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
@property (nonatomic, copy, readwrite) NSArray<NSDictionary *> *characters;
@property (nonatomic, copy, readwrite) NSArray<NSDictionary *> *stories;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *characterTags;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *storyTags;
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

- (void)retryFailedCharacterDetails {
    if (self.isSyncing) {
        return;
    }
    [self syncCharacterDetailsOnly];
}

- (void)forceRefresh {
    if (self.isSyncing) {
        return;
    }
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
    [self notifyUpdate];
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
    [self notifyUpdate];
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
        strongSelf.syncedCharacterCount = ids.count;
        [strongSelf updateProgressWithPhase:@"Персонажи" phaseDone:ids.count phaseTotal:ids.count];
        [strongSelf recalculateProgress];
        if (failed > 0) {
            [strongSelf failSyncWithError:nil
                                 fallback:[NSString stringWithFormat:@"Не удалось загрузить %lu карточек персонажей. Потяните вниз, чтобы повторить.",
                                           (unsigned long)failed]];
            [strongSelf saveCache];
            return;
        }
        [strongSelf finishSync];
    }];
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
            if (failed > 0) {
                NSLog(@"[Lumi] %lu character details failed", (unsigned long)failed);
            }
            if (missing.count > 0 && failed == missing.count) {
                [strongSelf failSyncWithError:nil fallback:@"Не удалось загрузить карточки персонажей. Проверьте соединение."];
                return;
            }
            strongSelf.syncedCharacterCount = ids.count;
            [strongSelf updateProgressWithPhase:@"Персонажи" phaseDone:ids.count phaseTotal:ids.count];
            [strongSelf recalculateProgress];
            [strongSelf notifyUpdate];
            [strongSelf saveCache];
            if (failed > 0) {
                // Partial success: keep what we have and let the user retry the rest.
                [strongSelf failSyncWithError:nil
                                     fallback:[NSString stringWithFormat:@"Не удалось загрузить %lu персонажей из %lu. Потяните вниз, чтобы повторить загрузку.",
                                               (unsigned long)failed, (unsigned long)ids.count]];
                return;
            }
            [strongSelf syncStoryIDs];
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
            if (failed > 0) {
                [strongSelf failSyncWithError:nil
                                     fallback:[NSString stringWithFormat:@"Не удалось загрузить %lu историй из %lu. Потяните вниз, чтобы повторить загрузку.",
                                               (unsigned long)failed, (unsigned long)ids.count]];
                [strongSelf saveCache];
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
    [self notifyUpdate];
    NSLog(@"[Lumi] catalog sync finished: %lu characters, %lu stories",
          (unsigned long)self.characters.count, (unsigned long)self.stories.count);
}

/// Runs a fixed number of workers (no thread blocking) so 1000+ requests cannot
/// starve NSURLSession's delegate queue.
- (void)syncDetailsForIDs:(NSArray<NSString *> *)ids
                     kind:(LumiCatalogSyncKind)kind
              alreadyDone:(NSUInteger)alreadyDone
             overallTotal:(NSUInteger)overallTotal
               completion:(void (^)(NSUInteger failed))completion {
    NSUInteger total = ids.count;
    if (total == 0) {
        completion(0);
        return;
    }
    LumiAPI *api = self.api;
    dispatch_queue_t scheduler = dispatch_queue_create("com.w3rn1ght.lumi.catalog.workers", DISPATCH_QUEUE_SERIAL);
    __block NSUInteger nextIndex = 0;
    __block NSUInteger completed = 0;
    __block NSUInteger failed = 0;
    __block NSUInteger inFlight = 0;
    __block NSUInteger rateLimited = 0;
    __block NSUInteger workers = kDetailInitialWorkers;
    __block BOOL finished = NO;
    NSUInteger maxWorkers = kDetailConcurrency;
    __block __weak void (^weakPump)(void);
    __block void (^pump)(void);
    __weak typeof(self) weakSelf = self;
    NSString *phase = kind == LumiCatalogSyncKindCharacter ? @"Персонажи" : @"Истории";
    NSString *kindSlug = kind == LumiCatalogSyncKindCharacter ? @"characters" : @"stories";
    NSUInteger reportEvery = kind == LumiCatalogSyncKindCharacter ? 5 : 4;
    NSUInteger saveEvery = kind == LumiCatalogSyncKindCharacter ? 150 : 100;

    dispatch_async(dispatch_get_main_queue(), ^{
        weakSelf.syncFailedCount = 0;
        weakSelf.syncRateLimited = NO;
    });

    pump = ^{
        if (finished) {
            return;
        }
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        while (inFlight < workers && nextIndex < total) {
            NSString *identifier = ids[nextIndex];
            nextIndex += 1;
            inFlight += 1;
            LumiAPICompletion handler = ^(id result, NSError *error) {
                BOOL ok = [result isKindOfClass:[NSDictionary class]];
                if (ok) {
                    if (kind == LumiCatalogSyncKindCharacter) {
                        [strongSelf addCharacterDetail:result];
                    } else {
                        [strongSelf addStoryDetail:result];
                    }
                }
                dispatch_async(scheduler, ^{
                    completed += 1;
                    if (!ok) {
                        failed += 1;
                        BOOL limited = (error.code == 429);
                        if (limited) {
                            rateLimited += 1;
                        }
                        if (!limited && error.code == 0) {
                            // Transport errors: keep going, they are usually transient.
                        }
                    }
                    inFlight -= 1;

                    // Adaptive back-off: if the server throttles, lower concurrency
                    // (min 3). Recover slowly when everything succeeds again.
                    if (rateLimited > 0 && completed % 12 == 0) {
                        workers = workers > kDetailMinimumWorkers ? workers - 4 : kDetailMinimumWorkers;
                        if (workers < kDetailMinimumWorkers) {
                            workers = kDetailMinimumWorkers;
                        }
                    } else if (rateLimited == 0 && workers < maxWorkers && completed % 40 == 0) {
                        workers += 2;
                        if (workers > maxWorkers) {
                            workers = maxWorkers;
                        }
                    }

                    NSUInteger done = alreadyDone + completed;
                    if (completed % reportEvery == 0 || completed == total) {
                        NSUInteger failedSnapshot = failed;
                        NSUInteger doneSnapshot = done;
                        NSUInteger totalSnapshot = total;
                        BOOL limitedSnapshot = rateLimited > 0;
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (kind == LumiCatalogSyncKindCharacter) {
                                strongSelf.syncedCharacterCount = doneSnapshot;
                            } else {
                                strongSelf.syncedStoryCount = doneSnapshot;
                            }
                            strongSelf.syncFailedCount = failedSnapshot;
                            strongSelf.syncRateLimited = limitedSnapshot;
                            [strongSelf updateProgressWithPhase:phase phaseDone:doneSnapshot phaseTotal:overallTotal];
                            [strongSelf recalculateProgress];
                            [strongSelf notifyUpdate];
                        });
                        if (completed % saveEvery == 0) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [strongSelf saveCache];
                            });
                        }
                    }
                    if (completed == total) {
                        if (finished) {
                            return;
                        }
                        finished = true;
                        NSUInteger failedFinal = failed;
                        dispatch_async(dispatch_get_main_queue(), ^{
                            completion(failedFinal);
                        });
                        return;
                    }
                    void (^nextPump)(void) = weakPump;
                    if (nextPump) {
                        nextPump();
                    }
                });
            };
            [api fetchCatalogDetailWithKind:kindSlug
                                 identifier:identifier
                      includeFailureStatus:YES
                                 completion:handler];
        }
    };
    weakPump = pump;
    dispatch_async(scheduler, pump);
    (void)total;
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
