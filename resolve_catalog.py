import re

import os
script_dir = os.path.dirname(os.path.abspath(__file__))
catalog_path = os.path.join(script_dir, 'Sources', 'LumiCatalogStore.m')

with open(catalog_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace the entire conflicted section
old_pattern = re.compile(
    r'<<<<<<< HEAD\n- \(void\)syncCharactersWithCursor \{.*?\n=======\n- \(void\)syncCharacterIDs \{.*?\n>>>>>>> origin/main\n\}' 
    r'|'
    r'<<<<<<< HEAD\n\n    NSMutableArray \*allStories = \[NSMutableArray array\];.*?\n=======\n\n    __weak typeof\(self\) weakSelf = self;.*?\n>>>>>>> origin/main\n\}',
    re.DOTALL
)

new_text = '''}
    [self syncStoryIDs];
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
                # Update progress periodically
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
}'''

# Split by the conflict markers and replace
parts = content.split('<<<<<<< HEAD')
if len(parts) > 1:
    # First conflict: syncCharactersWithCursor vs syncCharacterIDs + fetchAllCatalogCardsWithKind
    first_conflict = parts[1]
    # Find the ======= and >>>>>>> markers
    middle = first_conflict.split('=======')
    if len(middle) > 1:
        after_middle = middle[1].split('>>>>>>> origin/main')
        if len(after_middle) > 1:
            # Replace the first conflict
            content = parts[0] + new_text + after_middle[1]
            
            # Now handle the second conflict (syncStoriesWithCursor)
            parts2 = content.split('<<<<<<< HEAD')
            if len(parts2) > 1:
                second_conflict = parts2[1]
                middle2 = second_conflict.split('=======')
                if len(middle2) > 1:
                    after_middle2 = middle2[1].split('>>>>>>> origin/main')
                    if len(after_middle2) > 1:
                        content = parts2[0] + after_middle2[1]

with open(catalog_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Done")