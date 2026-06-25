#pragma once

#import <Foundation/Foundation.h>
#import <stdbool.h>

// ===========================================================================
// account/Persistence.h — KiouForge account identity storage.
//
// Ported from KiouEngineBridge/Settings_Persistence.h.
// All keys are prefixed with "kiou_forge.account." to avoid collisions with
// other tweaks. The account model is identical to KEB so accounts.json files
// can be shared between the two tweaks.
//
// Storage layout (NSUserDefaults under "kiou_forge.account.accounts"):
//   NSArray<NSDictionary> — each entry:
//     uuid:       NSString   (LoginArgs.deviceId substitution target)
//     userName:   NSString   (display name)
//     openId:     NSString   (XXXX-YYYY-ZZZZ-WWWW)
//     userId:     NSString   (JWT.sub — primary key)
//     distinctId: NSString   (TDAnalytics UUID)
//     savedAt:    NSNumber   (UNIX seconds)
//     ranks:      NSArray    (optional)
// ===========================================================================

// Notification posted on any account state change.
extern NSString *const KFAccountStateChangedNotification;

// Save or refresh an account. Primary key is `userId`.
void KFSaveAccount(NSString *uuid,
                   NSString *userName,
                   NSString *openId,
                   NSString *userId,
                   NSString *distinctId);

// Return saved accounts in insertion order.
NSArray<NSDictionary *> *KFListAccounts(void);

// Delete an account by userId. No-op if not found.
void KFDeleteAccount(NSString *userId);

// Merge openId + ranks into the saved entry for userId.
void KFUpdateAccountProfile(NSString *userId,
                            NSString *openId,
                            NSArray<NSDictionary *> *ranks);

// Most recently observed active account userId.
NSString *KFActiveAccountUserId(void);
void      KFSetActiveAccountUserId(NSString *userId);

// When true, next AccountExists check returns false unconditionally,
// routing KIOU into the name-entry Register flow.
bool KFForceRegisterOnNextLaunch(void);
void KFSetForceRegisterOnNextLaunch(bool enabled);

// Pending deviceId override — swapped into LoginArgs.Create.
NSString *KFPendingDeviceId(void);
void      KFSetPendingDeviceId(NSString *uuid);

// Pending distinctId override — swapped into RegisterUserArgs.Create.
NSString *KFPendingDistinctId(void);
void      KFSetPendingDistinctId(NSString *uuid);

// Arm the pending_device_id for account switching.
// Refuses if pending_distinct_id is already set (mid-Register flow).
void KFSwitchAccount(NSString *uuid);
