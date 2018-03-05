//
//  RTSPPacket.m
//  RTSPClient
//
//  Created by bingcai on 16/7/18.
//  Copyright © 2016年 sharetronic. All rights reserved.
//

#import "RTPPacket.h"
#import "NSString+Factory.h"

static const int RTPHeaderSize = 12;
const uint8_t startCode[] = {0x00, 0x00, 0x00, 0x01};
const uint8_t startCodeI[] = {0x00, 0x00, 0x00, 0x01, 0x65};
const uint8_t startCodeP[] = {0x00, 0x00, 0x00, 0x01, 0x61};

typedef struct {
    
    uint8_t version;
    bool padding;
    bool extension;
    uint8_t csrc;
    bool marker;
    uint8_t payloadType;
    int     sequenceNumber;
    unsigned int timeStamp;
}RTPHeader;

int twoByte(uint8_t *p) {

    int temp = (p[0] & 0xff) << 8;
    temp += (p[1] & 0xff);
    return temp;
}

unsigned int fourByte(uint8_t *p) {
    
    unsigned int temp = (p[0] & 0xff) << 24;
    temp += (p[1] & 0xff) << 16;
    temp += (p[2] & 0xff) << 8;
    temp += p[3] & 0xff;
    return temp;
}

@interface NalUnit : NSObject

@property int sequence;
@property int naluSize;
@property NSData *naluData;

@end

@implementation NalUnit

- (instancetype)initWithData:(NSData *)data size:(int)size sequence:(int)sequ{

    self = [super init];
    if (self) {
        self.naluSize = size;
        self.naluData = data;
        self.sequence = sequ;
    }
    return self;
}

@end


@implementation RTPPacket {

    RTPHeader rtpHeaer;
    NSMutableArray *sliceArray;
}

//+ (instancetype)creatWithData:(NSData *)data {
//
//    RTPPacket *packet = [[RTPPacket alloc] initWithData:data];
//    return packet;
//}

- (instancetype)init {

    self = [super init];
    if (self) {
        sliceArray = [NSMutableArray array];
    }
    return self;
}

- (void)addNalu:(NSData *)rtpData {

    bzero(&rtpHeaer, sizeof(rtpHeaer));
    
    
    uint8_t *dataByte = (uint8_t *)[rtpData bytes];
    
    rtpHeaer.version = (dataByte[0] & 0xc0) >> 6;
    rtpHeaer.padding = (dataByte[0] & 0x20 >> 5) == 1;
    rtpHeaer.extension = (dataByte[0] & 0x10 >> 4) == 1;
    rtpHeaer.payloadType = dataByte[1] & 0x7f;
    rtpHeaer.sequenceNumber = twoByte(dataByte + 2);
    rtpHeaer.timeStamp = fourByte(dataByte + 4);
    
    [self loadNalu:rtpData];
}

- (void)loadNalu:(NSData *)rtpData {

    char NaluHeader[2];
    [rtpData getBytes:NaluHeader range:NSMakeRange(RTPHeaderSize, 2)];
    int fuIndicator = NaluHeader[0] & 0x1f;
    switch (fuIndicator) {
        case 7:
            [sliceArray removeAllObjects];
        case 8:
        {
            NSData *subData = [rtpData subdataWithRange:NSMakeRange(RTPHeaderSize, rtpData.length - RTPHeaderSize)];
            NalUnit *unit = [[NalUnit alloc] initWithData:subData size:rtpData.length - RTPHeaderSize sequence:rtpHeaer.sequenceNumber];
            [sliceArray addObject:unit];
        }
            break;
        case 28:
        {
            int frameType = NaluHeader[1] & 0x1f;
            if (frameType == 5) {
                
                int frameLength = rtpData.length - RTPHeaderSize - 2;
                NSData *subData = [rtpData subdataWithRange:NSMakeRange(RTPHeaderSize + 2, frameLength)];
                NalUnit *unit = [[NalUnit alloc] initWithData:subData size:frameLength sequence:rtpHeaer.sequenceNumber];
                [sliceArray addObject:unit];
                
                int ser = (NaluHeader[1] & 0xe0) >> 5;
                if (ser == 2) {   //010 分片结束标志
                    //组装成frame，回调
                    [self packetAndSendIFrame];
                }
            } else if(frameType == 1){

                int ser = (NaluHeader[1] & 0xe0) >> 5;
                if (ser == 4) {   //100 分片开始
                    [sliceArray removeAllObjects];
                }
                
                int frameLength = rtpData.length - RTPHeaderSize - 2;
                NSData *subData = [rtpData subdataWithRange:NSMakeRange(RTPHeaderSize + 2, frameLength)];
                NalUnit *unit = [[NalUnit alloc] initWithData:subData size:frameLength sequence:rtpHeaer.sequenceNumber];
                [sliceArray addObject:unit];
                
                if (ser == 2) {
                    [self pASPFrame];
                }
            }
        }
            break;
        case 1:
            if (self.delegate && [self.delegate respondsToSelector:@selector(DidPacketFrame:size:sequence:)]) {
                
                int frameLength = rtpData.length - RTPHeaderSize + 4;
                uint8_t *buf = (uint8_t *)malloc(frameLength);
                memcpy(buf, startCode, 4);
                NSData *fData = [rtpData subdataWithRange:NSMakeRange(RTPHeaderSize, frameLength - 4)];
                memcpy(buf + 4, [fData bytes], frameLength - 4);
                [self.delegate DidPacketFrame:buf size:frameLength sequence:rtpHeaer.sequenceNumber];
                free(buf);
                buf = NULL;
            }
            break;
    }
    
    
}

- (void)packetAndSendIFrame {

    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"sequence" ascending:YES];
    NSArray *tArray = [sliceArray sortedArrayUsingDescriptors:[NSArray arrayWithObject:sortDescriptor]];
    int frameSize = 0;
    for (NalUnit *unit in tArray) {
        frameSize += unit.naluSize;
    }
    
    frameSize += 4 + 4 + 5;   //00000001sps头 00000001pps头 0000000165I帧头
    
    uint8_t *buf = (uint8_t *)malloc(frameSize);
    int curLoc = 0;
    for (int i = 0; i < tArray.count; i ++) {
        NalUnit *unit = [tArray objectAtIndex:i];
        if (i == 0 || i == 1) {
            memcpy(buf + curLoc, startCode, 4);
            curLoc += 4;
            memcpy(buf + curLoc, [unit.naluData bytes], unit.naluSize);
            curLoc += unit.naluSize;
        } else if (i == 2) {
            memcpy(buf + curLoc, startCodeI, 5);
            curLoc += 5;
            memcpy(buf + curLoc, [unit.naluData bytes], unit.naluSize);
            curLoc += unit.naluSize;
        } else {
            memcpy(buf + curLoc, [unit.naluData bytes], unit.naluSize);
            curLoc += unit.naluSize;
        }
    }
    
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(DidPacketFrame:size:sequence:)]) {
        [self.delegate DidPacketFrame:buf size:frameSize sequence:0];
    }
    free(buf);
    buf = NULL;
}

- (void)pASIFrame {
    
    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"sequence" ascending:YES];
    NSArray *tArray = [sliceArray sortedArrayUsingDescriptors:[NSArray arrayWithObject:sortDescriptor]];
    int frameSize = 0;
    for (NalUnit *unit in tArray) {
        frameSize += unit.naluSize;
    }
    
    frameSize += 5;   //0000000165 I帧头
    
    uint8_t *buf = (uint8_t *)malloc(frameSize);
    int curLoc = 0;
    for (int i = 0; i < tArray.count; i ++) {
        NalUnit *unit = [tArray objectAtIndex:i];
        if (i == 0) {
            memcpy(buf + curLoc, startCodeI, 5);
            curLoc += 5;
        }
        memcpy(buf + curLoc, [unit.naluData bytes], unit.naluSize);
        curLoc += unit.naluSize;
    }
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(DidPacketFrame:size:sequence:)]) {
        [self.delegate DidPacketFrame:buf size:frameSize sequence:0];
    }
    free(buf);
    buf = NULL;
}

- (void)pASPFrame {

    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"sequence" ascending:YES];
    NSArray *tArray = [sliceArray sortedArrayUsingDescriptors:[NSArray arrayWithObject:sortDescriptor]];
    int frameSize = 0;
    for (NalUnit *unit in tArray) {
        frameSize += unit.naluSize;
    }
    
    frameSize += 5;   //0000000165 P帧头
    
    uint8_t *buf = (uint8_t *)malloc(frameSize);
    int curLoc = 0;
    for (int i = 0; i < tArray.count; i ++) {
        NalUnit *unit = [tArray objectAtIndex:i];
        if (i == 0) {
            memcpy(buf + curLoc, startCodeP, 5);
            curLoc += 5;
        }
        memcpy(buf + curLoc, [unit.naluData bytes], unit.naluSize);
        curLoc += unit.naluSize;
    }
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(DidPacketFrame:size:sequence:)]) {
        [self.delegate DidPacketFrame:buf size:frameSize sequence:0];
    }
    free(buf);
    buf = NULL;
}

- (void)dealloc {

    free(self.buffer);
    self.buffer = NULL;
}

@end
