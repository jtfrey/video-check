//
// VideoCheckDelegate.h
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

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

/*!
  @constant VideoCheckDefaultMotionThreshold
  
  Motion is detected by comparing the square-root of the average across all
  pixel components of the interframe pixel variance.  If the value is
  above a threshold, then the color balance is changing enough that the
  frames are not remaining similar -- implying "motion" is occurring.
  
  The default threshold is 5.0.
*/
FOUNDATION_EXPORT double VideoCheckDefaultMotionThreshold;

/*!
  @constant VideoCheckDefaultColorThreshold
  
  The captured frames are deemed a "single color" if the average variance
  in pixel value across all frames is less than a threshold value.
  
  If average hue across a single frame has a narrow variance, then across
  all captured frames if that variance remains narrow the camera is assumed
  to be capturing a "single hue" in each frame.  Taken together with
  saturation and brightness criteria, this determines "single color."
  
   The default threshold is 15.0. 
*/
FOUNDATION_EXPORT double VideoCheckDefaultColorThreshold;

/*!
  @constant VideoCheckDefaultSaturationThreshold
  
  The captured frames are deemed a "single color" if the average variance
  in pixel value across all frames is less than a threshold value.
  
  If average saturation across a single frame has a narrow variance, then
  across all captured frames if that variance remains narrow the camera is
  assumed to be capturing a "narrow saturation" in each frame.  Taken
  together with hue and brightness criteria, this determines "single color."
  
   The default threshold is 0.075. 
*/
FOUNDATION_EXPORT double VideoCheckDefaultSaturationThreshold;

/*!
  @constant VideoCheckDefaultBrightnessThreshold
  
  The captured frames are deemed a "single color" if the average variance
  in pixel value across all frames is less than a threshold value.
  
  If average brightness across a single frame has a narrow variance, then
  across all captured frames if that variance remains narrow the camera is
  assumed to be capturing a "narrow brightness" in each frame.  Taken
  together with hue and saturation criteria, this determines "single color."
  
   The default threshold is 0.25. 
*/
FOUNDATION_EXPORT double VideoCheckDefaultBrightnessThreshold;

/*!
  @typedef VideoCheckAnalysisFormat
  
  An enumeration of the output formats the VideoCheckDelegate class can produce
  for the statistical summary of the capture session it monitored.
*/
typedef NS_OPTIONS(NSUInteger, VideoCheckAnalysisFormat) {
  kVideoCheckAnalysisFormatDefault = 0,
  kVideoCheckAnalysisFormatXML,
  kVideoCheckAnalysisFormatJSON,
  kVideoCheckAnalysisFormatQuick,
  kVideoCheckAnalysisFormatNone
};

/*!
  @class VideoCheckDelegate
  @abstract AVSampleBuffer delegate object
  
  Instance of this class are assigned as the delegate of an AVCaptureOutput
  object.  As video frames are completed by the AVCaptureOutput object, messages
  from the AVCaptureVideoDataOutputSampleBufferDelegate protocol are sent to the
  VideoCheckDelegate to allow it to "see" the frames that have been produced.
  
  This class in particular performs some simple statistical analyses of each
  frame:  the average pixel value and its variance are computed and used to update
  a global (across all captured frames) average and variance.  The mean variance
  is also calculated (as a measure of the time-averaged change in color balance).
  
  An "aggregate image" is maintained that represents the average value of each
  pixel across all frames processed.  The aggregate image can be saved to disk.
  
  A summary of the statistics gathered during the capture session can be produced
  and output in a variety of formats.
*/
@interface VideoCheckDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>

@property BOOL                      singleFrameOnly;
@property double                    leadInTime;
@property double                    motionThreshold;
@property double                    singleColorThreshold;
@property double                    saturationThreshold;
@property double                    brightnessThreshold;
@property NSString*                 aggregateImagePath;
@property NSString*                 aggregateImageVariancePath;
@property VideoCheckAnalysisFormat  analysisFormat;
@property (readonly) size_t         aggregateImageWidth;
@property (readonly) size_t         aggregateImageHeight;

/*!
  @method videoCheckDelegateForPixelFormat:
  
  Given a pixel type (coming from an AVCaptureOutput object) allocate and initialize
  a VideoCheckDelegate object that can act as a pixel buffer processing delegate to
  that AVCaptureOutput object.
*/
+ (VideoCheckDelegate*) videoCheckDelegateForPixelFormat:(OSType)pixelFormat;

/*!
  @method pixelFormat
  
  Returns the pixel format the receiver will process.
*/
- (OSType) pixelFormat;

/*!
  @method pixelFormatDescription
  
  Returns a C string that describes the pixel format the receiver will process.
*/
- (const char*) pixelFormatDescription;

/*!
  @method summarizeAnalysis
  
  If the receiver was able to perform statistical analysis of at least one video frame,
  this method writes to stdout the summary of that analysis.
  
  If the receiver's aggregateImagePath property has been set, then the aggregate image
  is saved to that path, as well.
*/
- (void) summarizeAnalysis;

@end
