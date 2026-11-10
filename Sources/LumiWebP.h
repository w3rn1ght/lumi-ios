#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Decodes a WebP image (lossy or lossless) into a UIImage.
/// Returns nil when the data is not a WebP file or decoding fails.
UIImage * _Nullable LumiDecodeWebPData(NSData *data);

/// Returns YES when the data starts with the RIFF/WEBP signature.
BOOL LumiDataIsWebP(NSData *data);

NS_ASSUME_NONNULL_END
