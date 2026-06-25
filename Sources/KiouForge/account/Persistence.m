#import "account/Persistence.h"
#import "logging.h"

// ===========================================================================
// account/Persistence.m — KiouForge account identity storage.
//
// Ported from KiouEngineBridge/Settings_Persistence.m.
// ===========================================================================

NSString *const KFAccountStateChangedNotification =
    @"KFAccountStateChangedNotification";

static inline void kfPostAccountStateChanged(void) {
    [[NSNotificationCenter defaultCenter]
        postNotificationName:KFAccountStateChangedNotification object:nil];
}

static NSString *const kKeyAccounts          = @"kiou_forge.account.accounts";
static NSString *const kKeyActiveUserId      = @"kiou_forge.account.active_user_id";
static NSString *const kKeyForceRegister     = @"kiou_forge.account.force_register_on_next_launch";
static NSString *const kKeyPendingDeviceId   = @"kiou_forge.account.pending_device_id";
static NSString *const kKeyPendingDistinctId = @"kiou_forge.account.pending_distinct_id";

static NSString *const kFieldUuid       = @"uuid";
static NSString *const kFieldUserName   = @"userName";
static NSString *const kFieldOpenId     = @"openId";
static NSString *const kFieldUserId     = @"userId";
static NSString *const kFieldDistinctId = @"distinctId";
static NSString *const kFieldSavedAt    = @"savedAt";

NSArray<NSDictionary *> *KFListAccounts(void) {
    NSArray *raw = [[NSUserDefaults standardUserDefaults] arrayForKey:kKeyAccounts];
    if (![raw isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:raw.count];
    for (id e in raw) {
        if ([e isKindOfClass:[NSDictionary class]]) [result addObject:e];
    }
    return result;
}

void KFSaveAccount(NSString *uuid, NSString *userName, NSString *openId,
                   NSString *userId, NSString *distinctId) {
    if (userId.length == 0) {
        IPALog([NSString stringWithFormat:
                  @"[ACCOUNT] save skipped: missing userId (uuid=%@ userName=%@)",
                  uuid ?: @"", userName ?: @""]);
        return;
    }
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSArray *existing = KFListAccounts();
    NSMutableArray<NSDictionary *> *next =
        [NSMutableArray arrayWithCapacity:existing.count + 1];
    BOOL replaced = NO;
    NSDictionary *fresh = @{
        kFieldUuid:       uuid       ?: @"",
        kFieldUserName:   userName   ?: @"",
        kFieldOpenId:     openId     ?: @"",
        kFieldUserId:     userId,
        kFieldDistinctId: distinctId ?: @"",
        kFieldSavedAt:    @((NSInteger)[[NSDate date] timeIntervalSince1970]),
    };
    for (NSDictionary *e in existing) {
        NSString *eId = e[kFieldUserId];
        if ([eId isKindOfClass:[NSString class]] && [eId isEqualToString:userId]) {
            NSMutableDictionary *merged = [fresh mutableCopy];
            if (uuid.length       == 0) merged[kFieldUuid]       = e[kFieldUuid]       ?: @"";
            if (userName.length   == 0) merged[kFieldUserName]   = e[kFieldUserName]   ?: @"";
            if (openId.length     == 0) merged[kFieldOpenId]     = e[kFieldOpenId]     ?: @"";
            if (distinctId.length == 0) merged[kFieldDistinctId] = e[kFieldDistinctId] ?: @"";
            [next addObject:merged];
            replaced = YES;
        } else {
            [next addObject:e];
        }
    }
    if (!replaced) [next addObject:fresh];
    [d setObject:next forKey:kKeyAccounts];
    IPALog([NSString stringWithFormat:
              @"[ACCOUNT] saved userId=%@ userName=%@ uuid=%@ total=%lu",
              userId, userName ?: @"", uuid ?: @"", (unsigned long)next.count]);
    kfPostAccountStateChanged();
}

void KFUpdateAccountProfile(NSString *userId, NSString *openId,
                            NSArray<NSDictionary *> *ranks) {
    if (userId.length == 0) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSArray *existing = KFListAccounts();
    BOOL found = NO;
    NSMutableArray<NSDictionary *> *next =
        [NSMutableArray arrayWithCapacity:existing.count];
    for (NSDictionary *e in existing) {
        NSString *eId = e[kFieldUserId];
        if ([eId isKindOfClass:[NSString class]] && [eId isEqualToString:userId]) {
            NSMutableDictionary *merged = [e mutableCopy];
            if (openId.length > 0) merged[kFieldOpenId] = openId;
            if (ranks.count   > 0) merged[@"ranks"] = ranks;
            [next addObject:merged];
            found = YES;
        } else {
            [next addObject:e];
        }
    }
    if (!found) return;
    [d setObject:next forKey:kKeyAccounts];
    IPALog([NSString stringWithFormat:
              @"[ACCOUNT] profile updated userId=%@ openId=%@ ranks=%lu",
              userId, openId ?: @"", (unsigned long)ranks.count]);
    kfPostAccountStateChanged();
}

void KFDeleteAccount(NSString *userId) {
    if (userId.length == 0) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSArray *existing = KFListAccounts();
    NSMutableArray<NSDictionary *> *next =
        [NSMutableArray arrayWithCapacity:existing.count];
    for (NSDictionary *e in existing) {
        NSString *eId = e[kFieldUserId];
        if ([eId isKindOfClass:[NSString class]] && [eId isEqualToString:userId]) continue;
        [next addObject:e];
    }
    [d setObject:next forKey:kKeyAccounts];
    IPALog([NSString stringWithFormat:
              @"[ACCOUNT] deleted userId=%@ remaining=%lu",
              userId, (unsigned long)next.count]);
    kfPostAccountStateChanged();
}

NSString *KFActiveAccountUserId(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:kKeyActiveUserId];
    return [v isKindOfClass:[NSString class]] ? v : nil;
}

void KFSetActiveAccountUserId(NSString *userId) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (userId.length == 0) {
        [d removeObjectForKey:kKeyActiveUserId];
    } else {
        [d setObject:userId forKey:kKeyActiveUserId];
    }
    IPALog([NSString stringWithFormat:@"[ACCOUNT] active_user_id=%@",
              userId.length > 0 ? userId : @"(none)"]);
    kfPostAccountStateChanged();
}

bool KFForceRegisterOnNextLaunch(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:kKeyForceRegister];
    return v ? [v boolValue] : false;
}

void KFSetForceRegisterOnNextLaunch(bool enabled) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (enabled) {
        [d setBool:YES forKey:kKeyForceRegister];
    } else {
        [d removeObjectForKey:kKeyForceRegister];
    }
    IPALog([NSString stringWithFormat:@"[ACCOUNT] force_register=%s",
              enabled ? "true" : "false"]);
}

NSString *KFPendingDeviceId(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:kKeyPendingDeviceId];
    return ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) ? v : nil;
}

void KFSetPendingDeviceId(NSString *uuid) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (uuid.length == 0) {
        [d removeObjectForKey:kKeyPendingDeviceId];
        IPALog(@"[ACCOUNT] pending_device_id cleared");
    } else {
        [d setObject:uuid forKey:kKeyPendingDeviceId];
        IPALog([NSString stringWithFormat:@"[ACCOUNT] pending_device_id=%@", uuid]);
    }
    kfPostAccountStateChanged();
}

NSString *KFPendingDistinctId(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:kKeyPendingDistinctId];
    return ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) ? v : nil;
}

void KFSetPendingDistinctId(NSString *uuid) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (uuid.length == 0) {
        [d removeObjectForKey:kKeyPendingDistinctId];
        IPALog(@"[ACCOUNT] pending_distinct_id cleared");
    } else {
        [d setObject:uuid forKey:kKeyPendingDistinctId];
        IPALog([NSString stringWithFormat:@"[ACCOUNT] pending_distinct_id=%@", uuid]);
    }
    kfPostAccountStateChanged();
}

void KFSwitchAccount(NSString *uuid) {
    NSString *armedDistinct = KFPendingDistinctId();
    if (armedDistinct.length > 0) {
        IPALog([NSString stringWithFormat:
                  @"[ACCOUNT] KFSwitchAccount refused: Register flow in progress "
                  @"(pending_distinct_id=%@)", armedDistinct]);
        return;
    }
    KFSetPendingDeviceId(uuid);
    IPALog([NSString stringWithFormat:
              @"[ACCOUNT] KFSwitchAccount armed pending_device_id=%@", uuid ?: @"(nil)"]);
}
