//
//  RTSPConnection.m
//  RTSPClient
//
//  Created by bingcai on 16/7/20.
//  Copyright © 2016年 sharetronic. All rights reserved.
//

#import "RTSPConnection.h"
#import "RTPReceiver.h"
#import "CocoaAsyncSocket.h"

#define HOST @"192.168.0.102"   //camera
//#define HOST @"192.168.0.111"
#define PORT 554

#define WRITE_TIMEOUT 3.0
#define READ_TIMEOUT 60.0

const static NSString *VERSION = @" RTSP/1.0\r\n";
const static NSString *RTSP_OK = @"RTSP/1.0 200 OK";

@interface RTSPConnection() <GCDAsyncSocketDelegate> {

    dispatch_queue_t socketQueue;
    GCDAsyncSocket *clientSocket;
    NSString *_host;
    uint16_t _port;
    int      _rtpPort;
    NSString *_rtspAddress;
    
    //    服务端返回数据
    NSString *_sessionId;
    NSString *_cliendPort;  //RTP、RTCP端口
    RTPReceiver *_rtpReceiver;
}

@end

@implementation RTSPConnection

- (instancetype)init {

    if (self = [super init]) {
        socketQueue = dispatch_queue_create("tcpSocketQueue", NULL);
        clientSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:socketQueue];
        
        _host = HOST;
        _port = PORT;
//        _rtspAddress = [NSString stringWithFormat:@"rtsp://%@:%d/", _host, _port];
        _rtspAddress = [NSString stringWithFormat:@"rtsp://%@:%d/live.264", _host, _port];
        _rtpPort = arc4random() % 10000 + 6000;
        _cliendPort = [NSString stringWithFormat:@"%d-%d", _rtpPort , _rtpPort + 1];
        
        _rtpReceiver = [[RTPReceiver alloc] initWithPort:_rtpPort];
        [_rtpReceiver startReceive];
        
        [self connectSocket];
    }
    return self;
}

- (void)connectSocket {
    
    NSError *error;
    int connectRet = [clientSocket connectToHost:_host onPort:_port error:&error];
    if (!connectRet) {
        NSLog(@"Error Connection: %@", error.localizedDescription);
    }
}

#pragma mard socketDelegate
- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port {
    NSLog(@"didConnectToHost, host: %@, port: %d", host, port);
    
    [self doOption];
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    
    NSString *dataString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSLog(@"didReadData: %ld, %@", tag, dataString);
    
    switch (tag) {
        case 0:
            [self doDecribe];
            break;
        case 1:
            [self doSetup];
            break;
        case 2:
        {
            NSError *error;  //@"Session:\\s(\\w+)[\\s\\S]+?client_port=(\\w+)
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"Session:\\s(\\w+)" options:NSRegularExpressionAllowCommentsAndWhitespace error:&error];
            NSArray *result = [regex matchesInString:dataString options:NSMatchingReportCompletion range:NSMakeRange(0, dataString.length)];
            
            if ([result count] == 0) {
                NSLog(@"ERROR!!! Cann't find session id and client port");
                return;
            }
            
            _sessionId = [dataString substringWithRange:[result[0] rangeAtIndex:1]];
//            [self doSetupSession];
            [self doPlay];
        }
            break;
        case 3:
//            [self doPlay];
            break;
            
        default:
            break;
    }
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {
    NSLog(@"didWriteDataWithTag: %ld", tag);
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
    NSLog(@"socketDidDisconnect: %@", err.localizedDescription);
}

- (NSTimeInterval)socket:(GCDAsyncSocket *)sock shouldTimeoutReadWithTag:(long)tag elapsed:(NSTimeInterval)elapsed bytesDone:(NSUInteger)length {
    
    NSLog(@"shouldTimeoutReadWithTag, elapsed: %f, bytesDone: %ld", elapsed, length);
    return 0.0;
}

#pragma mark send RTSP data
- (void)doOption {
    
    NSMutableString *dataString = [NSMutableString string];
    //    [dataString appendString:@"OPTIONS "];
    
    [dataString appendString:[NSString stringWithFormat:@"OPTIONS %@ RTSP/1.0\r\n", _rtspAddress]];
    [dataString appendString:@"CSeq: 1\r\n"];
    [dataString appendString:@"\r\n"];
    NSData *data = [dataString dataUsingEncoding:NSUTF8StringEncoding];
    [clientSocket writeData:data withTimeout:WRITE_TIMEOUT tag:0];
    [clientSocket readDataWithTimeout:READ_TIMEOUT tag:0];
}

- (void)doDecribe {
    
    NSMutableString *dataString = [NSMutableString string];
    [dataString appendString:[NSString stringWithFormat:@"DESCRIBE %@ RTSP/1.0\r\n", _rtspAddress]];
    [dataString appendString:@"Accept: application/sdp\r\n"];
    [dataString appendString:@"CSeq: 2\r\n"];
    [dataString appendString:@"\r\n"];
    
    NSData *data = [dataString dataUsingEncoding:NSUTF8StringEncoding];
    [clientSocket writeData:data withTimeout:WRITE_TIMEOUT tag:1];
    [clientSocket readDataWithTimeout:READ_TIMEOUT tag:1];
}

- (void)doSetup {
    
    NSMutableString *dataString = [NSMutableString string];
    [dataString appendString:[NSString stringWithFormat:@"SETUP %@/track1 RTSP/1.0\r\n", _rtspAddress]];
    [dataString appendString:[NSString stringWithFormat:@"Transport: RTP/AVP/UDP;unicast;client_port=%@\r\n", _cliendPort]];
    [dataString appendString:@"x-Dynamic-Rate: 0\r\n"];
    [dataString appendString:@"CSeq: 3\r\n"];
    [dataString appendString:@"\r\n"];
    
    NSData *data = [dataString dataUsingEncoding:NSUTF8StringEncoding];
    [clientSocket writeData:data withTimeout:WRITE_TIMEOUT tag:2];
    [clientSocket readDataWithTimeout:READ_TIMEOUT tag:2];
}

- (void)doSetupSession {

    NSMutableString *dataString = [NSMutableString string];
    [dataString appendString:[NSString stringWithFormat:@"SETUP %@/track2 RTSP/1.0\r\n", _rtspAddress]];
    [dataString appendString:[NSString stringWithFormat:@"Transport: RTP/AVP/UDP;unicast;client_port=%@\r\n", _cliendPort]];
    [dataString appendString:@"x-Dynamic-Rate: 0\r\n"];
    [dataString appendString:@"CSeq: 4\r\n"];
//    [dataString appendString:[NSString stringWithFormat:@"Session: %@", _sessionId]];
    [dataString appendString:@"\r\n"];
    
    NSData *data = [dataString dataUsingEncoding:NSUTF8StringEncoding];
    [clientSocket writeData:data withTimeout:WRITE_TIMEOUT tag:3];
    [clientSocket readDataWithTimeout:READ_TIMEOUT tag:3];
}

- (void)doPlay {
    
    NSMutableString *dataString = [NSMutableString string];
    [dataString appendString:[NSString stringWithFormat:@"PLAY %@ RTSP/1.0\r\n", _rtspAddress]];
    [dataString appendString:@"Range: npt=0.000-\r\n"];
    [dataString appendString:@"CSeq: 4\r\n"];
    [dataString appendString:@"\r\n"];
    
    NSData *data = [dataString dataUsingEncoding:NSUTF8StringEncoding];
    [clientSocket writeData:data withTimeout:WRITE_TIMEOUT tag:4];
    [clientSocket readDataWithTimeout:READ_TIMEOUT tag:4];
}



@end
