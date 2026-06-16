#import "Internal.h"
#import "Settings.h"
#import <mach-o/dyld.h>
#import <string.h>

// ===========================================================================
// KiouForge — entry point.
//
// Distribution shapes:
//   JB rootless / jailed (Dobby static): KFInstall*Hook() patches the
//     UnityFramework at runtime via MSHookFunction / DobbyHook.
//   Binpatch (make ipa): UnityFramework is statically rewritten so each
//     site BLs into a __TEXT cave; the dylib publishes hook pointers into
//     the __DATA slot table.
// ===========================================================================

#if IPA_BINPATCH

static void tryBootstrap(void) {
    if (!KFBinpatchPublished()) KFBinpatchBootstrap();
    if (!KFBinpatchPublished()) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            tryBootstrap();
        });
    }
}

#else  // !IPA_BINPATCH

static BOOL g_unityHooked = NO;

static void installUnityHooks(void) {
    if (g_unityHooked) return;

    uint32_t imgCount = _dyld_image_count();
    uintptr_t unityBase = 0;
    const char *unityName = NULL;
    for (uint32_t i = 0; i < imgCount; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "UnityFramework")) {
            unityBase = (uintptr_t)_dyld_get_image_header(i);
            unityName = name;
            break;
        }
    }
    if (unityBase == 0) return;

    file_log([NSString stringWithFormat:
              @"UnityFramework base=0x%lx (%s)",
              (unsigned long)unityBase, unityName ? unityName : "?"]);

    KFInstallFrameRateHook(unityBase);
    KFInstallAfkDisableHook(unityBase);
    KFInstallAnalysisTuneHook(unityBase);
    KFInstallVersionHook(unityBase);
    KFInstallKifuObserveHook(unityBase);

    g_unityHooked = YES;
    file_log(@"=== All KiouForge hooks installed ===");
}

static void retryInstallHooks(void) {
    if (!g_unityHooked) installUnityHooks();
    if (!g_unityHooked) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            retryInstallHooks();
        });
    }
}

#endif  // IPA_BINPATCH

__attribute__((constructor)) static void init(void) {
    logging_init("com.neconome.shogi.kiouforge");
    file_log([NSString stringWithFormat:
              @"=== KiouForge %s (%s) loaded ===",
              KIOU_FORGE_VERSION, KIOU_FORGE_COMMIT]);

#if IPA_BINPATCH
    tryBootstrap();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        tryBootstrap();
    });
#else
    installUnityHooks();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        retryInstallHooks();
    });
#endif

    KFGestureInstall();

    file_log(@"=== KiouForge constructor done ===");
}
