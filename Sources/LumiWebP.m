#import "LumiWebP.h"

#include "src/webp/decode.h"

static void LumiReleasePixelBuffer(void *info, const void *data, size_t size) {
    free((void *)data);
}

BOOL LumiDataIsWebP(NSData *data) {
    if (data.length < 12) {
        return NO;
    }
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    return bytes[0] == 'R' && bytes[1] == 'I' && bytes[2] == 'F' && bytes[3] == 'F' &&
           bytes[8] == 'W' && bytes[9] == 'E' && bytes[10] == 'B' && bytes[11] == 'P';
}

UIImage *LumiDecodeWebPData(NSData *data) {
    if (!LumiDataIsWebP(data)) {
        return nil;
    }
    int width = 0;
    int height = 0;
    uint8_t *pixels = WebPDecodeRGBA((const uint8_t *)data.bytes, data.length, &width, &height);
    if (!pixels || width <= 0 || height <= 0) {
        if (pixels) {
            WebPFree(pixels);
        }
        return nil;
    }

    size_t pixelCount = (size_t)width * (size_t)height;
    size_t byteCount = pixelCount * 4;
    uint8_t *premultiplied = (uint8_t *)malloc(byteCount);
    if (!premultiplied) {
        WebPFree(pixels);
        return nil;
    }
    for (size_t index = 0; index < pixelCount; index++) {
        uint8_t *source = pixels + index * 4;
        uint8_t *target = premultiplied + index * 4;
        uint32_t alpha = source[3];
        if (alpha == 255) {
            target[0] = source[0];
            target[1] = source[1];
            target[2] = source[2];
        } else if (alpha == 0) {
            target[0] = 0;
            target[1] = 0;
            target[2] = 0;
        } else {
            target[0] = (uint8_t)((source[0] * alpha + 127) / 255);
            target[1] = (uint8_t)((source[1] * alpha + 127) / 255);
            target[2] = (uint8_t)((source[2] * alpha + 127) / 255);
        }
        target[3] = (uint8_t)alpha;
    }
    WebPFree(pixels);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, premultiplied, byteCount, LumiReleasePixelBuffer);
    CGImageRef imageRef = CGImageCreate((size_t)width,
                                        (size_t)height,
                                        8,
                                        32,
                                        (size_t)width * 4,
                                        colorSpace,
                                        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big,
                                        provider,
                                        NULL,
                                        false,
                                        kCGRenderingIntentDefault);
    UIImage *image = nil;
    if (imageRef) {
        image = [UIImage imageWithCGImage:imageRef];
        CGImageRelease(imageRef);
    }
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    return image;
}
