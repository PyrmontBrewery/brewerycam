#!/bin/bash

# Pyrmont Brewery Cam

WEBCAM=/dev/video2

# Comment this if want to rebuild the Docker image
IMAGE_STATE=$(docker images -q brewerycam_raspi:latest 2> /dev/null)

# Comment this if want to restart the Docker container (docker rm brewerycam_raspi)
RUN_STATE=$(docker ps -qf "ancestor=brewerycam_raspi")

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
    docker run --rm --name brewerycam_raspi --cap-add sys_ptrace -p127.0.0.1:2222:22 -d -t -v $WEBCAM:$WEBCAM -v "$HERE:/host" -v "/tmp:/tmp" brewerycam_raspi
    sleep 2

    # update running state image id to be the newly created Docker container
    RUN_STATE=$(docker ps -qf "ancestor=brewerycam_raspi")

    ssh-keygen -f "$HOME/.ssh/known_hosts" -R [localhost]:2222
  fi

  #echo "Rejoining Pyrmont Brewery Cam Raspberry Pi container $RUN_STATE"
  #docker exec -i -t brewerycam_raspi /bin/bash -c "cd /host; /bin/bash"
  docker exec -i -t brewerycam_raspi /bin/bash -c "echo 'LD_LIBRARY_PATH=/root/brewerycam/lib /root/brewerycam/bin/ffmpeg' > /usr/bin/ffmpeg; chmod +x /usr/bin/ffmpeg; exit"
  docker exec -i -t brewerycam_raspi /bin/bash -c "echo 'LD_LIBRARY_PATH=/root/brewerycam/lib /root/brewerycam/bin/ffprobe' > /usr/bin/ffmpeg; chmod +x /usr/bin/ffprobe; exit"
  docker exec -i -t brewerycam_raspi /bin/bash
}

tail -f $ENCODER_LOG &

fetch_opencv_deps
create_docker_image
run_docker_container