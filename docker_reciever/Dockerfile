FROM ubuntu:18.04 as brewerycam_baseline
MAINTAINER kevleyski

# Pyrmont Brewery

# Pull in build cross compiler tool dependencies using Advanced Package Tool
ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Australia/Sydney

# Kev's dev baseline
RUN set -x \
    && DEBIAN_FRONTEND=noninteractive apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get --fix-missing -y install tzdata wget curl autoconf automake build-essential libass-dev libfreetype6-dev \
                                            libsdl1.2-dev libtheora-dev libtool libva-dev libvdpau-dev libvorbis-dev libxcb1-dev libxcb-shm0-dev \
                                            libxcb-xfixes0-dev pkg-config texinfo zlib1g-dev gettext tcl libssl-dev cmake mercurial unzip git \
                                            libdrm-dev valgrind libpciaccess-dev libxslt1-dev geoip-bin libgeoip-dev zlib1g-dev libpcre3 libpcre3-dev \
                                            libbz2-dev ca-certificates libssl-dev nasm v4l-utils libv4l-dev gtk2.0 ssh gcc g++ gdb clang rsync \
                                            tar python libx264-dev vim strace

COPY . brewerycam

FROM brewerycam_baseline AS brewerycam_baseline_zbar

# ImageMagic (v6 - note _not_ v7)
RUN set -x \
    && cd /brewerycam/imagemagick \
    && ./configure --prefix=/usr --enable-shared \
    && make -j$(nproc) \
    && make install

# ZBar (apt install -y zbar-tools libzbar-dev)
# --build=x86_64-unknown-linux-gnu
RUN set -x \
    && cd /brewerycam/zbar \
    && CFLAGS="" ./configure --prefix=/usr --disable-dependency-tracking --without-python --without-qt --disable-video --without-gtk --without-x --enable-shared \
    && make -j$(nproc) \
    && make install

FROM brewerycam_baseline_zbar AS brewerycam_baseline_ffmpeg

# NVIDIA CUDA
#wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/cuda-ubuntu1804.pin
#sudo mv cuda-ubuntu1804.pin /etc/apt/preferences.d/cuda-repository-pin-600
#sudo apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/7fa2af80.pub
#sudo add-apt-repository "deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/ /"
#sudo apt-get update
#sudo apt-get -y install cuda

# libSRT (dependency /usr/bin/tclsh)
RUN set -x \
    && cd ~/brewerycam \
    && wget https://github.com/PyrmontBrewery/PATCHES-srt/archive/refs/tags/pyrmontbrewery_v1.4.4.tar.gz -O srt-pyrmontbrewery_v1.4.4.tar.gz \
    && tar xvf srt-pyrmontbrewery_v1.4.4.tar.gz && mv PATCHES-srt-pyrmontbrewery_v1.4.4 srt\
    && rm -f srt-pyrmontbrewery_v1.4.4.tar.gz \
    && cd srt \
    && PATH="$HOME/bin:$PATH" ./configure --prefix="/usr" --enable-static --enable-shared \
    && PATH="$HOME/bin:$PATH" make -j$(cat /proc/cpuinfo | grep processor | wc -l) \
    && make install \
    && make clean

RUN set -x \
    && cd /brewerycam/ \
    && wget https://github.com/PyrmontBrewery/PATCHES-FFmpeg/archive/refs/tags/pyrmontbrewery-v4.1.7.tar.gz -O ffmpeg-pyrmontbrewery_v4.1.7.tar.gz \
    && tar xvf ffmpeg-pyrmontbrewery_v4.1.7.tar.gz && mv PATCHES-FFmpeg-pyrmontbrewery-v4.1.7 ffmpeg \
    && rm -f ffmpeg-pyrmontbrewery_v4.1.7.tar.gz \
    && cd /brewerycam/ffmpeg \
    && ./configure \
      --prefix="/usr" \
      --extra-libs="-lpthread -lm" \
      --enable-gpl \
      --disable-libxcb \
      --disable-xlib \
      --disable-lzma \
      --disable-alsa \
      --enable-libx264 \
      --enable-nonfree \
      --enable-openssl \
      --enable-libfreetype \
      --disable-doc \
      --enable-libsrt \
      --enable-shared \
      --disable-static \
    && make -j$(nproc) \
    && make install \
    && make distclean \
    && hash -r

FROM brewerycam_baseline_ffmpeg AS brewerycam_baseline_opencv

# OpenCV
RUN set -x \
    && cd /brewerycam/opencv \
    && mkdir -p cmake-build-debug \
    && cd cmake-build-debug \
    && cmake -DCMAKE_BUILD_TYPE=RELEASE \
        -DCMAKE_INSTALL_PREFIX:PATH=/usr \
        -DOPENCV_GENERATE_PKGCONFIG=ON \
        -DBUILD_opencv_world=OFF \
        -DBUILD_opencv_gapi=OFF \
        -DBUILD_DOCS=OFF \
        -DWITH_NVCUVID=OFF \
        -DWITH_CUDA=ON \
        -DWITH_FFMPEG=ON  \
        -DBUILD_TESTS=OFF \
        -DBUILD_PERF_TESTS=OFF \
        -DBUILD_EXAMPLES=OFF \
        -DOPENCV_EXTRA_MODULES_PATH="/brewerycam/opencv_contrib/modules" .. \
    && make -j$(nproc) \
    && make install

# DataMatrix
RUN set -x \
    && cd /brewerycam/libdmtx \
    && bash ./autogen.sh \
    && ./configure --prefix=/usr \
    && make -j$(nproc) \
    && make install

### KJSL dependencies above are known to build to this point

FROM brewerycam_baseline_opencv AS brewerycam_clion

RUN ( \
    echo 'LogLevel DEBUG2'; \
    echo 'PermitRootLogin yes'; \
    echo 'PasswordAuthentication yes'; \
    echo 'Subsystem sftp /usr/lib/openssh/sftp-server'; \
  ) > /etc/ssh/sshd_config_test_clion \
  && mkdir /run/sshd

RUN useradd -m pyrmontbrewery \
  && yes pyrmontbrewery | passwd pyrmontbrewery

RUN usermod -s /bin/bash pyrmontbrewery

CMD ["/usr/sbin/sshd", "-D", "-e", "-f", "/etc/ssh/sshd_config_test_clion"]