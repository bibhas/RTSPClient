//
//  RTPReceiver.m
//  RTSPClient
//
//  Created by bingcai on 16/7/18.
//  Copyright © 2016年 sharetronic. All rights reserved.
//

#import "RTPReceiver.h"
#import "CocoaAsyncSocket/GCD/GCDAsyncUdpSocket.h"
#import "RTPPacket.h"

@interface RTPReceiver() <GCDAsyncUdpSocketDelegate, RTPPacketDelegate> {
    
    int      _rtpPort;
    dispatch_queue_t _rtpQueue;
    GCDAsyncUdpSocket   *_rtpSocket;
    RTPPacket       *_rtpPacket;
}

@end

@implementation RTPReceiver

- (instancetype)initWithPort:(int)port {

    if (self == [super init]) {
        _rtpPort = port;
        
        _rtpQueue = dispatch_queue_create("rtpSocketQueue", NULL);
        _rtpSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:_rtpQueue];
        
        NSError *error;
        int connectRect = [_rtpSocket bindToPort:_rtpPort error:&error];
        if (!connectRect) {
            NSLog(@"ERROR!!! bind upd port: %@", error.localizedDescription);
        }
        
        _rtpPacket = [[RTPPacket alloc]init];
        _rtpPacket.delegate = self;
    }
    return self;
}

- (void)startReceive {
    
    NSError *error;
    [_rtpSocket beginReceiving:&error];
    if (error) {
        NSLog(@"ERROR!!! receive RTP: %@", error.localizedDescription);
    }
}

#pragma mark GCDAsyncUdpSocket Delegate
- (void)udpSocket:(GCDAsyncUdpSocket *)sock didReceiveData:(NSData *)data fromAddress:(NSData *)address withFilterContext:(id)filterContext {

//    NSString *string1 = @"";
//    int datalenght = data.length > 200 ? 200 : data.length;
//    char *dataByte = (char *)malloc(datalenght);
//    memcpy(dataByte, [data bytes], datalenght);
//    for (int i = 0; i < datalenght; i ++) {
//        NSString *temp = [NSString stringWithFormat:@"%x", dataByte[i]&0xff];
//        if ([temp length] == 1) {
//            temp = [NSString stringWithFormat:@"0%@", temp];
//        }
//        string1 = [string1 stringByAppendingString:temp];
//    }
//    NSLog(@"%@", string1);
    
    [_rtpPacket addNalu:data];
}

#pragma mark RTP Packet Delegate
- (void)DidPacketFrame:(uint8_t *)frame size:(int)size sequence:(int)sequ {

    NSString *string1 = @"";
    int datalenght = size > 200 ? 200 : size;
    for (int i = 0; i < datalenght; i ++) {
        NSString *temp = [NSString stringWithFormat:@"%x", frame[i]&0xff];
        if ([temp length] == 1) {
            temp = [NSString stringWithFormat:@"0%@", temp];
        }
        string1 = [string1 stringByAppendingString:temp];
    }
    NSLog(@"%@", string1);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *dict = @{@"data":[NSData dataWithBytes:frame length:size],
                               @"size":[NSNumber numberWithInt:size]};
        [[NSNotificationCenter defaultCenter] postNotificationName:@"client" object:dict];
    });
}

@end
