#import "Internal.h"

// ===========================================================================
// Kif_Writer.m — the entire reason this tweak exists.
//
// Called from Hook_MatchModeObserve.m::END_HOOK once OnMatchEndAsync fires.
// Reads the KIF text off the live GameController and writes it as a UTF-8
// .kif file under Documents/KiouForge/.
//
// Filename format:
//
//   {ISO8601_UTC}_{mode}_{black}vs{white}_{startpos}.kif
//
//   ISO8601_UTC : "20260614T234500" (UTC)
//   mode        : "AIMatchMode" | "CPUStreamMode" | "OnlinePvPMode"
//                 | "LocalPvPMode" | "RecordReplayMode" | "unknown"
//   black/white : player name strings, Unicode preserved (Japanese names
//                 are kept as-is; only NUL, '/', and control characters
//                 are stripped). Falls back to "unknown" per side.
//   startpos    : "startpos" | "sfen-<8 hex>" | "unknown"
//
// APFS and iOS Files handle Unicode filenames natively, so Japanese user
// names are safe to include directly without percent-encoding or hashing.
// ===========================================================================

NSString *KFKifWriterEmit(void *gameCtrl,
                                        void *matchConfig,
                                        void *stateStore,
                                        const char *matchModeTag) {
    // 1. Get the KIF text. matchConfig / stateStore may be NULL — in
    //    that case player names and time-rule label come out blank,
    //    which is acceptable.
    NSString *kif = KFKifTextFromGameController(gameCtrl,
                                              matchConfig,
                                              stateStore,
                                              matchModeTag);
    if (kif.length == 0) {
        IPALog([NSString stringWithFormat:
                  @"[KIF] emit skipped: GetKifuText returned empty "
                  @"(gameCtrl=%p mode=%s)",
                  gameCtrl, matchModeTag ? matchModeTag : "unknown"]);
        return nil;
    }

    // 2. Make sure the output directory exists.
    NSString *outDir = KFKifEnsureOutputDir();
    if (!outDir) {
        IPALog(@"[KIF] emit failed: output dir unavailable");
        return nil;
    }

    // 3. Build the filename.
    //    Format: {timestamp}_{mode}_{black}vs{white}_{startpos}.kif
    //    Player names are kept as-is (Unicode) — APFS and iOS Files handle
    //    Japanese filenames natively. Only POSIX-unsafe characters (NUL, '/',
    //    control codes) are stripped by KFKifSanitizeSegment.
    NSString *ts = KFKifTimestamp();
    NSString *modeSeg = KFKifSanitizeSegment(
        matchModeTag ? @(matchModeTag) : @"unknown", 32);
    NSString *opponentsSeg = KFKifDescribeOpponents(matchConfig, stateStore);
    NSString *startposSeg = KFKifDescribeStartpos(gameCtrl);

    NSString *filename = [NSString stringWithFormat:@"%@_%@_%@_%@.kif",
                          ts, modeSeg, opponentsSeg, startposSeg];
    NSString *path = [outDir stringByAppendingPathComponent:filename];

    // 4. Write atomically. KIF is a text format — UTF-8 with BOM-less
    //    output is what every Japanese kifu viewer (PiyoShogi, Shogi
    //    Browser Q, KifuCloud, …) accepts.
    NSError *err = nil;
    BOOL ok = [kif writeToFile:path
                    atomically:YES
                      encoding:NSUTF8StringEncoding
                         error:&err];
    if (!ok) {
        IPALog([NSString stringWithFormat:
                  @"[KIF] write failed: path=%@ err=%@", path, err]);
        return nil;
    }

    IPALog([NSString stringWithFormat:
              @"[KIF] wrote %lu bytes -> %@",
              (unsigned long)[kif lengthOfBytesUsingEncoding:NSUTF8StringEncoding],
              path]);
    return path;
}

// ===========================================================================
// KFKifuObserveMatchEnd — entry point for all 5 IMatchMode.OnMatchEnd
// sites. The observer cave (recipes/kiouforge.py) saves caller registers,
// injects the mode index in X2 via MOVZ, BLRs through the slot, restores
// registers, executes the displaced prologue, then jumps to orig+4. So
// our return value is effectively dead — we still zero a KFUniTaskRet for
// shape correctness.
//
// We honour two feature flags:
//   * master KIOU_FEATURE_KIFU_AUTOSAVE
//   * per-mode KFKifuModeEnabled(mode_index)
// Either being off skips emission silently.
// ===========================================================================

#define ONLINEPVPMODE_OFF_STATE_STORE   0x28
#define ONLINEPVPMODE_OFF_MATCHCONFIG   0x38

static void *kf_resolveGameController(void *self, uint32_t mode_index) {
    if (mode_index >= KIOU_MMODE_COUNT) {
        IPALog([NSString stringWithFormat:
                  @"[KIFU] mode_index=%u out of range", mode_index]);
        return NULL;
    }
    if (!ptrLooksValid(self)) return NULL;
    uintptr_t adapterOff = kKiouMatchModeAdapterOffsets[mode_index];
    void *adapter = readPtr(self, adapterOff);
    if (!adapter) {
        IPALog([NSString stringWithFormat:
                  @"[KIFU] resolve: self=%p mode=%s adapterOff=0x%lx -> adapter=NULL",
                  self, kKiouMatchModeTags[mode_index],
                  (unsigned long)adapterOff]);
        return NULL;
    }
    return readPtr(adapter, KIOU_ADAPTER_OFF_GAMECTRL);
}

KFUniTaskRet KFKifuObserveMatchEnd(void *self, void *ct,
                                      uint32_t mode_index) {
    (void)ct;
    KFUniTaskRet zero = { NULL, NULL };

    // Master toggle.
    if (!KFFeatureEnabled(KIOU_FEATURE_KIFU_AUTOSAVE)) return zero;

    // Per-mode toggle.
    if (mode_index < KIOU_MMODE_COUNT &&
        !KFKifuModeEnabled((KiouMatchMode)mode_index)) {
        return zero;
    }

    const char *modeName = (mode_index < KIOU_MMODE_COUNT)
                         ? kKiouMatchModeTags[mode_index] : "Unknown";

    void *gameCtrl = kf_resolveGameController(self, mode_index);
    if (!gameCtrl) {
        IPALog([NSString stringWithFormat:
                  @"[KIFU] %s self=%p: GameController unresolved, skipping",
                  modeName, self]);
        return zero;
    }

    // MatchConfig / GameStateStore only available on OnlinePvPMode's `self`;
    // other modes' KIF gets blank player names (acceptable for offline play).
    void *matchConfig = NULL;
    void *stateStore  = NULL;
    if (mode_index == KIOU_MMODE_ONLINE_PVP && ptrLooksValid(self)) {
        matchConfig = readPtr(self, ONLINEPVPMODE_OFF_MATCHCONFIG);
        stateStore  = readPtr(self, ONLINEPVPMODE_OFF_STATE_STORE);
    }

    IPALog([NSString stringWithFormat:
              @"[KIFU] %s self=%p gameCtrl=%p matchConfig=%p stateStore=%p — emitting",
              modeName, self, gameCtrl, matchConfig, stateStore]);

    NSString *path = KFKifWriterEmit(gameCtrl, matchConfig, stateStore, modeName);
    if (path) {
        IPALog([NSString stringWithFormat:@"[KIFU] %s -> %@", modeName, path]);
    }
    return zero;
}
