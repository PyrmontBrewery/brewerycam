#!/bin/bash

# Pyrmont Brewery Cam

# Kev's build script
HERE=$PWD

IMAGE_STATE=$(docker images -q brewerycam_raspi:latest 2> /dev/null)
RUN_STATE=$(docker ps -qf "ancestor=brewerycam_raspi")

# kill any other senders
script_name=${BASH_SOURCE[0]}
for pid in $(pidof -x $script_name); do
    if [ $pid != $$ ]; then
        kill -9 $pid
    fi
done

WATCHDOG_CONNECT_SECS=60 # needs to be at least as long as connection timeout  + time to start streaming + one re-attempt

FFMPEG=$USER_HOME/FFmpeg/ffmpeg

touch $ENCODER_LOG

echo "RESTARTED ($(date))" >>$ENCODER_LOG

# lookup table associative arrays which map Ethernet MAC address to select input type and SRT endpoint
declare -A map_macs_address_to_names
declare -A map_macs_address_to_inputs
declare -A map_macs_address_to_bitrates
declare -A map_macs_address_to_endpoint
declare -A map_macs_address_to_codec

# r01se camera names (max 21 chars)
map_macs_address_to_names+=(
  ["dca63211b9a6"]="PyrmontBrewery"
)

map_macs_address_to_inputs+=(
  ["dca63211b9a6"]="-re -f lavfi -i testsrc -t 30 -video_size 1920x1080 -pix_fmt yuv420p"
)

map_macs_address_to_bitrates+=(
  ["dca63211b9a6"]="2M"
)

# optionally turn hardware encoders on depedning on device capabilities and architecture
map_macs_address_to_codec+=(
       ["default"]="-c:v libx264 -pix_fmt yuv420p -preset superfast -tune zerolatency -movflags frag_keyframe+empty_moov -x264-params keyint=15:min-keyint=15:sps-id=1 -keyint_min 15 -ts mono2abs "
)

map_macs_address_to_endpoint+=(
  ["dca63211b9a6"]="-pkt_size 1316 -flush_packets 0 -f mpegts srt://pyrmontbrewery.com.au:24005?pkt_size=1316&streamid=brewerycam"
)

DEST_ENDPOINT=${map_macs_address_to_endpoint["default"]}
[ ${map_macs_address_to_endpoint[$THIS_MAC]+a} ] && DEST_ENDPOINT=${map_macs_address_to_endpoint[$THIS_MAC]}
SOURCE_CAPTURE=${map_macs_address_to_inputs["default"]}
[ ${map_macs_address_to_inputs[$THIS_MAC]+a} ] && SOURCE_CAPTURE=${map_macs_address_to_inputs[$THIS_MAC]}
FFMPEG_VID_BITRATE=${map_macs_address_to_bitrates["default"]}
[ ${map_macs_address_to_bitrates[$THIS_MAC]+a} ] && FFMPEG_VID_BITRATE=${map_macs_address_to_bitrates[$THIS_MAC]}
FFMPEG_VID_CODEC=${map_macs_address_to_codec["default"]}
[ ${map_macs_address_to_codec[$THIS_MAC]+a} ] && FFMPEG_VID_CODEC=${map_macs_address_to_codec[$THIS_MAC]}
CAMERA_NAME=${map_macs_address_to_names["default"]}
[ ${map_macs_address_to_names[$THIS_MAC]+a} ] && CAMERA_NAME=${map_macs_address_to_names[$THIS_MAC]}

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

  if [ -f "$USER_HOME/testcard" ]; then
    echo "$(date +"%Y%m%d_%H%M") startCapture: Encoding test card as $CAMERA_NAME to $DEST_ENDPOINT at rate $FFMPEG_VID_BITRATE" >> $WATCHDOG_LOG
    rm -f "$USER_HOME/testcard"  # revert back to normal camera if stream is reset or device is rebooted
    SOURCE_CAPTURE=${map_macs_address_to_inputs["testcard"]}
  fi

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
    $FFMPEG_OUTPUT \
    > /dev/null 2> $ENCODER_LOG &

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

  echo "$(date +"%Y%m%d_%H%M") startWatchdog: Starting... USER=${WHOAMI} VERSION=${VERSION}" >$WATCHDOG_LOG

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
      echo "$(date +"%Y%m%d_%H%M") FFmpeg process has stopped or didn't start :-(" >>$WATCHDOG_LOG
    fi

    if [ "$THIS_UPDATE" == "$LAST_UPDATE" ]; then
      echo "$(date +"%Y%m%d_%H%M") Something seems wrong going to retry capture..." >>$WATCHDOG_LOG

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

fetch_opencv_deps () {
  # Pull in deps ZBar 0.10
  if [ ! -d "zbar" ]; then
    git clone https://github.com/PyrmontBrewery/zbar.git --depth 1 zbar
  fi

  # ImageMagic (v6 not v7)
  if [ ! -d "imagemagick" ]; then
    git clone https://github.com/PyrmontBrewery/ImageMagick6.git  --depth 1 imagemagick
  fi

  # OpenCV
  if [ ! -d "opencv" ]; then
    git clone https://github.com/PyrmontBrewery/opencv.git --depth 1 opencv
    git clone https://github.com/PyrmontBrewery/opencv_contrib.git --depth 1 opencv_contrib
  fi

  # DMTX
  if [ ! -d "libdmtx" ]; then
    git clone https://github.com/PyrmontBrewery/libdmtx.git --depth 1 libdmtx
  fi
}

create_docker_image () {
  if [[ "$IMAGE_STATE" == "" ]]; then
    docker build -t brewerycam_raspi .
  fi
}

run_docker_container () {
  if [[ "$RUN_STATE" == "" ]]; then
    echo "Spinning up new container from image brewerycam_raspi:latest ($IMAGE_STATE)"
    docker run --rm --name brewerycam_raspi --cap-add sys_ptrace -p127.0.0.1:2222:22 -d -t -v "$HERE:/host" -v "/tmp:/tmp" brewerycam_raspi
    sleep 2

    # update running state image id to be the newly created Docker container
    RUN_STATE=$(docker ps -qf "ancestor=brewerycam_raspi")

    ssh-keygen -f "$HOME/.ssh/known_hosts" -R [localhost]:2222
  fi

  echo "Rejoining Pyrmont Brewery Cam Raspberry Pi container $RUN_STATE"
  docker exec -i -t "$RUN_STATE" /bin/bash -c "cd /host; do /bin/bash"
}

fetch_opencv_deps
create_docker_image
run_docker_container

startWatchdog