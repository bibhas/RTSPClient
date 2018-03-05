//
//  NSString+Factory.m
//  RTSPClient
//
//  Created by bingcai on 16/7/20.
//  Copyright © 2016年 sharetronic. All rights reserved.
//

#import "NSString+Factory.h"

@implementation NSString (Factory)

+ (NSString *)stringwithChar:(uint8_t *)data length:(int)length {

    NSString *string1 = @"";
    int datalenght = length > 200 ? 200 : length;
    for (int i = 0; i < datalenght; i ++) {
        NSString *temp = [NSString stringWithFormat:@"%x", data[i]&0xff];
        if ([temp length] == 1) {
            temp = [NSString stringWithFormat:@"0%@", temp];
        }
        string1 = [string1 stringByAppendingString:temp];
    }
    return string1;
}

@end
