//
//  ViewController.m
//  RTSPClient
//
//  Created by bingcai on 16/7/15.
//  Copyright © 2016年 sharetronic. All rights reserved.
//

#import "ViewController.h"
#import "RTSPConnection.h"

#import "HardwareDecoder.h"
#import "AAPLEAGLLayer.h"

#import "H264Decoder.h"

@interface ViewController () <HardwareDecoderDelegate> {

    RTSPConnection *_connection;
//    解码显示
    HardwareDecoder     *_hardwareDecoder;
    AAPLEAGLLayer *_glLayer;
    
//    ffmped解码
    H264Decoder         *_decoder;
}

@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIActivityIndicatorView *indicatorView;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
#pragma mark 硬解码
    _glLayer = [[AAPLEAGLLayer alloc] initWithFrame:CGRectMake(0, 20, self.view.frame.size.width, (self.view.frame.size.width * 9)/16 )] ;
    [self.view.layer addSublayer:_glLayer];
    _hardwareDecoder = [[HardwareDecoder alloc] init];
    _hardwareDecoder.delegate = self;
    
#pragma mark ffmpeg解码
    [self initImageView];
    _decoder = [[H264Decoder alloc] init];
    [_decoder videoDecoder_init];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveBuffer:) name:@"client" object:nil];
    
    _connection = [[RTSPConnection alloc]init];
}

- (void)initImageView {

    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGRect rect = CGRectMake(0, 20, screenWidth, screenWidth * 3 / 4);
    UIView *containerView = [[UIView alloc] initWithFrame:rect];
    
    self.imageView = [[UIImageView alloc] initWithFrame:rect];
    self.imageView.image = [self getBlackImage];
    
    self.indicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.indicatorView.frame = CGRectMake(rect.size.width / 2, rect.size.height / 2, self.indicatorView.frame.size.width, self.indicatorView.frame.size.height);
    
    [containerView addSubview:self.imageView];
    [containerView addSubview:self.indicatorView];
    [self.view addSubview:containerView];
    [self.indicatorView startAnimating];
}

#pragma mark Button Action
- (IBAction)sendAction:(id)sender {
    [_connection doOption];
}


#pragma mark 解码
- (void)receiveBuffer:(NSNotification *)notification{
    
    if (self.indicatorView.isAnimating) {
        [self.indicatorView stopAnimating];
    }
    
    NSDictionary *dict = (NSDictionary *)notification.object;
    NSData *dataBuffer = [dict objectForKey:@"data"];
    NSNumber *number = [dict objectForKey:@"size"];
    uint8_t *buf = (uint8_t *)[dataBuffer bytes];
    
//    [_hardwareDecoder hardwareDecode:buf size:[number intValue]];
    
    [self decodeFramesToImage:buf size:[number intValue]];
}

//ffmpeg解码
- (void)decodeFramesToImage:(uint8_t *)nalBuffer size:(int)inSize {
    
    //    调节分辨率后，能自适应，但清晰度有问题
    //    经过确认，是output值设置的问题。outputWidth、outputHeight代表输出图像的宽高，设置的和分辨率一样，是最清晰的效果
    CGSize fSize = [_decoder videoDecoder_decodeToImage:nalBuffer size:inSize];
    if (fSize.width == 0) {
        return;
    };
    
    UIImage *image = [_decoder currentImage];
    
    if (image) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.imageView.image = image;
        });
    }
}

//硬解码回调
- (void)displayDecodedFrame:(CVImageBufferRef)imageBuffer {

    if (imageBuffer) {
        _glLayer.pixelBuffer = imageBuffer;
        CVPixelBufferRelease(imageBuffer);
    }
}

#pragma mark public method
- (UIImage *)getBlackImage {
    
    CGSize imageSize = CGSizeMake(50, 50);
    UIGraphicsBeginImageContextWithOptions(imageSize, 0, [UIScreen mainScreen].scale);
    [[UIColor colorWithRed:0 green:0 blue:0 alpha:1.0] set];
    UIRectFill(CGRectMake(0, 0, imageSize.width, imageSize.height));
    UIImage *pressedColorImg = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return pressedColorImg;
}

@end
