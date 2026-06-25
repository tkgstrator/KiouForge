#import "Internal.h"
#import "account/Persistence.h"
#import <dlfcn.h>

// KF_CALL_ORIG_VOID / _RET — invoke orig on JB, no-op on chinlan.
// On chinlan the cave's displaced-prologue + B orig+4 runs orig for us.
#if IPA_CHINLAN
#  define KF_CALL_ORIG_VOID(ORIG, ...)         ((void)0)
#  define KF_CALL_ORIG_RET(RET_T, ORIG, ...)   ((RET_T){0})
#else
#  define KF_CALL_ORIG_VOID(ORIG, ...)                                        \
       do { if ((ORIG)) (ORIG)(__VA_ARGS__); } while (0)
#  define KF_CALL_ORIG_RET(RET_T, ORIG, ...)                                  \
       ((ORIG) ? (ORIG)(__VA_ARGS__) : (RET_T){0})
#endif

// ===========================================================================
// Hook_AccountObserve — account identity observation + switching.
//
// Ported from KiouEngineBridge/Hook_AccountObserve.m. The logic is
// identical; only the KEB* prefix → KF* prefix and the chinlan slot
// references have changed.
//
// Hook sites (KIOU 1.0.2 build 12):
//
//   UserSaveDataExtensions.AccountExists   RVA: 0x5922CD0  (CAVE_ENTRY on chinlan)
//   ILoginArgs.Create                      RVA: 0x5B9DC04  (CAVE_ENTRY on chinlan)
//   IRegisterUserArgs.Create               RVA: 0x5B9DC94  (CAVE_ENTRY on chinlan)
//   RunLoginSequenceAsync.MoveNext         RVA: 0x58152BC  (CAVE_ENTRY on chinlan)
//   GetSelfUserProfileAsync.MoveNext       RVA: 0x5BB99DC  (CAVE_ENTRY on chinlan)
//   TitleMenuPopupPresenter.RunResetUserDataSequenceAsync  RVA: 0x5DCC204
//   TitleMenuPopupPresenter.RunDeleteAccountSequenceAsync  RVA: 0x5DCC2B4
// ===========================================================================

// ---------------------------------------------------------------------------
// RVAs — sourced from ChinlanSites.h @generated block (make gen-sites).
// ---------------------------------------------------------------------------
#define KF_RVA_ACCOUNT_EXISTS                KIOU_KF_SITE_RVA_ACCOUNT_EXISTS
#define KF_RVA_LOGIN_ARGS_CREATE             KIOU_KF_SITE_RVA_LOGIN_ARGS_CREATE
#define KF_RVA_REGISTER_USER_ARGS_CREATE     KIOU_KF_SITE_RVA_REGISTER_USER_ARGS_CREATE
#define KF_RVA_RUN_LOGIN_SEQ_MOVENEXT        KIOU_KF_SITE_RVA_RUN_LOGIN_SEQ_MOVENEXT
#define KF_RVA_GET_SELF_PROFILE_MOVENEXT     KIOU_KF_SITE_RVA_GET_SELF_PROFILE_MOVENEXT
// RunReset / RunDelete are not in SITES (not binpatched); keep explicit RVAs.
#define KF_RVA_RUN_RESET_USER_DATA_SEQ       0x5DCC204
#define KF_RVA_RUN_DELETE_ACCOUNT_SEQ        0x5DCC2B4

// ---------------------------------------------------------------------------
// Field offsets
// ---------------------------------------------------------------------------
#define OFF_USER_SAVE_DATA_USER_NAME  0x10
#define OFF_USER_SAVE_DATA_OPEN_ID    0x18
#define OFF_USER_SAVE_DATA_USER_ID    0x20
#define OFF_USER_SAVE_DATA_DEVICE_ID  0x28

#define OFF_LOGIN_REPLY_ACCESS_TOKEN  0x18
#define OFF_LOGIN_REPLY_SESSION_ID    0x20
#define OFF_LOGIN_REPLY_DEVICE_ID     0x28
#define OFF_LOGIN_REPLY_USER_NAME     0x30

#define OFF_SM_LOGIN_STATE     0x00
#define OFF_SM_LOGIN_RESULT_D  0x50  // confirmed on KIOU 1.0.1 build 11

#define OFF_GET_SELF_PROFILE_REPLY_PROFILE  0x18
#define OFF_SELF_PROFILE_USER_NAME          0x18
#define OFF_SELF_PROFILE_OPEN_USER_ID       0x20
#define OFF_SELF_PROFILE_RANK_LIST          0x28
#define OFF_REPEATED_ARRAY                  0x10
#define OFF_REPEATED_COUNT                  0x18
#define OFF_RANK_STATUS_MATCH_TYPE     0x18
#define OFF_RANK_STATUS_RANK_RULE_TYPE 0x1C
#define OFF_RANK_STATUS_RANK           0x24
#define OFF_RANK_STATUS_RATING         0x28

// ---------------------------------------------------------------------------
// Observed state
// ---------------------------------------------------------------------------
static NSString *volatile g_latestObservedUserId = nil;

// il2cpp_string_new resolved via dlsym at install time.
typedef void *(*Il2CppStringNew_t)(const char *utf8);
static Il2CppStringNew_t g_il2cpp_string_new = NULL;

// ---------------------------------------------------------------------------
// JWT helper — extract "sub" claim from HS256 JWT.
// ---------------------------------------------------------------------------
static NSString *extractJWTSub(NSString *jwt) {
    if (jwt.length == 0) return nil;
    NSArray<NSString *> *parts = [jwt componentsSeparatedByString:@"."];
    if (parts.count < 2) return nil;
    NSString *payload = parts[1];
    payload = [payload stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    payload = [payload stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (payload.length % 4) payload = [payload stringByAppendingString:@"="];
    NSData *data = [[NSData alloc] initWithBase64EncodedString:payload options:0];
    if (!data) return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) return nil;
    id sub = ((NSDictionary *)obj)[@"sub"];
    return [sub isKindOfClass:[NSString class]] ? (NSString *)sub : nil;
}

// ---------------------------------------------------------------------------
// il2cpp string reader
// ---------------------------------------------------------------------------
static NSString *readIl2CppStr(void *strObj) {
    if (!strObj) return nil;
    @try {
        int32_t len = readI32(strObj, 0x10);
        if (len <= 0 || len > 4096) return nil;
        const uint16_t *chars = (const uint16_t *)((uint8_t *)strObj + 0x14);
        return [NSString stringWithCharacters:chars length:(NSUInteger)len];
    } @catch (...) { return nil; }
}

// ---------------------------------------------------------------------------
// Rank label helper
// ---------------------------------------------------------------------------
static const char *kfRankLabel(int32_t rank) {
    if (rank < 2) return "?";
    static const char *labels[] = {
        "10Kyu","9Kyu","8Kyu","7Kyu","6Kyu","5Kyu","4Kyu","3Kyu","2Kyu","1Kyu",
        "1Dan","2Dan","3Dan","4Dan","5Dan","6Dan","7Dan","8Dan","9Dan",
    };
    int idx = rank - 2;
    if (idx < 0 || idx >= (int)(sizeof(labels)/sizeof(labels[0]))) return "?";
    return labels[idx];
}

// ===========================================================================
// RegisterUserArgs.Create — distinctId substitution
// ===========================================================================
typedef void *(*RegisterUserArgsCreate_t)(void *userName, void *distinctId);
static RegisterUserArgsCreate_t orig_RegisterUserArgsCreate
    __attribute__((unused)) = NULL;

static void *kfSwapRegisterDistinctId(void *userName, void *distinctId) {
    NSString *pending = KFPendingDistinctId();
    if (pending.length > 0 && g_il2cpp_string_new) {
        void *newStr = g_il2cpp_string_new(pending.UTF8String);
        if (newStr) {
            IPALog([NSString stringWithFormat:
                      @"[ACCOUNT] RegisterUserArgs.Create distinctId → %@", pending]);
            return newStr;
        }
    }
    IPALog([NSString stringWithFormat:
              @"[ACCOUNT] RegisterUserArgs.Create userName=%@ distinctId=%@",
              readIl2CppStr(userName) ?: @"(nil)",
              readIl2CppStr(distinctId) ?: @"(nil)"]);
    return distinctId;
}

// ===========================================================================
// LoginArgs.Create — deviceId substitution
// ===========================================================================
typedef void *(*LoginArgsCreate_t)(void *deviceId, void *distinctId);
static LoginArgsCreate_t orig_LoginArgsCreate __attribute__((unused)) = NULL;

static void *kfSwapLoginDeviceId(void *deviceId, void *distinctId) {
    NSString *pending = KFPendingDeviceId();
    if (pending.length > 0 && g_il2cpp_string_new) {
        void *newStr = g_il2cpp_string_new(pending.UTF8String);
        if (newStr) {
            IPALog([NSString stringWithFormat:
                      @"[ACCOUNT] LoginArgs.Create deviceId → %@", pending]);
            return newStr;
        }
    }
    IPALog([NSString stringWithFormat:
              @"[ACCOUNT] LoginArgs.Create deviceId=%@ distinctId=%@",
              readIl2CppStr(deviceId) ?: @"(nil)",
              readIl2CppStr(distinctId) ?: @"(nil)"]);
    return deviceId;
}

#if !IPA_CHINLAN
void *KFHookRegisterUserArgsCreate(void *userName, void *distinctId) {
    void *useDistinctId = kfSwapRegisterDistinctId(userName, distinctId);
    return KF_CALL_ORIG_RET(void *, orig_RegisterUserArgsCreate,
                               userName, useDistinctId);
}

void *KFHookLoginArgsCreate(void *deviceId, void *distinctId) {
    void *useDeviceId = kfSwapLoginDeviceId(deviceId, distinctId);
    return KF_CALL_ORIG_RET(void *, orig_LoginArgsCreate,
                               useDeviceId, distinctId);
}
#endif

#if IPA_CHINLAN
void *KFHookLoginArgsCreateEntry(void *deviceId, void *distinctId) {
    void *useDeviceId = kfSwapLoginDeviceId(deviceId, distinctId);
    LoginArgsCreate_t bypass =
        (LoginArgsCreate_t)g_inject_entry[KIOU_KF_HOOK_LOGIN_ARGS_CREATE];
    if (!bypass) {
        IPALog(@"[ACCOUNT] LoginArgs.Create chinlan bypass not published — "
               @"returning NULL; the caller will likely abort the login");
        return NULL;
    }
    @try { return bypass(useDeviceId, distinctId); }
    @catch (NSException *e) {
        IPALog([NSString stringWithFormat:
                  @"[ACCOUNT] LoginArgs.Create chinlan bypass threw: %@", e]);
        return NULL;
    }
}

void *KFHookRegisterUserArgsCreateEntry(void *userName, void *distinctId) {
    void *useDistinctId = kfSwapRegisterDistinctId(userName, distinctId);
    RegisterUserArgsCreate_t bypass = (RegisterUserArgsCreate_t)
        g_inject_entry[KIOU_KF_HOOK_REGISTER_USER_ARGS_CREATE];
    if (!bypass) {
        IPALog(@"[ACCOUNT] RegisterUserArgs.Create chinlan bypass not published — "
               @"returning NULL");
        return NULL;
    }
    @try { return bypass(userName, useDistinctId); }
    @catch (NSException *e) {
        IPALog([NSString stringWithFormat:
                  @"[ACCOUNT] RegisterUserArgs.Create chinlan bypass threw: %@", e]);
        return NULL;
    }
}
#endif

// ===========================================================================
// RunLoginSequenceAsync.MoveNext — capture LoginReply
// ===========================================================================
typedef void (*MoveNextVoid_t)(void *self);
static MoveNextVoid_t orig_RunLoginSeqMoveNext __attribute__((unused)) = NULL;

static void observeRunLoginSeqCompletion(void *self) {
    if (!self) return;
    if (readI32(self, OFF_SM_LOGIN_STATE) != -2) return;

    uintptr_t offsets[] = { 0x38, 0x40, 0x48, OFF_SM_LOGIN_RESULT_D };
    for (size_t i = 0; i < sizeof(offsets)/sizeof(offsets[0]); i++) {
        void *candidate = readPtr(self, offsets[i]);
        if (!candidate) continue;
        NSString *accessToken = readIl2CppStr(readPtr(candidate, OFF_LOGIN_REPLY_ACCESS_TOKEN));
        NSString *deviceId    = readIl2CppStr(readPtr(candidate, OFF_LOGIN_REPLY_DEVICE_ID));
        NSString *userName    = readIl2CppStr(readPtr(candidate, OFF_LOGIN_REPLY_USER_NAME));
        if (!userName && !deviceId) continue;
        IPALog([NSString stringWithFormat:
                  @"[ACCOUNT] LoginReply @0x%lx userName=%@ deviceId=%@",
                  (unsigned long)offsets[i], userName ?: @"(nil)", deviceId ?: @"(nil)"]);

        NSString *userId = extractJWTSub(accessToken);
        if (userId.length == 0) userId = g_latestObservedUserId;
        if (userId.length > 0 && deviceId.length > 0) {
            KFSaveAccount(deviceId, userName, @"", userId, deviceId);
            KFSetActiveAccountUserId(userId);
        }
        KFSetPendingDeviceId(nil);
        KFSetPendingDistinctId(nil);
        KFSetForceRegisterOnNextLaunch(false);
        return;
    }
}

void KFHookRunLoginSeqMoveNext(void *self) {
    KF_CALL_ORIG_VOID(orig_RunLoginSeqMoveNext, self);
    observeRunLoginSeqCompletion(self);
}

#if IPA_CHINLAN
void KFHookRunLoginSeqMoveNextEntry(void *self) {
    MoveNextVoid_t bypass = (MoveNextVoid_t)
        g_inject_entry[KIOU_KF_HOOK_RUN_LOGIN_SEQ_MOVENEXT];
    if (bypass) {
        @try { bypass(self); }
        @catch (NSException *e) {
            IPALog([NSString stringWithFormat:
                      @"[ACCOUNT] RunLoginSeq.MoveNext chinlan bypass threw: %@", e]);
            return;
        }
    } else {
        IPALog(@"[ACCOUNT] RunLoginSeq.MoveNext chinlan bypass not published — "
               @"skipping observation");
        return;
    }
    observeRunLoginSeqCompletion(self);
}
#endif

// ===========================================================================
// GetSelfUserProfileAsync.MoveNext — capture rank / openId
// ===========================================================================
static MoveNextVoid_t orig_GetSelfProfileMoveNext __attribute__((unused)) = NULL;

static void observeGetSelfProfileCompletion(void *self) {
    if (!self) return;
    if (readI32(self, 0x00) != -2) return;

    for (uintptr_t off = 0x30; off <= 0x60; off += 0x08) {
        void *reply = readPtr(self, off);
        if (!reply) continue;
        void *profile = readPtr(reply, OFF_GET_SELF_PROFILE_REPLY_PROFILE);
        if (!profile) continue;
        NSString *userName   = readIl2CppStr(readPtr(profile, OFF_SELF_PROFILE_USER_NAME));
        NSString *openUserId = readIl2CppStr(readPtr(profile, OFF_SELF_PROFILE_OPEN_USER_ID));
        if (userName.length == 0 && openUserId.length == 0) continue;

        IPALog([NSString stringWithFormat:
                  @"[ACCOUNT] SelfProfile @0x%lx userName=%@ openUserId=%@",
                  (unsigned long)off, userName ?: @"(nil)", openUserId ?: @"(nil)"]);

        NSMutableArray<NSDictionary *> *rankDicts = [NSMutableArray array];
        void *rankListObj = readPtr(profile, OFF_SELF_PROFILE_RANK_LIST);
        void *array = readPtr(rankListObj, OFF_REPEATED_ARRAY);
        int32_t count = readI32(rankListObj, OFF_REPEATED_COUNT);
        if (array && count > 0 && count < 32) {
            for (int32_t ri = 0; ri < count; ri++) {
                void *entry = *(void **)((uint8_t *)array + 0x20 + ri * 8);
                if (!entry) continue;
                int32_t matchType = readI32(entry, OFF_RANK_STATUS_MATCH_TYPE);
                int32_t ruleType  = readI32(entry, OFF_RANK_STATUS_RANK_RULE_TYPE);
                int32_t rank      = readI32(entry, OFF_RANK_STATUS_RANK);
                int32_t rating    = readI32(entry, OFF_RANK_STATUS_RATING);
                [rankDicts addObject:@{
                    @"matchType": @(matchType),
                    @"ruleType":  @(ruleType),
                    @"rank":      @(rank),
                    @"rankLabel": @(kfRankLabel(rank)),
                    @"rating":    @(rating),
                }];
            }
        }

        NSString *activeUserId = KFActiveAccountUserId();
        if (activeUserId.length > 0)
            KFUpdateAccountProfile(activeUserId, openUserId, rankDicts);
        return;
    }
}

void KFHookGetSelfProfileMoveNext(void *self) {
    KF_CALL_ORIG_VOID(orig_GetSelfProfileMoveNext, self);
    observeGetSelfProfileCompletion(self);
}

#if IPA_CHINLAN
void KFHookGetSelfProfileMoveNextEntry(void *self) {
    MoveNextVoid_t bypass = (MoveNextVoid_t)
        g_inject_entry[KIOU_KF_HOOK_GET_SELF_PROFILE_MOVENEXT];
    if (bypass) {
        @try { bypass(self); }
        @catch (NSException *e) {
            IPALog([NSString stringWithFormat:
                      @"[ACCOUNT] GetSelfProfile.MoveNext chinlan bypass threw: %@", e]);
            return;
        }
    } else {
        IPALog(@"[ACCOUNT] GetSelfProfile.MoveNext chinlan bypass not published — "
               @"skipping observation");
        return;
    }
    observeGetSelfProfileCompletion(self);
}
#endif

// ===========================================================================
// AccountExists — observe + Force Register override
// ===========================================================================
typedef bool (*AccountExists_t)(void *data);
static AccountExists_t orig_AccountExists __attribute__((unused)) = NULL;

static void observeAccountExistsData(void *data) {
    if (!data) return;
    NSString *userName = readIl2CppStr(readPtr(data, OFF_USER_SAVE_DATA_USER_NAME));
    NSString *openId   = readIl2CppStr(readPtr(data, OFF_USER_SAVE_DATA_OPEN_ID));
    NSString *userId   = readIl2CppStr(readPtr(data, OFF_USER_SAVE_DATA_USER_ID));
    NSString *deviceId = readIl2CppStr(readPtr(data, OFF_USER_SAVE_DATA_DEVICE_ID));

    if (userId.length > 0) g_latestObservedUserId = userId;

    if (userId.length > 0 && deviceId.length > 0) {
        KFSaveAccount(deviceId, userName, openId, userId, deviceId);
        if (KFActiveAccountUserId().length == 0)
            KFSetActiveAccountUserId(userId);
    }
}

static bool accountExistsBody(void *data, bool origResult, const char *flavor) {
    observeAccountExistsData(data);
    bool forceRegister = KFForceRegisterOnNextLaunch();
    bool result = forceRegister ? false : origResult;
    if (forceRegister) {
        IPALog([NSString stringWithFormat:
                  @"[ACCOUNT] AccountExists (%s) overridden false (force_register)",
                  flavor]);
    }
    return result;
}

#if !IPA_CHINLAN
bool KFHookAccountExists(void *data) {
    bool origResult = false;
    @try { origResult = KF_CALL_ORIG_RET(bool, orig_AccountExists, data); }
    @catch (NSException *e) {
        IPALog([NSString stringWithFormat:@"[ACCOUNT] AccountExists orig threw: %@", e]);
    }
    return accountExistsBody(data, origResult, "jb");
}
#endif

#if IPA_CHINLAN
bool KFHookAccountExistsEntry(void *data) {
    bool origResult = false;
    AccountExists_t bypass = (AccountExists_t)
        g_inject_entry[KIOU_KF_HOOK_ACCOUNT_EXISTS];
    @try { origResult = bypass(data); }
    @catch (NSException *e) {
        IPALog([NSString stringWithFormat:
                  @"[ACCOUNT] AccountExists bypass threw: %@", e]);
    }
    return accountExistsBody(data, origResult, "chinlan");
}
#endif

// ===========================================================================
// RunResetUserDataSequenceAsync — generate fresh UUID for new account
// ===========================================================================
typedef KFUniTaskRet (*RunResetSeq_t)(void *ct);
static RunResetSeq_t orig_RunResetSeq         __attribute__((unused)) = NULL;
static RunResetSeq_t orig_RunDeleteAccountSeq __attribute__((unused)) = NULL;

KFUniTaskRet KFHookRunResetUserDataSeq(void *ct) {
    NSString *freshUuid = [[NSUUID UUID] UUIDString].lowercaseString;
    KFSetPendingDistinctId(freshUuid);
    KFSetPendingDeviceId(freshUuid);
    IPALog([NSString stringWithFormat:
              @"[ACCOUNT] RunResetUserDataSequenceAsync armed fresh_uuid=%@", freshUuid]);
    return KF_CALL_ORIG_RET(KFUniTaskRet, orig_RunResetSeq, ct);
}

KFUniTaskRet KFHookRunDeleteAccountSeq(void *ct) {
    IPALog([NSString stringWithFormat:
              @"[ACCOUNT] RunDeleteAccountSequenceAsync (active=%@)",
              KFActiveAccountUserId() ?: @"(none)"]);
    return KF_CALL_ORIG_RET(KFUniTaskRet, orig_RunDeleteAccountSeq, ct);
}

// ===========================================================================
// Public entry — drive BackToTitleSequence.RunAsync. Called by Settings UI
// after the user confirms the account-switch dialog so KIOU navigates back
// to the title scene, re-running AccountExists → LoginAsync with the
// pending_device_id substitution in effect (no app relaunch needed).
//
// BackToTitleSequence.RunAsync(CancellationToken) is a static method —
// no self pointer, and a default(CancellationToken) is encoded as NULL.
// ===========================================================================
typedef KFUniTaskRet (*BackToTitleRunAsync_t)(void *ct);

void KFNavigateToTitleScene(void) {
    if (g_unityBase == 0) {
        IPALog(@"[ACCOUNT] KFNavigateToTitleScene: unityBase not yet set");
        return;
    }
    BackToTitleRunAsync_t fn =
        (BackToTitleRunAsync_t)(g_unityBase + KIOU_KF_SITE_RVA_BACK_TO_TITLE_RUN_ASYNC);
    @try {
        (void)fn(NULL);
        IPALog(@"[ACCOUNT] BackToTitleSequence.RunAsync invoked");
    } @catch (NSException *e) {
        IPALog([NSString stringWithFormat:
                  @"[ACCOUNT] BackToTitleSequence.RunAsync threw: %@", e]);
    }
}

// ===========================================================================
// Installer
// ===========================================================================
void KFInstallAccountObserveHook(uintptr_t unityBase) {
    if (!g_il2cpp_string_new)
        g_il2cpp_string_new = (Il2CppStringNew_t)dlsym(RTLD_DEFAULT, "il2cpp_string_new");
#if IPA_CHINLAN
    IPALog(@"[ACCOUNT] chinlan: caves wired; JB-only hooks skipped");
#else
    struct { const char *tag; uintptr_t rva; void *hook; void **orig; } entries[] = {
        { "UserSaveDataExtensions.AccountExists",
          KF_RVA_ACCOUNT_EXISTS,
          (void *)KFHookAccountExists,
          (void **)&orig_AccountExists },
        { "ILoginArgs.Create",
          KF_RVA_LOGIN_ARGS_CREATE,
          (void *)KFHookLoginArgsCreate,
          (void **)&orig_LoginArgsCreate },
        { "IRegisterUserArgs.Create",
          KF_RVA_REGISTER_USER_ARGS_CREATE,
          (void *)KFHookRegisterUserArgsCreate,
          (void **)&orig_RegisterUserArgsCreate },
        { "RunLoginSequenceAsync.MoveNext",
          KF_RVA_RUN_LOGIN_SEQ_MOVENEXT,
          (void *)KFHookRunLoginSeqMoveNext,
          (void **)&orig_RunLoginSeqMoveNext },
        { "GetSelfUserProfileAsync.MoveNext",
          KF_RVA_GET_SELF_PROFILE_MOVENEXT,
          (void *)KFHookGetSelfProfileMoveNext,
          (void **)&orig_GetSelfProfileMoveNext },
        { "RunResetUserDataSequenceAsync",
          KF_RVA_RUN_RESET_USER_DATA_SEQ,
          (void *)KFHookRunResetUserDataSeq,
          (void **)&orig_RunResetSeq },
        { "RunDeleteAccountSequenceAsync",
          KF_RVA_RUN_DELETE_ACCOUNT_SEQ,
          (void *)KFHookRunDeleteAccountSeq,
          (void **)&orig_RunDeleteAccountSeq },
    };
    for (size_t i = 0; i < sizeof(entries)/sizeof(entries[0]); i++) {
        uintptr_t addr = unityBase + entries[i].rva;
        MSHookFunction((void *)addr, entries[i].hook, entries[i].orig);
        IPALog([NSString stringWithFormat:
                  @"[ACCOUNT] hooked %s @0x%lx", entries[i].tag, (unsigned long)addr]);
    }
    IPALog(@"[ACCOUNT] hooks installed");
#endif
}
