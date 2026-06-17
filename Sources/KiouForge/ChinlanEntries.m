#import "Internal.h"

#if IPA_CHINLAN

#import "chinlan.h"
#include <stdint.h>

// ===========================================================================
// ChinlanEntries.m — KiouForge-local glue for the IPA_CHINLAN build.
//
// Mirrors the pattern from KiouEditor/ChinlanEntries.m. See that file and
// Sources/Chinlan/chinlan.h for the full wiring explanation.
//
// Adding a new hook: add its slot to ChinlanSites.h, add a
// KFPublish*Slots() extern to Internal.h, and add a call here in
// kfPublishAll(). The recipe's _SITES table and KIOU_SLOT_COUNT must match.
// ===========================================================================

void **g_kfHookSlot = NULL;

uintptr_t KFResolveOrigTrampoline(uintptr_t unityBase, uintptr_t siteRVA) {
    return IPAChinlanResolveOrig(unityBase, siteRVA,
                                     KIOU_CHINLAN_CAVE_PAYLOAD_SIZE);
}

static BOOL g_kiou_chinlan_published = NO;

static void kfPublishAll(uintptr_t unityBase) {
    g_kfHookSlot = (void **)(unityBase + KIOU_HOOK_SLOT_BASE_RVA);
    IPALog([NSString stringWithFormat:
              @"[Chinlan] slot base=%p (unityBase+0x%X)",
              (void *)g_kfHookSlot, KIOU_HOOK_SLOT_BASE_RVA]);

    KFPublishFrameRateSlots(unityBase);
    KFPublishAfkDisableSlots(unityBase);
    KFPublishAnalysisTuneSlots(unityBase);
    KFPublishKifuObserveSlots(unityBase);
}

void KFChinlanBootstrap(void) {
    if (g_kiou_chinlan_published) return;

    uintptr_t unityBase = IPAChinlanFindImage("UnityFramework");
    if (unityBase == 0) return;

    IPALog([NSString stringWithFormat:
              @"[Chinlan] UnityFramework base=0x%lx",
              (unsigned long)unityBase]);

    kfPublishAll(unityBase);
    g_kiou_chinlan_published = YES;
    IPALog(@"[Chinlan] === all slots published ===");
}

BOOL KFChinlanPublished(void) {
    return g_kiou_chinlan_published;
}

#endif  // IPA_CHINLAN
