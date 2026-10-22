// The lyrics' look as stored, its presets and the preview's lines. The page is LyricsLookSettings.m.
#import "LyricsLook.h"
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Fonts/Fonts.h"
#import "Redesigned/Kit/SGRBridges.h"
#import <CoreText/CoreText.h>

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

BOOL SGRLyricsVexoraLookActive(void) {
    return SGRLyricsLookPresetIndex(SGRLyricsLookNow()) == SGRLyricsVexoraPresetIndex();
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
    [store removeObjectForKey:SGRKeyLyricsColor];
    [store removeObjectForKey:SGRKeyLyricsFullscreenBackground];
    [store removeObjectForKey:@"spotifyglass.redesign.lyricsColor0"];
    [store removeObjectForKey:@"spotifyglass.redesign.lyricsColor1"];
    [store removeObjectForKey:@"spotifyglass.redesign.lyricsColor2"];
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

static NSInteger lyricsTextRGB(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    if ([store objectForKey:SGRKeyLyricsColor] != nil) return storedRGB(SGRKeyLyricsColor);
    if ([store objectForKey:@"spotifyglass.redesign.lyricsColor0"] != nil) return storedRGB(@"spotifyglass.redesign.lyricsColor0");
    return kDefaultLyricsRGB;
}

static UIColor *colorFromBytes(CGFloat r, CGFloat g, CGFloat b) {
    return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1];
}

static CGFloat dist2(CGFloat ar, CGFloat ag, CGFloat ab, CGFloat br, CGFloat bg, CGFloat bb) {
    CGFloat dr = ar - br, dg = ag - bg, db = ab - bb;
    return dr * dr + dg * dg + db * db;
}

// The desktop Vexora cover read: a 40×40 sample, near-black and near-white dropped, then two clusters.
static NSArray<UIColor *> *coverPair(UIImage *image) {
    UIColor *fallback = [UIColor colorWithRed:30 / 255.0 green:215 / 255.0 blue:96 / 255.0 alpha:1];
    if (!image.CGImage) return @[fallback, fallback];
    const int w = 40, h = 40;
    uint8_t *data = calloc((size_t)(w * h), 4);
    if (!data) return @[fallback, fallback];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(data, w, h, 8, w * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!ctx) { free(data); return @[fallback, fallback]; }
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), image.CGImage);
    CGContextRelease(ctx);
    CGFloat rs[1600], gs[1600], bs[1600];
    int count = 0;
    for (int i = 0; i < w * h; i++) {
        int a = data[i * 4 + 3];
        if (a < 200) continue;
        int r = data[i * 4], g = data[i * 4 + 1], b = data[i * 4 + 2];
        CGFloat lum = (r + g + b) / 3.0;
        if (lum < 16 || lum > 244) continue;
        rs[count] = r; gs[count] = g; bs[count] = b;
        count++;
    }
    free(data);
    if (!count) return @[UIColor.whiteColor, UIColor.whiteColor];
    CGFloat meanR = 0, meanG = 0, meanB = 0;
    for (int i = 0; i < count; i++) { meanR += rs[i]; meanG += gs[i]; meanB += bs[i]; }
    meanR /= count; meanG /= count; meanB /= count;
    int seedA = 0, seedB = 0;
    CGFloat best = -1;
    for (int i = 0; i < count; i++) {
        CGFloat d = dist2(rs[i], gs[i], bs[i], meanR, meanG, meanB);
        if (d > best) { best = d; seedA = i; }
    }
    best = -1;
    for (int i = 0; i < count; i++) {
        CGFloat d = dist2(rs[i], gs[i], bs[i], rs[seedA], gs[seedA], bs[seedA]);
        if (d > best) { best = d; seedB = i; }
    }
    CGFloat c1r = rs[seedA], c1g = gs[seedA], c1b = bs[seedA], c2r = rs[seedB], c2g = gs[seedB], c2b = bs[seedB];
    CGFloat n1 = 0, n2 = 0;
    for (int iter = 0; iter < 8; iter++) {
        CGFloat s1r = 0, s1g = 0, s1b = 0, s2r = 0, s2g = 0, s2b = 0;
        n1 = n2 = 0;
        for (int i = 0; i < count; i++) {
            BOOL first = dist2(rs[i], gs[i], bs[i], c1r, c1g, c1b) <= dist2(rs[i], gs[i], bs[i], c2r, c2g, c2b);
            if (first) { s1r += rs[i]; s1g += gs[i]; s1b += bs[i]; n1++; }
            else { s2r += rs[i]; s2g += gs[i]; s2b += bs[i]; n2++; }
        }
        if (n1) { c1r = s1r / n1; c1g = s1g / n1; c1b = s1b / n1; }
        if (n2) { c2r = s2r / n2; c2g = s2g / n2; c2b = s2b / n2; }
    }
    if (n2 > n1) {
        CGFloat tr = c1r, tg = c1g, tb = c1b;
        c1r = c2r; c1g = c2g; c1b = c2b;
        c2r = tr; c2g = tg; c2b = tb;
    }
    return @[colorFromBytes(c1r, c1g, c1b), colorFromBytes(c2r, c2g, c2b)];
}

UIColor *SGRLyricsCoverColor(void) {
    return coverPair(SGRNowPlayingArtwork(NULL, NULL)).firstObject;
}

NSArray<UIColor *> *SGRLyricsCoverColors(void) {
    return coverPair(SGRNowPlayingArtwork(NULL, NULL));
}

NSArray<NSString *> *SGRLyricsColorModeNames(void) {
    return @[@"Follow cover", @"Custom"];
}

SGRLyricsColorMode SGRLyricsColorModeNow(void) {
    return SGInt(SGRKeyLyricsColorMode, SGRLyricsColorModeCover) == SGRLyricsColorModeCustom
        ? SGRLyricsColorModeCustom : SGRLyricsColorModeCover;
}

void SGRSetLyricsColorMode(SGRLyricsColorMode mode, id changer) {
    SGSetInt(SGRKeyLyricsColorMode, mode == SGRLyricsColorModeCustom ? 1 : 0);
    [NSNotificationCenter.defaultCenter postNotificationName:SGRLyricsLookDidChangeNotification object:changer];
}

UIColor *SGRLyricsTextColor(void) {
    if (SGRLyricsColorModeNow() == SGRLyricsColorModeCover) return SGRLyricsCoverColor();
    return colorFromRGB(lyricsTextRGB());
}

NSString *SGRLyricsTextColorLabel(void) {
    return [NSString stringWithFormat:@"#%06lX", (long)lyricsTextRGB()];
}

void SGRSetLyricsTextColor(UIColor *color, id changer) {
    if (!color) return;
    SGSetInt(SGRKeyLyricsColor, rgbFromColor(color));
    [NSNotificationCenter.defaultCenter postNotificationName:SGRLyricsLookDidChangeNotification object:changer];
}

UIColor *SGRLyricsColorForLineAtIndex(NSUInteger lineIndex, NSUInteger lineCount) {
    (void)lineIndex;
    (void)lineCount;
    return SGRLyricsTextColor();
}

@interface SGRLyricsColorPicker : NSObject <UIColorPickerViewControllerDelegate>
@end

@implementation SGRLyricsColorPicker
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)picker {
    SGRSetLyricsTextColor(picker.selectedColor, nil);
}
@end

void SGRPickLyricsTextColor(void) {
    static SGRLyricsColorPicker *delegate;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ delegate = [SGRLyricsColorPicker new]; });
    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.supportsAlpha = NO;
    picker.selectedColor = SGRLyricsTextColor();
    picker.delegate = delegate;
    [SGTopController() presentViewController:picker animated:YES completion:nil];
}

NSArray<NSString *> *SGRLyricsFullscreenBackgroundNames(void) {
    return @[@"Solid color", @"Cover glow", @"Original"];
}

SGRLyricsFullscreenBackground SGRLyricsFullscreenBackgroundNow(void) {
    NSInteger mode = SGInt(SGRKeyLyricsFullscreenBackground, SGRLyricsFullscreenBackgroundSolid);
    if (mode == SGRLyricsFullscreenBackgroundCover) return SGRLyricsFullscreenBackgroundCover;
    if (mode == SGRLyricsFullscreenBackgroundOriginal) return SGRLyricsFullscreenBackgroundOriginal;
    return SGRLyricsFullscreenBackgroundSolid;
}

void SGRSetLyricsFullscreenBackground(SGRLyricsFullscreenBackground mode, id changer) {
    NSInteger stored = 0;
    if (mode == SGRLyricsFullscreenBackgroundCover) stored = 1;
    else if (mode == SGRLyricsFullscreenBackgroundOriginal) stored = 2;
    SGSetInt(SGRKeyLyricsFullscreenBackground, stored);
    [NSNotificationCenter.defaultCenter postNotificationName:SGRLyricsLookDidChangeNotification object:changer];
}

UIColor *SGRLyricsSolidBackgroundColor(void) {
    return colorFromRGB(storedRGB(SGRKeyLyricsSolidColor) == kDefaultLyricsRGB && [NSUserDefaults.standardUserDefaults objectForKey:SGRKeyLyricsSolidColor] == nil
        ? 0x000000 : storedRGB(SGRKeyLyricsSolidColor));
}

NSString *SGRLyricsSolidBackgroundLabel(void) {
    NSInteger rgb = [NSUserDefaults.standardUserDefaults objectForKey:SGRKeyLyricsSolidColor] == nil ? 0x000000 : storedRGB(SGRKeyLyricsSolidColor);
    return [NSString stringWithFormat:@"#%06lX", (long)rgb];
}

void SGRSetLyricsSolidBackgroundColor(UIColor *color, id changer) {
    if (!color) return;
    SGSetInt(SGRKeyLyricsSolidColor, rgbFromColor(color));
    [NSNotificationCenter.defaultCenter postNotificationName:SGRLyricsLookDidChangeNotification object:changer];
}

@interface SGRLyricsSolidPicker : NSObject <UIColorPickerViewControllerDelegate>
@end

@implementation SGRLyricsSolidPicker
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)picker {
    SGRSetLyricsSolidBackgroundColor(picker.selectedColor, nil);
}
@end

void SGRPickLyricsSolidBackgroundColor(void) {
    static SGRLyricsSolidPicker *delegate;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ delegate = [SGRLyricsSolidPicker new]; });
    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.supportsAlpha = NO;
    picker.selectedColor = SGRLyricsSolidBackgroundColor();
    picker.delegate = delegate;
    [SGTopController() presentViewController:picker animated:YES completion:nil];
}

NSInteger SGRLyricsOriginalBlur(void) {
    NSInteger blur = SGInt(SGRKeyLyricsOriginalBlur, 60);
    return MAX(0, MIN(100, blur));
}

void SGRSetLyricsOriginalBlur(NSInteger percent, id changer) {
    SGSetInt(SGRKeyLyricsOriginalBlur, MAX(0, MIN(100, percent)));
    [NSNotificationCenter.defaultCenter postNotificationName:SGRLyricsLookDidChangeNotification object:changer];
}

#pragma mark - Mojangles (Vexora lyrics font)

static NSString *const kMojanglesFamily = @"Minecraft";

BOOL SGRegisterMojanglesFont(void) {
    static BOOL registered = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [NSBundle.mainBundle pathForResource:@"Mojangles" ofType:@"otf"];
        if (!path.length) return;
        NSURL *url = [NSURL fileURLWithPath:path];
        CFErrorRef error = NULL;
        if (!CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url, kCTFontManagerScopeProcess, &error)) {
            SGLog(@"lyrics font: Mojangles not registered: %@", CFBridgingRelease(error));
            return;
        }
        registered = [UIFont fontNamesForFamilyName:kMojanglesFamily].count > 0;
    });
    return registered;
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
    if (SGRegisterMojanglesFont()) [choices addObject:SGRLyricsFontMojangles];
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
    if ([choice isEqualToString:SGRLyricsFontMojangles] && SGRegisterMojanglesFont()) {
        UIFont *font = [UIFont fontWithName:[UIFont fontNamesForFamilyName:kMojanglesFamily].firstObject size:size];
        if (font) return font;
    }
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
