//
//  RTPReceiver.h
//  RTSPClient
//
//  Created by bingcai on 16/7/18.
//  Copyright © 2016年 sharetronic. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface RTPReceiver : NSObject

- (instancetype)initWithPort:(int)port;

- (void)startReceive;

@end
