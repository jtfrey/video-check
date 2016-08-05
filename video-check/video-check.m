//
// video-check.m
//
// A utility to check a video capture source for a static, single-color
// image presence as an indication that no useful video is present on
// the device.
//
// Copyright © 2016
// Dr. Jeffrey Frey, IT-NSS
// University of Delaware
//
// $Id$
//

#import <Foundation/Foundation.h>
#include <getopt.h>

#import "VideoCheckDelegate.h"

//

static NumVersion       VideoCheckVersion = {
                            .majorRev       = 1,
                            .minorAndBugRev = 0x01,
                            .stage          = finalStage,
                            .nonRelRev      = 0
                          };

const char*
VideoCheckVersionString(void)
{
  static char       versionString[64];
  BOOL              ready = NO;
  
  if ( ! ready ) {
    const char      *format;
    
    switch ( VideoCheckVersion.stage ) {
      
      case developStage:
        format = "%1$hhd.%2$1hhx.%3$1hhxdev%4$hhd";
        break;
        
      case alphaStage:
        format = "%1$hhd.%2$1hhx.%3$1hhxa%4$hhd";
        break;
    
      case betaStage:
        format = "%1$hhd.%2$1hhx.%3$1hhxb%4$hhd";
        break;
    
      case finalStage:
        format = ( VideoCheckVersion.minorAndBugRev &0xF ) ? "%1$hhd.%2$1hhx.%3$1hhx" : "%1$hhd.%2$1hhx (for Mac OS X %5$s)";
        break;
    
    }
    snprintf(versionString, sizeof(versionString), format,
                VideoCheckVersion.majorRev,
                ((VideoCheckVersion.minorAndBugRev & 0xF0) >> 4),
                (VideoCheckVersion.minorAndBugRev & 0xF),
                VideoCheckVersion.nonRelRev
              );
  }
  
  return (const char*)versionString;
}

//

static struct option videoCheckOptions[] = {
                                         { "list-devices",                    no_argument,       NULL, 'd' },
                                         { "select-by-vendor-and-product-id", required_argument, NULL, 'V' },
                                         { "select-by-location-id",           required_argument, NULL, 'L' },
                                         { "select-by-name",                  required_argument, NULL, 'N' },
                                         { "select-by-index",                 required_argument, NULL, 'I' },
                                         //
                                         { "aggregate-image",                 required_argument, NULL, 'i' },
                                         { "aggregate-image-variance",        required_argument, NULL, 'e' },
                                         { "format",                          required_argument, NULL, 'f' },
                                         { "format-info",                     optional_argument, NULL,  1  },
                                         { "prefer-rgb",                      no_argument,       NULL, 'R' },
                                         { "prefer-component",                no_argument,       NULL, 'Y' },
                                         { "single-frame",                    no_argument,       NULL, '1' },
                                         { "motion-threshold",                required_argument, NULL, 'm' },
                                         { "color-threshold",                 required_argument, NULL, 'c' },
                                         { "saturation-threshold",            required_argument, NULL, 's' },
                                         { "brightness-threshold",            required_argument, NULL, 'b' },
                                         { "sampling-time",                   required_argument, NULL, 't' },
                                         { "lead-in-time",                    required_argument, NULL, 'l' },
                                         //
                                         { "help",                            no_argument,       NULL, 'h' },
                                         { "version",                         no_argument,       NULL, 'v' },
                                         { "debug",                           no_argument,       NULL, 'D' },
                                         { NULL,                              0,                 NULL,  0  }
                                       };

//

CFTimeInterval              samplingTime = 5.0;
double                      leadInTime = 1.0;
VideoCheckAnalysisFormat    analysisFormat = kVideoCheckAnalysisFormatXML;

//

const char*                 analysisFormatStrs[] = { "plain", "xml", "json", "quick", "none" };

//

void
usage(
  const char  *exe
)
{
  printf(
      "usage:\n"
      "\n"
      "    %s {options/target selection}\n"
      "\n"
      "  Options:\n"
      "\n"
      "    -h, --help\n"
      "          Display this information and exit.\n"
      "\n"
      "    -v, --version\n"
      "          Display the program version and exit.\n"
      "\n"
      "    -D, --debug\n"
      "          Display additional (verbose) information as the program executes.\n"
      "\n"
      "    -i <file-path>, --aggregate-image=<file-path>\n"
      "          Save the aggregate (average) image in the given file in PNG format.  If this\n"
      "          flag is not explicitly provided, then the aggregate image is not saved.\n"
      "\n"
      "    -e <file-path>, --aggregate-image-variance=<file-path>\n"
      "          The program accumluates an image whose pixels represent the per-pixel variance\n"
      "          of the aggregate (average) image.  Use this option to save that image to a PNG\n"
      "          file.  If this flag is not explicitly provided, then that image is not saved.\n"
      "\n"
      "          The image is grayscale rather than color, to provide a better visualization of\n"
      "          the magnitude of variance in each pixel.\n"
      "\n"
      "    -f <format>, --format=<format>\n"
      "          Output the analysis of the capture session in the given format, where\n"
      "          format is one of: xml, json, plain, quick, none.\n"
      "\n"
      "          default: %s\n"
      "\n"
      "    --format-info{=<format>}\n"
      "          Displays a summary of the given output format (or the chosen output format the\n"
      "          program would use if <format> is not provided to this flag) and exits.\n"
      "\n"
      "    -R, --prefer-rgb\n"
      "          Use a capture mode for the device that generates RGB pixels\n"
      "\n"
      "    -Y, --prefer-component\n"
      "          Use a capture mode for the device that generates component (Y'CbCr) pixels\n"
      "\n"
      "    -1, --single-frame\n"
      "          Capture just a single frame from the device.  Single-color analysis will still\n"
      "          work, but motion cannot (naturally!) be detected.\n"
      "\n"
      "    -m <number>, --motion-threshold=<number>\n"
      "          Use the given (positive) floating-point value as the threshold for determining\n"
      "          when the inter-frame variance indicates the image is changing (in motion).\n"
      "          Should be in the range (0.0, +INF); lower values = tighter criteria.\n"
      "\n"
      "          default: %lg\n"
      "\n"
      "    -c <number>, --color-threshold=<number>\n"
      "          Use the given (positive) floating-point value as the threshold for determining\n"
      "          when the inter-frame mean hue value did not vary significantly (single color).\n"
      "          Should be in the range (0.0, 360.0]; lower values = tighter criteria.\n"
      "\n"
      "          default: %lg\n"
      "\n"
      "          The value can also be expressed as \"<number>%%\", which is interpreted as a\n"
      "          percentage of the number 360.\n"
      "\n"
      "    -s <number>, --saturation-threshold=<number>\n"
      "          Use the given (positive) floating-point value as the threshold for determining\n"
      "          when the inter-frame mean saturation value did not vary significantly (single color).\n"
      "          Should be in the range (0.0, 1.0]; lower values = tighter criteria.\n"
      "\n"
      "          default: %lg\n"
      "\n"
      "    -b <number>, --brightness-threshold=<number>\n"
      "          Use the given (positive) floating-point value as the threshold for determining\n"
      "          when the inter-frame mean brightness value did not vary significantly (single color).\n"
      "          Should be in the range (0.0, 1.0]; lower values = tighter criteria.\n"
      "\n"
      "          default: %lg\n"
      "\n"
      "    -t <value>, --sampling-time=<value>\n"
      "          The program will analyze frames from the capture device for a finite period of\n"
      "          time.  The time must be at least 2.5 seconds.  Values can be expressed as a single\n"
      "          floating-point value (in seconds) or in the typical colon-delimited h:m:s time\n"
      "          format.\n"
      "\n"
      "          default: %lg\n"
      "\n"
      "    -l <value>, --lead-in-time=<value>\n"
      "          Devices with auto-focus or leveling can produce radical color-changes when the\n"
      "          capture session starts, which will indicate \"motion\" to the analysis algorithm.\n"
      "          Use this option to discard frames during an initial period.  Values can be expressed\n"
      "          as a single floating-point value (in seconds) or in the typical colon-delimited\n"
      "          h:m:s time format.\n"
      "\n"
      "          default: %lg\n"
      "\n"
      "  Methods for selecting the target device:\n"
      "\n"
      "    -d, --list-devices\n"
      "          Display a list of all capture devices on the system\n"
      "\n"
      "    -I <device-index>, --select-by-index=<device-index>\n"
      "          Index of the device in the list of all devices (zero-based)\n"
      "\n"
      "    -V <vendor-id>:<product-id>, --select-by-vendor-and-product-id=<vendor-id>:<product-id>\n"
      "          Provide the hexadecimal- or integer-valued vendor and product identifier\n"
      "          (Prefix hexadecimal values with \"0x\")\n"
      "\n"
      "    -L <location-id>, --select-by-location-id=<location-id>\n"
      "          Provide the hexadecimal- or integer-valued USB locationID attribute\n"
      "          (Prefix hexadecimal values with \"0x\")\n"
      "\n"
      "    -N <device-name>, --select-by-name=<device-name>\n"
      "          Provide the product name (e.g. \"AV.io HDMI Video\")\n"
      "\n"
      ,
      exe,
      analysisFormatStrs[analysisFormat],
      VideoCheckDefaultMotionThreshold,
      VideoCheckDefaultColorThreshold,
      VideoCheckDefaultSaturationThreshold,
      VideoCheckDefaultBrightnessThreshold,
      samplingTime,
      leadInTime
    );
}

//

void
VideoCheckFormatSummary(
  VideoCheckAnalysisFormat  format
)
{
  switch ( format ) {
  
    case kVideoCheckAnalysisFormatNone:
      printf(
          "\n"
          "The \"none\" analysis format inhibits the display of any statistical analysis of the\n"
          "video captured from the selected device.  The aggregate image file will be saved if the\n"
          "-i/--aggregate-image option was used, though.\n"
          "\n"
        );
      break;
      
    case kVideoCheckAnalysisFormatQuick:
      printf(
          "\n"
          "The \"quick\" analysis format displays on a single line the word\n"
          "\n"
          "  motion\n"
          "\n"
          "if motion was detected in the analysis, and the words\n"
          "\n"
          "  single color\n"
          "\n"
          "if the analysis determined the capture session to be a single color.  If both properties\n"
          "were found, the two are displayed with a comma between them:\n"
          "\n"
          "  motion, single color\n"
          "\n"
        );
      break;
    
    case kVideoCheckAnalysisFormatDefault:
      printf(
          "\n"
          "The \"plain\" analysis format produces a simple human-readable summary of the capture\n"
          "session and the frame statistics:\n"
          "\n"
          "  ~~~~~~~~~~~~~~~\n"
          "  A N A L Y S I S\n"
          "  ~~~~~~~~~~~~~~~\n"
          "\n"
          "             Frame count: 41\n"
          "                    rate: 34.0 frame / s\n"
          "              dimensions: 1280 x 720\n"
          "     Native pixel format: 32ARGB\n"
          "              Pixel mean: HSV(139.9, 0.423, 0.459) RGB(106, 93, 92)\n"
          "          Pixel variance: HSV(4587.7, 0.004, 0.017) RGB(1277, 326, 945)\n"
          "     Mean pixel variance: HSV(118.0, 0.276, 0.283) RGB(67, 64, 78)\n"
          "\n"
          "    - Motion was detected\n"
          "    - Single color was detected\n"
          "    - Aggregate image saved to '/Users/frey/Desktop/test.png'\n"
          "\n"
          "The \"Motion was detected\" and \"Single color was detected\" lines are only present if\n"
          "those conditions are detected by the statistical analysis.  Likewise, the \"Aggregate\n"
          "image saved...\" line is only present if the -i/--aggregate-image flag was used.\n"
          "\n"
        );
      break;
    
    case kVideoCheckAnalysisFormatXML:
      printf(
          "\n"
          "The \"xml\" analysis format produces a summary XML document.  The <motion-detected>\n"
          "and <single-color> elements are only present if those conditions are detected by the\n"
          "statistical analysis.  Likewise, the <aggregate-image-path> element is only present if\n"
          "the -i/--aggregate-output flag was used.\n"
          "\n"
          "  <video-check frame-count=\"53\" frames-per-sec=\"34.0\" frame-width=\"1280\" frame-height=\"720\">\n"
          "    <native-pixel-format>32ARGB</native-pixel-format>\n"
          "    <pixel-mean><h>145.3</h><s>0.398</s><v>0.456</v><r>103</r><g>90</g><b>94</b></pixel-mean>\n"
          "    <pixel-variance><h>4587.7</h><s>0.004</s><v>0.017</v><r>1277</r><g>326</g><b>945</b></pixel-variance>\n"
          "    <mean-pixel-variance><h>119.7</h><s>0.237</s><v>0.275</v><r>63</r><g>62</g><b>76</b></mean-pixel-variance>\n"
          "    <motion-detected/>\n"
          "    <single-color/>\n"
          "    <aggregate-image-path>/Users/frey/Desktop/test.png</aggregate-image-path>\n"
          "  </video-check>\n"
          "\n"
        );
      break;
    
    case kVideoCheckAnalysisFormatJSON:
      printf(
          "\n"
          "The \"json\" analysis format produces a summary in JavaScript Object Notation:\n"
          "\n"
          "  {\n"
          "    \"frame-count\": 44,\n"
          "    \"frames-per-sec\": 34.0,\n"
          "    \"frame-width\": 1280,\n"
          "    \"frame-height\": 720,\n"
          "    \"native-pixel-format\": \"32ARGB\",\n"
          "    \"pixel-mean\": {\n"
          "      \"h\": 140.294967,\n"
          "      \"s\": 0.409113,\n"
          "      \"v\": 0.448497,\n"
          "      \"r\": 101.196418,\n"
          "      \"g\": 88.545466,\n"
          "      \"b\": 91.299947\n"
          "    },\n"
          "    \"pixel-mean-hsv\": [140.294967, 0.409113, 0.448497],\n"
          "    \"pixel-mean-rgb\": [101.196418, 88.545466, 91.299947],\n"
          "    \"pixel-variance\": {\n"
          "    \"h\": 4477.174779,\n"
          "    \"s\": 0.006611,\n"
          "    \"v\": 0.005454,\n"
          "    \"r\": 383.093008,\n"
          "    \"g\": 219.080330,\n"
          "    \"b\": 649.209370\n"
          "    },\n"
          "    \"pixel-variance-hsv\": [4477.174779,0.006611,0.005454],\n"
          "    \"pixel-variance-rgb\": [383.093008,219.080330,649.209370],\n"
          "    \"mean-pixel-variance\": {\n"
          "      \"h\": 119.026081,\n"
          "      \"s\": 0.247033,\n"
          "      \"v\": 0.272642,\n"
          "      \"r\": 62.736720,\n"
          "      \"g\": 60.864346,\n"
          "      \"b\": 75.173698\n"
          "    },\n"
          "    \"mean-pixel-variance-hsv\": [119.026081, 0.247033, 0.272642],\n"
          "    \"mean-pixel-variance-rgb\": [62.736720, 60.864346, 75.173698],\n"
          "    \"motion-detected\": true,\n"
          "    \"single-color\": false,\n"
          "    \"aggregate-image-path\":\"/Users/frey/Desktop/test.png\"\n"
          "  }\n"
          "\n"
          "The actual output is compacted, lacking the whitespace formatting shown here.\n"
          "The \"aggregate-image-path\" key is only present if the -i/--aggregate-output flag\n"
          "was used.\n"
          "\n"
        );
      break;
  
  }
}

//

BOOL
VideoCheckParseAnalysisFormat(
  const char                *formatStr,
  VideoCheckAnalysisFormat  *outFormat
)
{
  if ( strcasecmp(formatStr, "xml") == 0 ) { *outFormat = kVideoCheckAnalysisFormatXML; return YES; }
  if ( strcasecmp(formatStr, "json") == 0 ) { *outFormat = kVideoCheckAnalysisFormatJSON; return YES; }
  if ( strcasecmp(formatStr, "plain") == 0 ) { *outFormat = kVideoCheckAnalysisFormatDefault; return YES; }
  if ( strcasecmp(formatStr, "quick") == 0 ) { *outFormat = kVideoCheckAnalysisFormatQuick; return YES; }
  if ( strcasecmp(formatStr, "none") == 0 ) { *outFormat = kVideoCheckAnalysisFormatNone; return YES; }
  return NO;
}

//

BOOL
VideoCheckParseCaptureDeviceModelIdString(
  NSString              *modelId,
  uint16_t              *vendorId,
  uint16_t              *productId
)
{
  NSRegularExpression   *regex = [NSRegularExpression regularExpressionWithPattern:@"VendorID_((0x)?[A-F0-9]+) ProductID_((0x)?[A-F0-9]+)" options:NSRegularExpressionCaseInsensitive error:NULL];
  NSTextCheckingResult  *result = [regex firstMatchInString:modelId options:0 range:NSMakeRange(0, [modelId length])];
  
  if ( result && ([result numberOfRanges] == 5) ) {
    NSRange             matchRange;
    
    if ( ([result rangeAtIndex:2]).length == 0 ) {
      *vendorId = [[modelId substringWithRange:[result rangeAtIndex:1]] intValue];
    } else {
      unichar           c;
      NSUInteger        i, iMax;
      uint16_t          accum = 0;
      
      matchRange = [result rangeAtIndex:1];
      i = matchRange.location + 2;
      iMax = NSMaxRange(matchRange);
      while ( i < iMax ) {
        switch ( (c = [modelId characterAtIndex:i++]) ) {
          case '0':
          case '1':
          case '2':
          case '3':
          case '4':
          case '5':
          case '6':
          case '7':
          case '8':
          case '9':
            accum = accum * 16 + (c - '0');
            break;
          case 'a':
          case 'b':
          case 'c':
          case 'd':
          case 'e':
          case 'f':
            accum = accum * 16 + 10 + (c - 'a');
            break;
          case 'A':
          case 'B':
          case 'C':
          case 'D':
          case 'E':
          case 'F':
            accum = accum * 16 + 10 + (c - 'A');
            break;
        }
      }
      *vendorId = accum;
    }
    if ( (matchRange = [result rangeAtIndex:4]).length == 0 ) {
      *productId = [[modelId substringWithRange:[result rangeAtIndex:3]] intValue];
    } else {
      unichar           c;
      NSUInteger        i, iMax;
      uint16_t          accum = 0;
      
      matchRange = [result rangeAtIndex:3];
      i = matchRange.location + 2;
      iMax = NSMaxRange(matchRange);
      while ( i < iMax ) {
        switch ( (c = [modelId characterAtIndex:i++]) ) {
          case '0':
          case '1':
          case '2':
          case '3':
          case '4':
          case '5':
          case '6':
          case '7':
          case '8':
          case '9':
            accum = accum * 16 + (c - '0');
            break;
          case 'a':
          case 'b':
          case 'c':
          case 'd':
          case 'e':
          case 'f':
            accum = accum * 16 + 10 + (c - 'a');
            break;
          case 'A':
          case 'B':
          case 'C':
          case 'D':
          case 'E':
          case 'F':
            accum = accum * 16 + 10 + (c - 'A');
            break;
        }
      }
      *productId = accum;
    }
    return YES;
  }
  return NO;
}

//

int
main(
  int           argc,
  char*         argv[]
)
{
  int                 optCh;
  const char          *exe = argv[0];
  int                 rc = 0;
  BOOL                preferRGB = NO, preferComponent = NO, singleFrame = NO;
  BOOL                shouldDebug = NO;
  double              motionThreshold = -1.0, colorThreshold = -1.0, saturationThreshold = -1.0, brightnessThreshold = -1.0;
  NSString            *aggImagePath = nil;
  NSString            *aggImageVariancePath = nil;
  AVCaptureDevice     *targetDevice = nil;
  NSArray             *captureDevices = nil;
  
  if ( argc == 1 ) {
    usage(exe);
    exit(EINVAL);
  }
  
  @autoreleasepool {
    BOOL              shouldExit = NO, showFormatHelp = NO;
    
    captureDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    if ( ! captureDevices || ! [captureDevices count] ) {
      fprintf(stderr, "WARINIG:  No video capture devices present on this system!\n");
      exit(ENODEV);
    }
    
    while ( (optCh = getopt_long(argc, argv, "dV:L:N:I:i:e:f:\1::RY1m:c:s:b:t:l:hvD", videoCheckOptions, NULL)) != -1 ) {
      switch ( optCh ) {
        
        case 'f': {
          if ( optarg && *optarg ) {
            if ( VideoCheckParseAnalysisFormat(optarg, &analysisFormat) ) {
              if ( shouldDebug ) NSLog(@"Setting analysis output format to '%s'", analysisFormatStrs[analysisFormat]);
            } else {
              fprintf(stderr, "ERROR:  Invalid analysis format: %s\n", optarg);
              exit(EINVAL);
            }
          } else {
            fprintf(stderr, "ERROR:  No format name provided with -f/--format option\n");
            exit(EINVAL);
          }
          break;
        }
        
        case '\1': {
          if ( optarg && *optarg ) {
            VideoCheckAnalysisFormat    showFormat;
            
            if ( VideoCheckParseAnalysisFormat(optarg, &showFormat) ) {
              VideoCheckFormatSummary(showFormat);
            } else {
              fprintf(stderr, "ERROR:  Invalid analysis format: %s\n", optarg);
              exit(EINVAL);
            }
          } else {
            showFormatHelp = YES;
          }
          shouldExit = YES;
          break;
        }
      
        case 'd': {
          NSUInteger  deviceIdx = 0;

          printf("------------ -------------- ------------ ------------------------------------------------\n");
          printf("%-12s %-14s %-12s %s\n", "Index", "Vend:Prod", "LocationID", "Device name");
          printf("------------ -------------- ------------ ------------------------------------------------\n");
          for ( targetDevice in captureDevices ) {
            uint16_t      vendorId = 0, productId = 0;
            
            VideoCheckParseCaptureDeviceModelIdString([targetDevice modelID], &vendorId, &productId);
            
            printf("%-12lu 0x%04x:0x%04x  %-12s %s\n",
                deviceIdx++,
                vendorId, productId,
                [[[targetDevice uniqueID] substringWithRange:NSMakeRange(0,10)] cStringUsingEncoding:NSASCIIStringEncoding],
                [[targetDevice localizedName] cStringUsingEncoding:NSASCIIStringEncoding]
              );
          }
          printf("------------ -------------- ------------ ------------------------------------------------\n");
          shouldExit = YES;
          break;
        }
        
        case 'D': {
          shouldDebug = YES;
          break;
        }
      
        case 'h': {
          usage(exe);
          shouldExit = YES;
          break;
        }
        
        case 'v': {
          printf("%s\n", VideoCheckVersionString());
          printf("Build timestamp %s %s\n", __TIME__, __DATE__);
          shouldExit = YES;
          break;
        }
      }
    }
    if ( showFormatHelp ) VideoCheckFormatSummary(analysisFormat);
    if ( shouldExit ) exit(rc);
    
    if ( shouldDebug ) {
      NSLog(@"Capture device array:");
      for ( targetDevice in captureDevices ) {
        NSLog(@"  AVCaptureDevice@%p<%@,%@> = \"%@\"", targetDevice, [targetDevice uniqueID], [targetDevice modelID], [targetDevice localizedName]);
      }
    }
    
    optreset = optind = 1;
    while ( (optCh = getopt_long(argc, argv, "dV:L:N:I:i:e:f:\1::RY1m:c:s:b:t:l:hvD", videoCheckOptions, NULL)) != -1 ) {
      switch ( optCh ) {
      
        case 'I': {
          if ( optarg && *optarg ) {
            char              *endPtr = NULL;
            unsigned long     deviceIndex = strtoul(optarg, &endPtr, 10);
            
            if ( endPtr > optarg ) {
              if ( deviceIndex < [captureDevices count] ) {
                targetDevice = [captureDevices objectAtIndex:deviceIndex];
                if ( shouldDebug ) NSLog(@"Selected capture device AVCaptureDevice@%p<%@,%@> = \"%@\"", targetDevice, [targetDevice uniqueID], [targetDevice modelID], [targetDevice localizedName]);
              } else {
                fprintf(stderr, "ERROR:  invalid device index: %lu\n", deviceIndex);
                exit(EINVAL);
              }
            } else {
              fprintf(stderr, "ERROR:  invalid device index: %s\n", optarg);
              exit(EINVAL);
            }
          } else {
            fprintf(stderr, "ERROR:  No value provided with -i/--select-by-index option\n");
            exit(EINVAL);
          }
          break;
        }
        
        case 'N': {
          if ( optarg && *optarg ) {
            NSString        *targetName = [NSString stringWithCString:optarg encoding:NSASCIIStringEncoding];
            
            for ( targetDevice in captureDevices ) {
              if ( [[targetDevice localizedName] caseInsensitiveCompare:targetName] == NSOrderedSame ) {
                if ( shouldDebug ) NSLog(@"Selected capture device AVCaptureDevice@%p<%@,%@> = \"%@\"", targetDevice, [targetDevice uniqueID], [targetDevice modelID], [targetDevice localizedName]);
                break;
              }
            }
            if ( ! targetDevice ) {
              fprintf(stderr, "ERROR:  no capture device with the name \"%s\"\n", optarg);
              exit(ENODEV);
            }
          } else {
            fprintf(stderr, "ERROR:  missing argument to -N/--select-by-name\n");
            exit(EINVAL);
          }
          break;
        }

        case 'V': {
          if ( optarg && *optarg ) {
            uint16_t        vendorId, productId;
            int             nChar;
            
            if ( sscanf(optarg, "%hi:%n", &vendorId, &nChar) == 1 ) {
              if ( sscanf(optarg + nChar, "%hi", &productId) == 1 ) {
                NSRegularExpression   *regex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"VendorID_%d.*ProductID_%d", vendorId, productId] options:0 error:NULL];
                
                for ( targetDevice in captureDevices ) {
                  if ( [regex numberOfMatchesInString:[targetDevice modelID] options:0 range:NSMakeRange(0, [[targetDevice modelID] length])] > 0 ) {
                    if ( shouldDebug ) NSLog(@"Selected capture device AVCaptureDevice@%p<%@,%@> = \"%@\"", targetDevice, [targetDevice uniqueID], [targetDevice modelID], [targetDevice localizedName]);
                    break;
                  }
                }
                if ( ! targetDevice ) {
                  fprintf(stderr, "ERROR:  no capture device with vendor:product = 0x%04hx:0x%04hx\n", vendorId, productId);
                  exit(ENODEV);
                }
              } else {
                fprintf(stderr, "ERROR:  invalid product id: %s\n", optarg + nChar);
                exit(EINVAL);
              }
            } else {
              fprintf(stderr, "ERROR:  invalid vendor id: %s\n", optarg);
              exit(EINVAL);
            }
          } else {
            fprintf(stderr, "ERROR:  missing argument to -V/--select-by-vendor-and-product-id\n");
            exit(EINVAL);
          }
          break;
        }
      
        case 'L': {
          if ( optarg && *optarg ) {
            unsigned    locationId;
            
            if ( sscanf(optarg, "%i", &locationId) == 1 ) {
              char      locationIdStr[16];
              
              snprintf(locationIdStr, sizeof(locationIdStr), "0x%08x", locationId);
              NSString  *locationIdMatch = [NSString stringWithCString:locationIdStr encoding:NSASCIIStringEncoding];
              
              for ( targetDevice in captureDevices ) {
                if ( [[targetDevice uniqueID] compare:locationIdMatch options:NSAnchoredSearch|NSCaseInsensitiveSearch range:NSMakeRange(0, [locationIdMatch length])] == NSOrderedSame ) {
                  if ( shouldDebug ) NSLog(@"Selected capture device AVCaptureDevice@%p<%@,%@> = \"%@\"", targetDevice, [targetDevice uniqueID], [targetDevice modelID], [targetDevice localizedName]);
                  break;
                }
              }
            } else {
              NSString    *uniqueIdSubstring = [NSString stringWithCString:optarg encoding:NSASCIIStringEncoding];
              
              for ( targetDevice in captureDevices ) {
                if ( [[targetDevice uniqueID] compare:uniqueIdSubstring options:NSAnchoredSearch|NSCaseInsensitiveSearch range:NSMakeRange(0, [uniqueIdSubstring length])] == NSOrderedSame ) {
                  if ( shouldDebug ) NSLog(@"Selected capture device AVCaptureDevice@%p<%@,%@> = \"%@\"", targetDevice, [targetDevice uniqueID], [targetDevice modelID], [targetDevice localizedName]);
                  break;
                }
              }
            }
            if ( ! targetDevice ) {
              fprintf(stderr, "ERROR:  no capture device with location = 0x%08x\n", locationId);
              exit(ENODEV);
            }
          } else {
            fprintf(stderr, "ERROR:  missing argument to -L/--select-by-location-id\n");
            exit(EINVAL);
          }
          break;
        }
  
        case 'R': {
          if ( shouldDebug ) NSLog(@"Will prefer RGB pixel formats");
          preferRGB = YES; preferComponent = NO;
          break;
        }
        
        case 'Y': {
          if ( shouldDebug ) NSLog(@"Will prefer component (Y'CbCr) pixel formats");
          preferRGB = NO; preferComponent = YES;
          break;
        }
        
        case '1': {
          if ( shouldDebug ) NSLog(@"Will analyze a single frame only");
          singleFrame = YES;
          break;
        }
        
        case 'i': {
          if ( optarg && *optarg ) {
            aggImagePath = [NSString stringWithCString:optarg encoding:NSASCIIStringEncoding];
          } else {
            fprintf(stderr, "ERROR:  No file path provided with -i/--aggregate-image option\n");
            exit(EINVAL);
          }
          break;
        }
        
        case 'e': {
          if ( optarg && *optarg ) {
            aggImageVariancePath = [NSString stringWithCString:optarg encoding:NSASCIIStringEncoding];
          } else {
            fprintf(stderr, "ERROR:  No file path provided with -e/--aggregate-image-variance option\n");
            exit(EINVAL);
          }
          break;
        }
        
        case 'm': {
          errno = 0;
          if ( optarg && *optarg ) {
            char        *endPtr;
            double      newValue = strtod(optarg, &endPtr);
            
            if ( (endPtr > optarg) && (errno != ERANGE) ) {
              if ( newValue < 0.0 ) {
                fprintf(stderr, "ERROR:  Invalid motion threshold value: %s\n", optarg);
                exit(ERANGE);
              } else {
                motionThreshold = newValue;
                if ( shouldDebug ) NSLog(@"Setting motion threshold to %lg", motionThreshold);
              }
            } else {
              fprintf(stderr, "ERROR:  Invalid floating-point value: %s\n", optarg);
              exit(EINVAL);
            }
          } else {
            fprintf(stderr, "ERROR:  No value provided with -m/--motion-threshold option\n");
            exit(EINVAL);
          }
          break;
        }
        
        case 'c': {
          errno = 0;
          if ( optarg && *optarg ) {
            char        *endPtr;
            double      newValue = strtod(optarg, &endPtr);
            
            if ( (endPtr > optarg) && (errno != ERANGE) ) {
              if ( *endPtr == '%' ) newValue *= 0.01 * 360;
              if ( (newValue < 0.0) || (newValue > 360.0) ) {
                fprintf(stderr, "ERROR:  Invalid color threshold value: %s\n", optarg);
                exit(ERANGE);
              } else {
                colorThreshold = newValue;
                if ( shouldDebug ) NSLog(@"Setting color threshold to %lg", colorThreshold);
              }
            } else {
              fprintf(stderr, "ERROR:  Invalid floating-point value: %s\n", optarg);
              exit(EINVAL);
            }
          } else {
            fprintf(stderr, "ERROR:  No value provided with -c/--color-threshold option\n");
            exit(EINVAL);
          }
          break;
        }
        
        case 's': {
          errno = 0;
          if ( optarg && *optarg ) {
            char        *endPtr;
            double      newValue = strtod(optarg, &endPtr);
            
            if ( (endPtr > optarg) && (errno != ERANGE) ) {
              if ( (newValue < 0.0) || (newValue > 1.0) ) {
                fprintf(stderr, "ERROR:  Invalid saturation threshold value: %s\n", optarg);
                exit(ERANGE);
              } else {
                saturationThreshold = newValue;
                if ( shouldDebug ) NSLog(@"Setting saturation threshold to %lg", colorThreshold);
              }
            } else {
              fprintf(stderr, "ERROR:  Invalid floating-point value: %s\n", optarg);
              exit(EINVAL);
            }
          } else {
            fprintf(stderr, "ERROR:  No value provided with -s/--saturation-threshold option\n");
            exit(EINVAL);
          }
          break;
        }
        
        case 'b': {
          errno = 0;
          if ( optarg && *optarg ) {
            char        *endPtr;
            double      newValue = strtod(optarg, &endPtr);
            
            if ( (endPtr > optarg) && (errno != ERANGE) ) {
              if ( (newValue < 0.0) || (newValue > 1.0) ) {
                fprintf(stderr, "ERROR:  Invalid brightness threshold value: %s\n", optarg);
                exit(ERANGE);
              } else {
                brightnessThreshold = newValue;
                if ( shouldDebug ) NSLog(@"Setting brightness threshold to %lg", colorThreshold);
              }
            } else {
              fprintf(stderr, "ERROR:  Invalid floating-point value: %s\n", optarg);
              exit(EINVAL);
            }
          } else {
            fprintf(stderr, "ERROR:  No value provided with -s/--brightness-threshold option\n");
            exit(EINVAL);
          }
          break;
        }
        
        case 't': {
          errno = 0;
          if ( optarg && *optarg ) {
            CFTimeInterval    seconds = -1.0;
            char              *endPtr, *prevEndPtr = optarg;
            
            if ( strchr(optarg, ':') ) {
              double          piece = strtod(optarg, &endPtr);
              
              if ( (endPtr > prevEndPtr) && (errno != ERANGE) ) {
                seconds = piece;
                if ( *endPtr == ':' ) {
                  seconds *= 60;
                  piece = strtod((prevEndPtr = ++endPtr), &endPtr);
                  if ( (endPtr > prevEndPtr) && (errno != ERANGE) ) {
                    seconds += piece;
                    if ( *endPtr == ':' ) {
                      seconds *= 60;
                      piece = strtod((prevEndPtr = ++endPtr), &endPtr);
                      if ( (endPtr > prevEndPtr) && (errno != ERANGE) ) {
                        seconds += piece;
                      } else {
                        fprintf(stderr, "ERROR:  Invalid sampling-time at \"%s\"\n", endPtr);
                        exit(EINVAL);
                      }
                    } else if ( *endPtr ) {
                      fprintf(stderr, "ERROR:  Invalid sampling-time at \"%s\"\n", endPtr);
                      exit(EINVAL);
                    }
                  } else {
                    fprintf(stderr, "ERROR:  Invalid sampling-time at \"%s\"\n", endPtr);
                    exit(EINVAL);
                  }
                } else if ( *endPtr ) {
                  fprintf(stderr, "ERROR:  Invalid sampling-time at \"%s\"\n", endPtr);
                  exit(EINVAL);
                }
              } else {
                fprintf(stderr, "ERROR:  Invalid sampling-time: %s\n", optarg);
                exit(EINVAL);
              }
            } else {
              seconds = strtod(optarg, &endPtr);
              if ( ! (endPtr > optarg) || (errno == ERANGE) ) {
                fprintf(stderr, "ERROR:  Invalid sampling-time value: %s\n", optarg);
                exit(EINVAL);
              }
            }
            
            if ( seconds >= 2.5 ) {
              samplingTime = seconds;
              if ( shouldDebug ) NSLog(@"Setting sampling time to %lg seconds", seconds);
            } else {
              fprintf(stderr, "ERROR:  Sampling-time must be at least 2.5 seconds\n");
              exit(ERANGE);
            }
          } else {
            fprintf(stderr, "ERROR:  No value provided with -t/--sampling-time option\n");
            exit(EINVAL);
          }
          break;
        }
        
        case 'l': {
          errno = 0;
          if ( optarg && *optarg ) {
            CFTimeInterval    seconds = -1.0;
            char              *endPtr, *prevEndPtr = optarg;
            
            if ( strchr(optarg, ':') ) {
              double          piece = strtod(optarg, &endPtr);
              
              if ( (endPtr > prevEndPtr) && (errno != ERANGE) ) {
                seconds = piece;
                if ( *endPtr == ':' ) {
                  seconds *= 60;
                  piece = strtod((prevEndPtr = ++endPtr), &endPtr);
                  if ( (endPtr > prevEndPtr) && (errno != ERANGE) ) {
                    seconds += piece;
                    if ( *endPtr == ':' ) {
                      seconds *= 60;
                      piece = strtod((prevEndPtr = ++endPtr), &endPtr);
                      if ( (endPtr > prevEndPtr) && (errno != ERANGE) ) {
                        seconds += piece;
                      } else {
                        fprintf(stderr, "ERROR:  Invalid lead-in-time at \"%s\"\n", endPtr);
                        exit(EINVAL);
                      }
                    } else if ( *endPtr ) {
                      fprintf(stderr, "ERROR:  Invalid lead-in-time at \"%s\"\n", endPtr);
                      exit(EINVAL);
                    }
                  } else {
                    fprintf(stderr, "ERROR:  Invalid lead-in-time at \"%s\"\n", endPtr);
                    exit(EINVAL);
                  }
                } else if ( *endPtr ) {
                  fprintf(stderr, "ERROR:  Invalid lead-in-time at \"%s\"\n", endPtr);
                  exit(EINVAL);
                }
              } else {
                fprintf(stderr, "ERROR:  Invalid lead-in-time: %s\n", optarg);
                exit(EINVAL);
              }
            } else {
              seconds = strtod(optarg, &endPtr);
              if ( ! (endPtr > optarg) || (errno == ERANGE) ) {
                fprintf(stderr, "ERROR:  Invalid lead-in-time value: %s\n", optarg);
                exit(EINVAL);
              }
            }
            
            if ( seconds >= 1.0 ) {
              leadInTime = seconds;
              if ( shouldDebug ) NSLog(@"Setting lead-in time to %lg seconds", seconds);
            } else {
              fprintf(stderr, "ERROR:  Lead-in-time must be at least 1.0 seconds\n");
              exit(ERANGE);
            }
          } else {
            fprintf(stderr, "ERROR:  No value provided with -l/--lead-in-time option\n");
            exit(EINVAL);
          }
          break;
        }
      
      }
    }
  }
  
  if ( (samplingTime - leadInTime) < 1.0 ) {
    fprintf(stderr, "ERROR:  The sampling time (%lg) and lead-in time (%lg) are too close.\n"
                    "        Increase the sampling time or decrease the lead-in time.\n",
              samplingTime, leadInTime
            );
    exit(EINVAL);
  }
  
  @autoreleasepool {
    if ( targetDevice ) {
      AVCaptureSession  *session = [[AVCaptureSession alloc] init];
      NSError           *error = nil;
      
      [session beginConfiguration];
      [session setSessionPreset:AVCaptureSessionPreset320x240];
      if ( shouldDebug ) NSLog(@"Capture session created, pre-configured with 320x240 presents");
      
      AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:targetDevice error:&error];
      if ( input ) {
        [session addInput:input];
        if ( shouldDebug ) NSLog(@"Chosen capture device added to session");
        
        AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
        [session addOutput:output];
        if ( shouldDebug ) NSLog(@"Buffered output target added to session");
        
        VideoCheckDelegate        *videoProcessor = nil;
        NSArray                   *validPixelFormats = [output availableVideoCVPixelFormatTypes];
        OSType                    chosenPixelFormat = 0;
        
        if ( shouldDebug ) {
          NSLog(@"Supported pixel formats for capture device:");
          for ( NSNumber* pixelFormat in validPixelFormats ) {
            uint32_t              pixelFormatAsInt = [pixelFormat unsignedIntValue];
            
            if ( isprint((pixelFormatAsInt & 0xff000000) >> 24) ) {
              NSLog(@"  0x%08x ('%c%c%c%c')",
                  pixelFormatAsInt,
                  (pixelFormatAsInt & 0xff000000) >> 24,
                  (pixelFormatAsInt & 0x00ff0000) >> 16,
                  (pixelFormatAsInt & 0x0000ff00) >> 8,
                  (pixelFormatAsInt & 0x000000ff)
                );
            } else {
              NSLog(@"  0x%1$08x (%1$u)", pixelFormatAsInt);
            }
          }
        }
        
        for ( NSNumber* pixelFormat in validPixelFormats ) {
          BOOL                    earlyExit = NO;
          uint32_t                pixelFormatAsInt = [pixelFormat unsignedIntValue];
          
          switch ( pixelFormatAsInt ) {
          
            case kCVPixelFormatType_32ARGB:
            case kCVPixelFormatType_32BGRA: {
              chosenPixelFormat = pixelFormatAsInt;
              if ( preferRGB ) earlyExit = YES;
              break;
            }
            
            case kCVPixelFormatType_422YpCbCr8: {
              chosenPixelFormat = pixelFormatAsInt;
              if ( preferComponent ) earlyExit = YES;
              break;
            }
            
          }
          if ( earlyExit ) break;
        }
        
        if ( chosenPixelFormat ) {
          videoProcessor = [VideoCheckDelegate videoCheckDelegateForPixelFormat:chosenPixelFormat];
          [output setVideoSettings:@{ (NSString *)kCVPixelBufferPixelFormatTypeKey : @(chosenPixelFormat) }];
        }
        if ( videoProcessor ) {
          //
          // Setup any behavioral options provided by the user for the VideoCheckDelegate:
          //
          if ( motionThreshold > 0.0 ) videoProcessor.motionThreshold = motionThreshold;
          if ( colorThreshold > 0.0 ) videoProcessor.singleColorThreshold = colorThreshold;
          if ( saturationThreshold > 0.0 ) videoProcessor.saturationThreshold = saturationThreshold;
          if ( brightnessThreshold > 0.0 ) videoProcessor.brightnessThreshold = brightnessThreshold;
          videoProcessor.aggregateImagePath = aggImagePath;
          videoProcessor.aggregateImageVariancePath = aggImageVariancePath;
          videoProcessor.analysisFormat = analysisFormat;
          videoProcessor.leadInTime = leadInTime;
          videoProcessor.singleFrameOnly = singleFrame;
          
          if ( shouldDebug ) NSLog(@"Using video processor delegate %@", videoProcessor);
          
          //
          // Setup the work queue what will handle async frame processing:
          //
          dispatch_queue_t          videoProcessingQueue = dispatch_queue_create("VideoProcessingQueue", NULL);

          [output setSampleBufferDelegate:videoProcessor queue:videoProcessingQueue];
          
          //
          // Commit all configuration changes to the device and begin sampling:
          //
          [session commitConfiguration];
          if ( shouldDebug ) NSLog(@"Capture device has been configured, entering video processing phase");
          [session startRunning];
          
          //
          // Go to sleep for the specified amount of time:
          //
          CFRunLoopRunInMode(kCFRunLoopDefaultMode, samplingTime, false);
          
          //
          // Stop the capture session, please!
          //
          [session stopRunning];
          
          //
          // Summarize the statistics:
          //
          [videoProcessor summarizeAnalysis];
        } else {
          fprintf(stderr, "ERROR: Unable to find a usable pixel format for the capture device\n");
          exit(EINVAL);
        }
      }
    }
  }
  return rc;
}
