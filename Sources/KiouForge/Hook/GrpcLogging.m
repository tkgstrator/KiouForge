#import "Internal.h"
#import "Account/Persistence.h"
#import <dlfcn.h>

// ===========================================================================
// Hook_GrpcLogging — swap x-user-id gRPC header on account switch.
//
// Ported from KiouEngineBridge/Hook_GrpcLogging.m.
//
// KIOU's gRPC stack passes an x-user-id request header that identifies the
// logged-in user.  When KFSwitchAccount arms pending_device_id, LoginArgs
// sends a different deviceId to the server, but the header still names the
// previous user — the server rejects with -40004.
//
// Fix: CAVE_ENTRY on HttpMessageInvoker.SendAsync (the virtual base that
// every gRPC call routes through). Before calling orig via bypass, rewrite
// the header so it matches the account we are switching to.
//
// Hook site (KIOU 1.0.2 build 12):
//   HttpMessageInvoker.SendAsync   RVA: 0x6082AC0   prologue: 000840f9
//   (This is a vtable thunk — do NOT binpatch; use CAVE_ENTRY via the recipe.)
//
// Helper RVAs (same build):
//   HttpHeaders.TryAddWithoutValidation(string,string)  RVA: 0x608E9B8
//   HttpHeaders.Remove(string)                          RVA: 0x608EE70
// ===========================================================================

// ---------------------------------------------------------------------------
// RVAs
// ---------------------------------------------------------------------------
#define RVA_HTTPHEADERS_TRYADD   0x608E9B8
#define RVA_HTTPHEADERS_REMOVE   0x608EE70

// ---------------------------------------------------------------------------
// HttpRequestMessage field offsets (dump.cs line 1540968)
// ---------------------------------------------------------------------------
#define OFF_REQ_HEADERS  0x10   // HttpRequestHeaders*

// ---------------------------------------------------------------------------
// Function pointer types
// ---------------------------------------------------------------------------
typedef bool  (*HttpHeadersTryAdd_t)(void *headers, void *name, void *value);
typedef bool  (*HttpHeadersRemove_t)(void *headers, void *name);
typedef void *(*GrpcIl2CppStringNew_t)(const char *utf8);

static HttpHeadersTryAdd_t   g_HttpHeadersTryAdd = NULL;
static HttpHeadersRemove_t   g_HttpHeadersRemove = NULL;
static GrpcIl2CppStringNew_t g_GrpcStringNew     = NULL;

// ---------------------------------------------------------------------------
// Resolve the target userId for the pending device switch.
// Returns nil if no switch is armed.
//
// We trust active_user_id (set by Settings UI when the user picks an
// account) rather than reverse-mapping deviceId -> userId via the saved
// accounts list — the latter falls over when the same uuid is shared by
// multiple userIds (server re-issued userId on the same deviceId).
// ---------------------------------------------------------------------------
static NSString *targetUserIdForPendingDevice(void) {
    if (KFPendingDeviceId().length == 0) return nil;
    return KFActiveAccountUserId();
}

// ---------------------------------------------------------------------------
// Swap x-user-id header to the target account's userId.
// No-op when no switch is armed or helpers are not yet resolved.
// ---------------------------------------------------------------------------
static void swapUserIdHeader(void *request) {
    if (!request || !g_HttpHeadersTryAdd || !g_HttpHeadersRemove ||
        !g_GrpcStringNew) return;
    NSString *targetUserId = targetUserIdForPendingDevice();
    if (targetUserId.length == 0) return;
    void *headers = readPtr(request, OFF_REQ_HEADERS);
    if (!headers) return;
    void *nameStr  = g_GrpcStringNew("x-user-id");
    void *valueStr = g_GrpcStringNew(targetUserId.UTF8String);
    if (!nameStr || !valueStr) return;
    @try {
        g_HttpHeadersRemove(headers, nameStr);
        g_HttpHeadersTryAdd(headers, nameStr, valueStr);
        IPALog([NSString stringWithFormat:
                  @"[GRPC] x-user-id swapped → %@", targetUserId]);
    } @catch (NSException *e) {
        IPALog([NSString stringWithFormat:@"[GRPC] x-user-id swap threw: %@", e]);
    }
}

// ===========================================================================
// Chinlan entry hook
// ===========================================================================
typedef void *(*GenericSendAsync_t)(void *self, void *request, void *ct);

#if IPA_CHINLAN
void *KFHookHttpMsgInvokerSendAsyncEntry(void *self, void *request, void *ct) {
    swapUserIdHeader(request);
    GenericSendAsync_t bypass =
        (GenericSendAsync_t)g_inject_entry[KIOU_KF_HOOK_HTTPMSGINVOKER_SEND_ASYNC];
    return bypass ? bypass(self, request, ct) : NULL;
}
#else
static GenericSendAsync_t orig_HttpMsgInvokerSendAsync __attribute__((unused)) = NULL;

static void *KFHookHttpMsgInvokerSendAsync(void *self, void *request, void *ct) {
    swapUserIdHeader(request);
    return orig_HttpMsgInvokerSendAsync
        ? orig_HttpMsgInvokerSendAsync(self, request, ct)
        : NULL;
}
#endif

void KFInstallGrpcLoggingHook(uintptr_t unityBase) {
    g_HttpHeadersTryAdd =
        (HttpHeadersTryAdd_t)(unityBase + RVA_HTTPHEADERS_TRYADD);
    g_HttpHeadersRemove =
        (HttpHeadersRemove_t)(unityBase + RVA_HTTPHEADERS_REMOVE);
    if (!g_GrpcStringNew)
        g_GrpcStringNew =
            (GrpcIl2CppStringNew_t)dlsym(RTLD_DEFAULT, "il2cpp_string_new");
#if IPA_CHINLAN
    IPALog([NSString stringWithFormat:
              @"[GRPC] chinlan: entry hook wired tryAdd=%p remove=%p strNew=%p",
              g_HttpHeadersTryAdd, g_HttpHeadersRemove, g_GrpcStringNew]);
#else
    uintptr_t addr = unityBase + KIOU_KF_SITE_RVA_HTTPMSGINVOKER_SEND_ASYNC;
    MSHookFunction((void *)addr,
                   (void *)KFHookHttpMsgInvokerSendAsync,
                   (void **)&orig_HttpMsgInvokerSendAsync);
    IPALog([NSString stringWithFormat:
              @"[GRPC] hooked HttpMessageInvoker.SendAsync @0x%lx",
              (unsigned long)addr]);
#endif
}
