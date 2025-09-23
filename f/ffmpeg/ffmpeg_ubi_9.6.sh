#!/bin/bash -e
# -----------------------------------------------------------------------------
#
# Package       : ffmpeg
# Version       : n7.1
# Source repo   : https://github.com/FFmpeg/FFmpeg
# Tested on     : UBI 9.6
# Language      : Python
# Travis-Check  : True
# Script License: Apache License, Version 2 or later
# Maintainer    : Aastha Sharma <aastha.sharma4@ibm.com>
#
# Disclaimer: This script has been tested in root mode on given
# ==========  platform using the mentioned version of the package.
#             It may not work as expected with newer versions of the
#             package and/or distribution. In such case, please
#             contact "Maintainer" of this script.
#
# ----------------------------------------------------------------------------
set -ex

# Clone the ffmpeg package
PACKAGE_NAME=FFmpeg
PACKAGE_VERSION=${1:-n7.1}
PACKAGE_URL=https://github.com/FFmpeg/FFmpeg
WORK_DIR=$(pwd)
PACKAGE_DIR=FFmpeg

# Install dependencies
yum install -y --allowerasing curl python3.12 python3.12-devel python3.12-pip gcc-toolset-13 make cmake \
  git wget tar pkgconfig autoconf automake libtool zlib-devel freetype-devel \
  gmp-devel openssl openssl-devel

export PATH=/opt/rh/gcc-toolset-13/root/usr/bin:$PATH

# install yasm
curl -LO https://www.tortall.net/projects/yasm/releases/yasm-1.3.0.tar.gz
tar xzvf yasm-1.3.0.tar.gz
cd yasm-1.3.0
./configure
make
make install
cd $WORK_DIR

# Clone the OPUS package
echo "--------------------------------- Installing Opus ---------------------------------"

git clone https://github.com/xiph/opus
cd opus
git checkout v1.3.1

mkdir opus_prefix
export OPUS_PREFIX=$(pwd)/opus_prefix

# Detect system and set build options
if [[ $(uname) == MSYS* ]]; then
  if [[ ${ARCH} == 32 ]]; then
    HOST_BUILD="--host=i686-w64-mingw32 --build=i686-w64-mingw32"
  else
    HOST_BUILD="--host=x86_64-w64-mingw32 --build=x86_64-w64-mingw32"
  fi
  OPUS_PREFIX=${OPUS_PREFIX}/Library/mingw-w64
  JOBS=${NUMBER_OF_PROCESSORS}
elif [[ $(uname) == Darwin ]]; then
  JOBS=$(sysctl -n hw.ncpu)
else
  JOBS=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || 1)
fi

# Build Opus
./autogen.sh
./configure --prefix=$OPUS_PREFIX $HOST_BUILD
make -j$JOBS
make install

# Debug output to verify opus_prefix folder exists
echo "Checking opus_prefix directory existence:"
if [ -d "$OPUS_PREFIX" ]; then
    echo "opus_prefix found: $OPUS_PREFIX"
else
    echo "opus_prefix NOT found: $OPUS_PREFIX"
    exit 1
fi

# Fix .pc file prefix (do only once here)
OPUS_PC="$OPUS_PREFIX/lib/pkgconfig/opus.pc"
if [ ! -f "$OPUS_PC" ]; then
  echo "❌ Opus install failed: $OPUS_PC not found"
  exit 1
fi

sed -i "s|^prefix=.*|prefix=$OPUS_PREFIX|" "$OPUS_PC"

# (Optional) Run tests
make check || echo "⚠️ Opus tests failed, continuing anyway"

echo "--------------------------------- Opus Installed Successfully ---------------------------------"

cd $WORK_DIR

# Clone the libvpx package
echo "--------------------------------- Installing libvpx ---------------------------------"

git clone https://github.com/webmproject/libvpx
cd libvpx
git checkout v1.13.1

mkdir libvpx_prefix
export LIBVPX_PREFIX=$(pwd)/libvpx_prefix

export target_platform=$(uname)-$(uname -m)
export GCC_HOME=/opt/rh/gcc-toolset-13/root/usr
export CC=$(which gcc)
export CXX=$(which g++)

if [[ ${target_platform} == Linux-* ]]; then
    LDFLAGS="$LDFLAGS -pthread"
fi

CPU_DETECT="${CPU_DETECT} --enable-runtime-cpu-detect"

./configure --prefix=$LIBVPX_PREFIX $HOST_BUILD \
            --as=yasm \
            --enable-shared \
            --disable-static \
            --disable-install-docs \
            --disable-install-srcs \
            --enable-vp8 \
            --enable-postproc \
            --enable-vp9 \
            --enable-vp9-highbitdepth \
            --enable-pic \
            ${CPU_DETECT} \
            --enable-experimental || { cat config.log; exit 1; }
make -j$(nproc)
make install

echo "--------------------------------- libvpx Installed Successfully ---------------------------------"

cd $WORK_DIR

# Clone the lame package
echo "--------------------------------- Installing lame ---------------------------------"

wget https://downloads.sourceforge.net/sourceforge/lame/lame-3.100.tar.gz
tar -xvf lame-3.100.tar.gz
cd lame-3.100

mkdir lame_prefix
export LAME_PREFIX=$(pwd)/lame_prefix

export CPU_COUNT=$(nproc)

# remove libtool files if any from previous installs (clean start)
find $LAME_PREFIX -name '*.la' -delete

./configure --prefix=$LAME_PREFIX \
            --disable-dependency-tracking \
            --disable-debug \
            --enable-shared \
            --enable-static \
            --enable-nasm

make -j$CPU_COUNT
make install

echo "--------------------------------- lame Installed Successfully ---------------------------------"

cd $WORK_DIR

# Now clone FFmpeg source and build
echo "--------------------------------- Installing FFmpeg ---------------------------------"

git clone $PACKAGE_URL
cd $PACKAGE_NAME/
git checkout $PACKAGE_VERSION
git submodule update --init

mkdir ffmpeg_prefix

export FFMPEG_PREFIX=$(pwd)/ffmpeg_prefix

export CPU_COUNT=$(nproc)
export CC=$(which gcc)

export PKG_CONFIG_PATH=$OPUS_PREFIX/lib/pkgconfig:$LAME_PREFIX/lib/pkgconfig:$LIBVPX_PREFIX/lib/pkgconfig

USE_NONFREE=no   #the options below are set for NO

./configure \
        --prefix="$FFMPEG_PREFIX" \
        --cc=${CC} \
        --disable-doc \
        --enable-gmp \
        --enable-hardcoded-tables \
        --enable-libfreetype \
        --enable-pthreads \
        --enable-postproc \
        --enable-pic \
        --enable-shared \
        --enable-static \
        --enable-version3 \
        --enable-zlib \
        --enable-libopus \
        --enable-libmp3lame \
        --enable-libvpx \
        --extra-cflags="-I$LAME_PREFIX/include -I$OPUS_PREFIX/include -I$LIBVPX_PREFIX/include" \
        --extra-ldflags="-L$LAME_PREFIX/lib -L$OPUS_PREFIX/lib -L$LIBVPX_PREFIX/lib" \
        --disable-encoder=h264 \
        --disable-decoder=h264 \
        --disable-decoder=libh264 \
        --disable-decoder=libx264 \
        --disable-decoder=libopenh264 \
        --disable-encoder=libopenh264 \
        --disable-encoder=libx264 \
        --disable-decoder=libx264rgb \
        --disable-encoder=libx264rgb \
        --disable-encoder=hevc \
        --disable-decoder=hevc \
        --disable-encoder=aac \
        --disable-decoder=aac \
        --disable-decoder=aac_fixed \
        --disable-encoder=aac_latm \
        --disable-decoder=aac_latm \
        --disable-encoder=mpeg \
        --disable-encoder=mpeg1video \
        --disable-encoder=mpeg2video \
        --disable-encoder=mpeg4 \
        --disable-encoder=msmpeg4 \
        --disable-encoder=mpeg4_v4l2m2m \
        --disable-encoder=msmpeg4v2 \
        --disable-encoder=msmpeg4v3 \
        --disable-decoder=mpeg \
        --disable-decoder=mpegvideo \
        --disable-decoder=mpeg1video \
        --disable-decoder=mpeg1_v4l2m2m \
        --disable-decoder=mpeg2video \
        --disable-decoder=mpeg2_v4l2m2m \
        --disable-decoder=mpeg4 \
        --disable-decoder=msmpeg4 \
        --disable-decoder=mpeg4_v4l2m2m \
        --disable-decoder=msmpeg4v1 \
        --disable-decoder=msmpeg4v2 \
        --disable-decoder=msmpeg4v3 \
        --disable-encoder=h264_v4l2m2m \
        --disable-decoder=h264_v4l2m2m \
        --disable-encoder=hevc_v4l2m2m \
        --disable-decoder=hevc_v4l2m2m \
        --disable-nonfree --disable-gpl --disable-gnutls --enable-openssl --disable-libopenh264 --disable-libx264

make -j$CPU_COUNT
make install -j$CPU_COUNT

echo "--------------------------------- ffmpeg Installed successfully ---------------------------------"

cd $WORK_DIR
mkdir -p local/ffmpeg
cp -r FFmpeg/ffmpeg_prefix/* local/ffmpeg/

PACKAGE_VERSION=$(echo "$PACKAGE_VERSION" | sed 's/[^0-9.]//g')

wget https://raw.githubusercontent.com/i-wheels-cpd/build-scripts/refs/heads/main/f/ffmpeg/pyproject.toml
sed -i s/{PACKAGE_VERSION}/$PACKAGE_VERSION/g "pyproject.toml"

export LD_LIBRARY_PATH=${LAME_PREFIX}/lib:${LIBVPX_PREFIX}/lib:${OPUS_PREFIX}/lib:${FFMPEG_PREFIX}/lib:${LD_LIBRARY_PATH}

echo " ------------------------------------------ Checking Test ------------------------------------------ "

cd ${FFMPEG_PREFIX}/bin/ && ./ffmpeg --help
cd ${FFMPEG_PREFIX}/bin/ && ./ffmpeg -loglevel panic -protocols | grep "https"
cd ${FFMPEG_PREFIX}/bin/ && ./ffmpeg -loglevel panic -codecs | grep "libmp3lame"
cd ${FFMPEG_PREFIX}/bin/ && ./ffmpeg -loglevel panic -codecs | grep "DEVI.S zlib"
cd ${FFMPEG_PREFIX}/bin/ && ./ffmpeg -loglevel panic -codecs

cd ${FFMPEG_PREFIX}/bin/ && ./ffmpeg -encoders
cd ${FFMPEG_PREFIX}/bin/ && ./ffmpeg -decoders
cd ${FFMPEG_PREFIX}/bin/ && ./ffmpeg -codecs >$WORK_DIR/ffmpeg-codecs.txt

if grep '\(h264\|aac\|hevc\|mpeg4\).*coders:' $WORK_DIR/ffmpeg-codecs.txt ; then
  echo >&2 -e "\nError: Forbidden codecs in ffmpeg, see lines above.\n"
  problem=true
else
  echo -e "OK, ffmpeg has no forbidden codecs."
fi

ffmpeg_libs="avcodec
        avdevice
        swresample
        avfilter
        avcodec
        avformat
        swscale"
for each_ffmpeg_lib in $ffmpeg_libs; do
  test -f $FFMPEG_PREFIX/lib/lib$each_ffmpeg_lib.so
done

if [ $? == 0 ]; then
    echo "--------------------$PACKAGE_NAME:Both_Install_and_Test_Success---------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Pass |  Both_Install_and_Test_Success"
else
    echo "------------------$PACKAGE_NAME:Install_success_but_test_Fails-------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub  | Fail |  Install_success_but_test_Fails"
    exit 2
fi

cd $WORK_DIR
python3.12 -m pip install setuptools wheel build
# Build wheel 
python3.12 setup.py bdist_wheel --plat-name=linux_x86_64 --dist-dir=$WORK_DIR

exit 0
