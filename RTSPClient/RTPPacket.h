//
//  RTSPPacket.h
//  RTSPClient
//
//  Created by bingcai on 16/7/18.
//  Copyright © 2016年 sharetronic. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, NalType) {
    NalTypeSPS = 0,
    NalTypePPS,
    NalTypeIFrame,
    NalTypeIFrameS,  //I frame start, S：E：R ＝ 1：0：0
    NalTypeIFrameM,  //I frame middle, S：E：R ＝ 0：0：0
    NalTypeIFrameE,  //I frame end, S：E：R ＝ 0：1：0
    NalTypePFrame,
    NalTypeUnknown
};

@protocol RTPPacketDelegate <NSObject>

- (void)DidPacketFrame:(uint8_t *)frame size:(int)size sequence:(int)sequ;

@end

@interface RTPPacket : NSObject

- (void)addNalu:(NSData *)rtpData;

@property NalType nalType;
@property uint8_t *buffer;

@property(nonatomic, weak) id<RTPPacketDelegate> delegate;

@end
