//
//  H264Decoder.h
//  AVSamplePlayer
//
//  Created by bingcai on 16/7/1.
//  Copyright © 2016年 sharetronic. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>

typedef enum {
    
    KxMovieFrameTypeAudio,
    KxMovieFrameTypeVideo,
    KxMovieFrameTypeArtwork,
    KxMovieFrameTypeSubtitle,
    
} KxMovieFrameType;

typedef enum {
    
    KxVideoFrameFormatRGB,
    KxVideoFrameFormatYUV,
    
} KxVideoFrameFormat;

@interface KxMovieFrame : NSObject
@property (readonly, nonatomic) KxMovieFrameType type;
@property (readonly, nonatomic) CGFloat position;
@property (readonly, nonatomic) CGFloat duration;
@end

@interface KxAudioFrame : KxMovieFrame
@property (readonly, nonatomic, strong) NSData *samples;
@end

@interface KxVideoFrame : KxMovieFrame
@property (readonly, nonatomic) KxVideoFrameFormat format;
@property (readonly, nonatomic) NSUInteger width;
@property (readonly, nonatomic) NSUInteger height;
@end

@interface KxVideoFrameRGB : KxVideoFrame
@property (readonly, nonatomic) NSUInteger linesize;
@property (readonly, nonatomic, strong) NSData *rgb;
//- (UIImage *) asImage;
@end

@interface KxVideoFrameYUV : KxVideoFrame
@property (readonly, nonatomic, strong) NSData *luma;
@property (readonly, nonatomic, strong) NSData *chromaB;
@property (readonly, nonatomic, strong) NSData *chromaR;
@end

@interface H264Decoder : NSObject

@property (readonly, nonatomic) NSUInteger frameWidth;
@property (readonly, nonatomic) NSUInteger frameHeight;

@property (nonatomic) int outputWidth, outputHeight;

/* Last decoded picture as UIImage */
@property (nonatomic, readonly) UIImage *currentImage;

- (void)videoDecoder_init;
- (NSArray *)videoDecoder_decode:(uint8_t *)nalBuffer size:(int)inSize;
- (CVPixelBufferRef)videoDecoder_decodeToPixel:(uint8_t *)nalBuffer size:(int)inSize;
- (UIImage *)decodeToImage:(uint8_t *)nalBuffer size:(int)inSize;

//decode nalu 
- (CGSize)videoDecoder_decodeToImage:(uint8_t *)nalBuffer size:(int)inSize;

- (BOOL) setupVideoFrameFormat: (KxVideoFrameFormat) format;

@end
