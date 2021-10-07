#!/bin/bash

# Kev's build script
HERE=$PWD

IMAGE_STATE=$(docker images -q brewerycam:latest 2> /dev/null)
RUN_STATE=$(docker ps -qf "ancestor=brewerycam")

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
    docker build -t brewerycam .
  fi
}

run_docker_container () {
  if [[ "$RUN_STATE" == "" ]]; then
    echo "Spinning up new container from image brewerycam:latest ($IMAGE_STATE)"
    docker run --rm --name brewerycam --cap-add sys_ptrace -p127.0.0.1:2222:22 -d -t -v "$HERE:/host" -v "/tmp:/tmp" brewerycam
    sleep 2

    # update running state image id to be the newly created Docker container
    RUN_STATE=$(docker ps -qf "ancestor=brewerycam")

    ssh-keygen -f "$HOME/.ssh/known_hosts" -R [localhost]:2222
  fi

  echo "Rejoining Pyrmont Brewery Cam container $RUN_STATE"
  docker exec -i -t "$RUN_STATE" /bin/bash -c "cd /host; while true; do /bin/bash; done"
}

fetch_opencv_deps
create_docker_image
run_docker_container