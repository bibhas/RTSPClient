//
//  NSString+Factory.h
//  RTSPClient
//
//  Created by bingcai on 16/7/20.
//  Copyright © 2016年 sharetronic. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSString (Factory)

+ (NSString *)stringwithChar:(uint8_t *)data length:(int)length;

@end
