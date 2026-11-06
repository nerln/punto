#import "VirtualDisplayBridge.h"

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <math.h>

// These classes belong to CoreGraphics but are absent from the public SDK.
// Runtime lookup keeps the regular display-mode path usable if Apple removes
// them. This optional backend cannot be distributed through the Mac App Store.
// API shapes can be compared with Chromium's independently published headers:
// https://chromium.googlesource.com/chromium/src/+/HEAD/ui/display/mac/test/virtual_display_util_mac.mm
// No capture, IOSurface copies, display stream, or render loop runs here.

@interface CGVirtualDisplayDescriptor : NSObject
@property(nonatomic, strong) NSString *name;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) unsigned int maxPixelsWide;
@property(nonatomic) unsigned int maxPixelsHigh;
@property(nonatomic) CGPoint redPrimary;
@property(nonatomic) CGPoint greenPrimary;
@property(nonatomic) CGPoint bluePrimary;
@property(nonatomic) CGPoint whitePoint;
@property(nonatomic) unsigned int vendorID;
@property(nonatomic) unsigned int productID;
@property(nonatomic) unsigned int serialNum;
@property(nonatomic) unsigned int serialNumber;
@property(nonatomic, copy) void (^terminationHandler)(id, id);
@end

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(unsigned int)width
                      height:(unsigned int)height
                 refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property(nonatomic, strong) NSArray *modes;
@property(nonatomic) unsigned int hiDPI;
@end

@interface CGVirtualDisplay : NSObject
@property(nonatomic, readonly) unsigned int displayID;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

static CGVirtualDisplay *gDisplay;
static CGVirtualDisplayDescriptor *gDescriptor;
static CGVirtualDisplaySettings *gSettings;
static NSString *gLastError;
static uint32_t gDisplayID;
static NSUInteger gGeneration;

static void PVSetError(const char **output, NSString *message) {
    gLastError = message;
    if (output) *output = gLastError.UTF8String;
}

static void PVClearError(const char **output) {
    gLastError = nil;
    if (output) *output = NULL;
}

bool PVVirtualDisplayAvailable(void) {
    Class display = NSClassFromString(@"CGVirtualDisplay");
    Class descriptor = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class mode = NSClassFromString(@"CGVirtualDisplayMode");
    Class settings = NSClassFromString(@"CGVirtualDisplaySettings");
    if (!display || !descriptor || !mode || !settings) return false;
    if (![display instancesRespondToSelector:@selector(initWithDescriptor:)] ||
        ![display instancesRespondToSelector:@selector(applySettings:)] ||
        ![display instancesRespondToSelector:@selector(displayID)] ||
        ![mode instancesRespondToSelector:@selector(initWithWidth:height:refreshRate:)] ||
        ![settings instancesRespondToSelector:@selector(setModes:)] ||
        ![settings instancesRespondToSelector:@selector(setHiDPI:)]) return false;
    SEL required[] = {
        @selector(setName:), @selector(setQueue:),
        @selector(setSizeInMillimeters:), @selector(setMaxPixelsWide:),
        @selector(setMaxPixelsHigh:), @selector(setRedPrimary:),
        @selector(setGreenPrimary:), @selector(setBluePrimary:),
        @selector(setWhitePoint:), @selector(setVendorID:),
        @selector(setProductID:), @selector(setSerialNum:)
    };
    for (size_t i = 0; i < sizeof(required) / sizeof(required[0]); i++) {
        if (![descriptor instancesRespondToSelector:required[i]]) return false;
    }
    return true;
}

uint32_t PVCreateVirtualDisplay(uint32_t logicalWidth, uint32_t logicalHeight,
                               double refreshRate, double widthMM,
                               double heightMM, const char **error) {
    PVClearError(error);
    if (![NSThread isMainThread]) {
        PVSetError(error, @"La creazione del display richiede il thread principale.");
        return 0;
    }
    if (gDisplay) {
        PVSetError(error, @"Esiste già un display virtuale. Ripristinalo prima di crearne un altro.");
        return 0;
    }
    if (!PVVirtualDisplayAvailable()) {
        PVSetError(error, @"Questa versione di macOS non espone le API per il display virtuale.");
        return 0;
    }
    if (logicalWidth < 320 || logicalHeight < 200 || logicalWidth > 4096 ||
        logicalHeight > 4096 || !isfinite(refreshRate) || refreshRate < 1 ||
        refreshRate > 240) {
        PVSetError(error, @"Dimensioni o frequenza del display virtuale non valide.");
        return 0;
    }

    @try {
        CGVirtualDisplayDescriptor *descriptor =
            [[NSClassFromString(@"CGVirtualDisplayDescriptor") alloc] init];
        descriptor.name = @"Punto · HiDPI";
        descriptor.queue = dispatch_get_main_queue();
        descriptor.maxPixelsWide = logicalWidth * 2;
        descriptor.maxPixelsHigh = logicalHeight * 2;
        descriptor.sizeInMillimeters =
            CGSizeMake(isfinite(widthMM) && widthMM > 0 ? widthMM : logicalWidth / 3.78,
                       isfinite(heightMM) && heightMM > 0 ? heightMM : logicalHeight / 3.78);
        // D65 / sRGB primaries. All-zero chromaticities can reject creation.
        descriptor.redPrimary = CGPointMake(0.640, 0.330);
        descriptor.greenPrimary = CGPointMake(0.300, 0.600);
        descriptor.bluePrimary = CGPointMake(0.150, 0.060);
        descriptor.whitePoint = CGPointMake(0.3127, 0.3290);
        descriptor.vendorID = 0x5056;
        // Saved WindowServer preferences are keyed by display identity. Use a
        // deterministic identity per size so a stale preference for another
        // resolution cannot silently select a different backing resolution.
        uint32_t identity = (logicalWidth * 73856093u) ^ (logicalHeight * 19349663u);
        descriptor.productID = identity & 0xFFFFu;
        descriptor.serialNum = identity ?: 1;
        if ([descriptor respondsToSelector:@selector(setSerialNumber:)]) {
            descriptor.serialNumber = identity ?: 1;
        }
        NSUInteger generation = ++gGeneration;
        if ([descriptor respondsToSelector:@selector(setTerminationHandler:)]) {
            descriptor.terminationHandler = ^(id info, id display) {
                (void)info;
                (void)display;
                if (generation == gGeneration) gDisplayID = 0;
            };
        }

        CGVirtualDisplaySettings *settings =
            [[NSClassFromString(@"CGVirtualDisplaySettings") alloc] init];
        Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
        // Physical backing mode first: on current WindowServer versions this
        // synthesizes the desired half-size logical HiDPI mode. Also advertise
        // the logical-size mode for versions interpreting hiDPI differently.
        // The caller MUST match width/height AND pixelWidth/pixelHeight after
        // applySettings; merely setting hiDPI=1 does not prove active Retina.
        id backingMode = [[modeClass alloc] initWithWidth:logicalWidth * 2
                                                  height:logicalHeight * 2
                                             refreshRate:refreshRate];
        id logicalMode = [[modeClass alloc] initWithWidth:logicalWidth
                                                  height:logicalHeight
                                             refreshRate:refreshRate];
        if (!backingMode || !logicalMode) {
            PVSetError(error, @"macOS non ha accettato le modalità HiDPI richieste.");
            return 0;
        }
        settings.hiDPI = 1;
        settings.modes = @[backingMode, logicalMode];

        CGVirtualDisplay *display =
            [[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:descriptor];
        if (!display || display.displayID == 0) {
            PVSetError(error, @"WindowServer non ha creato il display virtuale.");
            return 0;
        }
        gDescriptor = descriptor;
        gSettings = settings;
        gDisplay = display;
        gDisplayID = display.displayID;
        return gDisplayID;
    } @catch (NSException *exception) {
        PVDestroyVirtualDisplay();
        PVSetError(error, [NSString stringWithFormat:@"Display virtuale non disponibile: %@",
                           exception.reason ?: exception.name]);
        return 0;
    }
}

bool PVApplyVirtualSettings(const char **error) {
    PVClearError(error);
    if (![NSThread isMainThread]) {
        PVSetError(error, @"La configurazione del display richiede il thread principale.");
        return false;
    }
    if (!gDisplay || !gSettings || !gDisplayID) {
        PVSetError(error, @"Il display virtuale non è disponibile.");
        return false;
    }
    @try {
        if (![gDisplay applySettings:gSettings]) {
            PVSetError(error, @"WindowServer ha rifiutato le impostazioni HiDPI del display virtuale.");
            return false;
        }
        return true;
    } @catch (NSException *exception) {
        PVSetError(error, [NSString stringWithFormat:@"Configurazione HiDPI fallita: %@",
                           exception.reason ?: exception.name]);
        return false;
    }
}

uint32_t PVVirtualDisplayID(void) {
    return gDisplayID;
}

void PVDestroyVirtualDisplay(void) {
    // Callers must stop mirroring before releasing. The mirror output returns
    // to its own display configuration when this object is destroyed.
    ++gGeneration;
    gDisplayID = 0;
    gDisplay = nil;
    gSettings = nil;
    gDescriptor = nil;
}
