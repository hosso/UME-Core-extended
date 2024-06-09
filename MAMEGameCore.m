/*
 Copyright (c) 2013, OpenEmu Team
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
     * Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.
     * Neither the name of the OpenEmu Team nor the
       names of its contributors may be used to endorse or promote products
       derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "MAMEGameCore.h"

#import <OpenEmuBase/OERingBuffer.h>
#import <OpenGL/gl.h>
#import <os/log.h>

@interface MAMEAuditResult: NSObject

/*! Returns the unique identifier of this result
 *
 * @remarks
 *
 * Identifier which groups resources by their driver, parent or CHD name
 */
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) NSString *fileName;

- (instancetype)initWithDriver:(NSString *)driver auditRecord:(AuditRecord *)record;
- (BOOL)checkSetExistsInDir:(NSURL *)dir;

@end

@interface MAMEGameCore () <OEArcadeSystemResponderClient>
{
    uint32_t _buttons[8][OEArcadeButtonCount];
    uint32_t _axes[8][InputMaxAxis];
    
    uint32_t *_buffer;
    OEIntSize _bufferSize;
    OEIntRect _screenRect;
    OEIntSize _aspectSize;
    
    NSTimeInterval _frameInterval;
    

    // dylib
    void *_handle;
    OSD *_osd;
    BOOL _supportsRewinding;
}

@end

static int32_t joystick_get_state(void *device_internal, void *item_internal)
{
    return *(int32_t *)item_internal;
}

static os_log_t OE_CORE_LOG, OE_CORE_AUDIT_LOG;

@implementation MAMEGameCore

#pragma mark - Lifecycle

+ (void)initialize
{
    OE_CORE_LOG         = os_log_create("org.openemu.MAME", "");
    OE_CORE_AUDIT_LOG   = os_log_create("org.openemu.MAME", "audit");
}

- (id)init
{
    self = [super init];
    if(!self)
    {
        return nil;
    }

    // Sensible defaults
    _bufferSize    = OEIntSizeMake(1024, 1024);
    _frameInterval = 60;
    _screenRect = { {0,0}, _bufferSize };
    _aspectSize = { 4, 3 };

    _osd = [OSD shared];
    _osd.delegate = self;

    return self;
}

#pragma mark - OSDDelegate

- (void)didInitialize
{
    // initialize joysticks
    for (int i = 0; i < 8; i++) {
        NSString *name = [NSString stringWithFormat:@"OpenEmu Player %d", i];
        InputDevice *dev = [_osd.joystick addDeviceNamed:name];
        [dev addItemNamed:@"X Axis" id:InputItemID_XAXIS getter:joystick_get_state context:&_axes[i][0]];
        [dev addItemNamed:@"Y Axis" id:InputItemID_YAXIS getter:joystick_get_state context:&_axes[i][1]];
        [dev addItemNamed:@"Start" id:InputItemID_START getter:joystick_get_state context:&_buttons[i][OEArcadeButtonP1Start]];
        [dev addItemNamed:@"Insert Coin" id:InputItemID_SELECT getter:joystick_get_state context:&_buttons[i][OEArcadeButtonInsertCoin]];
        [dev addItemNamed:@"Button 1" id:InputItemID_BUTTON1 getter:joystick_get_state context:&_buttons[i][OEArcadeButton1]];
        [dev addItemNamed:@"Button 2" id:InputItemID_BUTTON2 getter:joystick_get_state context:&_buttons[i][OEArcadeButton2]];
        [dev addItemNamed:@"Button 3" id:InputItemID_BUTTON3 getter:joystick_get_state context:&_buttons[i][OEArcadeButton3]];
        [dev addItemNamed:@"Button 4" id:InputItemID_BUTTON4 getter:joystick_get_state context:&_buttons[i][OEArcadeButton4]];
        [dev addItemNamed:@"Button 5" id:InputItemID_BUTTON5 getter:joystick_get_state context:&_buttons[i][OEArcadeButton5]];
        [dev addItemNamed:@"Button 6" id:InputItemID_BUTTON6 getter:joystick_get_state context:&_buttons[i][OEArcadeButton6]];
    }
    
    // Special keys
    InputDevice *kb = [_osd.keyboard addDeviceNamed:@"OpenEmu Keyboard"];
    [kb addItemNamed:@"Service" id:InputItemID_F2 getter:joystick_get_state context:&_buttons[0][OEArcadeButtonService]];
    [kb addItemNamed:@"UI Configure" id:InputItemID_TAB getter:joystick_get_state context:&_buttons[0][OEArcadeUIConfigure]];

    // Keyboard keys
    [kb addItemNamed:@"A" id:InputItemID_A getter:joystick_get_state context:&_buttons[0][OEArcadeA]];
    [kb addItemNamed:@"B" id:InputItemID_B getter:joystick_get_state context:&_buttons[0][OEArcadeB]];
    [kb addItemNamed:@"C" id:InputItemID_C getter:joystick_get_state context:&_buttons[0][OEArcadeC]];
    [kb addItemNamed:@"D" id:InputItemID_D getter:joystick_get_state context:&_buttons[0][OEArcadeD]];
    [kb addItemNamed:@"E" id:InputItemID_E getter:joystick_get_state context:&_buttons[0][OEArcadeE]];
    [kb addItemNamed:@"F" id:InputItemID_F getter:joystick_get_state context:&_buttons[0][OEArcadeF]];
    [kb addItemNamed:@"G" id:InputItemID_G getter:joystick_get_state context:&_buttons[0][OEArcadeG]];
    [kb addItemNamed:@"H" id:InputItemID_H getter:joystick_get_state context:&_buttons[0][OEArcadeH]];
    [kb addItemNamed:@"I" id:InputItemID_I getter:joystick_get_state context:&_buttons[0][OEArcadeI]];
    [kb addItemNamed:@"J" id:InputItemID_J getter:joystick_get_state context:&_buttons[0][OEArcadeJ]];
    [kb addItemNamed:@"K" id:InputItemID_K getter:joystick_get_state context:&_buttons[0][OEArcadeK]];
    [kb addItemNamed:@"L" id:InputItemID_L getter:joystick_get_state context:&_buttons[0][OEArcadeL]];
    [kb addItemNamed:@"M" id:InputItemID_M getter:joystick_get_state context:&_buttons[0][OEArcadeM]];
    [kb addItemNamed:@"N" id:InputItemID_N getter:joystick_get_state context:&_buttons[0][OEArcadeN]];
    [kb addItemNamed:@"O" id:InputItemID_O getter:joystick_get_state context:&_buttons[0][OEArcadeO]];
    // Assign P to the colon key instead of Pause
    [kb addItemNamed:@"P" id:InputItemID_COLON getter:joystick_get_state context:&_buttons[0][OEArcadeP]];
    // [kb addItemNamed:@"P" id:InputItemID_P getter:joystick_get_state context:&_buttons[0][OEArcadeP]];
    [kb addItemNamed:@"Q" id:InputItemID_Q getter:joystick_get_state context:&_buttons[0][OEArcadeQ]];
    [kb addItemNamed:@"R" id:InputItemID_R getter:joystick_get_state context:&_buttons[0][OEArcadeR]];
    [kb addItemNamed:@"S" id:InputItemID_S getter:joystick_get_state context:&_buttons[0][OEArcadeS]];
    [kb addItemNamed:@"T" id:InputItemID_T getter:joystick_get_state context:&_buttons[0][OEArcadeT]];
    [kb addItemNamed:@"U" id:InputItemID_U getter:joystick_get_state context:&_buttons[0][OEArcadeU]];
    [kb addItemNamed:@"V" id:InputItemID_V getter:joystick_get_state context:&_buttons[0][OEArcadeV]];
    [kb addItemNamed:@"W" id:InputItemID_W getter:joystick_get_state context:&_buttons[0][OEArcadeW]];
    [kb addItemNamed:@"X" id:InputItemID_X getter:joystick_get_state context:&_buttons[0][OEArcadeX]];
    [kb addItemNamed:@"Y" id:InputItemID_Y getter:joystick_get_state context:&_buttons[0][OEArcadeY]];
    [kb addItemNamed:@"Z" id:InputItemID_Z getter:joystick_get_state context:&_buttons[0][OEArcadeZ]];
    [kb addItemNamed:@"0" id:InputItemID_0 getter:joystick_get_state context:&_buttons[0][OEArcade0]];
    [kb addItemNamed:@"1" id:InputItemID_1 getter:joystick_get_state context:&_buttons[0][OEArcade1]];
    [kb addItemNamed:@"2" id:InputItemID_2 getter:joystick_get_state context:&_buttons[0][OEArcade2]];
    [kb addItemNamed:@"3" id:InputItemID_3 getter:joystick_get_state context:&_buttons[0][OEArcade3]];
    [kb addItemNamed:@"4" id:InputItemID_4 getter:joystick_get_state context:&_buttons[0][OEArcade4]];
    [kb addItemNamed:@"5" id:InputItemID_5 getter:joystick_get_state context:&_buttons[0][OEArcade5]];
    [kb addItemNamed:@"6" id:InputItemID_6 getter:joystick_get_state context:&_buttons[0][OEArcade6]];
    [kb addItemNamed:@"7" id:InputItemID_7 getter:joystick_get_state context:&_buttons[0][OEArcade7]];
    [kb addItemNamed:@"8" id:InputItemID_8 getter:joystick_get_state context:&_buttons[0][OEArcade8]];
    [kb addItemNamed:@"9" id:InputItemID_9 getter:joystick_get_state context:&_buttons[0][OEArcade9]];
    // Disable ESC key
    // [kb addItemNamed:@"ESC" id:InputItemID_ESC getter:joystick_get_state context:&_buttons[0][OEArcadeESC]];
    // Disable the On Screen Display
    // [kb addItemNamed:@"TILDE" id:InputItemID_TILDE getter:joystick_get_state context:&_buttons[0][OEArcadeTILDE]];
    [kb addItemNamed:@"MINUS" id:InputItemID_MINUS getter:joystick_get_state context:&_buttons[0][OEArcadeMINUS]];
    [kb addItemNamed:@"EQUALS" id:InputItemID_EQUALS getter:joystick_get_state context:&_buttons[0][OEArcadeEQUALS]];
    [kb addItemNamed:@"BACKSPACE" id:InputItemID_BACKSPACE getter:joystick_get_state context:&_buttons[0][OEArcadeBACKSPACE]];
    [kb addItemNamed:@"TAB" id:InputItemID_TAB getter:joystick_get_state context:&_buttons[0][OEArcadeTAB]];
    [kb addItemNamed:@"OPENBRACE" id:InputItemID_OPENBRACE getter:joystick_get_state context:&_buttons[0][OEArcadeOPENBRACE]];
    [kb addItemNamed:@"CLOSEBRACE" id:InputItemID_CLOSEBRACE getter:joystick_get_state context:&_buttons[0][OEArcadeCLOSEBRACE]];
    [kb addItemNamed:@"ENTER" id:InputItemID_ENTER getter:joystick_get_state context:&_buttons[0][OEArcadeENTER]];
    [kb addItemNamed:@"COLON" id:InputItemID_COLON getter:joystick_get_state context:&_buttons[0][OEArcadeCOLON]];
    [kb addItemNamed:@"QUOTE" id:InputItemID_QUOTE getter:joystick_get_state context:&_buttons[0][OEArcadeQUOTE]];
    [kb addItemNamed:@"BACKSLASH" id:InputItemID_BACKSLASH getter:joystick_get_state context:&_buttons[0][OEArcadeBACKSLASH]];
    [kb addItemNamed:@"BACKSLASH2" id:InputItemID_BACKSLASH2 getter:joystick_get_state context:&_buttons[0][OEArcadeBACKSLASH2]];
    [kb addItemNamed:@"COMMA" id:InputItemID_COMMA getter:joystick_get_state context:&_buttons[0][OEArcadeCOMMA]];
    [kb addItemNamed:@"STOP" id:InputItemID_STOP getter:joystick_get_state context:&_buttons[0][OEArcadeSTOP]];
    [kb addItemNamed:@"SLASH" id:InputItemID_SLASH getter:joystick_get_state context:&_buttons[0][OEArcadeSLASH]];
    [kb addItemNamed:@"SPACE" id:InputItemID_SPACE getter:joystick_get_state context:&_buttons[0][OEArcadeSPACE]];
    [kb addItemNamed:@"LSHIFT" id:InputItemID_LSHIFT getter:joystick_get_state context:&_buttons[0][OEArcadeLSHIFT]];
    [kb addItemNamed:@"RSHIFT" id:InputItemID_RSHIFT getter:joystick_get_state context:&_buttons[0][OEArcadeRSHIFT]];
    [kb addItemNamed:@"LCONTROL" id:InputItemID_LCONTROL getter:joystick_get_state context:&_buttons[0][OEArcadeLCONTROL]];
    [kb addItemNamed:@"RCONTROL" id:InputItemID_RCONTROL getter:joystick_get_state context:&_buttons[0][OEArcadeRCONTROL]];
    [kb addItemNamed:@"LALT" id:InputItemID_LALT getter:joystick_get_state context:&_buttons[0][OEArcadeLALT]];
    [kb addItemNamed:@"RALT" id:InputItemID_RALT getter:joystick_get_state context:&_buttons[0][OEArcadeRALT]];
    [kb addItemNamed:@"LWIN" id:InputItemID_LWIN getter:joystick_get_state context:&_buttons[0][OEArcadeLWIN]];
    [kb addItemNamed:@"RWIN" id:InputItemID_RWIN getter:joystick_get_state context:&_buttons[0][OEArcadeRWIN]];
}

- (void)didChangeDisplayBounds:(NSSize)bounds fps:(double)fps aspect:(NSSize)aspect
{
    _screenRect = {{0, 0}, OEIntSizeMake(bounds.width, bounds.height)};
    
    // for single screen games:
    BOOL singleScreen = YES;
    if (singleScreen)
    {
        CGFloat newHeight = (aspect.height / aspect.width) * bounds.width;
        _aspectSize = OEIntSizeMake(bounds.width, newHeight);
    }
    else
    {
        _aspectSize = OEIntSizeMake(bounds.width, bounds.height);
    }
    
    _frameInterval = fps;
}

- (void)updateAudioBuffer:(const int16_t *)buffer samples:(NSInteger)samples
{
    id<OEAudioBuffer> buf = [self audioBufferAtIndex:0];
    [buf write:buffer maxLength:samples * 2 * sizeof(int16_t)];
}

- (void)logLevel:(OSDLogLevel)level message:(NSString *)msg
{
    switch (level) {
        case OSDLogLevelError:
            os_log_error(OE_CORE_LOG, "%{public}s", msg.UTF8String);
            break;
            
        case OSDLogLevelVerbose:
            os_log_debug(OE_CORE_LOG, "%{public}s", msg.UTF8String);
            break;
            
        default:
            os_log_info(OE_CORE_LOG, "%{public}s", msg.UTF8String);
            break;
    }
}

#pragma mark - Execution

BOOL driverIsNotWorking(GameDriverOptions o)
{
    if ((o & GameDriverMachineNotWorking) == GameDriverMachineNotWorking) {
        return YES;
    }
    
    if ((o & GameDriverMachineIsSkeleton) == GameDriverMachineIsSkeleton) {
        return YES;
    }
    
    return NO;
}

- (BOOL)validateGameDriver:(GameDriver *)driver error:(NSError **)error
{
    GameDriverOptions o = driver.flags;
    
    if (o & (GameDriverMachineClickableArtwork | GameDriverMachineRequiresArtwork | GameDriverMachineMechanical))
    {
        if (error != nil)
        {
            *error = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadROMError userInfo:@{
                NSLocalizedDescriptionKey : @"Unable to load ROM.",
                NSLocalizedRecoverySuggestionErrorKey: [NSString stringWithFormat:@"\"%@\" (%@).\n\nMechanical systems or systems which require artwork to operate are not supported.", driver.fullName, driver.name],
            }];
        }
        return NO;
    }
    
    if (driverIsNotWorking(o)) {
        if (error != nil)
        {
            *error = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadROMError userInfo:@{
                NSLocalizedDescriptionKey : @"Unable to load ROM.",
                NSLocalizedRecoverySuggestionErrorKey: [NSString stringWithFormat:@"\"%@\" (%@).\n\nThis machine does not work and the emulation is not yet complete. There is nothing you can do to fix this problem except wait for the MAME developers to improve the emulation.", driver.fullName, driver.name],
            }];
        }
        return NO;
    }
    
    return YES;
}

- (BOOL)loadFileAtPath:(NSString *)path error:(NSError **)error
{
    NSString *romDir = [path stringByDeletingLastPathComponent];
    Options *opts = _osd.options;
    [opts setBasePath:self.supportDirectoryPath];
    opts.romsPath = romDir;
    BOOL prev;
    prev = opts.autoStretchXY;
    opts.autoStretchXY = NO;
    prev = opts.unevenStretchX;
    opts.unevenStretchX = NO;
    prev = opts.unevenStretchY;
    opts.unevenStretchY = NO;
    prev = opts.unevenStretch;
    opts.unevenStretch = NO;
    opts.keepAspect = YES;
    
    _osd.verboseOutput = NO; // TODO: debug only; remove later

    NSString *rom = [[path lastPathComponent] stringByDeletingPathExtension];
    AuditResult *ar;
    BOOL success = [_osd setDriver:rom withAuditResult:&ar error:error];
    if (!success)
    {
        return NO;
    }
    
    if (![self validateGameDriver:_osd.driver error:error])
    {
        return NO;
    }
    
    if (ar.summary == AuditSummaryIncorrect || ar.summary == AuditSummaryNotFound)
    {
        if (error != nil)
        {
            *error = [self processAuditResult:ar forRomDir:romDir];
        }
        return NO;
    }
    
    if (![_osd initializeWithError:error])
    {
        return NO;
    }
    
    _supportsRewinding = _osd.supportsSave && _osd.stateSize < 1e6;
    if (_osd.supportsSave && !_supportsRewinding)
    {
        os_log_info(OE_CORE_LOG, "disabling rewind support, save state size too big %{iec-bytes}ld", _osd.stateSize);
    }

    return YES;
}

- (NSError *)processAuditResult:(AuditResult *)ar forRomDir:(NSString *)romDir
{
    GameDriver *driver = _osd.driver;
    NSString *gameDriverName = driver.name;
    NSMutableOrderedSet<MAMEAuditResult *> *results = [NSMutableOrderedSet new];
    
    for (AuditRecord *rec in ar.records) {
        
        switch (rec.substatus) {
            case AuditSubstatusGood:
                continue;
                
            case AuditSubstatusFoundNodump:
            case AuditSubstatusGoodNeedsRedump:
            case AuditSubstatusNotFoundNoDump:
            case AuditSubstatusNotFoundOptional:
                // acceptable conditions, based on audit.cpp:media_auditor::summarize method,
                // which all result in a BEST_AVAILABLE status
                continue;

            // bad conditions
                
            case AuditSubstatusFoundWrongLength: {
                os_log_debug(OE_CORE_AUDIT_LOG, "wrong length: %{public}@, media type %ld", rec.name, rec.mediaType);
                [results addObject:[[MAMEAuditResult alloc] initWithDriver:gameDriverName auditRecord:rec]];
                break;
            }
                
            case AuditSubstatusFoundBadChecksum: {
                os_log_debug(OE_CORE_AUDIT_LOG, "bad checksum: %{public}@, media type %ld", rec.name, rec.mediaType);
                [results addObject:[[MAMEAuditResult alloc] initWithDriver:gameDriverName auditRecord:rec]];
                break;
            }
                
            case AuditSubstatusNotFound: {
                os_log_debug(OE_CORE_AUDIT_LOG, "not found: %{public}@, media type %ld", rec.name, rec.mediaType);
                [results addObject:[[MAMEAuditResult alloc] initWithDriver:gameDriverName auditRecord:rec]];
                break;
            }
                
            case AuditSubstatusUnverified:
            default:
                continue;
        }
    }
    
    // Sort missing files by ascending order
    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"self"
                                                                     ascending:YES];
    [results sortUsingDescriptors:@[sortDescriptor]];
    
    // Determine if ROMs exist with missing files, or are not found
    NSURL *romDirURL = [NSURL fileURLWithPath:romDir isDirectory:YES];
    NSMutableString *missingFilesList = [NSMutableString string];
    for(MAMEAuditResult *result in results)
    {
        if ([result checkSetExistsInDir:romDirURL])
        {
            [missingFilesList appendString:[NSString stringWithFormat:@"%@  \t- INCORRECT SET\n", result.fileName]];
        }
        else
        {
            [missingFilesList appendString:[NSString stringWithFormat:@"%@  \t- NOT FOUND\n", result.fileName]];
        }
    }
    
    // Give an audit report to the user
    NSString *game = [NSString stringWithFormat:@"%@ (%@.zip)", driver.fullName, gameDriverName];
    NSString *versionRequired = [[[[[self owner] bundle] infoDictionary] objectForKey:@"CFBundleVersion"] substringToIndex:5];

    NSError *outErr = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadROMError userInfo:@{
        NSLocalizedDescriptionKey : @"Required files are missing.",
        NSLocalizedRecoverySuggestionErrorKey : [NSString stringWithFormat:@"%@ requires:\n\n%@\nThese ROMs must be from a MAME %@ ROM set. Some of these files can be parent/device/BIOS ROMs, which are not part of the game, but are still required. Delete files already imported and reimport with correct files.", game, missingFilesList, versionRequired],
        }];

    return outErr;
}

- (void)resetEmulation
{
    [_osd scheduleHardReset];
}

#pragma mark - Video

- (const void *)getVideoBufferWithHint:(void *)hint
{
    _buffer = (uint32_t *)hint;
    [_osd setBuffer:hint size:NSSizeFromOEIntSize(_bufferSize)];
    return _buffer;
}

- (OEIntSize)bufferSize
{
    return _bufferSize;
}

- (OEIntRect)screenRect {
    return _screenRect;
}

- (OEIntSize)aspectSize
{
    return _aspectSize;
}

- (GLenum)pixelFormat
{
    return GL_BGRA;
}

- (GLenum)pixelType
{
    return GL_UNSIGNED_INT_8_8_8_8_REV;
}

#pragma mark - execution

- (void)executeFrame
{
    [_osd execute];
}

- (void)stopEmulation
{
    [_osd unload];
    _osd.delegate = nil;
    [super stopEmulation];
}

- (NSTimeInterval)frameInterval
{
    return _frameInterval;
}

#pragma mark - Audio

- (double)audioSampleRate
{
    return 48000;
}

- (NSUInteger)channelCount
{
    return 2;
}

#pragma mark - Input

- (void)setState:(BOOL)pressed ofButton:(OEArcadeButton)button forPlayer:(NSUInteger)player
{
    _buttons[player-1][button] = pressed ? 1 : 0;
    _axes[player-1][0] = _buttons[player-1][OEArcadeButtonLeft] ? InputAbsoluteMin : (_buttons[player-1][OEArcadeButtonRight] ? InputAbsoluteMax : 0);
    _axes[player-1][1] = _buttons[player-1][OEArcadeButtonUp] ? InputAbsoluteMin : (_buttons[player-1][OEArcadeButtonDown] ? InputAbsoluteMax : 0);
}

- (oneway void)didPushArcadeButton:(OEArcadeButton)button forPlayer:(NSUInteger)player
{
    [self setState:YES ofButton:button forPlayer:player];
}

- (oneway void)didReleaseArcadeButton:(OEArcadeButton)button forPlayer:(NSUInteger)player
{
    [self setState:NO ofButton:button forPlayer:player];
}

#pragma mark - Save State

- (void)saveStateToFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
    BOOL res     = NO;
    NSError *err = nil;
    
    if (_osd.supportsSave)
    {
        res = [_osd saveStateFromFileAtPath:fileName error:&err];
    }
    else
    {
        err = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotSaveStateError userInfo:@{
            NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Game \"%@\" does not not support save states.", _osd.driver.fullName],
        }];
    }
    
    block(res, err);
}

- (void)loadStateFromFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
    BOOL res     = NO;
    NSError *err = nil;
    
    if (_osd.supportsSave)
    {
        res = [_osd loadStateFromFileAtPath:fileName error:&err];
    }
    else
    {
        err = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotSaveStateError userInfo:@{
            NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Game \"%@\" does not not support save states.", _osd.driver.fullName],
        }];
    }
    
    block(res, err);
}

- (BOOL)supportsRewinding
{
    return _supportsRewinding;
}

- (NSData *)serializeStateWithError:(NSError *__autoreleasing *)outError
{
    return [_osd serializeState];
}

- (BOOL)deserializeState:(NSData *)state withError:(NSError *__autoreleasing *)outError
{
    return [_osd deserializeState:state];
}

@end

@implementation MAMEAuditResult
{
    NSString    *_driver;
    AuditRecord *_record;
}

- (instancetype)initWithDriver:(NSString *)driver auditRecord:(AuditRecord *)record
{
    if ((self = [super init]))
    {
        _driver = driver;
        _record = record;
    }
    return self;
}

- (NSString *)identifier
{
    if (_record.mediaType == AuditMediaTypeDisk)
    {
        // a CHD
        return _record.name;
    }
    
    Device *parent = _record.sharedDevice;
    if (parent)
    {
        return parent.shortName;
    }
    
    return _driver;
}

- (NSArray<NSString *> *)extensions
{
    if (_record.mediaType == AuditMediaTypeDisk)
    {
        return @[@".chd"];
    }
    
    return @[@".zip", @".7z"];
}

- (BOOL)isEqual:(id)object
{
    if (object == nil || ![object isKindOfClass:self.class])
    {
        return NO;
    }
    
    MAMEAuditResult *other = (MAMEAuditResult *)object;
    return self.identifier == other.identifier;
}

- (NSComparisonResult)compare:(MAMEAuditResult *)other
{
    return [self.identifier compare:other.identifier];
}

/*! Returns the first valid file name for this result
 */
- (NSString *)fileName
{
    return [self.identifier stringByAppendingString:[[self extensions] firstObject]];
}

/*! Determines if the ROM set exists
 */
- (BOOL)checkSetExistsInDir:(NSURL *)dir
{
    for (NSString *ext in [self extensions])
    {
        NSURL *missingFileURL = [dir URLByAppendingPathComponent:[self.identifier stringByAppendingString:ext]];
    
        if([missingFileURL checkResourceIsReachableAndReturnError:nil])
        {
            return YES;
        }
    }
    return NO;
}

- (NSUInteger)hash
{
    return self.identifier.hash;
}

@end
