//
//  RangingProbe.hpp
//  Observation hook for Apple Watch Auto Unlock ranging requests.
//
//  The probe is off by default. It is enabled either by the boot argument
//  -itlawdlrangingprobe or by ITLRangingProbeEnabled in the IOKit personality
//  (tools/build.py --probe). All state lives in AirportItlwmV2.cpp so every
//  translation unit shares one set of counters.
//
//  No request payload is ever read: only selector integers (command numbers
//  and request values) are recorded. The apple80211_ranging_* structs are
//  only forward-declared in Apple's headers, so dereferencing one here would
//  risk a kernel panic on an unknown layout.
//

#ifndef RangingProbe_hpp
#define RangingProbe_hpp

#include <IOKit/IOService.h>

namespace RangingProbe {

enum Site {
    kCmdEnable = 0,        // APPLE80211_IOC_RANGING_ENABLE  (241)
    kCmdStart,             // APPLE80211_IOC_RANGING_START   (242)
    kCmdAuthenticate,      // APPLE80211_IOC_RANGING_AUTHENTICATE (243)
    kCmdCaps,              // APPLE80211_IOC_RANGING_CAPS    (266)
    kGetEnable,
    kGetStart,
    kGetCaps,
    kSetEnable,
    kSetStart,
    kSetAuthenticate,
    kDispatchIoctl,
    kDispatchSkywalk1,
    kDispatchSkywalk2,
    kSiteCount
};

// Called once from AirportItlwm::init. Reads the boot args/personality and
// publishes the initial snapshot when enabled.
void init(IOService *owner);

bool enabled();
uint32_t capsMask();

// Counts one virtual entry point. Safe to call from any translation unit.
void note(Site site);

// Counts a dispatch-site call and, when the command is a known ranging
// selector, the matching command counter. cmd/request are integers supplied
// by the caller; data is not touched.
void noteRequest(Site site, unsigned cmd, unsigned request);

} // namespace RangingProbe

#endif /* RangingProbe_hpp */
