# cross compile build native FFmpeg static with SRT
# Pyrmont Brewery

FROM arm64v8/ubuntu:18.04
MAINTAINER kevleyski

# Pull in build cross compiler tool dependencies using Advanced Package Tool
ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Australia/Sydney
RUN apt-get update && apt-get install -y tzdata

RUN set -x \
    && DEBIAN_FRONTEND=noninteractive apt-get -y install wget curl autoconf automake build-essential libass-dev libfreetype6-dev \
      libsdl1.2-dev libtheora-dev libtool libvdpau-dev libvorbis-dev libxcb1-dev libxcb-shm0-dev \
      libxcb-xfixes0-dev pkg-config texinfo zlib1g-dev gettext tcl libssl-dev libx264-dev libomxil-bellagio-dev cmake mercurial unzip \
    && mkdir ~/brewerycam \
    && apt-get -y install yasm \
    && cd ~/brewerycam \
    && wget http://www.tortall.net/projects/yasm/releases/yasm-1.3.0.tar.gz \
    && tar xzvf yasm-1.3.0.tar.gz \
    && rm -f yasm-1.3.0.tar.gz \
    && cd yasm-1.3.0 \
    && ./configure --prefix="$HOME/brewerycam" --bindir="$HOME/bin" \
    && make -j$(cat /proc/cpuinfo | grep processor | wc -l) \
    && make install \
    && make distclean

# libSRT (dependency /usr/bin/tclsh)
#FROM brewerycam_ubuntu18_baseline AS brewerycam_srt
RUN set -x \
    && cd ~/brewerycam \
    && wget https://github.com/PyrmontBrewery/PATCHES-srt/archive/refs/tags/pyrmontbrewery_v1.4.4.tar.gz -O srt-pyrmontbrewery_v1.4.4.tar.gz \
    && tar xvf srt-pyrmontbrewery_v1.4.4.tar.gz && mv PATCHES-srt-pyrmontbrewery_v1.4.4 srt\
    && rm -f srt-pyrmontbrewery_v1.4.4.tar.gz \
    && cd srt \
    && rm -f CMakeCache.txt \
    && PATH="$HOME/bin:$PATH" PKG_CONFIG_PATH="$HOME/brewerycam/lib/pkgconfig" ./configure --prefix="$HOME/brewerycam" --enable-static --enable-shared \
    && PATH="$HOME/bin:$PATH" make -j$(cat /proc/cpuinfo | grep processor | wc -l) \
    && make install \
    && make clean

# Build FFmpeg
#FROM brewerycam_ubuntu18_baseline AS brewerycam_ffmpeg
RUN cd ~/brewerycam \

    && wget https://github.com/PyrmontBrewery/PATCHES-FFmpeg/archive/refs/tags/pyrmontbrewery-v4.1.7.tar.gz -O ffmpeg-pyrmontbrewery_v4.1.7.tar.gz \
    && tar xvf pyrmontbrewery-v4.1.7.tar.gz && mv ffmpeg-pyrmontbrewery_v4.1.7 ffmpeg \
    && rm -f ffmpeg-pyrmontbrewery_v4.1.7.tar.gz \
    && cd ffmpeg \
    && PATH="$HOME/bin:$PATH" PKG_CONFIG_PATH="$HOME/brewerycam/lib/pkgconfig" ./configure \
      --prefix="$HOME/brewerycam" \
      --extra-libs=-L../bmdsdk/Linux/include \
      --extra-cflags=-I../bmdsdk/Linux/include \
      --extra-cflags="-I$HOME/brewerycam/include" \
      --extra-ldflags="-L$HOME/brewerycam/lib" \
      --extra-libs="-lpthread -lm" \
      --bindir="$HOME/brewerycam/bin" \
      --enable-ffplay \
      --enable-gpl \
      --disable-libxcb \
      --disable-xlib \
      --disable-lzma \
      --disable-alsa \
      --enable-libx264 \
      --enable-nonfree \
      --enable-openssl \
      --enable-omx \
      --enable-omx-rpi \
      --enable-libsrt \
      --enable-libfreetype \
      --disable-doc \
      --pkg-config-flags="--static" \
    && PATH="$HOME/bin:$PATH" make -j$(cat /proc/cpuinfo | grep processor | wc -l) \
    && make install \
    && make distclean \
    && hash -r

# Build MQTT Mosquito
RUN cd ~/brewerycam \
    && wget https://github.com/PyrmontBrewery/mosquitto/archive/refs/tags/pyrmontbrewery_v2.0.12.tar.gz \
    && tar xvf pyrmontbrewery_v2.0.12.tar.gz && mv mosquitto-pyrmontbrewery_v2.0.12.tar.gz mosquitto \
    && rm -f pyrmontbrewery_v2.0.12.tar.gz \
    && cd mosquitto \
    && mkdir build \
    && cd build \
    && cmake CMAKE_INSTALL_PREFIX="$HOME/brewerycam" -DWITH_SHARED_LIBRARIES=OFF -DWITH_STATIC_LIBRARIES=ON .. \
    && PATH="$HOME/bin:$PATH" make -j$(cat /proc/cpuinfo | grep processor | wc -l)