// The lyrics' look as stored, its presets and the preview's lines. The page is LyricsLookSettings.m.
#import "LyricsLook.h"
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Fonts/Fonts.h"

NSNotificationName const SGRLyricsLookDidChangeNotification = @"spotifyglass.redesign.lyricsLookDidChange";

// The sliders' ranges, which a stored look is held to as well.
static const SGRLyricsLook kLeast = {22, 12, 0, 0, 0}, kMost = {40, 40, 2, 2, 2};

static SGRLyricsLook presets[] = {
    {30, 24, 1, 1, 1},          // Apple Music: its 30 pt lines, 24 pt apart
    {36, 28, 1, 1, 1},          // Large
    {25, 16, 1, 1, 1},          // Compact
    {30, 24, 0, 0, 0},          // Calm: every line sharp, and nothing held glows or waves
    {32, 26, 1.4, 1.6, 1.8},    // Vivid
    {34, 16, 0.4, 1.35, 0},     // Vexora: bold stacked lines, dim context, glow on the active line
};

NSArray<NSString *> *SGRLyricsLookPresetNames(void) {
    return @[@"Apple Music", @"Large", @"Compact", @"Calm", @"Vivid", @"Vexora"];
}

NSInteger SGRLyricsVexoraPresetIndex(void) {
    return (NSInteger)(sizeof(presets) / sizeof(*presets) - 1);
}

SGRLyricsLook SGRLyricsLookPreset(NSUInteger index) {
    return presets[MIN(index, sizeof(presets) / sizeof(*presets) - 1)];
}

static CGFloat held(CGFloat value, CGFloat least, CGFloat most) {
    return isfinite(value) ? MAX(least, MIN(most, value)) : least;
}

static CGFloat stored(NSDictionary *look, NSString *name, CGFloat fallback, CGFloat least, CGFloat most) {
    id value = look[name];
    return [value isKindOfClass:NSNumber.class] ? held([value doubleValue], least, most) : fallback;
}

SGRLyricsLook SGRLyricsLookNow(void) {
    SGRLyricsLook look = presets[0];
    NSDictionary *saved = [NSUserDefaults.standardUserDefaults dictionaryForKey:SGRKeyLyricsLook];
    if (!saved) return look;
    look.size = stored(saved, @"size", look.size, kLeast.size, kMost.size);
    look.spacing = stored(saved, @"spacing", look.spacing, kLeast.spacing, kMost.spacing);
    look.blur = stored(saved, @"blur", look.blur, kLeast.blur, kMost.blur);
    look.glow = stored(saved, @"glow", look.glow, kLeast.glow, kMost.glow);
    look.wave = stored(saved, @"wave", look.wave, kLeast.wave, kMost.wave);
    return look;
}

void SGRSetLyricsLook(SGRLyricsLook look, id changer) {
    [NSUserDefaults.standardUserDefaults setObject:@{
        @"size": @(held(look.size, kLeast.size, kMost.size)),
        @"spacing": @(held(look.spacing, kLeast.spacing, kMost.spacing)),
        @"blur": @(held(look.blur, kLeast.blur, kMost.blur)),
        @"glow": @(held(look.glow, kLeast.glow, kMost.glow)),
        @"wave": @(held(look.wave, kLeast.wave, kMost.wave)),
    } forKey:SGRKeyLyricsLook];
    [NSNotificationCenter.defaultCenter postNotificationName:SGRLyricsLookDidChangeNotification object:changer];
}

// Equal to the slider's step, so a look slid back onto a preset's values reads as that preset again.
static BOOL same(CGFloat a, CGFloat b) {
    return fabs(a - b) < 0.01;
}

NSInteger SGRLyricsLookPresetIndex(SGRLyricsLook look) {
    for (NSUInteger i = 0; i < sizeof(presets) / sizeof(*presets); i++) {
        SGRLyricsLook preset = presets[i];
        if (same(look.size, preset.size) && same(look.spacing, preset.spacing) && same(look.blur, preset.blur)
            && same(look.glow, preset.glow) && same(look.wave, preset.wave)) return (NSInteger)i;
    }
    return -1;
}

#pragma mark - the animation

NSArray<NSString *> *SGRLyricsAnimationNames(void) {
    return @[@"Wave", @"Glow", @"Bounce", @"Ripple", @"Float", @"Apple Music", @"Snappy"];
}

static const SGRLyricsAnimation animations[] = {
    // letters wordLift letterLift glow spread bounce feather dim  riseMs move damp stagger fade
    {YES, 0,  5,   8,  0.5,  NO,  22, 0.97, 700,  0.7, 0.86, 0.04, 0.35},   // Wave: letters rise and glow one after another
    {YES, 0,  1.5, 14, 0.7,  NO,  26, 0.97, 700,  0.7, 0.86, 0.04, 0.35},   // Glow: hardly rise, shine
    {YES, 0,  9,   6,  0.45, YES, 14, 0.94, 700,  0.8, 0.6,  0.05, 0.3},    // Bounce: letters spring up and overshoot
    {YES, 0,  7,   10, 0.9,  NO,  40, 0.96, 1100, 0.9, 0.9,  0.08, 0.5},    // Ripple: a slow, wide wave through the word
    {NO,  10, 0,   0,  0,    NO,  44, 0.97, 1600, 0.9, 0.9,  0.05, 0.6},    // Float: the whole word drifts up
    {NO,  2.5, 0,  0,  0,    NO,  22, 0.97, 700,  0.7, 0.86, 0.04, 0.35},   // Apple Music
    {NO,  1,  0,   0,  0,    NO,  10, 0.97, 500,  0.3, 1.0,  0,    0.12},   // Snappy: nearly at once
};

void SGRResetLyricsLook(id changer) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    [store removeObjectForKey:SGRKeyLyricsLook];
    [store removeObjectForKey:SGRKeyLyricsFont];
    [store removeObjectForKey:SGRKeyLyricsAnimation];
    [store removeObjectForKey:SGRKeyLyricsOutline];
    [store removeObjectForKey:SGRKeyLyricsColor0];
    [store removeObjectForKey:SGRKeyLyricsColor1];
    [store removeObjectForKey:SGRKeyLyricsColor2];
    [NSNotificationCenter.defaultCenter postNotificationName:SGRLyricsLookDidChangeNotification object:changer];
}

#pragma mark - lyrics text color and outline

static const NSInteger kDefaultLyricsRGB = 0xFFFFFF;

static NSInteger storedRGB(NSString *key) {
    NSInteger rgb = SGInt(key, kDefaultLyricsRGB);
    return rgb >= 0 && rgb <= 0xFFFFFF ? rgb : kDefaultLyricsRGB;
}

static UIColor *colorFromRGB(NSInteger rgb) {
    CGFloat r = ((rgb >> 16) & 0xFF) / 255.0, g = ((rgb >> 8) & 0xFF) / 255.0, b = (rgb & 0xFF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:1];
}

static NSInteger rgbFromColor(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return ((NSInteger)lround(MIN(1, MAX(0, r)) * 255) << 16)
         | ((NSInteger)lround(MIN(1, MAX(0, g)) * 255) << 8)
         | (NSInteger)lround(MIN(1, MAX(0, b)) * 255);
}

BOOL SGRLyricsOutlineEnabled(void) {
    return SGFlag(SGRKeyLyricsOutline, NO);
}

UIColor *SGRLyricsColorAtIndex(NSUInteger index) {
    static NSString *const keys[] = {SGRKeyLyricsColor0, SGRKeyLyricsColor1, SGRKeyLyricsColor2};
    return colorFromRGB(storedRGB(keys[MIN(index, 2)]));
}

NSString *SGRLyricsColorLabelAtIndex(NSUInteger index) {
    static NSString *const keys[] = {SGRKeyLyricsColor0, SGRKeyLyricsColor1, SGRKeyLyricsColor2};
    return [NSString stringWithFormat:@"#%06lX", (long)storedRGB(keys[MIN(index, 2)])];
}

void SGRSetLyricsColorAtIndex(NSUInteger index, UIColor *color, id changer) {
    static NSString *const keys[] = {SGRKeyLyricsColor0, SGRKeyLyricsColor1, SGRKeyLyricsColor2};
    if (index > 2 || !color) return;
    SGSetInt(keys[index], rgbFromColor(color));
    [NSNotificationCenter.defaultCenter postNotificationName:SGRLyricsLookDidChangeNotification object:changer];
}

static UIColor *blendColors(UIColor *from, UIColor *to, CGFloat t) {
    t = MAX(0, MIN(1, t));
    CGFloat r0 = 0, g0 = 0, b0 = 0, a0 = 0, r1 = 0, g1 = 0, b1 = 0, a1 = 0;
    [from getRed:&r0 green:&g0 blue:&b0 alpha:&a0];
    [to getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
    return [UIColor colorWithRed:r0 + (r1 - r0) * t green:g0 + (g1 - g0) * t blue:b0 + (b1 - b0) * t alpha:1];
}

UIColor *SGRLyricsColorForLineAtIndex(NSUInteger lineIndex, NSUInteger lineCount) {
    UIColor *c0 = SGRLyricsColorAtIndex(0);
    UIColor *c1 = SGRLyricsColorAtIndex(1);
    UIColor *c2 = SGRLyricsColorAtIndex(2);
    if (storedRGB(SGRKeyLyricsColor0) == storedRGB(SGRKeyLyricsColor1)
        && storedRGB(SGRKeyLyricsColor1) == storedRGB(SGRKeyLyricsColor2))
        return c0;
    if (lineCount <= 1) return c0;
    CGFloat t = (CGFloat)lineIndex / (CGFloat)(lineCount - 1);
    if (t <= 0.5) return blendColors(c0, c1, t * 2);
    return blendColors(c1, c2, (t - 0.5) * 2);
}

@interface SGRLyricsColorPicker : NSObject <UIColorPickerViewControllerDelegate>
@property (nonatomic) NSUInteger slot;
@end

@implementation SGRLyricsColorPicker
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)picker {
    SGRSetLyricsColorAtIndex(self.slot, picker.selectedColor, nil);
}
@end

void SGRPickLyricsColorAtIndex(NSUInteger index) {
    static SGRLyricsColorPicker *delegates[3];
    index = MIN(index, 2);
    if (!delegates[index]) delegates[index] = [SGRLyricsColorPicker new];
    delegates[index].slot = index;
    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.supportsAlpha = NO;
    picker.selectedColor = SGRLyricsColorAtIndex(index);
    picker.delegate = delegates[index];
    [SGTopController() presentViewController:picker animated:YES completion:nil];
}

NSInteger SGRLyricsAnimationIndex(void) {
    NSInteger index = [NSUserDefaults.standardUserDefaults integerForKey:SGRKeyLyricsAnimation];
    return index >= 0 && index < (NSInteger)SGRLyricsAnimationNames().count ? index : 0;
}

void SGRSetLyricsAnimationIndex(NSInteger index, id changer) {
    [NSUserDefaults.standardUserDefaults setInteger:index forKey:SGRKeyLyricsAnimation];
    [NSNotificationCenter.defaultCenter postNotificationName:SGRLyricsLookDidChangeNotification object:changer];
}

SGRLyricsAnimation SGRLyricsAnimationNow(void) {
    return animations[SGRLyricsAnimationIndex()];
}

#pragma mark - the font

NSArray<NSString *> *SGRLyricsFontChoices(void) {
    NSMutableArray<NSString *> *choices = [@[@"System", @"Rounded", @"Serif", @"Mono"] mutableCopy];
    NSString *imported = [NSUserDefaults.standardUserDefaults stringForKey:SGKeyAppFontName];
    if (imported.length && SGRegisterCustomFont()) [choices addObject:imported];
    for (NSString *family in SGAppFontFamilies()) if (![choices containsObject:family]) [choices addObject:family];
    return choices;
}

NSString *SGRLyricsFontChoice(void) {
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:SGRKeyLyricsFont];
    return saved.length && [SGRLyricsFontChoices() containsObject:saved] ? saved : @"System";
}

void SGRSetLyricsFontChoice(NSString *choice, id changer) {
    [NSUserDefaults.standardUserDefaults setObject:choice forKey:SGRKeyLyricsFont];
    [NSNotificationCenter.defaultCenter postNotificationName:SGRLyricsLookDidChangeNotification object:changer];
}

UIFont *SGRLyricsFont(CGFloat size, UIFontWeight weight) {
    NSString *choice = SGRLyricsFontChoice();
    UIFontDescriptorSystemDesign design = nil;
    if ([choice isEqualToString:@"Rounded"]) design = UIFontDescriptorSystemDesignRounded;
    else if ([choice isEqualToString:@"Serif"]) design = UIFontDescriptorSystemDesignSerif;
    else if ([choice isEqualToString:@"Mono"]) design = UIFontDescriptorSystemDesignMonospaced;
    UIFont *system = [UIFont systemFontOfSize:size weight:weight];
    if (design) {
        UIFontDescriptor *descriptor = [system.fontDescriptor fontDescriptorWithDesign:design];
        return descriptor ? [UIFont fontWithDescriptor:descriptor size:size] : system;
    }
    if ([choice isEqualToString:@"System"]) return system;
    // A family: its upright face nearest the weight; the system's font where the family has none.
    UIFontDescriptor *descriptor = [UIFontDescriptor fontDescriptorWithFontAttributes:@{
        UIFontDescriptorFamilyAttribute: choice,
        UIFontDescriptorTraitsAttribute: @{UIFontWeightTrait: @(weight), UIFontSlantTrait: @0},
    }];
    UIFont *font = [UIFont fontWithDescriptor:descriptor size:size];
    return font ?: system;
}

#pragma mark - the preview's song

// Each word as [text, start, end] in ms; a line runs from its first word's start to its last word's end.
static SGKaraokeLine *sampleLine(NSArray<NSArray *> *timed) {
    NSMutableArray<SGKaraokeWord *> *words = [NSMutableArray array];
    for (NSArray *piece in timed) {
        SGKaraokeWord *word = [SGKaraokeWord new];
        word.text = piece[0];
        word.start = [piece[1] integerValue];
        word.end = [piece[2] integerValue];
        [words addObject:word];
    }
    SGKaraokeLine *line = [SGKaraokeLine new];
    line.words = words;
    line.start = words.firstObject.start;
    line.end = words.lastObject.end;
    line.timing = SGKaraokeTimingWords;
    return line;
}

// Words of the mod's own. The second line holds its last word for three seconds, so the glow and the wave
// show on every round.
NSArray<SGKaraokeLine *> *SGRLyricsSampleLines(void) {
    static NSArray<SGKaraokeLine *> *lines;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        lines = @[
            sampleLine(@[@[@"Light", @600, @1000], @[@"comes", @1000, @1400], @[@"over", @1400, @1800], @[@"the", @1800, @2000], @[@"water", @2000, @2900]]),
            sampleLine(@[@[@"hold", @3100, @3500], @[@"on", @3500, @3800], @[@"to", @3800, @4000], @[@"the", @4000, @4200], @[@"night", @4200, @7200]]),
            sampleLine(@[@[@"we", @7500, @7800], @[@"sing", @7800, @8300], @[@"it", @8300, @8500], @[@"louder", @8500, @9500]]),
            sampleLine(@[@[@"all", @9800, @10100], @[@"the", @10100, @10300], @[@"way", @10300, @10700], @[@"home", @10700, @12000]]),
        ];
    });
    return lines;
}

NSInteger SGRLyricsSampleLength(void) {
    return 13500;   // a pause after the last line, then the first again
}
