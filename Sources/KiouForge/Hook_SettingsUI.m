#import "Internal.h"
#import "Settings.h"
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

// Root settings view controller. Hosted inside a UINavigationController so
// rows that drill into sub-screens (e.g. Kifu Autosave → per-mode toggles)
// get push transitions for free.
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

#define KF_SECTION_FEATURES    0
#define KF_SECTION_PERFORMANCE 1
#define KF_SECTION_ENGINE      2
#define KF_SECTION_ABOUT       3
#define KF_SECTION_COUNT       4

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
        case KF_SECTION_FEATURES:    return @"Features";
        case KF_SECTION_PERFORMANCE: return @"Performance";
        case KF_SECTION_ENGINE:      return @"Engine";
        case KF_SECTION_ABOUT:       return @"About";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
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
        case KF_SECTION_FEATURES:    return KIOU_FEATURE_COUNT;
        case KF_SECTION_PERFORMANCE: return KF_PERF_ROW_COUNT;
        case KF_SECTION_ENGINE:      return KF_ENGINE_ROW_COUNT;
        case KF_SECTION_ABOUT:       return KF_ABOUT_ROW_COUNT;
        default: return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == KF_SECTION_FEATURES) {
        KiouFeature f = (KiouFeature)indexPath.row;
        // Two row shapes:
        //   * Plain toggle row     — UISwitch accessory, no disclosure.
        //   * Navigation row       — Value1 cell with detail caption (e.g.
        //                            "3 of 5") + disclosure indicator.
        // We dequeue under distinct identifiers so the cached style stays
        // correct across reuse.
        if (kiou_featureHasNavigation(f)) {
            static NSString *kId = @"feature-nav";
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kId];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                              reuseIdentifier:kId];
            }
            cell.textLabel.text = kiou_featureLabel(f);
            cell.accessoryView = nil;  // disclosure indicator below
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            // Caption: master state + per-mode count for Kifu Autosave.
            if (f == KIOU_FEATURE_KIFU_AUTOSAVE) {
                if (!kiou_featureEnabled(f)) {
                    cell.detailTextLabel.text = @"Off";
                } else {
                    int32_t on = 0;
                    for (int i = 0; i < KIOU_MMODE_COUNT; i++) {
                        if (kiou_kifuModeEnabled((KiouMatchMode)i)) on++;
                    }
                    cell.detailTextLabel.text =
                        [NSString stringWithFormat:@"%d of %d", on, KIOU_MMODE_COUNT];
                }
            } else {
                cell.detailTextLabel.text =
                    kiou_featureEnabled(f) ? @"On" : @"Off";
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
        cell.textLabel.text = kiou_featureLabel(f);
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = kiou_featureEnabled(f);
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
        int32_t idx = kiou_fpsIndex();
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
                                         (int)kiou_analysisDepth()];
            self.depthValueLabel = cell.detailTextLabel;
            stepper.minimumValue = 1;
            stepper.maximumValue = 36;
            stepper.stepValue    = 1;
            stepper.value        = kiou_analysisDepth();
            [stepper addTarget:self action:@selector(onDepthChanged:)
                forControlEvents:UIControlEventValueChanged];

        } else if (indexPath.row == KF_ENGINE_ROW_HASH) {
            int32_t idx = kiou_analysisHashIndex();
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
                                         (int)kiou_analysisSkillLevel()];
            self.skillValueLabel = cell.detailTextLabel;
            stepper.minimumValue = 1;
            stepper.maximumValue = 20;
            stepper.stepValue    = 1;
            stepper.value        = kiou_analysisSkillLevel();
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

    if (indexPath.section == KF_SECTION_FEATURES) {
        KiouFeature f = (KiouFeature)indexPath.row;
        if (!kiou_featureHasNavigation(f)) return;
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

- (void)onFeatureToggle:(UISwitch *)sw {
    KiouFeature f = (KiouFeature)sw.tag;
    kiou_setFeatureEnabled(f, sw.isOn);
    file_log([NSString stringWithFormat:
              @"[SETTINGS] %@ -> %@", kiou_featureLabel(f), sw.isOn ? @"ON" : @"OFF"]);
}

- (void)onFpsChanged:(UIStepper *)stepper {
    int32_t idx = (int32_t)stepper.value;
    kiou_setFpsIndex(idx);
    int32_t fps = kiou_targetFps();
    self.fpsValueLabel.text = [NSString stringWithFormat:@"%d", fps];
    KFApplyFPS(fps);  // apply immediately
    file_log([NSString stringWithFormat:@"[SETTINGS] fps -> %d (idx=%d)", fps, idx]);
}

- (void)onDepthChanged:(UIStepper *)stepper {
    int32_t v = (int32_t)stepper.value;
    kiou_setAnalysisDepth(v);
    self.depthValueLabel.text = [NSString stringWithFormat:@"%d", v];
    file_log([NSString stringWithFormat:@"[SETTINGS] analysis depth -> %d", v]);
}

- (void)onHashChanged:(UIStepper *)stepper {
    int32_t idx = (int32_t)stepper.value;
    kiou_setAnalysisHashIndex(idx);
    int32_t mb = kiou_analysisHashMB();
    self.hashValueLabel.text = [NSString stringWithFormat:@"%d MB", mb];
    file_log([NSString stringWithFormat:@"[SETTINGS] analysis hash -> %d MB (idx=%d)", mb, idx]);
}

- (void)onSkillChanged:(UIStepper *)stepper {
    int32_t v = (int32_t)stepper.value;
    kiou_setAnalysisSkillLevel(v);
    self.skillValueLabel.text = [NSString stringWithFormat:@"%d", v];
    file_log([NSString stringWithFormat:@"[SETTINGS] analysis skill -> %d", v]);
}

@end

// ===========================================================================
// KFKifuModesViewController — per-mode kifu autosave toggles.
//
// Pushed by the root controller when the Kifu Autosave row is tapped. One
// section, KIOU_MMODE_COUNT rows (AI / CPUStream / LocalPvP / OnlinePvP /
// RecordReplay), each a UISwitch on `kiou_kifuModeEnabled(mode)`.
//
// Independent of the master KIOU_FEATURE_KIFU_AUTOSAVE flag — the master
// stays where it is on the root screen; this screen edits only the per-mode
// flags. The on-device hook (Hook_KifuObserve.m's
// kiou_kifuObserveMatchEnd) gates emission on BOTH the master and the
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
    cell.textLabel.text = kiou_kifuModeLabel(m);
    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = kiou_kifuModeEnabled(m);
    sw.tag = m;
    [sw addTarget:self action:@selector(onModeToggle:)
 forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

- (void)onModeToggle:(UISwitch *)sw {
    KiouMatchMode m = (KiouMatchMode)sw.tag;
    kiou_setKifuModeEnabled(m, sw.isOn);
    file_log([NSString stringWithFormat:
              @"[SETTINGS] kifu mode %@ -> %@",
              kiou_kifuModeLabel(m), sw.isOn ? @"ON" : @"OFF"]);
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
        if (!win) { file_log(@"[SETTINGS] no active window"); return; }
        UIViewController *root = win.rootViewController;
        if (!root) { file_log(@"[SETTINGS] no root vc"); return; }
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
            file_log(@"[SETTINGS] modal presented");
        }];
    });
}
