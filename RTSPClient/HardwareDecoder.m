//
//  HardwareDecoder.m
//  AVSamplePlayer
//
//  Created by bingcai on 16/7/8.
//  Copyright © 2016年 sharetronic. All rights reserved.
//

#import "HardwareDecoder.h"
//#import "VideoFileParser.h"

NSString * const naluTypesStrings[] =
{
    @"0: Unspecified (non-VCL)",
    @"1: Coded slice of a non-IDR picture (VCL)",    // P frame
    @"2: Coded slice data partition A (VCL)",
    @"3: Coded slice data partition B (VCL)",
    @"4: Coded slice data partition C (VCL)",
    @"5: Coded slice of an IDR picture (VCL)",      // I frame
    @"6: Supplemental enhancement information (SEI) (non-VCL)",
    @"7: Sequence parameter set (non-VCL)",         // SPS parameter
    @"8: Picture parameter set (non-VCL)",          // PPS parameter
    @"9: Access unit delimiter (non-VCL)",
    @"10: End of sequence (non-VCL)",
    @"11: End of stream (non-VCL)",
    @"12: Filler data (non-VCL)",
    @"13: Sequence parameter set extension (non-VCL)",
    @"14: Prefix NAL unit (non-VCL)",
    @"15: Subset sequence parameter set (non-VCL)",
    @"16: Reserved (non-VCL)",
    @"17: Reserved (non-VCL)",
    @"18: Reserved (non-VCL)",
    @"19: Coded slice of an auxiliary coded picture without partitioning (non-VCL)",
    @"20: Coded slice extension (non-VCL)",
    @"21: Coded slice extension for depth view components (non-VCL)",
    @"22: Reserved (non-VCL)",
    @"23: Reserved (non-VCL)",
    @"24: STAP-A Single-time aggregation packet (non-VCL)",
    @"25: STAP-B Single-time aggregation packet (non-VCL)",
    @"26: MTAP16 Multi-time aggregation packet (non-VCL)",
    @"27: MTAP24 Multi-time aggregation packet (non-VCL)",
    @"28: FU-A Fragmentation unit (non-VCL)",
    @"29: FU-B Fragmentation unit (non-VCL)",
    @"30: Unspecified (non-VCL)",
    @"31: Unspecified (non-VCL)",
};

@interface HardwareDecoder()

@property (nonatomic, assign) CMVideoFormatDescriptionRef formatDesc;
@property (nonatomic, assign) VTDecompressionSessionRef decompressionSession;
//@property (nonatomic, retain) AVSampleBufferDisplayLayer *videoLayer;
@property (nonatomic, assign) int spsSize;
@property (nonatomic, assign) int ppsSize;

@end

@implementation HardwareDecoder {
    
    // 解码
    uint8_t *_sps;
    //    NSInteger _spsSize;
    uint8_t *_pps;
    //    NSInteger _ppsSize;
    VTDecompressionSessionRef _deocderSession;
    CMVideoFormatDescriptionRef _decoderFormatDescription;
}

#pragma mark - 硬解码 from stack overflow
- (void)receivedRawVideoFrame:(uint8_t *)frame withSize:(uint32_t)frameSize
{
    OSStatus status;
    
    uint8_t *data = NULL;
    uint8_t *pps = NULL;
    uint8_t *sps = NULL;
    
    // I know what my H.264 data source's NALUs look like so I know start code index is always 0.
    // if you don't know where it starts, you can use a for loop similar to how i find the 2nd and 3rd start codes
    int startCodeIndex = 0;
    int secondStartCodeIndex = 0;
    int thirdStartCodeIndex = 0;
    
    long blockLength = 0;
    
    CMSampleBufferRef sampleBuffer = NULL;
    CMBlockBufferRef blockBuffer = NULL;
    
    int nalu_type = (frame[startCodeIndex + 4] & 0x1F);
    NSLog(@"~~~~~~~ Received NALU Type \"%@\" ~~~~~~~~", naluTypesStrings[nalu_type]);
    
    // if we havent already set up our format description with our SPS PPS parameters, we
    // can't process any frames except type 7 that has our parameters
    if (nalu_type != 7 && _formatDesc == NULL)
    {
        NSLog(@"Video error: Frame is not an I Frame and format description is null");
        return;
    }
    
    // NALU type 7 is the SPS parameter NALU
    if (nalu_type == 7)
    {
        // find where the second PPS start code begins, (the 0x00 00 00 01 code)
        // from which we also get the length of the first SPS code
        for (int i = startCodeIndex + 4; i < startCodeIndex + 40; i++)
        {
            if (frame[i] == 0x00 && frame[i+1] == 0x00 && frame[i+2] == 0x00 && frame[i+3] == 0x01)
            {
                secondStartCodeIndex = i;
                _spsSize = secondStartCodeIndex;   // includes the header in the size
                break;
            }
        }
        
        // find what the second NALU type is
        nalu_type = (frame[secondStartCodeIndex + 4] & 0x1F);
        NSLog(@"~~~~~~~ Received NALU Type \"%@\" ~~~~~~~~", naluTypesStrings[nalu_type]);
    }
    
    // type 8 is the PPS parameter NALU
    if(nalu_type == 8)
    {
        // find where the NALU after this one starts so we know how long the PPS parameter is
        for (int i = _spsSize + 4; i < _spsSize + 30; i++)
        {
            if (frame[i] == 0x00 && frame[i+1] == 0x00 && frame[i+2] == 0x00 && frame[i+3] == 0x01)
            {
                thirdStartCodeIndex = i;
                _ppsSize = thirdStartCodeIndex - _spsSize;
                nalu_type = (frame[thirdStartCodeIndex + 4] & 0x1F);
                if (nalu_type == 5) {
                    break;
                }
                
            }
        }
        
        // allocate enough data to fit the SPS and PPS parameters into our data objects.
        // VTD doesn't want you to include the start code header (4 bytes long) so we add the - 4 here
        sps = malloc(_spsSize - 4);
        pps = malloc(_ppsSize - 4);
        
        // copy in the actual sps and pps values, again ignoring the 4 byte header
        memcpy (sps, &frame[4], _spsSize-4);
        memcpy (pps, &frame[_spsSize+4], _ppsSize-4);
        
        // now we set our H264 parameters
        uint8_t*  parameterSetPointers[2] = {sps, pps};
        size_t parameterSetSizes[2] = {_spsSize-4, _ppsSize-4};
        
        status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2,
                                                                     (const uint8_t *const*)parameterSetPointers,
                                                                     parameterSetSizes, 4,
                                                                     &_formatDesc);
        
        NSLog(@"\t\t Creation of CMVideoFormatDescription: %@", (status == noErr) ? @"successful!" : @"failed...");
        if(status != noErr) NSLog(@"\t\t Format Description ERROR type: %d", (int)status);
        
        // See if decomp session can convert from previous format description
        // to the new one, if not we need to remake the decomp session.
        // This snippet was not necessary for my applications but it could be for yours
        /*BOOL needNewDecompSession = (VTDecompressionSessionCanAcceptFormatDescription(_decompressionSession, _formatDesc) == NO);
         if(needNewDecompSession)
         {
         [self createDecompSession];
         }*/
        
        // now lets handle the IDR frame that (should) come after the parameter sets
        // I say "should" because that's how I expect my H264 stream to work, YMMV
        nalu_type = (frame[thirdStartCodeIndex + 4] & 0x1F);
        NSLog(@"~~~~~~~ Received NALU Type \"%@\" ~~~~~~~~", naluTypesStrings[nalu_type]);
    }
    
    // create our VTDecompressionSession.  This isnt neccessary if you choose to use AVSampleBufferDisplayLayer
    if((status == noErr) && (_decompressionSession == NULL))
    {
        [self createDecompSession];
    }
    
    // type 5 is an IDR frame NALU.  The SPS and PPS NALUs should always be followed by an IDR (or IFrame) NALU, as far as I know
    if(nalu_type == 5)
    {
        // find the offset, or where the SPS and PPS NALUs end and the IDR frame NALU begins
        int offset = _spsSize + _ppsSize;
        blockLength = frameSize - offset;
        data = malloc(blockLength);
        data = memcpy(data, &frame[offset], blockLength);
        
        // replace the start code header on this NALU with its size.
        // AVCC format requires that you do this.
        // htonl converts the unsigned int from host to network byte order
        uint32_t dataLength32 = htonl (blockLength - 4);
        memcpy (data, &dataLength32, sizeof (uint32_t));
        
        // create a block buffer from the IDR NALU
        status = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, data,  // memoryBlock to hold buffered data
                                                    blockLength,  // block length of the mem block in bytes.
                                                    kCFAllocatorNull, NULL,
                                                    0, // offsetToData
                                                    blockLength,   // dataLength of relevant bytes, starting at offsetToData
                                                    0, &blockBuffer);
        
        NSLog(@"\t\t BlockBufferCreation: \t %@", (status == kCMBlockBufferNoErr) ? @"successful!" : @"failed...");
    }
    
    // NALU type 1 is non-IDR (or PFrame) picture
    if (nalu_type == 1)
    {
        // non-IDR frames do not have an offset due to SPS and PSS, so the approach
        // is similar to the IDR frames just without the offset
        blockLength = frameSize;
        data = malloc(blockLength);
        data = memcpy(data, &frame[0], blockLength);
        
        // again, replace the start header with the size of the NALU
        uint32_t dataLength32 = htonl (blockLength - 4);
        memcpy (data, &dataLength32, sizeof (uint32_t));
        
        status = CMBlockBufferCreateWithMemoryBlock(NULL, data,  // memoryBlock to hold data. If NULL, block will be alloc when needed
                                                    blockLength,  // overall length of the mem block in bytes
                                                    kCFAllocatorNull, NULL,
                                                    0,     // offsetToData
                                                    blockLength,  // dataLength of relevant data bytes, starting at offsetToData
                                                    0, &blockBuffer);
        
        NSLog(@"\t\t BlockBufferCreation: \t %@", (status == kCMBlockBufferNoErr) ? @"successful!" : @"failed...");
    }
    
    // now create our sample buffer from the block buffer,
        if(status == noErr)
        {
            // here I'm not bothering with any timing specifics since in my case we displayed all frames immediately
            const size_t sampleSize = blockLength;
            status = CMSampleBufferCreate(kCFAllocatorDefault,
                                          blockBuffer, true, NULL, NULL,
                                          _formatDesc, 1, 0, NULL, 1,
                                          &sampleSize, &sampleBuffer);
    
            NSLog(@"\t\t SampleBufferCreate: \t %@", (status == noErr) ? @"successful!" : @"failed...");
        }
    
        if(status == noErr)
        {
            // set some values of the sample buffer's attachments
            CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
            CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
            CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
    
            // either send the samplebuffer to a VTDecompressionSession or to an AVSampleBufferDisplayLayer
            [self render:sampleBuffer];
        }
    
    // free memory to avoid a memory leak, do the same for sps, pps and blockbuffer
    if (NULL != data)
    {
        free (data);
        data = NULL;
    }
}

//The following method creates your VTD session. Recreate it whenever you receive new parameters. (You don't have to recreate it every time you receive parameters, pretty sure.)
//If you want to set attributes for the destination CVPixelBuffer, read up on CoreVideo PixelBufferAttributes values and put them in NSDictionary *destinationImageBufferAttributes.
-(void) createDecompSession
{
    // make sure to destroy the old VTD session
    _decompressionSession = NULL;
    VTDecompressionOutputCallbackRecord callBackRecord;
    callBackRecord.decompressionOutputCallback = decompressionSessionDecodeFrameCallback;
    
    // this is necessary if you need to make calls to Objective C "self" from within in the callback method.
    callBackRecord.decompressionOutputRefCon = (__bridge void *)self;
    
    // you can set some desired attributes for the destination pixel buffer.  I didn't use this but you may
    // if you need to set some attributes, be sure to uncomment the dictionary in VTDecompressionSessionCreate
    NSDictionary *destinationImageBufferAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                                      [NSNumber numberWithBool:YES],
                                                      (id)kCVPixelBufferOpenGLESCompatibilityKey,
                                                      nil];
    
    OSStatus status =  VTDecompressionSessionCreate(NULL, _formatDesc, NULL,
                                                    NULL, // (__bridge CFDictionaryRef)(destinationImageBufferAttributes)
                                                    &callBackRecord, &_decompressionSession);
    NSLog(@"Video Decompression Session Create: \t %@", (status == noErr) ? @"successful!" : @"failed...");
    if(status != noErr) NSLog(@"\t\t VTD ERROR type: %d", (int)status);
}

//Now this method gets called every time VTD is done decompressing any frame you sent to it. This method gets called even if there's an error or if the frame is dropped.
void decompressionSessionDecodeFrameCallback(void *decompressionOutputRefCon,
                                             void *sourceFrameRefCon,
                                             OSStatus status,
                                             VTDecodeInfoFlags infoFlags,
                                             CVImageBufferRef imageBuffer,
                                             CMTime presentationTimeStamp,
                                             CMTime presentationDuration)
{
    HardwareDecoder *streamManager = (__bridge HardwareDecoder *)decompressionOutputRefCon;
    
    if (status != noErr)
    {
        NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        NSLog(@"Decompressed error: %@", error);
    }
    else
    {
        NSLog(@"Decompressed sucessfully");
        //        CIImage *ciImage = [CIImage imageWithCVImageBuffer:imageBuffer];
        //        UIImage *image = [UIImage imageWithCIImage:ciImage];
        
        CVPixelBufferRef *outputPixelBuffer = (CVPixelBufferRef *)sourceFrameRefCon;
        *outputPixelBuffer = CVPixelBufferRetain(imageBuffer);
        
        if (!streamManager.delegate) {
            [streamManager.delegate displayDecodedFrame:imageBuffer];
        }
        
        //        dispatch_async(dispatch_get_main_queue(), ^{
        //            [[NSNotificationCenter defaultCenter] postNotificationName:@"image" object:image];
        //        });
        // do something with your resulting CVImageBufferRef that is your decompressed frame
        //        [streamManager displayDecodedFrame:imageBuffer];
    }
}

//This is where we actually send the sampleBuffer off to the VTD to be decoded.
- (void) render:(CMSampleBufferRef)sampleBuffer
{
    VTDecodeFrameFlags flags = kVTDecodeFrame_EnableAsynchronousDecompression;
    VTDecodeInfoFlags flagOut;
    NSDate* currentTime = [NSDate date];
    VTDecompressionSessionDecodeFrame(_decompressionSession, sampleBuffer, flags,
                                      (void*)CFBridgingRetain(currentTime), &flagOut);
    
    CFRelease(sampleBuffer);
    
    //    UIImage *image = [self imageFromSampleBuffer:sampleBuffer];
    dispatch_async(dispatch_get_main_queue(), ^{
        //        self.imageView.image = image;
        //        [self.videoLayer enqueueSampleBuffer:sampleBuffer];
    });
    
    // if you're using AVSampleBufferDisplayLayer, you only need to use this line of code
    
}

#pragma mark - 硬解码——从解码本地文件改
- (void)hardwareDecode:(uint8_t *)buf size:(int)inSize {
    
    NSString *byteString = [self startByteFrom:buf size:inSize];
    NSRange ppsRange = [byteString rangeOfString:@"0000000168"];
    BOOL isKeyFrame = ppsRange.location != NSNotFound;

    if (isKeyFrame) {
        
        int spsLength = (int)ppsRange.location / 2;
        uint8_t *spsData = (uint8_t *)malloc(spsLength);
        memcpy(spsData, buf, spsLength);
        
//        00000001674d001f95a814016e8400000fa00001d4c0100000000168ee3c800000000106e501a8800000000165b800000f9bf0bffeced6afe1b11a32d639e05db83b1341baefb9ded91702fbd91a7c6c4700bfbcf1ae33ebce56e84c01f0d6b06c77669fc13c4903f755227
//        中间包含sei增强，先过滤点。把这个数据当成PPS解码，偶尔会出现绿屏

//        NSRange seiRange = [byteString rangeOfString:@"0000000106"];
//        int ppsLength = (int)(seiRange.location - ppsRange.location) / 2;
//        uint8_t *ppsData = (uint8_t *)malloc(ppsLength);
//        memcpy(ppsData, buf + spsLength, ppsLength);
        
        NSRange iFrameRange = [byteString rangeOfString:@"0000000165"];
        int ppsLength = (int)(iFrameRange.location - ppsRange.location) / 2;
        uint8_t *ppsData = (uint8_t *)malloc(ppsLength);
        memcpy(ppsData, buf + spsLength, ppsLength);
        
        int iFrameLocation = (int)iFrameRange.location / 2;
        uint8_t *iFrameData = (uint8_t *)malloc(inSize - iFrameLocation);
        memcpy(iFrameData, buf + iFrameLocation, inSize - iFrameLocation);
        for (int i = 0; i < 3; i ++) {
            switch (i) {
                case 0:
                    [self decodeNalu:spsData size:spsLength];
                    break;
                case 1:
                    [self decodeNalu:ppsData size:ppsLength];
                    break;
                case 2:
                    [self decodeNalu:iFrameData size:(inSize - iFrameLocation)];
                    break;
            }
        }
    } else {
        
        [self decodeNalu:buf size:inSize];
    }
}

- (void)decodeNalu:(uint8_t *)buf size:(int)inSize {
    
    uint32_t nalSize = (uint32_t)(inSize- 4);
    uint8_t *pNalSize = (uint8_t*)(&nalSize);
    buf[0] = *(pNalSize + 3);
    buf[1] = *(pNalSize + 2);
    buf[2] = *(pNalSize + 1);
    buf[3] = *(pNalSize);
    
    CVPixelBufferRef pixelBuffer = NULL;
    int nalType = buf[4] & 0x1F;
    switch (nalType) {
        case 0x05:
            if([self initH264Decoder]) {
                pixelBuffer = [self decode:buf withSize:inSize];
            }
            break;
        case 0x07:
            _spsSize = inSize - 4;
            _sps = malloc(_spsSize);
            memcpy(_sps, buf + 4, _spsSize);
            break;
        case 0x08:
            _ppsSize = inSize - 4;
            _pps = malloc(_ppsSize);
            memcpy(_pps, buf + 4, _ppsSize);
            break;
            
        default:
            pixelBuffer = [self decode:buf withSize:inSize];
            break;
    }
}

-(BOOL)initH264Decoder {
//    if(_deocderSession) {
//        return YES;
//    }
    
    const uint8_t* const parameterSetPointers[2] = { _sps, _pps };
    const size_t parameterSetSizes[2] = { _spsSize, _ppsSize };
    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                          2, //param count
                                                                          parameterSetPointers,
                                                                          parameterSetSizes,
                                                                          4, //nal start code size
                                                                          &_decoderFormatDescription);
    
    if(status == noErr) {
        NSLog(@"CMVideoFormatDescriptionCreateFromH264ParameterSets sucess!");
//        如果属性设置为空，pixelBuffer显示的时候会报错，Why is CVOpenGLESTextureCacheCreateTextureFromImage() returning an error of -6683?  参考https://developer.apple.com/library/ios/qa/qa1781/_index.html
        CFDictionaryRef attrs = NULL;
        NSDictionary* destinationPixelBufferAttributes = @{
                                                           (id)kCVPixelBufferPixelFormatTypeKey : [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange],
                                                           (id)kCVPixelBufferWidthKey : [NSNumber numberWithInt:1280],
                                                           (id)kCVPixelBufferHeightKey : [NSNumber numberWithInt:720],
                                                           //这里款高和编码反的
                                                           (id)kCVPixelBufferOpenGLCompatibilityKey : [NSNumber numberWithBool:YES]
                                                           };
        //硬解必须是 kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange 或者是kCVPixelFormatType_420YpCbCr8Planar
        //因为iOS是  nv12  其他是nv21
        const void *keys[] = { kCVPixelBufferPixelFormatTypeKey };
        //      kCVPixelFormatType_420YpCbCr8Planar is YUV420
        //      kCVPixelFormatType_420YpCbCr8BiPlanarFullRange is NV12
        uint32_t v = kCVPixelFormatType_420YpCbCr8Planar;
        const void *values[] = { CFNumberCreate(NULL, kCFNumberSInt32Type, &v) };
        attrs = CFDictionaryCreate(NULL, keys, values, 1, NULL, NULL);
        
        VTDecompressionOutputCallbackRecord callBackRecord;
        callBackRecord.decompressionOutputCallback = didDecompress;
        callBackRecord.decompressionOutputRefCon = (__bridge void *)self;
        
        status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                              _decoderFormatDescription,
                                              NULL, (__bridge CFDictionaryRef)destinationPixelBufferAttributes,
                                              &callBackRecord,
                                              &_deocderSession);
        CFRelease(attrs);
    } else {
        NSLog(@"IOS8VT: reset decoder session failed status=%d", (int)status);
    }
    
    return YES;
}

static void didDecompress( void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef pixelBuffer, CMTime presentationTimeStamp, CMTime presentationDuration ){
    
    CVPixelBufferRef *outputPixelBuffer = (CVPixelBufferRef *)sourceFrameRefCon;
    *outputPixelBuffer = CVPixelBufferRetain(pixelBuffer);
    
    HardwareDecoder *decoder = (__bridge HardwareDecoder *)decompressionOutputRefCon;
    if (decoder.delegate && [decoder.delegate respondsToSelector:@selector(displayDecodedFrame:)]) {
        [decoder.delegate displayDecodedFrame:pixelBuffer];
    }
}

-(CVPixelBufferRef)decode:(uint8_t *)frame withSize:(uint32_t)frameSize
{
    CVPixelBufferRef outputPixelBuffer = NULL;
    
    CMBlockBufferRef blockBuffer = NULL;
    OSStatus status  = CMBlockBufferCreateWithMemoryBlock(NULL,
                                                          (void *)frame,
                                                          frameSize,
                                                          kCFAllocatorNull,
                                                          NULL,
                                                          0,
                                                          frameSize,
                                                          FALSE,
                                                          &blockBuffer);
    if(status == kCMBlockBufferNoErr) {
        CMSampleBufferRef sampleBuffer = NULL;
        const size_t sampleSizeArray[] = {frameSize};
        status = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                           blockBuffer,
                                           _decoderFormatDescription ,
                                           1, 0, NULL, 1, sampleSizeArray,
                                           &sampleBuffer);
        if (status == kCMBlockBufferNoErr && sampleBuffer) {
            VTDecodeFrameFlags flags = 0;
            VTDecodeInfoFlags flagOut = 0;
            OSStatus decodeStatus = VTDecompressionSessionDecodeFrame(_deocderSession,
                                                                      sampleBuffer,
                                                                      flags,
                                                                      &outputPixelBuffer,
                                                                      &flagOut);
            
            if(decodeStatus == kVTInvalidSessionErr) {
                NSLog(@"IOS8VT: Invalid session, reset decoder session");
            } else if(decodeStatus == kVTVideoDecoderBadDataErr) {
                NSLog(@"IOS8VT: decode failed status=%d(Bad data)", decodeStatus);
            } else if(decodeStatus != noErr) {
                NSLog(@"IOS8VT: decode failed status=%d", decodeStatus);
            }
            CFRelease(sampleBuffer);
        }
        CFRelease(blockBuffer);
    }
    
    return outputPixelBuffer;
}

- (BOOL)containIFrame:(uint8_t *)nalBuffer size:(int)size {
    
    NSString *string1 = @"";
    int dataLength = size > 500 ? 500 : size;
    for (int i = 0; i < dataLength; i ++) {
        NSString *temp = [NSString stringWithFormat:@"%x", nalBuffer[i]&0xff];
        if ([temp length] == 1) {
            temp = [NSString stringWithFormat:@"0%@", temp];
        }
        string1 = [string1 stringByAppendingString:temp];
    }
    NSLog(@"%@", string1);
    
    NSRange range = [string1 rangeOfString:@"00000000165"];

    return range.location != NSNotFound;
}

- (NSString *)startByteFrom:(uint8_t *)nalBuffer size:(int)size {
    
    NSString *string1 = @"";
    int dataLength = size > 100 ? 100 : size;   //I帧的位置通常在80
    for (int i = 0; i < dataLength; i ++) {
        NSString *temp = [NSString stringWithFormat:@"%x", nalBuffer[i]&0xff];
        if ([temp length] == 1) {
            temp = [NSString stringWithFormat:@"0%@", temp];
        }
        string1 = [string1 stringByAppendingString:temp];
    }
    
    return string1;
}

@end
