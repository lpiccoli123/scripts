#!/bin/bash
#set -x
#
# sync-capture.sh
#

#
# infoPrint level parameters
#
INFO=0
DEBUG=1
WARN=2
ERROR=3

#
# infoPrint timestamp parameter
#
NOTIME=0
TIME=1

#
# infoPrint output parameter
#
LOG=0
OUT=1
BOTH=2

#
# Paremeters
# $1, 0=don't print, 1=print
# $2, $level: 0=INFO, 1=DEBUG, 2=WARN, 3=ERROR
# $3, $timestamp: 0=no timestamp, 1=timestamp
# $4, $output: 0=$_logFile only, 1=stdout only, 2=both
# $5, message to be printed
#
function infoPrint {
    if (( $1 > 0 )); then
	level=$2
	timestamp=$3
	output=$4
	
	messageStr=""
	if (( timestamp > 0 )); then
	    messageStr=`date +'[%D %H:%M:%S]'`
	fi
	
	case $level in
	    0)
		messageStr="$messageStr INFO: "
		;;
	    1)
		messageStr="$messageStr DEBUG: "
		;;
	    2)
		messageStr="$messageStr WARN: "
		;;
	    3)
		messageStr="$messageStr ERROR: "
		;;
	esac
	
	messageStr="$messageStr $5"
	
	case $output in
	    0)
		echo $messageStr >> $_logFile
		;;
	    1)
		echo $messageStr
		;;
	    2)
		echo $messageStr | tee -a $_logFile
		;;
	esac
    fi
}

#
# Print command line options
#
function printUsage {
    echo "Usage: sync-capture [switches]"
    echo "  -t <testDirName>: base directory name created for each capture (default \"test\")"
    echo "                    the test number is appended to the <testDirName>"
    echo "  -D <ioc localDir>: local absolut directory path where the <testDirName> can be accessed by the IOC"
    echo "  -d <localDir>: local absolut directory path where the <testDirName> can be accessed"
    echo "  -n <numImages>: number of images to acquire (default 100)"
    echo "  -r <repeat>: repeat acquisition this number of times (default 1)"
    echo "  -s <number>: number of times output trigger to camera is disabled/enabled (every second)"
    echo "               if test is too short it may not stop camera at all"
    echo "  -c <PV name>: base name for the camera PV (e.g. OTRS:DMP1:695)"
    echo "  -e <EVR PV name>: base name for the EVR (e.g. EVR:DMP1:PM10)"
    echo "  -v : turns on verbose output"
    echo "  -g : turn on debug output"
    echo "Pattern checking options:"
    echo "  -p : enable pattern checking"
    echo "  -i <number>: expected difference between PulseIds (default $_idDiff - for 120Hz)"
    echo "  -w <number>: window around mean intensity (default $_meanWindow)"    
    echo "  -x <number>: number of times a test pattern must repeat before being accepted (default $_patternRepeat)"
    echo "  -k : only check images, don't collect them"
    echo "  -1 <rate> : LED1 blink rate (when using -k)"
    echo "  -2 <rate> : LED2 blink rate (when using -k)"
    echo "  -z : ask user to identify LED patterns (select which average correspont to which state)"
    echo "  -Z : automatically finds pattern averages"
    echo "  -S <size> : maximum pattern size to test (default 15)"
    echo "Rate options:"
    echo "  -R <number> : set camera and LED rates"
    echo "                0 - camera 120Hz (event 140), LED1 40Hz (event 162), LED2 60Hz (event 141)"
    echo "                1 - camera  60Hz (event 141), LED1 10Hz (event 143), LED2 30Hz (event 142)"
    echo "                2 - camera  30Hz (event 142), LED1  5Hz (event 144), LED2 10Hz (event 143)"
    echo "                3 - camera  10Hz (event 143), LED1  5Hz (event 144), LED2  1Hz (event 145)"
}

#
# Configure EVR triggers
# - Set the camera trigger
# - Set LED1/LED2 to a know pattern
#
# The camera must be connected to EVR output 0
# LED1 must be connected to EVR output 1 or 2
# LED2 must be connected to EVR output 2 or 1
#
function configureEvr {
    # 120 Hz camera configuration
    cameraEvent=140
    cameraRate=120
    cameraRestart=141

    led1Event=162
    led1Rate=40

    led2Event=141
    led2Rate=60

    case $_rate in
	1) # 60 Hz camera configuration
	    cameraEvent=141
	    cameraRate=60
	    cameraRestart=142
	    led1Event=143
	    led1Rate=10
	    led2Event=142
	    led2Rate=30
	;;
	2) # 30 Hz camera configuration
	    cameraEvent=142
	    cameraRate=30
	    cameraRestart=143
	    led1Event=144
	    led1Rate=5
	    led2Event=143
	    led2Rate=10	  
	    ;;
	3) # 10 Hz camera configuration
	    cameraEvent=143
	    cameraRate=10
	    cameraRestart=144
	    led1Event=144
	    led1Rate=5
	    led2Event=145
	    led2Rate=1
	    ;;
    esac

    infoPrint 1 6 $NOTIME $OUT "+== EVR configuration ==="
    infoPrint 1 6 $NOTIME $OUT "| Device : Event : Rate Hz"
    infoPrint 1 6 $NOTIME $OUT "| CAMR   : $cameraEvent : $cameraRate"
    infoPrint 1 6 $NOTIME $OUT "| LED1 : $led1Event : $led1Rate"
    infoPrint 1 6 $NOTIME $OUT "| LED2 : $led2Event : $led2Rate"
    infoPrint 1 6 $NOTIME $OUT "+========================"
    

    # Disable non used events
    infoPrint 1 $INFO $NOTIME $OUT "Disabling unused events (only first three events are used for testing the camera"
    for (( i=4; i<=14; i++ )); do
	pv=$_evrPv:"EVENT${i}CTRL.ENAB"
	infoPrint $_debugPrint $DEBUG $NOTIME $OUT "Disabling output $i ($pv)"
	caput $pv 0 >> /dev/null
    done

    # Setup LED EVR outputs
    infoPrint 1 $INFO $NOTIME $OUT "Setting up LED1 trigger output (width/delay/enable)"
    caput $_evrPv":CTRL.DG1W"  15000 >> /dev/null
    caput $_evrPv":CTRL.DG1D" 100000 >> /dev/null
    caput $_evrPv":CTRL.DG1E"      1 >> /dev/null

    infoPrint 1 $INFO $NOTIME $OUT "Setting up LED2 trigger output (width/delay/enable)"
    caput $_evrPv":CTRL.DG2W"   5000 >> /dev/null 
    caput $_evrPv":CTRL.DG2D" 100000 >> /dev/null
    caput $_evrPv":CTRL.DG2E"      1 >> /dev/null

    # LED1 trigger
    infoPrint 1 $INFO $NOTIME $OUT "Setting up LED1 trigger event $led1Event (irq/out)"
    pv=$_evrPv:"EVENT2CTRL.ENM"
    caput $pv $led1Event >> /dev/null
    pv=$_evrPv:"EVENT2CTRL.ENAB"
    caput $pv 1 >> /dev/null
    pv=$_evrPv":EVENT2CTRL.OUT1"
    caput $pv 1 >> /dev/null
    pv=$_evrPv":EVENT2CTRL.VME"
    caput $pv 0 >> /dev/null
    pv=$_evrPv":EVENT2CTRL.VME"
    caput $pv 1 >> /dev/null

    # LED2 trigger
    infoPrint 1 $INFO $NOTIME $OUT "Setting up LED2 trigger event $led2Event (irq/out)"
    pv=$_evrPv:"EVENT3CTRL.ENM"
    caput $pv $led2Event >> /dev/null
    pv=$_evrPv:"EVENT3CTRL.ENAB"
    caput $pv 1 >> /dev/null
    pv=$_evrPv":EVENT3CTRL.OUT2"
    caput $pv 1 >> /dev/null
    pv=$_evrPv":EVENT3CTRL.VME"
    caput $pv 0 >> /dev/null
    pv=$_evrPv":EVENT3CTRL.VME"
    caput $pv 1 >> /dev/null

    # Camera EVR output
    infoPrint 1 $INFO $NOTIME $OUT "Setting up camera trigger event (irq/out)"
    caput $_evrPv":CTRL.DG0E"      1 >> /dev/null
    caput $_evrPv":CTRL.DG0W"    714 >> /dev/null 
    caput $_evrPv":CTRL.DG0D"  71419 >> /dev/null

    # Camera trigger
    infoPrint 1 $INFO $NOTIME $OUT "Setting up camera trigger event $cameraEvent (irq/out)"
    pv=$_evrPv:"EVENT1CTRL.ENM"
    caput $pv $cameraEvent >> /dev/null
    pv=$_evrPv:"EVENT1CTRL.ENAB"
    caput $pv 1 >> /dev/null
    pv=$_evrPv":EVENT1CTRL.OUT0"
    caput $pv 1 >> /dev/null
    pv=$_evrPv":EVENT1CTRL.VME"
    caput $pv 0 >> /dev/null
    pv=$_evrPv":EVENT1CTRL.VME"
    caput $pv 1 >> /dev/null


    # Check if EVR is receiving events at the expected rate
    infoPrint 1 $INFO $NOTIME $OUT "Checking if rates were set correcly"
    sleep 1
    infoPrint 1 $INFO $NOTIME $OUT "Checking..."
    sleep 1
    infoPrint 1 $INFO $NOTIME $OUT "Checking..."
    sleep 1

    rate=`caget -t $_evrPv:EVENT1RATE`
    rateCheck=`echo $rate != $cameraRate | bc -l`
    if (( rateCheck > 0)) ; then
	infoPrint 1 $ERROR $NOTIME $OUT "Expected rate of $cameraRate Hz, got $rate Hz for camera trigger"
	infoPrint 1 $ERROR $NOTIME $OUT "Please check EVR configuration for event $cameraEvent"
    fi

    rate=`caget -t $_evrPv:EVENT2RATE`
    rateCheck=`echo $rate != $led1Rate | bc -l`
    if (( rateCheck > 0)) ; then
	infoPrint 1 $ERROR $NOTIME $OUT "Expected rate of $led1Rate Hz, got $rate Hz for LED1 trigger"
	infoPrint 1 $ERROR $NOTIME $OUT "Please check EVR configuration for event $led1Event"
    fi

    rate=`caget -t $_evrPv:EVENT3RATE`
    rateCheck=`echo $rate != $led2Rate | bc -l`
    if (( rateCheck > 0)) ; then
	infoPrint 1 $ERROR $NOTIME $OUT "Expected rate of $led2Rate Hz, got $rate Hz for LED2 trigger"
	infoPrint 1 $ERROR $NOTIME $OUT "Please check EVR configuration for event $led2Event"
    fi 
    
    # Camera TSS records - need to change these according to the camera trigger
    pv=$_cameraPv":TSS_RESTART.EVNT"
    caput $pv $cameraRestart >> /dev/null
    pv=$_cameraPv":TSS_START.EVNT"
    caput $pv $cameraEvent >> /dev/null

}

#
# Test if parameter $1 is a number, exit if not
#
function isNumber {
    numberStr=$1
    re='^[0-9]+$'
    if ! [[ $numberStr =~ $re ]] ; then
	infoPrint 1 $ERROR $TIME $BOTH "$numberStr is not a valid number";
	exit 1
    fi
}

#
# Test if parameter $1 is a floting point number (e.g. 0.123), exit if not
#
function isFloatNumber {
    re='^[0-9]+\.?[0-9]+$'
    if ! [[ $1 =~ $re ]] ; then
	infoPrint 1 $ERROR $TIME $BOTH "$1 is not a valid float number";
	exit 1
    fi
}

#
# Check if required command line switches are present
#
function checkRequiredParameters {
    if [ "$_localDir" == "" ]; then
	infoPrint 1 $ERROR $NOTIME $OUT "Missing local directory name (-d option). Example: /nfs/slac/g/lcls/epics/ioc/data/vioc-b34-pm01/sync"
	printUsage
	exit 1
    elif [ ! -d "$_localDir" ]; then
	if (( $_setRate < 1 )); then
	    infoPrint 1 $ERROR $TIME $OUT  "Specified local directory $_localDir does not exist"
	    exit 1
	fi
    elif [ ! -w "$_localDir" ]; then
	if (( $_setRate < 1 )); then
	    infoPrint 1 $ERROR $NOTIME $OUT "Specified local directory $_localDir is not writable"
	    exit 1
	fi
    fi

    if ( [ "$_localIOCDir" == "" ] && (( _identifyPattern == 2 )) ) ; then
	infoPrint 1 $ERROR $NOTIME $OUT "Must specify local IOC directory name (-D) if -Z option is used"
	printUsage
	exit 1
    fi

    if [ "$_localIOCDir" == "" ]; then
	infoPrint 1 $ERROR $NOTIME $OUT "Missing local IOC directory name (-D option). Example: /data/vioc-b34-pm01/sync"
	printUsage
	exit 1
    fi

    if ([ "$_cameraPv" == "" ] && (( _identifyPattern == 2 )) ) ; then
	infoPrint 1 $ERROR $NOTIME $OUT "Must specify camera PV base name (-c) if -Z option is used"
	printUsage
	exit 1
    fi

    if [ "$_cameraPv" == "" ]; then
	infoPrint 1 $ERROR $NOTIME $OUT "Missing camera PV base name (-c option). Example: OTRS:DMP1:695"
	printUsage
	exit 1
    fi

    if ([ "$_evrPv" == "" ] && (( _identifyPattern == 2 )) ) ; then
	infoPrint 1 $ERROR $NOTIME $OUT "Must specify EVR PV base name (-e) if -Z option is used"
	printUsage
	exit 1
    fi

    if [ "$_evrPv" == "" ]; then
	infoPrint 1 $ERROR $NOTIME $OUT "Missing EVR PV base name (-e option). Example: EVR:DMP1:PM10"
	printUsage
	exit 1
    fi    
}

#
# Print out configuration (from command line options)
#
function printConfiguration {
    echo "=== Test Configuration ==="
    echo '  '$_testFileName$'\t: file name base (-f option)'
    echo '  '$_testDir$'\t: test directory name (-t option)'
    echo '  '$_numImages$'\t: number of images (-n option)'
    echo '  '$_numTests$'\t: repeat test count (-r option)'
    echo '  '$_stopCamera$'\t: number of camera trigger interruptions (every second) (-s option)'
    echo '  '$_cameraPv$'\t: camera PV name (-c option)'
    echo '  '$_evrPv$'\t: EVR PV name (-e option)'
    echo '  '$_localDir$'\t: local directory (-d option)'
    echo '  '$_localIOCDir$'\t: local IOC directory (-D option)'
    echo '  --- Pattern check options'
    echo '   '$_patternEnabled$'\t: 1 if pattern check is enabled (-p option)'
    echo '   '$_idDiff$'\t: expected difference between PulseIds (-i option)'
    echo '   '$_meanWindow$'\t: mean window around average intensity (-w option)'
    echo '   '$_patternRepeat$'\t: number of times a test pattern must repeat (-x option)'
    echo '   '$_checkOnly$'\t: only check the images, not acquire (-k option)'
    echo '   '$_led1Rate$'\t: LED1 blink rate (-1 option)'
    echo '   '$_led2Rate$'\t: LED2 blink rate (-2 option)'
    echo '   '$_identifyPattern$'\t: 1 if user will be asked to identify pattern (-z option)'
    echo '   '$_identifyPattern$'\t: 2 autogenerate images and identify pattern, no user input (-Z option)'
    echo '   '$_identifyPattern$'\t: 3 use same files if already generated with -Z before (-Y option)'
    echo '   '$_maxPatternSize$'\t: maximum pattern size (-S option)'
}

#
# Check whether camera is streaming, if not enable it
#
function checkCamera {
    pv=$_cameraPv":Acquisition"
    acquisition=`caget -nt $pv`
    if [ ! "$?" == "0" ]; then
	infoPrint 1 $ERROR $TIME $BOTH "Can't read PV $pv, exiting..."
	exit 1
    fi

    # if camera is not streaming images, enable it
    if [ ! "$acquisition" == "1" ]; then
	infoPrint 1 $WARN $TIME $BOTH "Camera not streaming, enabling it now."
	caput $pv 1 > /dev/null
    fi

    sleep 2

    pv=$_cameraPv:"ArrayRate_RBV"
    rate=`caget -nt $pv`
    if [ ! "$?" == "0" ]; then
	infoPrint 1 $ERROR $TIME $BOTH "Can't read PV $pv, exiting..."
	exit 1
    fi
    rate=`expr $rate`
    if (( rate < 1 )); then
	infoPrint 1 $ERROR $TIME $BOTH "Detected zero frame rate, exiting..."
	exit 1
    fi
    infoPrint 1 $INFO $TIME $LOG "Camera streaming at $rate Hz"
}

#
# Setup test
# - Change directory
# - Create test directory
# - Enable camera 
# - Setup PVs 
#
function prepareTest {
    # Go to local test location
    pushd $_localDir >& /dev/null

    localTestDir=$_localDir"/"$_testDir$_testCount
    # Create test directory
    if (( _checkOnly < 1 )); then
	if [ -d $localTestDir ]; then
	    infoPrint 1 $INFO $NOTIME $OUT "Local test directory exists ($localTestDir), removing..."
	    rm -rf $localTestDir
	fi

	mkdir $localTestDir
	if [ "$?" == 1 ]; then
	    infoPrint 1 $ERROR $NOTIME $OUT "Failed to create test directory, exiting tests..."
	    exit 1
	fi
    fi
    cd $localTestDir

    if (( _checkOnly < 1 )); then
	_logFile=$localTestDir"/"$_testFileName".log"
    else
	_logFile=$localTestDir"/"$_testFileName"-check.log"
    fi

    infoPrint 1 $INFO $TIME $LOG "Setting up test #$_testCount"
    printConfiguration >> $_logFile

    if (( _checkOnly < 1 )); then    
        # Make sure camera is taking data
	checkCamera

	# Figure out the LED rates
	_led1Rate=`caget -t $_evrPv:EVENT2RATE`
	_led1Rate=`expr $_led1Rate`
	_led1Event=`caget -t $_evrPv:EVENT2CTRL.ENM`
	infoPrint 1 $INFO $TIME $BOTH "LED1 blink rate is $_led1Rate Hz (Event $_led1Event)"

	_led2Rate=`caget -t $_evrPv:EVENT3RATE`
	_led2Rate=`expr $_led2Rate`
	_led2Event=`caget -t $_evrPv:EVENT3CTRL.ENM`
	infoPrint 1 $INFO $TIME $BOTH "LED2 blink rate is $_led2Rate Hz (Event $_led2Event)"

        # Setup TIFF plugin parameters
	caput -S $_cameraPv":TIFF:FilePath" $_localIOCDir"/"$_testDir$_testCount >> /dev/null
	caput -S $_cameraPv":TIFF:FileName" $_testFileName >> /dev/null
	caput $_cameraPv":TIFF:FileNumber" 0 >> /dev/null
	caput -S $_cameraPv":TIFF:FileTemplate" "%s%s_%5.5d.tif" >> /dev/null
	caput $_cameraPv":TIFF:NumCapture" $_numImages >> /dev/null
	caput $_cameraPv":TIFF:FileWriteMode" 1 >> /dev/null
	caput $_cameraPv":TIFF:EnableCallbacks" 1 >> /dev/null
	
	
        # Reset ADSupport TSS counters
	caput $_cameraPv":TSS_IMAGE_ACQUSITION_RESET.PROC" 1 >> /dev/null
	
        # Save number of images 'lost' before test
	lostImagesBefore=`caget -t $_cameraPv:TSS_IMAGE_LOST_COUNT`
    fi
}

#
# Briefly stop camera trigger, generates missing images
#
function interruptCamera {
    caput $_evrPv":EVENT1CTRL.OUT0" 0 >> /dev/null
    caput $_evrPv":EVENT1CTRL.OUT0" 1 >> /dev/null
}

#
# Run a single test
#
function acquireImages {
    infoPrint 1 $INFO $TIME $LOG "Running test"

    # Enable TIFF capture
    caput $_cameraPv":TIFF:Capture" 1 >> /dev/null

    # Wait capture to be done
    pv=$_cameraPv":TIFF:Capture_RBV"
    doneCapture=`caget -nt $pv`
    infoPrint 1 $INFO $TIME $LOG "doneCapture=$doneCapture"
    numInterrupts=$_stopCamera
    while [ $doneCapture == 1 ]; do
	sleep 1
	# Disabled camera momentarily
	if (( numInterrupts > 0 )); then
	    infoPrint 1 $INFO $TIME $LOG "Interrupting camera trigger [$numInterrupts]"
	    numInterrupts=`expr $numInterrupts - 1`
	    interruptCamera
	fi
	doneCapture=`caget -nt $pv`
	infoPrint 1 $INFO $TIME $LOG "doneCapture=$doneCapture"
    done
    numCaptured=`caget -nt $_cameraPv":TIFF:NumCaptured_RBV"`

    infoPrint 1 $INFO $TIME $LOG "Captured "$numCaptured" images"
    lostImagesAfter=`caget -nt $_cameraPv":TSS_IMAGE_LOST_COUNT"`

    sleep 1
    infoPrint 1 $INFO $TIME $LOG "Disabling camera"
    caput $_cameraPv":Acquisition" 0 >> /dev/null

    # Save images to disk (may take a long time)
    infoPrint 1 $INFO $TIME $LOG "Saving images to disk..."
    caput $_cameraPv":TIFF:WriteFile" 1 >> /dev/null
    doneWrite=`caget -t $_cameraPv":TIFF:WriteFile_RBV"`
    while [ $doneWrite == 1 ]; do
	sleep 1
	infoPrint 1 $INFO $TIME $LOG "Still saving files..."
	doneWrite=`caget -t $_cameraPv":TIFF:WriteFile_RBV"`
    done

    # Make sure the files show up in the destination directory
    numFiles=`ls -l *.tif | wc -l`
    while [ $numCaptured -gt $numFiles ]; do
	sleep 1
	numFiles=`ls -l *.tif | wc -l`
    done

    infoPrint 1 $INFO $TIME $LOG "Images saved."

    elapsed=`caget -t $_cameraPv:TSS_ELAPSED_MIN`
    egu=`caget -t $_cameraPv:TSS_ELAPSED_MIN.EGU`
    infoPrint 1 $INFO $TIME $LOG "Elapsed min: $elapsed $egu"
    elapsed=`caget -t $_cameraPv:TSS_ELAPSED_MAX`
    infoPrint 1 $INFO $TIME $LOG "Elapsed max: $elapsed $egu"
    infoPrint 1 $INFO $TIME $LOG "Lost before: $lostImagesBefore"
    infoPrint 1 $INFO $TIME $LOG "Lost after: $lostImagesAfter"
    lostImages=`expr $lostImagesAfter - $lostImagesBefore`
    infoPrint 1 $INFO $TIME $LOG "Lost total: $lostImages"
}

#
# Clean up after test
# - Enable camera
#
function cleanUpTest {
    popd >& /dev/null
    if (( _checkOnly < 1 )); then
	pv=$_cameraPv":Acquisition"
	caput $pv 1 > /dev/null
    fi
}

#
# Extract the PulseId information from the image files.
#
# The PulseId is the lower 17 bits in the field named 65003.
# The tiffinfo command prints out all image information.
# The *.ids output file has on each line the image number (starting at 1)
# followed by a space and the PulseId.
# The *.diffs output file has the difference between consecutive
# PulseIds - file format is the same.
#
# An array of all PulseIds is saved in _ids for latter pattern matching test,
# the number of PulseIds is in _numIds
# 
function extractPulseIds {
    idFile=$_testFileName.ids
    diffFile=$_testFileName.diff

    lastPulseId=132000

    if (( _checkOnly < 1 )); then
	infoPrint 1 $INFO $TIME $BOTH "Extracting PulseId information from images"
	i=1
	for f in $_testFileName_*.tif; do
	    timestamp=`tiffinfo $f |& grep Tag | grep "65003:" | cut -d":" -f2`
	    pulseId=`python -c "print ($timestamp & 131071)"`
	    echo $i" "$pulseId >> $idFile
	    
    	    # Calculate difference between PulseIds
	    if (( lastPulseId < 132000 )); then
		diff=`expr $pulseId - $lastPulseId`
		echo `expr $i - 1`" "$diff >> $diffFile
	    fi
	    lastPulseId=$pulseId
	    
	    _ids[i]=$pulseId
	    _numIds=$i
	    i=`expr $i + 1`
	done

        # Create .jpg plot of PulseIds (y-axis) and image count (x-axis)
	echo "set xlabel \"Image Counter\"
              set ylabel \"PulseId\"
              set term postscript
              set title \"PulseId\"
              set obj 1 rectangle behind from screen 0,0 to screen 1,1
              set output \"$idFile.png\"
              set datafile missing \"131071\"
              plot \"$idFile\" with lines" > sample.gp && gnuplot sample.gp >& /dev/null

	convert -rotate 90 $idFile.{png,jpg}
	\rm $idFile.png

        # Create .jpg plot of PulseId differences (y-axis) and image count (x-axis)
        echo "set xlabel \"Image Counter\"
              set ylabel \"PulseId Diff\"
              set term postscript
              set title \"PulseId Differences\"
              set obj 1 rectangle behind from screen 0,0 to screen 1,1
              set output \"$diffFile.png\"
              plot \"$diffFile\" with lines" > sample.gp && gnuplot sample.gp >& /dev/null

	convert -rotate 90 $diffFile.{png,jpg}
	\rm $diffFile.png
	\rm sample.gp
	infoPrint 1 $INFO $TIME $BOTH "Done extracting PulseId information from images"
    else
	_numIds=`wc -l $idFile | cut -d" " -f1`
	infoPrint 1 $INFO $TIME $LOG "Found $_numIds PulseIds"
	for (( i=1; i<=$_numIds; i++ )); do
	    _ids[i]=`grep ^"$i " $idFile | cut -d" " -f 2`
	done
   fi
}

#
# Extract the mean pixel intesity value from each image and
# produce an output file *.avg.
#
# Each line from the 'identify' command looks like this:
#     mean: 759.776 (0.0115934)
#
# The first 6 characters after the '(' are extracted as the image mean
# intensity.
#
# All means are saved in the _means array, number of elements is in _numMeans
#
function extractMeanIntensities {
    meansFile=$_testFileName.avg

    if (( _checkOnly < 1 )); then
	infoPrint 1 $INFO $TIME $BOTH "Extracting intensity average information from images"
	i=1
	for f in $_testFileName_*.tif; do
	    line=`identify -verbose $f |& grep mean`
	    avg=`echo $line | sed 's/^.*(//;s/)$//'`
	    re='^[0-9]+\.?[0-9]+$'
	    if ! [[ $avg =~ $re ]] ; then
		infoPrint 1 $ERROR $TIME $BOTH "$avg is not a valid average"
		exit 1
	    fi
	    
	    if (( _checkOnly < 1 )); then
		echo $i" "$avg >> $meansFile
	    fi
	    _means[i]=$avg
	    _numMeans=$i
	    i=`expr $i + 1`
	done

        # Create .jpg plot of intensities (y-axis) and image count (x-axis)
        echo "set xlabel \"Image counter\"
              set ylabel \"LED On/Off\"
              set term postscript
              set title \"LED State\"
              set obj 1 rectangle behind from screen 0,0 to screen 1,1
              set output \"$meansFile.png\"
              plot \"$meansFile\" with lines" > sample.gp && gnuplot sample.gp >& /dev/null

	convert -rotate 90 $meansFile.{png,jpg}
	\rm $meansFile.png
	\rm sample.gp
	infoPrint 1 $INFO $TIME $BOTH "Done extracting intensity average information from images"
    else
	_numMeans=`wc -l $meansFile | cut -d" " -f1`
	infoPrint 1 $INFO $TIME $LOG "Found $_numMeans averages"
	for (( i=1; i<=$_numMeans; i++ )); do
	    _means[i]=`grep ^"$i " $meansFile | cut -d" " -f 2`
	done
    fi
}

#
# For a given PulseId and rate, find whether LED should be on/off
# 
function getExpectedState {
#    set -x
    pulseId=$1
    rate=$2

    state='-'
    case $rate in
	1)
	    if (( `expr $pulseId % 360` == 0 )); then
		state='X'
	    fi
	    ;;
	    

	5)
	    if (( `expr $pulseId % 72` == 0 )); then
		state='X'
	    fi
	    ;;

	10)
	    if (( `expr $pulseId % 36` == 0 )); then
		state='X'
	    fi
	    ;;
		
	30)
	    if (( `expr $pulseId % 12` == 0 )); then
		state='X'
	    fi
	    ;;
		
	40)
	    if (( `expr $pulseId % 9` == 0 )); then
		state='X'
	    fi
	    ;;
		
	60)
	    if (( `expr $pulseId % 2` == 0 )); then
		state='X'
	    fi
	    ;;	
    esac
#    set +x
    echo $state
}

#
# Extract the PulseIds and mean intensity averages.
# number of averages and PulseIds must match
#
function checkImages {
    extractPulseIds
    extractMeanIntensities

    if [ $_numIds != $_numMeans ]; then
	infoPrint 1 $ERROR $TIME $BOTH "Found $_numIds pulseIds, and $_numMeans average intensities, exiting test..."
	exit 1
    else
	infoPrint 1 $INFO $TIME $BOTH "Found $_numIds images"
    fi
}

#
# Test whether the pattern of size _patternSize
# repeats _patternRepeat times.
#
# Return 0 if pattern does not repeat, 1 if it does
#
function tryPattern {
    next=`expr $_patternSize + 1`
    nextPattern=1
    failPattern=0
    patternCount=0
    doneTrying=0

    neededMeans=`echo "$_patternSize * ($_patternRepeat + 1)" | bc`
    if (( neededMeans > _numMeans )); then
	infoPrint 1 $ERROR $TIME $BOTH "Can't find pattern, not enough samples. Need $neededMeans, got only $_numMeans"
    else
	while (( doneTrying < 1 )); do
	    if (( next < _numMeans )); then
                # 1 if mean is smaller than pattern - window
		lessThan=`echo ${_means[next]}'<'${_patternMin[nextPattern]} | bc -l`
	
                # 1 if mean is greater than pattern + window
		greaterThan=`echo ${_means[next]}'>'${_patternMax[nextPattern]} | bc -l`

		if [[ $greaterThan -eq "1" ]]; then
		    failPattern=1
		elif [[ $lessThan -eq "1" ]]; then
		    failPattern=1
		fi
	    else
		infoPrint 1 3 1 2 "Trying to access sample $next, maximum is $_numMeans"
		failPattern=1
	    fi

	    # Next average
	    next=`expr $next + 1`

   	    # Next pattern
	    nextPattern=`expr $nextPattern + 1`
	    if (( nextPattern > _patternSize )); then
		nextPattern=1
		patternCount=`expr $patternCount + 1`
	    fi
	    
	    # Have we found the pattern or failed aleady?
	    if (( patternCount > _patternRepeat )); then
		doneTrying=1
	    fi
	    if (( failPattern > 0 )); then
		doneTrying=1
	    fi
	    
	done
	
	if (( failPattern == 0 )); then
	    _patternFound=1
	fi
    fi
}

#
# Asks user to select which mean average corresponds to states
#
#   LED1 LED2
# 1 On   On
# 2 On   Off
# 3 Off  On
# 4 Off  Off
#
# The expected mean average +/- the acceptance window are
# saved to the variables _expectedPatternMin/_expectedPatternMax
#
function identifyPattern {
    patternString="0 "
    for (( i=1; i<=_patternSize; i++ )); do
	patternString="$patternString ${_means[i]}"
    done

    i=1

    # State "XX"
    led1State[1]="On"
    led2State[1]="On"
    _stateString[1]="XX"

    # State "X-"
    led1State[2]="On"
    led2State[2]="Off"
    _stateString[2]="X-"

    # State "-X"
    led1State[3]="Off"
    led2State[3]="On"
    _stateString[3]="-X"

    # State "--"
    led1State[4]="Off"
    led2State[4]="Off"
    _stateString[4]="--"

    for (( i=1; i<5; i++ )); do
	question="Select which average corresponds to LED1="${led1State[i]}" and LED2="${led2State[i]}
	selection=$(zenity --window-icon=$f2 --list $patternString --column="" --text="$question" --title="Choose LEDs State")
	echo $selection

	_expectedPatternMin[i]=`echo $selection - $_meanWindow | bc -l`
	_expectedPatternMax[i]=`echo $selection + $_meanWindow | bc -l`
    done
}

#
# Configure LED state
# $1 - LED1 state: 1=On 0=Off
# $2 - LED2 state: 1=On 0=Off
#
function configurePattern {
    if (( _identifyPattern == 2 )); then
#    pv=$_evrPv:"EVENT2CTRL.ENAB"
	pv=$_evrPv":EVENT1CTRL.OUT1"
	caput $pv $1 >> /dev/null

#    pv=$_evrPv:"EVENT3CTRL.ENAB"
	pv=$_evrPv":EVENT1CTRL.OUT2"
	caput $pv $2 >> /dev/null
    fi
}

#
# Get one single test image for pattern identification
#
# $1 - index for the _expectedPatternMin/Max array
# $2 - LED1 "On" or "Off" string
# $3 - LED2 "On" or "Off" string
#
function acquireSingleImage {
    infoPrint 1 $INFO $TIME $LOG "Running pattern identification [$2 $3]"
    
    patternFileName="Pattern-LED1-"$2"-LED2-"$3
    if (( _identifyPattern == 2 )); then
	infoPrint 1 $INFO $TIME $LOG "Setting up pattern"

        # Make sure camera is taking data
	checkCamera

        # Setup TIFF plugin parameters
	caput -S $_cameraPv":TIFF:FilePath" $_localIOCDir"/Pattern" >> /dev/null
	caput -S $_cameraPv":TIFF:FileName" $patternFileName >> /dev/null
	caput $_cameraPv":TIFF:FileNumber" 0 >> /dev/null
	caput -S $_cameraPv":TIFF:FileTemplate" "%s%s.tif" >> /dev/null
	caput $_cameraPv":TIFF:NumCapture" 1 >> /dev/null
	caput $_cameraPv":TIFF:FileWriteMode" 1 >> /dev/null
	caput $_cameraPv":TIFF:EnableCallbacks" 1 >> /dev/null

        # Enable TIFF capture
	caput $_cameraPv":TIFF:Capture" 1 >> /dev/null

        # Wait capture to be done
	pv=$_cameraPv":TIFF:Capture_RBV"
	doneCapture=`caget -nt $pv`
	infoPrint 1 $INFO $TIME $LOG "doneCapture=$doneCapture"
	while [ $doneCapture == 1 ]; do
	    sleep 1
	    doneCapture=`caget -nt $pv`
	    infoPrint 1 $INFO $TIME $LOG "doneCapture=$doneCapture"
	done
	numCaptured=`caget -nt $_cameraPv":TIFF:NumCaptured_RBV"`

	infoPrint 1 $INFO $TIME $LOG "Captured "$numCaptured" sample images"
	
	sleep 1
#    infoPrint 1 $INFO $TIME $LOG "Disabling camera"
#    caput $_cameraPv":Acquisition" 0 >> /dev/null

        # Save images to disk (may take a long time)
	infoPrint 1 $INFO $TIME $LOG "Saving image to disk..."
	caput $_cameraPv":TIFF:WriteFile" 1 >> /dev/null
	doneWrite=`caget -t $_cameraPv":TIFF:WriteFile_RBV"`
	while [ $doneWrite == 1 ]; do
	    sleep 1
	    infoPrint 1 $INFO $TIME $LOG "Still saving files..."
	    doneWrite=`caget -t $_cameraPv":TIFF:WriteFile_RBV"`
	done
    fi

    # Make sure the files show up in the destination directory
    patternFileName=$patternFileName".tif"
    while [ ! -e $patternFileName ]; do
	sleep 1
    done
    sleep 1


    if (( _identifyPattern == 2 )); then
	infoPrint 1 $INFO $TIME $LOG "Image for Pattern $2 $3 saved (File $patternFileName)."
    else
	infoPrint 1 $INFO $TIME $LOG "Reading image for Pattern $2 $3 previously saved (File $patternFileName)."
    fi

    infoPrint 1 $INFO $TIME $LOG "Extracting intensity average"

    line=`identify -verbose $patternFileName |& grep mean`
    avg=`echo $line | sed 's/^.*(//;s/)$//'`
    re='^[0-9]+\.?[0-9]+$'
    if ! [[ $avg =~ $re ]] ; then
	infoPrint 1 $ERROR $TIME $BOTH "$avg is not a valid average for Pattern $2 $3"
	exit 1
    fi

    infoPrint 1 $INFO $TIME $BOTH "Found intensity $avg for Pattern $2 $3"
    _expectedPatternMin[$1]=`echo $avg - $_meanWindow | bc -l`
    _expectedPatternMax[$1]=`echo $avg + $_meanWindow | bc -l`
}

#
# Also asks user to select which mean average corresponds to states
#
#   LED1 LED2
# 1 On   On
# 2 On   Off
# 3 Off  On
# 4 Off  Off
#
# But in this function the camera and LEDs are configured to 
# generate the image and average automaticaly without user
# input
#
function identifyPatternAutomatic {
    # Go to local test location
    pushd $_localDir >& /dev/null

    localTestDir=$_localDir"/Pattern"

    # Create test directory (if -Z option)
    if (( _identifyPattern == 2 )); then
	if [ -d $localTestDir ]; then
	    infoPrint 1 $INFO $NOTIME $OUT "Local test directory exists ($localTestDir), removing..."
	    rm -rf $localTestDir
	fi
	
	mkdir $localTestDir
	if [ "$?" == 1 ]; then
	    infoPrint 1 $ERROR $NOTIME $OUT "Failed to create test directory, exiting tests..."
	    exit 1
	fi
    else
	if [ ! -d $localTestDir ]; then
	    infoPrint 1 $ERROR $NOTIME $OUT "Local Pattern directory missing, please use -Z to create it..."
	    exit 1
	fi
    fi
    cd $localTestDir
    
    _logFile=$localTestDir"/Pattern.log"

    if (( _identifyPattern == 2 )); then
	infoPrint 1 $INFO $NOTIME $BOTH "Generating patterns to identify images"

        # Set camera rate to 30 Hz
        pv=$_evrPv:"EVENT1CTRL.ENM"
	cameraEventSave=`caget -t $pv`
	cameraEvent=142
	caput $pv $cameraEvent >> /dev/null
	pv=$_evrPv":EVENT1CTRL.OUT0"
	caput $pv 0 >> /dev/null
	caput $pv 1 >> /dev/null
	pv=$_evrPv":EVENT1CTRL.VME"
	caput $pv 0 >> /dev/null
	caput $pv 1 >> /dev/null
	infoPrint 1 $INFO $NOTIME $BOTH "Changing camera event from $cameraEventSave to $cameraEvent (30 Hz)"

        # Disable LED events for this, LEDs will be driven
        # by the same camera event
	pv=$_evrPv":EVENT2CTRL.ENAB"
	caput $pv 0 >> /dev/null
	pv=$_evrPv":EVENT3CTRL.ENAB"
	caput $pv 0 >> /dev/null
    fi

    configurePattern 1 1
    _stateString[1]="XX"
    acquireSingleImage 1 "On" "On"
    
    configurePattern 1 0
    _stateString[2]="X-"
    acquireSingleImage 2 "On" "Off"

    configurePattern 0 1
    _stateString[3]="-X"
    acquireSingleImage 3 "Off" "On"

    configurePattern 0 0
    _stateString[4]="--"
    acquireSingleImage 4 "Off" "Off"

    # Restore camera event
    if (( _identifyPattern == 2 )); then
	pv=$_evrPv:"EVENT1CTRL.ENM"
	caput $pv $cameraEventSave >> /dev/null
	pv=$_evrPv":EVENT1CTRL.OUT0"
	caput $pv 0 >> /dev/null
	caput $pv 1 >> /dev/null
	pv=$_evrPv":EVENT1CTRL.VME"
	caput $pv 0 >> /dev/null
	caput $pv 1 >> /dev/null
	infoPrint 1 $INFO $NOTIME $BOTH "Restoring camera event to $cameraEventSave"

        # Disable OUT1/OUT2 for camera event
	configurePattern 0 0

        # Reenable LED events
	pv=$_evrPv":EVENT2CTRL.ENAB"
	caput $pv 1 >> /dev/null
	pv=$_evrPv":EVENT3CTRL.ENAB"
	caput $pv 1 >> /dev/null
    fi
    popd >& /dev/null
}

#
# Check if a given average (_means[i]) is within the _expectedPatternMin[]
# and the _expectedPatternMax[] values
#
function getStateBasedOnAverage {
    gotState=0
    for (( k=1; k<5; k++ )); do
        # 1 if mean is smaller than pattern - window
	lessThanMax=`echo ${_means[i]}'<'${_expectedPatternMax[k]} | bc -l`
	
        # 1 if mean is greater than pattern + window
	greaterThanMin=`echo ${_means[i]}'>'${_expectedPatternMin[k]} | bc -l`
	    
	if [[ $greaterThanMin -eq "1" ]]; then
	    if [[ $lessThanMax -eq "1" ]]; then
		gotState=$k
	    fi
	fi
    done

    if (( gotState > 0 )); then
	_foundState=${_stateString[gotState]}
    else
	_foundState="??"
    fi
}

#
# Set _patternFound to 1 if pattern has been found, or 0 if
# there is no pattern.
#
function findPattern {
    done=0

    # First fill out min/max for test patterns
    # up to _maxPatternSize
    i=1
    while (( i < _maxPatternSize+1 )); do
	_patternMin[i]=`echo ${_means[i]} - $_meanWindow | bc -l`
	_patternMax[i]=`echo ${_means[i]} + $_meanWindow | bc -l`
	i=`expr $i + 1`
    done

    _patternSize=`expr $_maxPatternSize + 1`
    while (( done < 1 )); do
	_patternSize=`expr $_patternSize - 1`

	_patternFound=0
	tryPattern

	if (( _patternFound > 0 )); then
	    done=1
	fi

	if (( _patternSize == 1 )); then
	    done=1
	fi
    done

    if (( _patternFound < 1 )); then
	infoPrint 1 $ERROR $TIME $BOTH "No pattern found"
    else
	infoPrint 1 $INFO $NOTIME $BOTH "Found pattern, repeating first $_patternSize elements"
	echo -n "INFO: " >> $_logFile
	i=1
	while (( i < _patternSize + 1 )); do
	    echo -n "${_means[i]} " >> $_logFile
	    i=`expr $i + 1`
	done
	echo "" >> $_logFile
	if (( _identifyPattern > 0 )); then
	    if (( _getPattern < 1 )); then # Ask user about patterns only once if there are multiple tests
		if (( _identifyPattern == 1 )); then
		    identifyPattern
		fi
		_getPattern=1
	    fi
	fi
    fi
}

function resyncPattern {
    gap=`expr ${_ids[i]} - $lastValidPulseId`
    currentId=$lastValidPulseId

    while (( currentId < ${_ids[i]} )); do
	currentId=`expr $currentId + $_idDiff`

#	echo "GAP: $currentId ${pattern[nextPattern]} ($nextPattern)"

	if (( currentId < ${_ids[i]} )); then
	    infoPrint $_debugPrint $DEBUG $NOTIME $BOTH "Skipping PulseId=$currentId, pattern=${_means[nextPattern]}"
	    missingImages=`expr $missingImages + 1`
	    nextPattern=`expr $nextPattern + 1`
	    if (( nextPattern > $_patternSize )); then
		nextPattern=1
	    fi
	fi
    done
}

#
# Check if all data follows the patten (_patternMin/_patternMax).
#
function verifyData {
    i=1
    done=0
    match=1
    nextPattern=1
    invalidId=131071
    lastValidPulseId=132000
    gapCount=0
    missingImages=0

    while (( done < 1 )); do
	if (( ${_ids[i]} == invalidId )); then
	    infoPrint 1 $WARN $NOTIME $BOTH "Found invalid Id, skipping..."
	else
	    if (( lastValidPulseId < 132000 )); then
		# nextId is the next expected PulseId, which is the last good
                # PulseId plus the idDiff
		nextId=`expr $lastValidPulseId + $_idDiff`
		infoPrint $_debugPrint $DEBUG $NOTIME $BOTH "Next expected PulseId=$nextId (lastGoodId=$lastValidPulseId)"

		# If current it is greater than the expected nextId, then
                # we have missing images
		if (( ${_ids[i]} > nextId )); then
		    infoPrint 1 $WARN $TIME $BOTH "PulseIds jumped from $lastValidPulseId to ${_ids[i]}"
		    resyncPattern
		    gapCount=`expr $gapCount + 1`
		fi		
	    fi

            # 1 if mean is smaller than pattern - window
	    lessThan=`echo ${_means[i]}'<'${_patternMin[nextPattern]} | bc -l`
	
            # 1 if mean is greater than pattern + window
	    greaterThan=`echo ${_means[i]}'>'${_patternMax[nextPattern]} | bc -l`
	    
	    if [[ $greaterThan -eq "1" ]]; then
		infoPrint 1 $WARN $NOTIME $BOTH "[$i] Value ${_means[i]} for PulseId ${_ids[i]} does not match pattern ${_means[nextPattern]}"
		match=0
		done=1
	    elif [[ $lessThan -eq "1" ]]; then
		infoPrint 1 $WARN $NOTIME $BOTH "[$i] Value ${_means[i]} for PulseId ${_ids[i]} does not match pattern ${_means[nextPattern]}"
		match=0
		done=1
	    fi
	    
	    # Save last good PulseId, in case synchronization is lost
	    lastValidPulseId=${_ids[i]}

	    # Check if LED states are the expected based on the PulseId and 
	    # average intensity
	    _led1State=$(getExpectedState $lastValidPulseId $_led1Rate)
	    _led2State=$(getExpectedState $lastValidPulseId $_led2Rate)

	    expectedState=$_led1State$_led2State
	    if (( _identifyPattern > 0 )); then
		getStateBasedOnAverage

		if [ "$_foundState" == "??" ]; then
		    infoPrint 1 $ERROR $NOTIME $BOTH "Failed to identify LED state for the intensity ${_means[nextPattern]}"
		else
		    if [ "$expectedState" == "$_foundState" ]; then
			infoPrint _debugPrint $DEBUG $NOTIME $BOTH "[$i] PulseId=$lastValidPulseId: PulseId=[$expectedState] Image=[$_foundState], avg=${_means[nextPattern]}"
		    else
			infoPrint 1 $ERROR $NOTIME $BOTH "[$i] PulseId=$lastValidPulseId: PulseId=[$expectedState] Image=[$_foundState], avg=${_means[nextPattern]} (MISMATCH)"
		    fi
		fi

#		infoPrint $_debugPrint $DEBUG $NOTIME $BOTH "[$i] PulseId=$lastValidPulseId: pattern=${_means[nextPattern]} [$_led1State$_led2State] [$_foundState]"
	    fi

   	    # Next pattern
	    nextPattern=`expr $nextPattern + 1`
	    if (( nextPattern > _patternSize )); then
		nextPattern=1
	    fi
	    infoPrint $_debugPrint $DEBUG $NOTIME $BOTH "nextPattern=$nextPattern"
	fi
	i=`expr $i + 1`
	if (( i > _numMeans )); then
	    done=1
	fi
    done

    if (( match < 1 )); then
	infoPrint 1 $ERROR $NOTIME $BOTH "Data does not follow pattern"
    else
	infoPrint 1 $INFO $NOTIME $BOTH "All data matches the pattern"
	if (( missingImages > 0 )); then
	    infoPrint 1 $WARN $NOTIME $BOTH "There are $missingImages missing images"
	fi
    fi

}

#
#
#
function checkPattern {
    findPattern
    if (( _patternFound > 0 )); then
	verifyData
    fi
}

#
# Run tests $_numTest times
#
function runTests {
    if (( _identifyPattern > 0 )); then
	if (( _identifyPattern >= 2 )); then
	    identifyPatternAutomatic
	fi
    fi

    for _testCount in `seq 1 $_numTests`; do
	echo `date +'[%D %H:%M:%S]'` "Running test #$_testCount"
	prepareTest
	if (( _checkOnly < 1 )); then
	    acquireImages
	fi
	checkImages
	if (( _patternEnabled > 0 )); then
	    checkPattern
	fi
	cleanUpTest
	sleep 1
    done
}

#=== MAIN ===

# Global variables used all over the place
# (note: all bash variables are global anyway, unless declared local)
_verbose=0          # -v option
_testFileName="LED" # -f option
_testDir="test"     # -t option
_localDir=""        # -d option
_localIOCDir=""     # -D option
_numImages=100      # -n option
_numTests=1         # -r option
_cameraPv=""        # -c option
_evrPv=""           # -e option
_stopCamera=0       # -s option
_idDiff=3           # -i option
_patternEnabled=0   # -p option
_patternRepeat=4    # -x option
_meanWindow=0.0005  # -w option
_checkOnly=0        # -k option
_identifyPattern=0  # -z option (or -Z option, or -Y option)
_maxPatternSize=15  # -S option
_debugPrint=0       # -g option
_setRate=0          # -R set camera and LED rates
_rate=0
_led1Rate=0         # -1 option (with -k only)
_led2Rate=0         # -2 option (with -k only)
_getPattern=0

while getopts ":vt:d:D::n:hc:e:s:f:r:i:pw:x:kgR:1:2:zZYS:" opt; do
    case $opt in
	v)
	    _verbose=1
	    ;;
	t)
	    _testDir=$OPTARG
	    ;;
	f)
	    _testFileName=$OPTARG
	    ;;
	n)
	    _numImages=`expr $OPTARG`
	    isNumber $_numImages
	    ;;
	S)
	    _maxPatternSize=`expr $OPTARG`
	    isNumber $_maxPatternSize
	    ;;
	r)
	    _numTests=`expr $OPTARG`
	    isNumber $_numTests
	    ;;
	1)
	    _led1Rate=`expr $OPTARG`
	    isNumber $_led1Rate
	    ;;
	2)
	    _led2Rate=`expr $OPTARG`
	    isNumber $_led2Rate
	    ;;
	d)
	    _localDir=$OPTARG
	    ;;
	D)
	    _localIOCDir=$OPTARG
	    ;;
	c)
	    _cameraPv=$OPTARG
	    ;;
	e)
	    _evrPv=$OPTARG
	    ;;
	s)
	    _stopCamera=$OPTARG
	    isNumber $_stopCamera
	    ;;
	w)
	    _meanWindow=$OPTARG
	    isFloatNumber $_meanWindow
	    ;;
	i)
	    _idDiff=$OPTARG
	    isNumber $_idDiff
	    ;;
	p)
	    _patternEnabled=1
	    ;;
	z)
	    _identifyPattern=1
	    ;;
	Z)
	    _identifyPattern=2
	    # -Z requires -e option
	    # -Z requires -c opt
	    # -Z requires -D opt
	    ;;
	Y)
	    _identifyPattern=3
	    _evrPv="(-e not needed with -Y)"
	    _cameraPv="(-c not needed with -Y)"
	    _localIOCDir="(-D not needed with -Y)"
	    ;;
	g)
	    _debugPrint=1
	    ;;
	k)
	    _checkOnly=1
	    # -k option requires -p option
	    _patternEnabled=1
	    ;;
	R)
	    _setRate=1
	    _rate=$OPTARG
	    _localIOCDir="not needed with -k option"
	    _localDir="not needed with -k option"
	    isNumber $_rate
	    ;;
	x)
	    _patternRepeat=`expr $OPTARG`
	    isNumber $_patternRepeat
	    ;;
	h)
	    printUsage
	    exit 1
	    ;;
	\?)
    	    echo "Invalid option: -$OPTARG" >&2
	    ;;
	:)
	    echo "Option -$OPTARG requires an argument." >&2
	    exit 1
	    ;;
    esac
done

checkRequiredParameters

if (( _setRate > 0 )); then
    configureEvr
    exit 0
fi

if (( _verbose > 0 )); then
    printConfiguration
fi

runTests