# video-check

A utility to capture video from a device and analyze it for motion or its being a single color (e.g. no signal, blue screen, etc.).

Written at the request of the University's Media Services department, to aid in their remote diagnosis of problems with classroom capture systems.

The utility's built-in help screen:

~~~~
usage:

    ./video-check {options/target selection}

  Options:

    -h, --help
          Display this information and exit.

    -v, --version
          Display the program version and exit.

    -D, --debug
          Display additional (verbose) information as the program executes.

    -i <file-path>, --aggregate-image=<file-path>
          Save the aggregate (average) image in the given file in PNG format.  If this
          flag is not explicitly provided, then the aggregate image is not saved.

    -e <file-path>, --aggregate-image-variance=<file-path>
          The program accumluates an image whose pixels represent the per-pixel variance
          of the aggregate (average) image.  Use this option to save that image to a PNG
          file.  If this flag is not explicitly provided, then that image is not saved.

          The image is grayscale rather than color, to provide a better visualization of
          the magnitude of variance in each pixel.

    -f <format>, --format=<format>
          Output the analysis of the capture session in the given format, where
          format is one of: xml, json, plain, quick, none.

          default: xml

    --format-info{=<format>}
          Displays a summary of the given output format (or the chosen output format the
          program would use if <format> is not provided to this flag) and exits.

    -R, --prefer-rgb
          Use a capture mode for the device that generates RGB pixels

    -Y, --prefer-component
          Use a capture mode for the device that generates component (Y'CbCr) pixels

    -1, --single-frame
          Capture just a single frame from the device.  Single-color analysis will still
          work, but motion cannot (naturally!) be detected.

    -m <number>, --motion-threshold=<number>
          Use the given (positive) floating-point value as the threshold for determining
          when the inter-frame variance indicates the image is changing (in motion).
          Should be in the range (0.0, +INF); lower values = tighter criteria.

          default: 5

    -c <number>, --color-threshold=<number>
          Use the given (positive) floating-point value as the threshold for determining
          when the inter-frame mean hue value did not vary significantly (single color).
          Should be in the range (0.0, 360.0]; lower values = tighter criteria.

          default: 15

          The value can also be expressed as "<number>%", which is interpreted as a
          percentage of the number 360.

    -s <number>, --saturation-threshold=<number>
          Use the given (positive) floating-point value as the threshold for determining
          when the inter-frame mean saturation value did not vary significantly (single color).
          Should be in the range (0.0, 1.0]; lower values = tighter criteria.

          default: 0.075

    -b <number>, --brightness-threshold=<number>
          Use the given (positive) floating-point value as the threshold for determining
          when the inter-frame mean brightness value did not vary significantly (single color).
          Should be in the range (0.0, 1.0]; lower values = tighter criteria.

          default: 0.25

    -t <value>, --sampling-time=<value>
          The program will analyze frames from the capture device for a finite period of
          time.  The time must be at least 2.5 seconds.  Values can be expressed as a single
          floating-point value (in seconds) or in the typical colon-delimited h:m:s time
          format.

          default: 5

    -l <value>, --lead-in-time=<value>
          Devices with auto-focus or leveling can produce radical color-changes when the
          capture session starts, which will indicate "motion" to the analysis algorithm.
          Use this option to discard frames during an initial period.  Values can be expressed
          as a single floating-point value (in seconds) or in the typical colon-delimited
          h:m:s time format.

          default: 1

  Methods for selecting the target device:

    -d, --list-devices
          Display a list of all capture devices on the system

    -I <device-index>, --select-by-index=<device-index>
          Index of the device in the list of all devices (zero-based)

    -V <vendor-id>:<product-id>, --select-by-vendor-and-product-id=<vendor-id>:<product-id>
          Provide the hexadecimal- or integer-valued vendor and product identifier
          (Prefix hexadecimal values with "0x")

    -L <location-id>, --select-by-location-id=<location-id>
          Provide the hexadecimal- or integer-valued USB locationID attribute
          (Prefix hexadecimal values with "0x")

    -N <device-name>, --select-by-name=<device-name>
          Provide the product name (e.g. "AV.io HDMI Video")

~~~~

