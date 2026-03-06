#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "AppleMusicIcon" asset catalog image resource.
static NSString * const ACImageNameAppleMusicIcon AC_SWIFT_PRIVATE = @"AppleMusicIcon";

/// The "DromosIcon" asset catalog image resource.
static NSString * const ACImageNameDromosIcon AC_SWIFT_PRIVATE = @"DromosIcon";

/// The "SpotifyIcon" asset catalog image resource.
static NSString * const ACImageNameSpotifyIcon AC_SWIFT_PRIVATE = @"SpotifyIcon";

#undef AC_SWIFT_PRIVATE
