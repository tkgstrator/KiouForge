#import "Internal.h"
#import "Settings.h"
#import "Account/Persistence.h"
#import <UIKit/UIKit.h>

// ===========================================================================
// Hook_SettingsUI.m — UIKit settings modal for KiouForge.
//
// Presented by the right-edge swipe gesture (Settings.m).
// Three sections:
//   "Features"   — one UISwitch per KiouFeature
//   "Engine"     — Analysis Hash and Skill steppers
//   "About"      — repo link, author X handle, build commit
// ===========================================================================

// Declare the apply helper from Hook_FrameRate.m so we can call it from
// the FPS stepper callback.
extern void KFApplyFPS(int32_t fps);

// ---------------------------------------------------------------------------
// KFAccountsViewController — account list with select / delete / reorder.
// ---------------------------------------------------------------------------
@interface KFAccountsViewController : UITableViewController
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *accounts;
@end

@implementation KFAccountsViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    self.title = @"Accounts";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UIBarButtonItem *share =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                      target:self
                                                      action:@selector(exportAccounts:)];
    self.navigationItem.rightBarButtonItems = @[self.editButtonItem, share];
    self.accounts = [NSMutableArray arrayWithArray:KFListAccounts()];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(onAccountStateChanged:)
               name:KFAccountStateChangedNotification
             object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.accounts = [NSMutableArray arrayWithArray:KFListAccounts()];
    [self.tableView reloadData];
}

- (void)onAccountStateChanged:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.accounts = [NSMutableArray arrayWithArray:KFListAccounts()];
        [self.tableView reloadData];
    });
}

- (void)exportAccounts:(UIBarButtonItem *)sender {
    NSError *err = nil;
    NSData *data = [NSJSONSerialization
                       dataWithJSONObject:KFListAccounts()
                                  options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                    error:&err];
    if (data.length == 0) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Export failed"
                              message:err.localizedDescription ?: @"(unknown)"
                       preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    NSURL *tmpURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:@"kf_accounts.json"]];
    [data writeToURL:tmpURL atomically:YES];
    UIActivityViewController *vc =
        [[UIActivityViewController alloc] initWithActivityItems:@[tmpURL]
                                          applicationActivities:nil];
    vc.popoverPresentationController.barButtonItem = sender;
    [self presentViewController:vc animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return self.accounts.count;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
    if (self.accounts.count == 0)
        return @"No accounts saved yet. Log in once and KiouForge will remember the identity.";
    return @"Tap to switch. App relaunch required.";
}

- (UITableViewCell *)tableView:(UITableView *)tv
         cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *kId = @"kf_account_row";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:kId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:kId];
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.showsReorderControl = YES;
    }
    NSDictionary *acc = self.accounts[ip.row];
    NSString *userName = acc[@"userName"];
    NSString *openId   = acc[@"openId"];
    NSString *userId   = acc[@"userId"];
    cell.textLabel.text       = userName.length > 0 ? userName : @"(no name)";
    cell.detailTextLabel.text = openId.length  > 0 ? openId  : @"(no open id)";
    NSString *activeUserId = KFActiveAccountUserId();
    cell.accessoryType = ([userId isKindOfClass:[NSString class]] &&
                          [userId isEqualToString:activeUserId])
        ? UITableViewCellAccessoryCheckmark
        : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (self.tableView.isEditing) return;
    if (ip.row >= (NSInteger)self.accounts.count) return;
    NSDictionary *acc = self.accounts[ip.row];
    NSString *userId   = acc[@"userId"];
    NSString *uuid     = acc[@"uuid"];
    NSString *userName = acc[@"userName"];
    if (![userId isKindOfClass:[NSString class]] || userId.length == 0) return;
    NSString *title = [NSString stringWithFormat:@"%@に切り替え",
                       userName.length > 0 ? userName : @"このアカウント"];
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:title
                          message:nil
                   preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"切り替え"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *_) {
        if (uuid.length > 0) KFSwitchAccount(uuid);
        KFSetActiveAccountUserId(userId);
        // Close the settings modal then let KIOU navigate itself back to the
        // title scene — that re-runs AccountExists → LoginAsync with the
        // pending_device_id substitution in effect, no app relaunch needed.
        UIViewController *modalRoot = self.navigationController ?: self;
        UIViewController *presenter = modalRoot.presentingViewController;
        [presenter dismissViewControllerAnimated:YES completion:^{
            KFNavigateToTitleScene();
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip { return YES; }
- (BOOL)tableView:(UITableView *)tv canMoveRowAtIndexPath:(NSIndexPath *)ip { return YES; }

- (void)tableView:(UITableView *)tv
    commitEditingStyle:(UITableViewCellEditingStyle)style
     forRowAtIndexPath:(NSIndexPath *)ip {
    if (style != UITableViewCellEditingStyleDelete) return;
    if (ip.row >= (NSInteger)self.accounts.count) return;
    NSString *userId = self.accounts[ip.row][@"userId"];
    [self.accounts removeObjectAtIndex:ip.row];
    if ([userId isKindOfClass:[NSString class]]) KFDeleteAccount(userId);
    [tv deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)tableView:(UITableView *)tv
    moveRowAtIndexPath:(NSIndexPath *)src
           toIndexPath:(NSIndexPath *)dst {
    if (src.row >= (NSInteger)self.accounts.count) return;
    NSDictionary *moved = self.accounts[src.row];
    [self.accounts removeObjectAtIndex:src.row];
    [self.accounts insertObject:moved atIndex:dst.row];
    [[NSUserDefaults standardUserDefaults] setObject:self.accounts
                                              forKey:@"kiou_forge.account.accounts"];
}

@end

// ---------------------------------------------------------------------------
// Root settings view controller.
// ---------------------------------------------------------------------------
@interface KFSettingsViewController : UITableViewController
@property (nonatomic, strong) UILabel *fpsValueLabel;
@property (nonatomic, strong) UILabel *depthValueLabel;
@property (nonatomic, strong) UILabel *hashValueLabel;
@property (nonatomic, strong) UILabel *skillValueLabel;
@end

// Sub-screen: per-match-mode toggles for kifu autosave.
@interface KFKifuModesViewController : UITableViewController
@end

// Mirror of the preset tables in Persistence.m for local label rendering.
static const int32_t kFpsPresets[]  = { 15, 24, 30, 45, 60, 90, 120 };
static const int32_t kHashPresets[] = { 16, 64, 128, 256, 512, 1024 };

#define KF_SECTION_ACCOUNT     0
#define KF_SECTION_FEATURES    1
#define KF_SECTION_PERFORMANCE 2
#define KF_SECTION_ENGINE      3
#define KF_SECTION_ABOUT       4
#define KF_SECTION_COUNT       5

#define KF_ACCOUNT_ROW_ACTIVE         0
#define KF_ACCOUNT_ROW_FORCE_REGISTER 1
#define KF_ACCOUNT_ROW_COUNT          2

#define KF_PERF_ROW_FPS     0
#define KF_PERF_ROW_COUNT   1

#define KF_ENGINE_ROW_DEPTH 0
#define KF_ENGINE_ROW_HASH  1
#define KF_ENGINE_ROW_SKILL 2
#define KF_ENGINE_ROW_COUNT 3

#define KF_ABOUT_ROW_REPO    0
#define KF_ABOUT_ROW_TWITTER 1
#define KF_ABOUT_ROW_COUNT   2

static NSString *const kAboutRepoURL    = @"https://github.com/IPA-Patch/KiouForge";
static NSString *const kAboutTwitterURL = @"https://x.com/tkgling";

@implementation KFSettingsViewController

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        self.title = @"KiouForge";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                             target:self
                             action:@selector(onClose:)];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(onAccountStateChanged:)
               name:KFAccountStateChangedNotification
             object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)onAccountStateChanged:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isViewLoaded && self.view.window) {
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:KF_SECTION_ACCOUNT]
                          withRowAnimation:UITableViewRowAnimationNone];
        }
    });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Reload after returning from a sub-screen so the feature row's
    // disclosure caption (e.g. "3 of 5") and switches reflect any
    // changes made there.
    [self.tableView reloadData];
}

- (void)onClose:(id)sender {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return KF_SECTION_COUNT;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case KF_SECTION_ACCOUNT:     return @"Account";
        case KF_SECTION_FEATURES:    return @"Features";
        case KF_SECTION_PERFORMANCE: return @"Performance";
        case KF_SECTION_ENGINE:      return @"Engine";
        case KF_SECTION_ABOUT:       return @"About";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == KF_SECTION_ACCOUNT) {
        return @"New Register: routes the next launch into the name-entry "
               @"flow to create a fresh account without going through KIOU's "
               @"Reset button.";
    }
    if (section == KF_SECTION_FEATURES) {
        return @"AFK Guard suppresses the \"no input\" warning during long-think "
               @"sessions. Analysis Tune strengthens the on-device engine "
               @"used for post-game kifu analysis only — never in live play.";
    }
    if (section == KF_SECTION_PERFORMANCE) {
        return @"FPS preset; >60 requires a ProMotion device and the Patched "
               @"IPA build (CADisableMinimumFrameDurationOnPhone is added "
               @"automatically).";
    }
    if (section == KF_SECTION_ENGINE) {
        return @"Analysis Depth / Hash / Skill apply to the on-device engine "
               @"used for post-game kifu analysis only "
               @"(retail defaults: depth 15 / 16 MB / skill 20). "
               @"Higher depth and hash give a stronger analysis at the cost "
               @"of longer run time.";
    }
    if (section == KF_SECTION_ABOUT) {
        return [NSString stringWithFormat:@"%s (%s)",
                KIOU_FORGE_VERSION, KIOU_FORGE_COMMIT];
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case KF_SECTION_ACCOUNT:     return KF_ACCOUNT_ROW_COUNT;
        case KF_SECTION_FEATURES:    return KIOU_FEATURE_COUNT;
        case KF_SECTION_PERFORMANCE: return KF_PERF_ROW_COUNT;
        case KF_SECTION_ENGINE:      return KF_ENGINE_ROW_COUNT;
        case KF_SECTION_ABOUT:       return KF_ABOUT_ROW_COUNT;
        default: return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == KF_SECTION_ACCOUNT) {
        if (indexPath.row == KF_ACCOUNT_ROW_ACTIVE) {
            static NSString *kId = @"kf_account_active";
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kId];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                              reuseIdentifier:kId];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
            }
            cell.textLabel.text = @"Active";
            NSString *activeUserId = KFActiveAccountUserId();
            NSString *activeName = nil;
            for (NSDictionary *acc in KFListAccounts()) {
                NSString *u = acc[@"userId"];
                if ([u isKindOfClass:[NSString class]] && [u isEqualToString:activeUserId]) {
                    NSString *n = acc[@"userName"];
                    if ([n isKindOfClass:[NSString class]]) activeName = n;
                    break;
                }
            }
            cell.detailTextLabel.text =
                activeName.length > 0 ? activeName : @"(not logged in)";
            return cell;
        }
        // KF_ACCOUNT_ROW_FORCE_REGISTER
        static NSString *kId2 = @"kf_force_register";
        UITableViewCell *cell2 = [tableView dequeueReusableCellWithIdentifier:kId2];
        if (!cell2) {
            cell2 = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                           reuseIdentifier:kId2];
            cell2.selectionStyle = UITableViewCellSelectionStyleNone;
            UISwitch *sw = [[UISwitch alloc] init];
            [sw addTarget:self action:@selector(onForceRegisterChanged:)
         forControlEvents:UIControlEventValueChanged];
            cell2.accessoryView = sw;
        }
        cell2.textLabel.text = @"New Register";
        ((UISwitch *)cell2.accessoryView).on = KFForceRegisterOnNextLaunch();
        return cell2;
    }

    if (indexPath.section == KF_SECTION_FEATURES) {
        KiouFeature f = (KiouFeature)indexPath.row;
        // Two row shapes:
        //   * Plain toggle row     — UISwitch accessory, no disclosure.
        //   * Navigation row       — Value1 cell with detail caption (e.g.
        //                            "3 of 5") + disclosure indicator.
        // We dequeue under distinct identifiers so the cached style stays
        // correct across reuse.
        if (KFFeatureHasNavigation(f)) {
            static NSString *kId = @"feature-nav";
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kId];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                              reuseIdentifier:kId];
            }
            cell.textLabel.text = KFFeatureLabel(f);
            cell.accessoryView = nil;  // disclosure indicator below
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            // Caption: master state + per-mode count for Kifu Autosave.
            if (f == KIOU_FEATURE_KIFU_AUTOSAVE) {
                if (!KFFeatureEnabled(f)) {
                    cell.detailTextLabel.text = @"Off";
                } else {
                    int32_t on = 0;
                    for (int i = 0; i < KIOU_MMODE_COUNT; i++) {
                        if (KFKifuModeEnabled((KiouMatchMode)i)) on++;
                    }
                    cell.detailTextLabel.text =
                        [NSString stringWithFormat:@"%d of %ld",
                         on, (long)KIOU_MMODE_COUNT];
                }
            } else {
                cell.detailTextLabel.text =
                    KFFeatureEnabled(f) ? @"On" : @"Off";
            }
            cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
            return cell;
        }

        static NSString *kId = @"feature";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kId];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                          reuseIdentifier:kId];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
        cell.textLabel.text = KFFeatureLabel(f);
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = KFFeatureEnabled(f);
        sw.tag = f;
        [sw addTarget:self action:@selector(onFeatureToggle:)
     forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }

    if (indexPath.section == KF_SECTION_PERFORMANCE) {
        static NSString *kId = @"perf";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kId];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                          reuseIdentifier:kId];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
        cell.accessoryView = nil;
        UIStepper *stepper = [[UIStepper alloc] init];
        stepper.continuous = NO;

        // Only one row in Performance (FPS) for now.
        int32_t idx = KFFPSIndex();
        cell.textLabel.text = @"FPS";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%d", kFpsPresets[idx]];
        self.fpsValueLabel = cell.detailTextLabel;
        stepper.minimumValue = 0;
        stepper.maximumValue = KIOU_FPS_PRESET_COUNT - 1;
        stepper.stepValue    = 1;
        stepper.value        = idx;
        [stepper addTarget:self action:@selector(onFpsChanged:)
            forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = stepper;
        return cell;
    }

    if (indexPath.section == KF_SECTION_ENGINE) {
        static NSString *kId = @"engine";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kId];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                          reuseIdentifier:kId];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
        cell.accessoryView = nil;
        UIStepper *stepper = [[UIStepper alloc] init];
        stepper.continuous = NO;

        if (indexPath.row == KF_ENGINE_ROW_DEPTH) {
            cell.textLabel.text = @"Analysis Depth";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%d",
                                         (int)KFAnalysisDepth()];
            self.depthValueLabel = cell.detailTextLabel;
            stepper.minimumValue = 1;
            stepper.maximumValue = 36;
            stepper.stepValue    = 1;
            stepper.value        = KFAnalysisDepth();
            [stepper addTarget:self action:@selector(onDepthChanged:)
                forControlEvents:UIControlEventValueChanged];

        } else if (indexPath.row == KF_ENGINE_ROW_HASH) {
            int32_t idx = KFAnalysisHashIndex();
            cell.textLabel.text = @"Analysis Hash";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%d MB", kHashPresets[idx]];
            self.hashValueLabel = cell.detailTextLabel;
            stepper.minimumValue = 0;
            stepper.maximumValue = KIOU_ANALYSIS_HASH_PRESET_COUNT - 1;
            stepper.stepValue    = 1;
            stepper.value        = idx;
            [stepper addTarget:self action:@selector(onHashChanged:)
                forControlEvents:UIControlEventValueChanged];

        } else { // KF_ENGINE_ROW_SKILL
            cell.textLabel.text = @"Analysis Skill";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%d",
                                         (int)KFAnalysisSkillLevel()];
            self.skillValueLabel = cell.detailTextLabel;
            stepper.minimumValue = 1;
            stepper.maximumValue = 20;
            stepper.stepValue    = 1;
            stepper.value        = KFAnalysisSkillLevel();
            [stepper addTarget:self action:@selector(onSkillChanged:)
                forControlEvents:UIControlEventValueChanged];
        }
        cell.accessoryView = stepper;
        return cell;
    }

    // About section
    static NSString *kId = @"about";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:kId];
    }
    if (indexPath.row == KF_ABOUT_ROW_REPO) {
        cell.textLabel.text       = @"GitHub";
        cell.detailTextLabel.text = kAboutRepoURL;
    } else {
        cell.textLabel.text       = @"Author (X)";
        cell.detailTextLabel.text = kAboutTwitterURL;
    }
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == KF_SECTION_ACCOUNT &&
        indexPath.row == KF_ACCOUNT_ROW_ACTIVE) {
        KFAccountsViewController *vc = [[KFAccountsViewController alloc] init];
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }

    if (indexPath.section == KF_SECTION_FEATURES) {
        KiouFeature f = (KiouFeature)indexPath.row;
        if (!KFFeatureHasNavigation(f)) return;
        if (f == KIOU_FEATURE_KIFU_AUTOSAVE) {
            KFKifuModesViewController *vc = [[KFKifuModesViewController alloc] init];
            [self.navigationController pushViewController:vc animated:YES];
        }
        return;
    }

    if (indexPath.section != KF_SECTION_ABOUT) return;
    NSString *str = (indexPath.row == KF_ABOUT_ROW_REPO) ? kAboutRepoURL : kAboutTwitterURL;
    NSURL *url = [NSURL URLWithString:str];
    if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

// ---------------------------------------------------------------------------
// Control handlers
// ---------------------------------------------------------------------------

- (void)onForceRegisterChanged:(UISwitch *)sw {
    KFSetForceRegisterOnNextLaunch(sw.on);
    if (sw.on) {
        NSString *fresh = [[NSUUID UUID] UUIDString].lowercaseString;
        KFSetPendingDistinctId(fresh);
        KFSetPendingDeviceId(fresh);
    } else {
        KFSetPendingDistinctId(nil);
        KFSetPendingDeviceId(nil);
    }
    IPALog([NSString stringWithFormat:@"[SETTINGS] force_register=%s",
              sw.on ? "true" : "false"]);
}

- (void)onFeatureToggle:(UISwitch *)sw {
    KiouFeature f = (KiouFeature)sw.tag;
    KFSetFeatureEnabled(f, sw.isOn);
    IPALog([NSString stringWithFormat:
              @"[SETTINGS] %@ -> %@", KFFeatureLabel(f), sw.isOn ? @"ON" : @"OFF"]);
}

- (void)onFpsChanged:(UIStepper *)stepper {
    int32_t idx = (int32_t)stepper.value;
    KFSetFPSIndex(idx);
    int32_t fps = KFTargetFPS();
    self.fpsValueLabel.text = [NSString stringWithFormat:@"%d", fps];
    KFApplyFPS(fps);  // apply immediately
    IPALog([NSString stringWithFormat:@"[SETTINGS] fps -> %d (idx=%d)", fps, idx]);
}

- (void)onDepthChanged:(UIStepper *)stepper {
    int32_t v = (int32_t)stepper.value;
    KFSetAnalysisDepth(v);
    self.depthValueLabel.text = [NSString stringWithFormat:@"%d", v];
    IPALog([NSString stringWithFormat:@"[SETTINGS] analysis depth -> %d", v]);
}

- (void)onHashChanged:(UIStepper *)stepper {
    int32_t idx = (int32_t)stepper.value;
    KFSetAnalysisHashIndex(idx);
    int32_t mb = KFAnalysisHashMB();
    self.hashValueLabel.text = [NSString stringWithFormat:@"%d MB", mb];
    IPALog([NSString stringWithFormat:@"[SETTINGS] analysis hash -> %d MB (idx=%d)", mb, idx]);
}

- (void)onSkillChanged:(UIStepper *)stepper {
    int32_t v = (int32_t)stepper.value;
    KFSetAnalysisSkillLevel(v);
    self.skillValueLabel.text = [NSString stringWithFormat:@"%d", v];
    IPALog([NSString stringWithFormat:@"[SETTINGS] analysis skill -> %d", v]);
}

@end

// ===========================================================================
// KFKifuModesViewController — per-mode kifu autosave toggles.
//
// Pushed by the root controller when the Kifu Autosave row is tapped. One
// section, KIOU_MMODE_COUNT rows (AI / CPUStream / LocalPvP / OnlinePvP /
// RecordReplay), each a UISwitch on `KFKifuModeEnabled(mode)`.
//
// Independent of the master KIOU_FEATURE_KIFU_AUTOSAVE flag — the master
// stays where it is on the root screen; this screen edits only the per-mode
// flags. The on-device hook (Hook_KifuObserve.m's
// KFKifuObserveMatchEnd) gates emission on BOTH the master and the
// per-mode flag.
// ===========================================================================

@implementation KFKifuModesViewController

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        self.title = @"Kifu Autosave";
    }
    return self;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return KIOU_MMODE_COUNT;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"Modes";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"Pick which match modes get auto-saved as a .kif file under "
           @"Documents/KiouForge/ when the match ends. The master Kifu "
           @"Autosave toggle on the previous screen must also be on.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *kId = @"kifu-mode";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:kId];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    KiouMatchMode m = (KiouMatchMode)indexPath.row;
    cell.textLabel.text = KFKifuModeLabel(m);
    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = KFKifuModeEnabled(m);
    sw.tag = m;
    [sw addTarget:self action:@selector(onModeToggle:)
 forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

- (void)onModeToggle:(UISwitch *)sw {
    KiouMatchMode m = (KiouMatchMode)sw.tag;
    KFSetKifuModeEnabled(m, sw.isOn);
    IPALog([NSString stringWithFormat:
              @"[SETTINGS] kifu mode %@ -> %@",
              KFKifuModeLabel(m), sw.isOn ? @"ON" : @"OFF"]);
}

@end

// ---------------------------------------------------------------------------
// Presenter bridge — called from Settings.m (right-edge swipe).
// ---------------------------------------------------------------------------

static UIWindow *kfActiveWindow(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (!app) return nil;
    UIWindow *fallback = nil;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        for (UIWindow *w in ws.windows) {
            if (w.isKeyWindow) return w;
            if (!fallback) fallback = w;
        }
    }
    return fallback;
}

void KFPresentSettings(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = kfActiveWindow();
        if (!win) { IPALog(@"[SETTINGS] no active window"); return; }
        UIViewController *root = win.rootViewController;
        if (!root) { IPALog(@"[SETTINGS] no root vc"); return; }
        UIViewController *top = root;
        while (top.presentedViewController) top = top.presentedViewController;

        // Wrap in a UINavigationController so feature rows that need a
        // sub-screen (e.g. Kifu Autosave's per-mode toggles) get push
        // transitions for free.
        KFSettingsViewController *root_vc = [[KFSettingsViewController alloc] init];
        UINavigationController *nav =
            [[UINavigationController alloc] initWithRootViewController:root_vc];
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
        [top presentViewController:nav animated:YES completion:^{
            IPALog(@"[SETTINGS] modal presented");
        }];
    });
}
