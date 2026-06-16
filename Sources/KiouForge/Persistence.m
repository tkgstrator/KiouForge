#import "Internal.h"

// ===========================================================================
// Persistence.m — KiouForge feature flags and engine tuning storage.
//
// All keys under the "kiou_forge.*" namespace in NSUserDefaults.
// Feature flags default to YES so a fresh install is all-on.
// ===========================================================================

static NSString *featureKey(KiouFeature f) {
    switch (f) {
        case KIOU_FEATURE_FPS_OVERRIDE:  return @"kiou_forge.feature.fps_override";
        case KIOU_FEATURE_DISABLE_AFK:   return @"kiou_forge.feature.disable_afk";
        case KIOU_FEATURE_ANALYSIS_TUNE: return @"kiou_forge.feature.analysis_tune";
        default: return nil;
    }
}

NSString *kiou_featureLabel(KiouFeature f) {
    switch (f) {
        case KIOU_FEATURE_FPS_OVERRIDE:  return @"FPS Override";
        case KIOU_FEATURE_DISABLE_AFK:   return @"AFK Guard";
        case KIOU_FEATURE_ANALYSIS_TUNE: return @"Analysis Tune";
        default: return @"";
    }
}

bool kiou_featureEnabled(KiouFeature f) {
    NSString *key = featureKey(f);
    if (!key) return false;
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    id obj = [defs objectForKey:key];
    if (obj == nil) return true;  // all features default on
    return [defs boolForKey:key];
}

void kiou_setFeatureEnabled(KiouFeature f, bool enabled) {
    NSString *key = featureKey(f);
    if (!key) return;
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    [defs setBool:enabled forKey:key];
    [defs synchronize];
}

// ---------------------------------------------------------------------------
// FPS preset table and accessor.
// Default index 4 = 60 (retail default) so a fresh install does not
// silently change behaviour.
// ---------------------------------------------------------------------------

static NSString *const kFpsIndexKey = @"kiou_forge.fps_index";

static const int32_t kFpsPresets[KIOU_FPS_PRESET_COUNT] = {
    15, 24, 30, 45, 60, 90, 120
};

static int32_t clampInt(int32_t v, int32_t lo, int32_t hi) {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

int32_t kiou_fpsIndex(void) {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    if ([defs objectForKey:kFpsIndexKey] == nil) return 4;  // index 4 = 60 fps
    return clampInt((int32_t)[defs integerForKey:kFpsIndexKey],
                    0, KIOU_FPS_PRESET_COUNT - 1);
}

void kiou_setFpsIndex(int32_t idx) {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    [defs setInteger:clampInt(idx, 0, KIOU_FPS_PRESET_COUNT - 1)
              forKey:kFpsIndexKey];
    [defs synchronize];
}

int32_t kiou_targetFps(void) {
    return kFpsPresets[kiou_fpsIndex()];
}

// ---------------------------------------------------------------------------
// Post-game analysis engine tuning.
// ---------------------------------------------------------------------------

static NSString *const kAnalysisDepthKey      = @"kiou_forge.analysis_depth";
static NSString *const kAnalysisHashIndexKey  = @"kiou_forge.analysis_hash_idx";
static NSString *const kAnalysisSkillLevelKey = @"kiou_forge.analysis_skill_level";

int32_t kiou_analysisDepth(void) {
    // Match the retail KifuDetailPopupAnalysisPresenter.SearchDepth default (15).
    // Users raise it for stronger analysis at the cost of longer run time.
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    if ([defs objectForKey:kAnalysisDepthKey] == nil) return 15;
    return clampInt((int32_t)[defs integerForKey:kAnalysisDepthKey], 1, 36);
}

void kiou_setAnalysisDepth(int32_t v) {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    [defs setInteger:clampInt(v, 1, 36) forKey:kAnalysisDepthKey];
    [defs synchronize];
}

// Hash MB presets. Default index 0 = 16 MB (retail default) so a fresh
// install matches the game's own behavior.
static const int32_t kAnalysisHashPresetsMB[KIOU_ANALYSIS_HASH_PRESET_COUNT] = {
    16, 64, 128, 256, 512, 1024
};

int32_t kiou_analysisHashIndex(void) {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    if ([defs objectForKey:kAnalysisHashIndexKey] == nil) return 0;  // 16 MB
    return clampInt((int32_t)[defs integerForKey:kAnalysisHashIndexKey],
                    0, KIOU_ANALYSIS_HASH_PRESET_COUNT - 1);
}

void kiou_setAnalysisHashIndex(int32_t idx) {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    [defs setInteger:clampInt(idx, 0, KIOU_ANALYSIS_HASH_PRESET_COUNT - 1)
              forKey:kAnalysisHashIndexKey];
    [defs synchronize];
}

int32_t kiou_analysisHashMB(void) {
    return kAnalysisHashPresetsMB[kiou_analysisHashIndex()];
}

int32_t kiou_analysisSkillLevel(void) {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    if ([defs objectForKey:kAnalysisSkillLevelKey] == nil) return 20;
    return clampInt((int32_t)[defs integerForKey:kAnalysisSkillLevelKey], 1, 20);
}

void kiou_setAnalysisSkillLevel(int32_t v) {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    [defs setInteger:clampInt(v, 1, 20) forKey:kAnalysisSkillLevelKey];
    [defs synchronize];
}
