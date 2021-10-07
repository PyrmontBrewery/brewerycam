#!/bin/bash

# Pyrmont Brewery Cam

# Kev's build script
HERE=$PWD
ENCODER_LOG=~/raspi_encoder.log

# kill any other senders
script_name=${BASH_SOURCE[0]}
for pid in $(pidof -x $script_name); do
    if [ $pid != $$ ]; then
        kill -9 $pid
    fi
done

WATCHDOG_CONNECT_SECS=60 # needs to be at least as long as connection timeout  + time to start streaming + one re-attempt

FFMPEG="/usr/bin/ffmpeg"

echo "RESTARTED ($(date))" >>$ENCODER_LOG

DEST_ENDPOINT="-pkt_size 1316 -flush_packets 0 -f mpegts srt://pyrmontbrewery.com.au:24005?pkt_size=1316&streamid=brewerycam"
SOURCE_CAPTURE="-re -f lavfi -i testsrc -t 30 -video_size 1920x1080 -pix_fmt yuv420p"
FFMPEG_VID_BITRATE="2M"
FFMPEG_VID_CODEC="-c:v libx264 -pix_fmt yuv420p -preset superfast -tune zerolatency -movflags frag_keyframe+empty_moov -x264-params keyint=15:min-keyint=15:sps-id=1 -keyint_min 15 -ts mono2abs "
CAMERA_NAME="PyrmontBrewery"

FFMPEG_OUTPUT=$DEST_ENDPOINT

FONTFILE=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf
FONTSIZE=54
BITC_OVERLAY_PREFIX="-filter_complex ${FFMPEG_VID_FILTER}format=yuv420p,setpts=(RTCTIME-RTCSTART)/(TB*1000000),scale=1920:1080,drawbox=y=(ih)-${FONTSIZE}*2-10:color=black@0.6:width=(${FONTSIZE}*13.5):height=${FONTSIZE}+${FONTSIZE}+20:t=fill,drawtext=fontfile=${FONTFILE}:fontsize=${FONTSIZE}:fontcolor=white:x=20:y=h-${FONTSIZE}*2:text="
BITC_OVERLAY_SUFFIX=":shadowx=3:shadowy=3:shadowcolor=black@0.7,drawtext=fontfile=${FONTFILE}:fontsize=${FONTSIZE}:fontcolor=white:x=20:y=h-${FONTSIZE}:text='%{localtime\:%d-%b-%Y_%X}':shadowx=3:shadowy=3:shadowcolor=black@0.7'"
BITC_OVERLAY=${BITC_OVERLAY_PREFIX}${CAMERA_NAME}${BITC_OVERLAY_SUFFIX}

# State flags
RESTART_CAPTURE=true
FLAGGED_HAS_STARTED=false

startCapture() {
  killCapture

  WATCHDOG_TIMEOUT=$WATCHDOG_CONNECT_SECS

  $FFMPEG \
    -y \
    -re -f v4l2 -framerate 20 -pixel_format mjpeg -video_size 2048x1536 -i /dev/video2 \
    $FFMPEG_VID_CODEC \
    -b:v $FFMPEG_VID_BITRATE \
    -maxrate $FFMPEG_VID_BITRATE \
    -bufsize 10M \
    ${BITC_OVERLAY} \
    -an \
    -r 20 \
    -g 20 \
    -refs 3 \
    -bf 0 \
    -flags +cgop \
    -sc_threshold 0 \
    -drop_pkts_on_overflow 1 \
    -attempt_recovery 1 \
    -recover_any_error 1 \
    -stimeout 10000000 \
    -reconnect 1 \
    -reconnect_at_eof 1 \
    -reconnect_streamed 1 \
    -reconnect_delay_max 2 \
    $FFMPEG_OUTPUT

  STILL_RUNNING="yes"
  FFMPEG_PID=$!
}

killCapture() {
  pkill ffmpeg
  pkill -9 ffmpeg
  rm -f /tmp/pipe
  FLAGGED_HAS_STARTED=false
  STILL_RUNNING="killed"

  sleep 2
}

# watchdog
startWatchdog() {
  local LAST_UPDATE
  local THIS_UPDATE

  echo "$(date +"%Y%m%d_%H%M") startWatchdog: Starting... USER=${WHOAMI} VERSION=${VERSION}" > $ENCODER_LOG

  while true; do
    THIS_UPDATE="notknown"
    LAST_UPDATE=$(stat -c %Z $ENCODER_LOG)
    if [ $RESTART_CAPTURE == true ]; then
      startCapture
      RESTART_CAPTURE=false
    fi

    # check process still running
    sleep $WATCHDOG_TIMEOUT

    if ps -p $FFMPEG_PID > /dev/null; then
      THIS_UPDATE=$(stat -c %Z $ENCODER_LOG)
    else
      STILL_RUNNING="stopped"
      WATCHDOG_TIMEOUT=$WATCHDOG_RETEST_RATE_SECS
      sleep $WATCHDOG_TIMEOUT
      THIS_UPDATE=$LAST_UPDATE
      echo "$(date +"%Y%m%d_%H%M") FFmpeg process has stopped or didn't start :-(" >>$ENCODER_LOG
    fi

    if [ "$THIS_UPDATE" == "$LAST_UPDATE" ]; then
      echo "$(date +"%Y%m%d_%H%M") Something seems wrong going to retry capture..." >>$ENCODER_LOG

      WATCHDOG_TIMEOUT=$WATCHDOG_RETEST_RATE_SECS
      RESTART_CAPTURE=true
    else
      if [ $FLAGGED_HAS_STARTED == false ]; then
        # ping health check to say we've been turned on
        FLAGGED_HAS_STARTED=true
      fi
    fi
  done
}

tail -f $ENCODER_LOG &

startWatchdog
