//
// VideoCheckDelegate.m
//
// Class that acts as a frame-processing delegate to an AVCaptureOutput
// instance, affecting the statistical analysis of the image stream.
//
// Copyright © 2016
// Dr. Jeffrey Frey, IT-NSS
// University of Delaware
//
// $Id$
//

#import "VideoCheckDelegate.h"

//

double VideoCheckDefaultMotionThreshold = 5.0;
double VideoCheckDefaultColorThreshold = 15.0;
double VideoCheckDefaultSaturationThreshold = 0.075;
double VideoCheckDefaultBrightnessThreshold = 0.25;

//

typedef struct {
  UInt8     r, g, b;
} VideoCheckRGBPixel;

typedef struct {
  float     h, s, v;
} VideoCheckHSVPixel;

//

NS_INLINE VideoCheckHSVPixel
VideoCheckRGBPixelConvertToHSV(
  VideoCheckRGBPixel    rgb
)
{
  VideoCheckHSVPixel    outPixel;
  float                 r = (1.0/255.0) * rgb.r;
  float                 g = (1.0/255.0) * rgb.g;
  float                 b = (1.0/255.0) * rgb.b;
  float                 CMax = r, CMin = r, delta;
  float                 hPrime = 0;
  UInt8                 WMax = 1;
  
  if ( g > CMax ) { CMax = g; WMax = 2; }
  if ( b > CMax ) { CMax = b; WMax = 3; }
  if ( g < CMin ) CMin = g;
  if ( b < CMin ) CMin = b;
  delta = CMax - CMin;
  
  outPixel.v = CMax;
  outPixel.s = CMax ? (delta / CMax) : 0;
  if ( CMax == CMin ) {
    outPixel.h = 0;
  } else {
    switch ( WMax ) {
    
      case 1:
        hPrime = (g - b) / delta;
        break;
      
      case 2:
        hPrime = 2 + ((b - r) / delta);
        break;
      
      case 3:
        hPrime = 4 + ((r - g) / delta);
        break;
    
    }
    hPrime *= 60;
    if ( hPrime < 0.0 ) hPrime += 360;
    outPixel.h = hPrime;
  }
  return outPixel;
}

//

@interface VideoCheckDelegate_32ARGB : VideoCheckDelegate
{
  UInt8       *_row, *_rowBase;
  size_t      _bytesPerRow, _width, _horizIndex;
}

- (void) decodePixelAtCurrentPointer:(VideoCheckRGBPixel*)rgbPixel;

@end

//

@interface VideoCheckDelegate_32BGRA : VideoCheckDelegate_32ARGB

@end

//

@interface VideoCheckDelegate_422YpCbCr8 : VideoCheckDelegate
{
  UInt8       *_row, *_rowBase;
  size_t      _bytesPerRow, _width, _horizIndex;
  UInt8       _Cb, _Cr;
  BOOL        _tickTock;
}

@end

//
#if 0
#pragma mark -
#endif
//

@interface VideoCheckDelegate()
{
  double      _mean[6];
  double      _variance[6];
  double      _varianceMean[6];
  UInt32      _minVar, _maxVar;
  
  BOOL        _didLimitFrameRate;
  time_t      _firstFrameTime, _lastFrameTime;
  uint64_t    _frameCount, _totalFrameCount;
  
  size_t      _aggregateImageBufferSize;
  void        *_aggregateImageBufferPtr;
  void        *_aggregateImageVarianceBufferPtr;
}

+ (int) expectedBytesPerPixel;

- (void) analyzeFrame:(void*)baseAddress width:(size_t)width height:(size_t)height bytesPerRow:(size_t)bytesPerRow;

- (BOOL) saveAggregateImage;
- (BOOL) saveAggregateImageVariance;

//
// Analysis output "callbacks"
//
- (void) summarizeAnalysisHeader;
- (void) summarizeAnalysisBody;
- (void) summarizeAnalysisFooter;

//
// Subclass "callback" interface for pixel analysis:
//
- (BOOL) startFrameAnalysis:(void*)baseAddress width:(size_t)width height:(size_t)height bytesPerRow:(size_t)bytesPerRow;
- (BOOL) nextRGBPixel:(VideoCheckRGBPixel*)rgbPixel;
- (void) endFrameAnalysis;

@end

//

@implementation VideoCheckDelegate

  + (VideoCheckDelegate*) videoCheckDelegateForPixelFormat:(OSType)pixelFormat
  {
    switch ( pixelFormat ) {
    
      case kCVPixelFormatType_32ARGB:
        return [[VideoCheckDelegate_32ARGB alloc] init];
    
      case kCVPixelFormatType_32BGRA:
        return [[VideoCheckDelegate_32BGRA alloc] init];
        
      case kCVPixelFormatType_422YpCbCr8:
        return [[VideoCheckDelegate_422YpCbCr8 alloc] init];
        
    }
    return nil;
  }

//

  - (id) init
  {
    if ( (self = [super init]) ) {
      self.motionThreshold = VideoCheckDefaultMotionThreshold;
      self.singleColorThreshold = VideoCheckDefaultColorThreshold;
      self.saturationThreshold = VideoCheckDefaultSaturationThreshold;
      self.brightnessThreshold = VideoCheckDefaultBrightnessThreshold;
    }
    return self;
  }

//

  - (OSType) pixelFormat { return 0; }
  - (const char*) pixelFormatDescription
  {
    return nil;
  }

//

  - (void) summarizeAnalysis
  {
    if ( _frameCount ) {
      [self summarizeAnalysisHeader];
      if ( _frameCount ) {
        [self summarizeAnalysisBody];
      }
      [self summarizeAnalysisFooter];
    }
  }

//

  + (int) expectedBytesPerPixel { return 0; }
  
//

  - (void) analyzeFrame:(void *)baseAddress
    width:(size_t)width
    height:(size_t)height
    bytesPerRow:(size_t)bytesPerRow
  {
    if ( ! _aggregateImageBufferPtr ) {
      //
      // We'll compile a 32-bit RGBA image from the frames:
      //
      _aggregateImageBufferSize = width * height * 4;
      
      _aggregateImageWidth = width;
      _aggregateImageHeight = height;
      _aggregateImageBufferPtr = malloc(_aggregateImageBufferSize);
      if ( ! _aggregateImageBufferPtr ) {
        fprintf(stderr, "FATAL ERROR:  Unable to allocate aggregate image buffer.\n");
        exit(ENOMEM);
      }
      
      _aggregateImageVarianceBufferPtr = malloc(4 * _aggregateImageBufferSize);
      if ( ! _aggregateImageVarianceBufferPtr ) {
        fprintf(stderr, "FATAL ERROR:  Unable to allocate aggregate image buffer.\n");
        exit(ENOMEM);
      }
      
      _minVar = 0xFFFFFFFF; _maxVar = 0x00000000;
    }
    if ( (width == _aggregateImageWidth) && (height == _aggregateImageHeight) && [self startFrameAnalysis:baseAddress width:width height:height bytesPerRow:bytesPerRow] ) {
      double                h_m = 0.0, s_m = 0.0, v_m = 0.0;
      double                h_s = 0.0, s_s = 0.0, v_s = 0.0;
      double                r_m = 0.0, g_m = 0.0, b_m = 0.0;
      double                r_s = 0.0, g_s = 0.0, b_s = 0.0;
      
      VideoCheckRGBPixel    rgbPixel;
      BOOL                  firstPixel = YES;
      size_t                j = _aggregateImageHeight;
      double                k = 1;
      UInt8                 *aggImgPtr = _aggregateImageBufferPtr;
      UInt32                *aggImgVarPtr = _aggregateImageVarianceBufferPtr;
      BOOL                  success = YES;
      
      while ( j-- ) {
        VideoCheckHSVPixel    hsvPixel;
        size_t                i = _aggregateImageWidth;
        
        if ( firstPixel ) {
          if ( (success = [self nextRGBPixel:&rgbPixel]) ) {
            hsvPixel = VideoCheckRGBPixelConvertToHSV(rgbPixel);
            h_m = hsvPixel.h;
            s_m = hsvPixel.s;
            v_m = hsvPixel.v;
            r_m = rgbPixel.r;
            g_m = rgbPixel.g;
            b_m = rgbPixel.b;
            if ( _frameCount ) {
              double      divisor = 1.0 / (_frameCount + 1);
              
              UInt8       r_m_prime = aggImgPtr[0] + (rgbPixel.r - aggImgPtr[0]) * divisor;
              UInt8       g_m_prime = aggImgPtr[1] + (rgbPixel.g - aggImgPtr[1]) * divisor;
              UInt8       b_m_prime = aggImgPtr[2] + (rgbPixel.b - aggImgPtr[2]) * divisor;
              
              aggImgVarPtr[0] += (rgbPixel.r - aggImgPtr[0]) * (rgbPixel.r - r_m_prime); if ( aggImgVarPtr[0] > _maxVar ) _maxVar = aggImgVarPtr[0];  if ( aggImgVarPtr[0] < _minVar ) _minVar = aggImgVarPtr[0];
              aggImgVarPtr[1] += (rgbPixel.g - aggImgPtr[1]) * (rgbPixel.g - g_m_prime); if ( aggImgVarPtr[1] > _maxVar ) _maxVar = aggImgVarPtr[1];  if ( aggImgVarPtr[1] < _minVar ) _minVar = aggImgVarPtr[1];
              aggImgVarPtr[2] += (rgbPixel.b - aggImgPtr[2]) * (rgbPixel.b - b_m_prime); if ( aggImgVarPtr[2] > _maxVar ) _maxVar = aggImgVarPtr[2];  if ( aggImgVarPtr[2] < _minVar ) _minVar = aggImgVarPtr[2];
              aggImgPtr[0] = r_m_prime;
              aggImgPtr[1] = g_m_prime;
              aggImgPtr[2] = b_m_prime;
            } else {
              aggImgPtr[0] = rgbPixel.r;
              aggImgPtr[1] = rgbPixel.g;
              aggImgPtr[2] = rgbPixel.b;
              aggImgVarPtr[0] = aggImgVarPtr[1] = aggImgVarPtr[2] = 0;
            }
            aggImgPtr[3] = 255;
            aggImgVarPtr[3] = 0xFFFFFFFF;
            aggImgPtr += 4; aggImgVarPtr += 4;
            firstPixel = NO;
            i--;
          } else {
            break;
          }
        }
        while ( i-- && (success = [self nextRGBPixel:&rgbPixel]) ) {
          hsvPixel = VideoCheckRGBPixelConvertToHSV(rgbPixel);
          
          double h_m_prime = h_m + (hsvPixel.h - h_m) / k; h_s += (hsvPixel.h - h_m) * (hsvPixel.h - h_m_prime); h_m = h_m_prime;
          double s_m_prime = s_m + (hsvPixel.s - s_m) / k; s_s += (hsvPixel.s - s_m) * (hsvPixel.s - s_m_prime); s_m = s_m_prime;
          double v_m_prime = v_m + (hsvPixel.v - v_m) / k; v_s += (hsvPixel.v - v_m) * (hsvPixel.v - v_m_prime); v_m = v_m_prime;
          double r_m_prime = r_m + (rgbPixel.r - r_m) / k; r_s += (rgbPixel.r - r_m) * (rgbPixel.r - r_m_prime); r_m = r_m_prime;
          double g_m_prime = g_m + (rgbPixel.g - g_m) / k; g_s += (rgbPixel.g - g_m) * (rgbPixel.g - g_m_prime); g_m = g_m_prime;
          double b_m_prime = b_m + (rgbPixel.b - b_m) / k; b_s += (rgbPixel.b - b_m) * (rgbPixel.b - b_m_prime); b_m = b_m_prime;
          
          if ( _frameCount ) {
            double      divisor = 1.0 / (_frameCount + 1);
              
            UInt8       r_m_prime = aggImgPtr[0] + (rgbPixel.r - aggImgPtr[0]) * divisor;
            UInt8       g_m_prime = aggImgPtr[1] + (rgbPixel.g - aggImgPtr[1]) * divisor;
            UInt8       b_m_prime = aggImgPtr[2] + (rgbPixel.b - aggImgPtr[2]) * divisor;
              
            aggImgVarPtr[0] += (rgbPixel.r - aggImgPtr[0]) * (rgbPixel.r - r_m_prime);  if ( aggImgVarPtr[0] > _maxVar ) _maxVar = aggImgVarPtr[0];  if ( aggImgVarPtr[0] < _minVar ) _minVar = aggImgVarPtr[0];
            aggImgVarPtr[1] += (rgbPixel.g - aggImgPtr[1]) * (rgbPixel.g - g_m_prime); if ( aggImgVarPtr[1] > _maxVar ) _maxVar = aggImgVarPtr[1];  if ( aggImgVarPtr[1] < _minVar ) _minVar = aggImgVarPtr[1];
            aggImgVarPtr[2] += (rgbPixel.b - aggImgPtr[2]) * (rgbPixel.b - b_m_prime);if ( aggImgVarPtr[2] > _maxVar ) _maxVar = aggImgVarPtr[2];  if ( aggImgVarPtr[2] < _minVar ) _minVar = aggImgVarPtr[2];
            aggImgPtr[0] = r_m_prime;
            aggImgPtr[1] = g_m_prime;
            aggImgPtr[2] = b_m_prime;
          } else {
            aggImgPtr[0] = rgbPixel.r;
            aggImgPtr[1] = rgbPixel.g;
            aggImgPtr[2] = rgbPixel.b;
            aggImgVarPtr[0] = aggImgVarPtr[1] = aggImgVarPtr[2] = 0;
          }
          aggImgPtr[3] = 255;
          aggImgVarPtr[3] = 0xFFFFFFFF;
          aggImgPtr += 4; aggImgVarPtr += 4;
          k++;
        }
      }
      
      k = 1 / (k - 1);
      if ( _frameCount ) {
        double    h_m_prime = _mean[0] + (h_m - _mean[0]) / (_frameCount + 1);
        double    s_m_prime = _mean[1] + (s_m - _mean[1]) / (_frameCount + 1);
        double    v_m_prime = _mean[2] + (v_m - _mean[2]) / (_frameCount + 1);
        double    r_m_prime = _mean[3] + (r_m - _mean[3]) / (_frameCount + 1);
        double    g_m_prime = _mean[4] + (g_m - _mean[4]) / (_frameCount + 1);
        double    b_m_prime = _mean[5] + (b_m - _mean[5]) / (_frameCount + 1);
        
        _variance[0] += (h_m - _mean[0]) * (h_m - h_m_prime); _mean[0] = h_m_prime;
        _variance[1] += (s_m - _mean[1]) * (s_m - s_m_prime); _mean[1] = s_m_prime;
        _variance[2] += (v_m - _mean[2]) * (v_m - v_m_prime); _mean[2] = v_m_prime;
        _variance[3] += (r_m - _mean[3]) * (r_m - r_m_prime); _mean[3] = r_m_prime;
        _variance[4] += (g_m - _mean[4]) * (g_m - g_m_prime); _mean[4] = g_m_prime;
        _variance[5] += (b_m - _mean[5]) * (b_m - b_m_prime); _mean[5] = b_m_prime;
        
        _varianceMean[0] += ((h_s * k) - _varianceMean[0]) / (_frameCount + 1);
        _varianceMean[1] += ((s_s * k) - _varianceMean[1]) / (_frameCount + 1);
        _varianceMean[2] += ((v_s * k) - _varianceMean[2]) / (_frameCount + 1);
        _varianceMean[3] += ((r_s * k) - _varianceMean[3]) / (_frameCount + 1);
        _varianceMean[4] += ((g_s * k) - _varianceMean[4]) / (_frameCount + 1);
        _varianceMean[5] += ((b_s * k) - _varianceMean[5]) / (_frameCount + 1);
      } else {
        _mean[0] = h_m;
        _mean[1] = s_m;
        _mean[2] = v_m;
        _mean[3] = r_m;
        _mean[4] = g_m;
        _mean[5] = b_m;
        _varianceMean[0] = h_s * k;
        _varianceMean[1] = s_s * k;
        _varianceMean[2] = v_s * k;
        _varianceMean[3] = r_s * k;
        _varianceMean[4] = g_s * k;
        _varianceMean[5] = b_s * k;
      }
    
      [self endFrameAnalysis];
    }
  }

//

  - (BOOL) saveAggregateImage
  {
    BOOL                success = NO;
    CGColorSpaceRef     aggrImgColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGDataProviderRef   aggrImgDataProv = CGDataProviderCreateWithData(
                                        NULL,
                                        _aggregateImageBufferPtr,
                                        _aggregateImageBufferSize,
                                        NULL
                                      );
    CGImageRef          aggrCGImg = CGImageCreate(
                                        _aggregateImageWidth,
                                        _aggregateImageHeight,
                                        8,
                                        32,
                                        4 * _aggregateImageWidth,
                                        aggrImgColorSpace,
                                        (kCGImageAlphaLast) & kCGBitmapAlphaInfoMask,
                                        aggrImgDataProv,
                                        NULL,
                                        NO,
                                        kCGRenderingIntentDefault
                                      );
    CGColorSpaceRelease(aggrImgColorSpace);
    CGDataProviderRelease(aggrImgDataProv);
    
    if ( aggrCGImg ) {
      CFURLRef                  aggrImgPath = CFURLCreateWithFileSystemPath(
                                                  kCFAllocatorDefault,
                                                  (__bridge CFStringRef)self.aggregateImagePath,
                                                  kCFURLPOSIXPathStyle,
                                                  false
                                                );
      if ( aggrImgPath ) {
        CGImageDestinationRef     aggrImgFile = CGImageDestinationCreateWithURL(
                                                    aggrImgPath,
                                                    kUTTypePNG,
                                                    1,
                                                    NULL
                                                  );
        CFRelease(aggrImgPath);
        if ( aggrImgFile ) {
          CGImageDestinationAddImage(aggrImgFile, aggrCGImg, NULL);
          if ( ! (success = CGImageDestinationFinalize(aggrImgFile)) ) {
            fprintf(stderr, "ERROR:  Unable to serialize image data to destination file.\n");
          }
          CFRelease(aggrImgFile);
        } else {
          fprintf(stderr, "ERROR:  Unable to create destination image file wrapper.\n");
        }
      } else {
        fprintf(stderr, "ERROR:  Unable to create URL for destination image file.\n");
      }
      CGImageRelease(aggrCGImg);
    } else {
      fprintf(stderr, "ERROR:  Unable to create image wrapper from aggregate data.\n");
    }
    return success;
  }

//

  - (BOOL) saveAggregateImageVariance
  {
    BOOL                  success = NO;
    
    if ( _minVar <= _maxVar ) {
      size_t              j = _aggregateImageHeight;
      UInt32              *aggImgVarSrcPtr = _aggregateImageVarianceBufferPtr;
      UInt8               *aggImgVarDstPtr = _aggregateImageVarianceBufferPtr;
      double              multiplier = 255.0 / (_maxVar - _minVar);
      
      //
      // Loop over rows...
      ///
      while ( j-- ) {
        size_t            i = _aggregateImageWidth;
        
        //
        // Loop over columns...
        ///
        while ( i-- ) {
          double          value = floor(multiplier * (*aggImgVarSrcPtr++ - _minVar));
          
          value += floor(multiplier * (*aggImgVarSrcPtr++ - _minVar));
          value += floor(multiplier * (*aggImgVarSrcPtr++ - _minVar));
          //
          // Gray level = the average of the three normalized per-pixel component intensities:
          //
          *aggImgVarDstPtr++ = value / 3.0;
          *aggImgVarDstPtr++ = 255; aggImgVarSrcPtr++;
        }
      }

      CGColorSpaceRef     aggrImgColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericGrayGamma2_2); //kCGColorSpaceSRGB);
      CGDataProviderRef   aggrImgDataProv = CGDataProviderCreateWithData(
                                          NULL,
                                          _aggregateImageVarianceBufferPtr,
                                          _aggregateImageBufferSize,
                                          NULL
                                        );
      CGImageRef          aggrCGImg = CGImageCreate(
                                          _aggregateImageWidth,
                                          _aggregateImageHeight,
                                          8,
                                          16,
                                          2 * _aggregateImageWidth,
                                          aggrImgColorSpace,
                                          (kCGImageAlphaLast) & kCGBitmapAlphaInfoMask,
                                          aggrImgDataProv,
                                          NULL,
                                          NO,
                                          kCGRenderingIntentDefault
                                        );
      CGColorSpaceRelease(aggrImgColorSpace);
      CGDataProviderRelease(aggrImgDataProv);
      
      if ( aggrCGImg ) {
        CFURLRef                  aggrImgPath = CFURLCreateWithFileSystemPath(
                                                    kCFAllocatorDefault,
                                                    (__bridge CFStringRef)self.aggregateImageVariancePath,
                                                    kCFURLPOSIXPathStyle,
                                                    false
                                                  );
        if ( aggrImgPath ) {
          CGImageDestinationRef     aggrImgFile = CGImageDestinationCreateWithURL(
                                                      aggrImgPath,
                                                      kUTTypePNG,
                                                      1,
                                                      NULL
                                                    );
          CFRelease(aggrImgPath);
          if ( aggrImgFile ) {
            CGImageDestinationAddImage(aggrImgFile, aggrCGImg, NULL);
            if ( ! (success = CGImageDestinationFinalize(aggrImgFile)) ) {
              fprintf(stderr, "ERROR:  Unable to serialize image data to destination file.\n");
            }
            CFRelease(aggrImgFile);
          } else {
            fprintf(stderr, "ERROR:  Unable to create destination image file wrapper.\n");
          }
        } else {
          fprintf(stderr, "ERROR:  Unable to create URL for destination image file.\n");
        }
        CGImageRelease(aggrCGImg);
      } else {
        fprintf(stderr, "ERROR:  Unable to create image wrapper from aggregate data.\n");
      }
    }
    return success;
  }

//

  - (void) summarizeAnalysisHeader
  {
    double      frameRate = _lastFrameTime - _firstFrameTime;
    
    if ( frameRate > DBL_EPSILON ) frameRate = (1.0 / frameRate) * _totalFrameCount;
    
    switch ( self.analysisFormat ) {
      default:
      case kVideoCheckAnalysisFormatNone:
        break;
      
      case kVideoCheckAnalysisFormatJSON: {
        printf(
            "{\"frame-count\":%llu,\"frames-per-sec\":%.1lf,\"frame-width\":%lu,\"frame-height\":%lu,\"native-pixel-format\":\"%s\"",
            _frameCount,
            frameRate,
            self.aggregateImageWidth, self.aggregateImageHeight,
            [self pixelFormatDescription]
          );
        break;
      }
      
      case kVideoCheckAnalysisFormatXML: {
        printf(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            "<video-check frame-count=\"%llu\" frames-per-sec=\"%.1lf\" frame-width=\"%lu\" frame-height=\"%lu\">\n"
            "  <native-pixel-format>%s</native-pixel-format>\n",
            _frameCount,
            frameRate,
            self.aggregateImageWidth, self.aggregateImageHeight,
            [self pixelFormatDescription]
          );
        break;
      }
      
      case kVideoCheckAnalysisFormatDefault: {
        printf(
            "\n"
            "~~~~~~~~~~~~~~~\n"
            "A N A L Y S I S\n"
            "~~~~~~~~~~~~~~~\n"
            "\n"
            "           Frame count: %llu\n"
            "                  rate: %.1lf frame / s\n"
            "            dimensions: %lu x %lu\n"
            "   Native pixel format: %s\n",
            _frameCount,
            frameRate,
            self.aggregateImageWidth, self.aggregateImageHeight,
            [self pixelFormatDescription]
          );
        break;
      }
      
    }
  }
  - (void) summarizeAnalysisBody
  {
    double    totalRGBVariance = sqrt((_variance[3] + _variance[4] + _variance[5]) / 3);
    double    meanPixelVariance[6] = { sqrt(_varianceMean[0]), sqrt(_varianceMean[1]), sqrt(_varianceMean[2]), 
                                       sqrt(_varianceMean[3]), sqrt(_varianceMean[4]), sqrt(_varianceMean[5])
                                     };
    BOOL      isSingleColor = (meanPixelVariance[0] <= self.singleColorThreshold) &&
                              (meanPixelVariance[1] <= self.saturationThreshold) &&
                              (meanPixelVariance[2] <= self.brightnessThreshold);
    
    switch ( self.analysisFormat ) {
      default:
      case kVideoCheckAnalysisFormatNone:
        break;
      
      case kVideoCheckAnalysisFormatQuick:
        if ( totalRGBVariance > self.motionThreshold ) {
          if ( isSingleColor ) {
            printf("motion, single color\n");
          } else {
            printf("motion\n");
          }
        } else if ( isSingleColor ) {
          printf("single color\n");
        }
        break;
      
      case kVideoCheckAnalysisFormatJSON: {
        printf(
            ",\"pixel-mean\":{"
              "\"h\":%1$lf,\"s\":%2$lf,\"v\":%3$lf,"
              "\"r\":%4$lf,\"g\":%5$lf,\"b\":%6$lf"
            "},\"pixel-mean-hsv\":[%1$lf,%2$lf,%3$lf],"
            "\"pixel-mean-rgb\":[%4$lf,%5$lf,%6$lf],"
            
            "\"pixel-variance\":{"
              "\"h\":%7$lf,\"s\":%8$lf,\"v\":%9$lf,"
              "\"r\":%10$lf,\"g\":%11$lf,\"b\":%12$lf"
            "},\"pixel-variance-hsv\":[%7$lf,%8$lf,%9$lf],"
            "\"pixel-variance-rgb\":[%10$lf,%11$lf,%12$lf],"
            
            "\"mean-pixel-variance\":{"
              "\"h\":%13$lf,\"s\":%14$lf,\"v\":%15$lf,"
              "\"r\":%16$lf,\"g\":%17$lf,\"b\":%18$lf"
            "},\"mean-pixel-variance-hsv\":[%13$lf,%14$lf,%15$lf],"
            "\"mean-pixel-variance-rgb\":[%16$lf,%17$lf,%18$lf],"
            
            "\"motion-detected\":%19$s,"
            "\"single-color\":%20$s",
            _mean[0], _mean[1], _mean[2], _mean[3], _mean[4], _mean[5],
            _variance[0], _variance[1], _variance[2], _variance[3], _variance[4], _variance[5],
            meanPixelVariance[0], meanPixelVariance[1], meanPixelVariance[2], meanPixelVariance[3], meanPixelVariance[4], meanPixelVariance[5],
            (totalRGBVariance > self.motionThreshold) ? "true" : "false",
            isSingleColor ? "true" : "false"
          );
        break;
      }
      
      case kVideoCheckAnalysisFormatDefault: {
        printf(
            "            Pixel mean: HSV(%5.1lf, %5.3lf, %5.3lf) RGB(%.0lf, %.0lf, %.0lf)\n"
            "        Pixel variance: HSV(%5.1lf, %5.3lf, %5.3lf) RGB(%.0lf, %.0lf, %.0lf)\n"
            "   Mean pixel variance: HSV(%5.1lf, %5.3lf, %5.3lf) RGB(%.0lf, %.0lf, %.0lf)\n"
            "\n"
            "%s"
            "%s",
            _mean[0], _mean[1], _mean[2], _mean[3], _mean[4], _mean[5],
            _variance[0], _variance[1], _variance[2], _variance[3], _variance[4], _variance[5],
            meanPixelVariance[0], meanPixelVariance[1], meanPixelVariance[2], meanPixelVariance[3], meanPixelVariance[4], meanPixelVariance[5],
            (totalRGBVariance > self.motionThreshold) ? "  - Motion was detected\n" : "",
            isSingleColor ? "  - Single color was detected\n" : ""
          );
        break;
      }
      
      case kVideoCheckAnalysisFormatXML: {
        printf(
            "  <pixel-mean><h>%.1lf</h><s>%.3lf</s><v>%.3lf</v><r>%.0lf</r><g>%.0lf</g><b>%.0lf</b></pixel-mean>\n"
            "  <pixel-variance><h>%.1lf</h><s>%.3lf</s><v>%.3lf</v><r>%.0lf</r><g>%.0lf</g><b>%.0lf</b></pixel-variance>\n"
            "  <mean-pixel-variance><h>%.1lf</h><s>%.3lf</s><v>%.3lf</v><r>%.0lf</r><g>%.0lf</g><b>%.0lf</b></mean-pixel-variance>\n"
            "%s"
            "%s",
            _mean[0], _mean[1], _mean[2], _mean[3], _mean[4], _mean[5],
            _variance[0], _variance[1], _variance[2], _variance[3], _variance[4], _variance[5],
            meanPixelVariance[0], meanPixelVariance[1], meanPixelVariance[2], meanPixelVariance[3], meanPixelVariance[4], meanPixelVariance[5],
            (totalRGBVariance > self.motionThreshold) ? "  <motion-detected/>\n" : "",
            isSingleColor ? "  <single-color/>\n" : ""
          );
        break;
      }
      
    }
  }
  - (void) summarizeAnalysisFooter
  {
    BOOL      didWriteAggrImage = (self.aggregateImagePath != nil) && [self saveAggregateImage];
    
    switch ( self.analysisFormat ) {
      default:
        break;
      
      case kVideoCheckAnalysisFormatJSON: {
        if ( didWriteAggrImage ) {
          printf(
              ",\"aggregate-image-path\":\"%s\"",
              [self.aggregateImagePath cStringUsingEncoding:NSASCIIStringEncoding]
            );
        }
        printf("}\n");
        break;
      }
      
      case kVideoCheckAnalysisFormatXML: {
        if ( didWriteAggrImage ) {
          printf(
              "  <aggregate-image-path>%s</aggregate-image-path>\n",
              [self.aggregateImagePath cStringUsingEncoding:NSASCIIStringEncoding]
            );
        }
        break;
      }
      
      case kVideoCheckAnalysisFormatDefault: {
        if ( didWriteAggrImage ) {
          printf(
              "  - Aggregate image saved to '%s'\n\n",
              [self.aggregateImagePath cStringUsingEncoding:NSASCIIStringEncoding]
            );
        }
        printf(
            "\n"
          );
        break;
      }
      
    }
    
    didWriteAggrImage = (self.aggregateImageVariancePath != nil) && [self saveAggregateImageVariance];
    
    switch ( self.analysisFormat ) {
      default:
        break;
      
      case kVideoCheckAnalysisFormatJSON: {
        if ( didWriteAggrImage ) {
          printf(
              ",\"aggregate-image-variance-path\":\"%s\"",
              [self.aggregateImageVariancePath cStringUsingEncoding:NSASCIIStringEncoding]
            );
        }
        printf("}\n");
        break;
      }
      
      case kVideoCheckAnalysisFormatXML: {
        if ( didWriteAggrImage ) {
          printf(
              "  <aggregate-image-variance-path>%s</aggregate-image-variance-path>\n",
              [self.aggregateImageVariancePath cStringUsingEncoding:NSASCIIStringEncoding]
            );
        }
        printf(
            "</video-check>\n"
          );
        break;
      }
      
      case kVideoCheckAnalysisFormatDefault: {
        if ( didWriteAggrImage ) {
          printf(
              "  - Aggregate image variance saved to '%s'\n\n",
              [self.aggregateImageVariancePath cStringUsingEncoding:NSASCIIStringEncoding]
            );
        }
        printf(
            "\n"
          );
        break;
      }
      
    }
  }

//

  - (BOOL) startFrameAnalysis:(void*)baseAddress
    width:(size_t)width
    height:(size_t)height
    bytesPerRow:(size_t)bytesPerRow
  {
    return NO;
  }
  - (BOOL) nextRGBPixel:(VideoCheckRGBPixel*)rgbPixel
  {
    return NO;
  }
  - (void) endFrameAnalysis
  {
  }

//

  - (void)captureOutput:(AVCaptureOutput *)captureOutput
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
    fromConnection:(AVCaptureConnection *)connection
  {
    CMItemCount           numSamples = CMSampleBufferGetNumSamples(sampleBuffer);
    
    if ( self.singleFrameOnly && _frameCount ) return;
    
    if ( numSamples > 0 ) {
      // Get a CMSampleBuffer's Core Video image buffer for the media data
      CVImageBufferRef        imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
      
      if ( imageBuffer ) {
        // Lock the base address of the pixel buffer
        CVPixelBufferLockBaseAddress(imageBuffer, 0);
     
        // Get the number of bytes per row for the pixel buffer
        void                    *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
     
        // Get the number of bytes per row for the pixel buffer
        size_t                  bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
        
        // Get the pixel buffer width and height
        size_t                  width = CVPixelBufferGetWidth(imageBuffer);
        size_t                  height = CVPixelBufferGetHeight(imageBuffer);
        
        // As long as the rows are at least as long as we expect, let's process them:
        if ( (bytesPerRow / width) >= [[self class] expectedBytesPerPixel] ) {
          BOOL                  shouldProcess = NO;
          
          if ( _firstFrameTime == 0 ) {
            _firstFrameTime = time(NULL);
          } else {
            _lastFrameTime = time(NULL);
            if ( _lastFrameTime - _firstFrameTime >= self.leadInTime ) shouldProcess = YES;
          }
          if ( ! (self.singleFrameOnly && _frameCount) && shouldProcess ) {
            [self analyzeFrame:baseAddress width:width height:height bytesPerRow:bytesPerRow];
            _frameCount++;
            if ( self.singleFrameOnly ) CFRunLoopStop(CFRunLoopGetMain());
          }
          _totalFrameCount++;
        }
        
        // Unlock the pixel buffer
        CVPixelBufferUnlockBaseAddress(imageBuffer,0);
      }
    }
  }
  
//

  - (void)captureOutput:(AVCaptureOutput *)captureOutput
    didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer
    fromConnection:(AVCaptureConnection *)connection
  {
    if ( ! _didLimitFrameRate ) {
      // If we haven't yet, limit the rate:
      [connection setVideoMinFrameDuration:CMTimeMake(1, 15)];
      _didLimitFrameRate = YES;
    }
  }

@end

//
#if 0
#pragma mark -
#endif
//

@implementation VideoCheckDelegate_32ARGB

  + (int) expectedBytesPerPixel { return 4; }
  - (OSType) pixelFormat { return kCVPixelFormatType_32ARGB; }
  - (const char*) pixelFormatDescription
  {
    return "32ARGB";
  }

//

  - (BOOL) startFrameAnalysis:(void*)baseAddress
    width:(size_t)width
    height:(size_t)height
    bytesPerRow:(size_t)bytesPerRow
  {
    _row = _rowBase = baseAddress;
    _bytesPerRow = bytesPerRow;
    _width = width;
    _horizIndex = 0;
    
    return YES;
  }
  - (BOOL) nextRGBPixel:(VideoCheckRGBPixel*)rgbPixel
  {
    [self decodePixelAtCurrentPointer:rgbPixel];
    if ( ++_horizIndex == _width ) {
      _rowBase = _row = (_rowBase + _bytesPerRow);
      _horizIndex = 0;
    } else {
      _row += 4;
    }
    return YES;
  }
  
//

  - (void) decodePixelAtCurrentPointer:(VideoCheckRGBPixel *)rgbPixel
  {
    rgbPixel->r = _row[1];
    rgbPixel->g = _row[2];
    rgbPixel->b = _row[3];
  }

@end

//
#if 0
#pragma mark -
#endif
//

@implementation VideoCheckDelegate_32BGRA

  - (OSType) pixelFormat { return kCVPixelFormatType_32BGRA; }
  - (const char*) pixelFormatDescription
  {
    return "32BGRA";
  }

//

  - (void) decodePixelAtCurrentPointer:(VideoCheckRGBPixel *)rgbPixel
  {
    rgbPixel->r = _row[2];
    rgbPixel->g = _row[1];
    rgbPixel->b = _row[0];
  }
  
@end

//
#if 0
#pragma mark -
#endif
//

@implementation VideoCheckDelegate_422YpCbCr8

  + (int) expectedBytesPerPixel
  {
    return 2;
  }
  - (OSType) pixelFormat { return kCVPixelFormatType_422YpCbCr8; }
  - (const char*) pixelFormatDescription
  {
    return "422YpCbCr8";
  }

//
  
//

  - (BOOL) startFrameAnalysis:(void*)baseAddress
    width:(size_t)width
    height:(size_t)height
    bytesPerRow:(size_t)bytesPerRow
  {
    _row = _rowBase = baseAddress;
    _bytesPerRow = bytesPerRow;
    _width = width;
    _horizIndex = 0;
    _tickTock = NO;
    
    return YES;
  }
  - (BOOL) nextRGBPixel:(VideoCheckRGBPixel*)rgbPixel
  {
    UInt8     Y;
    
    if ( _tickTock ) {
      Y = *_row++;
    } else {
      _Cb = *_row++;
      Y = *_row++;
      _Cr = *_row++;
    }
    
    rgbPixel->r = Y + 1.402 * (_Cr - 128);
    rgbPixel->g = Y - 0.3444136 * (_Cb - 128) - 0.714136 * (_Cr - 128);
    rgbPixel->b = Y + 1.772 * (_Cb - 128);
    
    _tickTock = !_tickTock;
    if ( ++_horizIndex == _width ) {
      _rowBase = _row = (_rowBase + _bytesPerRow);
      _horizIndex = 0;
    }
    return YES;
  }

@end
