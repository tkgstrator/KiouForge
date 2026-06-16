#import "Internal.h"

#if IPA_BINPATCH

#import "binpatch.h"
#include <stdint.h>

// ===========================================================================
// BinpatchEntries.m — KiouForge-local glue for the IPA_BINPATCH build.
//
// Mirrors the pattern from KiouEditor/BinpatchEntries.m. See that file and
// Sources/Common/binpatch.h for the full wiring explanation.
//
// Adding a new hook: add its slot to binpatch_sites.h, add a
// publish_*_slots() extern to Internal.h, and add a call here in
// publish_all(). The recipe's _SITES table and KIOU_SLOT_COUNT must match.
// ===========================================================================

void **g_kiou_hook_slot = NULL;

uintptr_t kiou_resolve_orig_trampoline(uintptr_t unityBase, uintptr_t siteRVA) {
    return ipa_binpatch_resolve_orig(unityBase, siteRVA,
                                     KIOU_BINPATCH_CAVE_PAYLOAD_SIZE);
}

static BOOL g_kiou_binpatch_published = NO;

static void publish_all(uintptr_t unityBase) {
    g_kiou_hook_slot = (void **)(unityBase + KIOU_HOOK_SLOT_BASE_RVA);
    file_log([NSString stringWithFormat:
              @"[binpatch] slot base=%p (unityBase+0x%X)",
              (void *)g_kiou_hook_slot, KIOU_HOOK_SLOT_BASE_RVA]);

    publish_FrameRate_slots(unityBase);
    publish_AfkDisable_slots(unityBase);
    publish_AnalysisTune_slots(unityBase);
    publish_Version_slots(unityBase);
    publish_KifuObserve_slots(unityBase);
}

void kiou_binpatch_bootstrap(void) {
    if (g_kiou_binpatch_published) return;

    uintptr_t unityBase = ipa_binpatch_find_image("UnityFramework");
    if (unityBase == 0) return;

    file_log([NSString stringWithFormat:
              @"[binpatch] UnityFramework base=0x%lx",
              (unsigned long)unityBase]);

    publish_all(unityBase);
    g_kiou_binpatch_published = YES;
    file_log(@"[binpatch] === all slots published ===");
}

BOOL kiou_binpatch_published(void) {
    return g_kiou_binpatch_published;
}

#endif  // IPA_BINPATCH
