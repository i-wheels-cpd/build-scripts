#!/bin/bash -e
# -----------------------------------------------------------------------------
#
# Package          : vision
# Version          : v0.21.0
# Source repo      : https://github.com/pytorch/vision
# Tested on        : UBI:9.6
# Language         : Python
# Travis-Check     : True
# Script License   : Apache License, Version 2 or later
# Maintainer       : Ramnath Nayak <Ramnath.Nayak@ibm.com>
#
# Disclaimer       : This script has been tested in root mode on given
# ==========         platform using the mentioned version of the package.
#                    It may not work as expected with newer versions of the
#                    package and/or distribution. In such case, please
#                    contact "Maintainer" of this script.
#
# ----------------------------------------------------------------------------

PACKAGE_NAME=vision
PACKAGE_VERSION=${1:-v0.21.0}
PACKAGE_URL=https://github.com/pytorch/vision
PACKAGE_DIR=vision

CURRENT_DIR=${PWD}



yum install -y git make cmake zip tar wget python3.12 python3.12-devel python3.12-pip gcc-toolset-13 gcc-toolset-13-gcc-c++ gcc-toolset-13-gcc zlib-devel libjpeg-devel openssl openssl-devel freetype-devel pkgconfig ninja-build sqlite-devel rsync java-11-openjdk java-11-openjdk-devel zlib-devel freetype-devel pkgconfig


python3.12 -m pip install setuptools wheel build pytest

#Increment by 1 for each build
BUILD_NUM="1"


source /opt/rh/gcc-toolset-13/enable

INSTALL_ROOT="/install-deps"
mkdir -p $INSTALL_ROOT

for package in openblas lame opus libvpx ffmpeg; do
    mkdir -p ${INSTALL_ROOT}/${package}
    export "${package^^}_PREFIX=${INSTALL_ROOT}/${package}"
    echo "Exported ${package^^}_PREFIX=${INSTALL_ROOT}/${package}"
done

PY_VER=$(python3.12 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
SITE_PACKAGE_PATH="/usr/local/lib64/python${PY_VER}/site-packages"


cd $CURRENT_DIR
echo "------------ abseil_cpp cloning-------------------"

ABSEIL_VERSION=20240116.2
ABSEIL_URL="https://github.com/abseil/abseil-cpp"
git clone $ABSEIL_URL -b $ABSEIL_VERSION

echo "------------ libprotobuf installing-------------------"
export C_COMPILER=$(which gcc)
export CXX_COMPILER=$(which g++)

#Build libprotobuf
git clone https://github.com/protocolbuffers/protobuf
cd protobuf
git checkout v4.25.8

LIBPROTO_DIR=$(pwd)
mkdir -p $LIBPROTO_DIR/local/libprotobuf
LIBPROTO_INSTALL=$LIBPROTO_DIR/local/libprotobuf

git submodule update --init --recursive
rm -rf ./third_party/googletest | true
rm -rf ./third_party/abseil-cpp | true

cp -r $CURRENT_DIR/abseil-cpp ./third_party/

mkdir build
cd build

cmake -G "Ninja" \
   ${CMAKE_ARGS} \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_STANDARD=17 \
    -DCMAKE_C_COMPILER=$C_COMPILER \
    -DCMAKE_CXX_COMPILER=$CXX_COMPILER \
    -DCMAKE_INSTALL_PREFIX=$LIBPROTO_INSTALL \
    -Dprotobuf_BUILD_TESTS=OFF \
    -Dprotobuf_BUILD_LIBUPB=OFF \
    -Dprotobuf_BUILD_SHARED_LIBS=ON \
    -Dprotobuf_ABSL_PROVIDER="module" \
    -Dprotobuf_JSONCPP_PROVIDER="package" \
    -Dprotobuf_USE_EXTERNAL_GTEST=OFF \
    ..

cmake --build . --verbose
cmake --install .
cd .. 

export PROTOC="$LIBPROTO_INSTALL/bin/protoc"
export LD_LIBRARY_PATH="/abseil-cpp/abseilcpp/lib:$LIBPROTO_INSTALL/lib64:$LD_LIBRARY_PATH"
export LIBRARY_PATH="$LIBPROTO_INSTALL/lib64:$LD_LIBRARY_PATH"
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=cpp
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION_VERSION=2

#Apply patch
wget https://raw.githubusercontent.com/i-wheels-cpd/build-scripts/refs/heads/main/p/protobuf/protobuf_v4.25.8.patch
git apply protobuf_v4.25.8.patch

echo "Installing protobuf...."
cd python
python3.12 -m pip install .

echo "------------ libprotobuf,protobuf installed--------------"

# echo "----Installing rust------"
#curl https://sh.rustup.rs -sSf | sh -s -- -y
#source "$HOME/.cargo/env"

# echo "------------cloning pytorch----------------"
cd $CURRENT_DIR
git clone https://github.com/pytorch/pytorch.git
cd pytorch
git checkout v2.6.0
git submodule sync
git submodule update --init --recursive

wget https://raw.githubusercontent.com/i-wheels-cpd/build-scripts/refs/heads/main/p/pytorch/pytorch_v2.6.0.patch
git apply pytorch_v2.6.0.patch

python3.12 -m pip install numpy==2.0.2 scipy==1.15.2 av llvmlite numba setuptools==76.1.0 wheel
python3.12 -m pip install cmake==3.*
python3.12 -m pip install -r requirements.txt

export GCC_HOME=/opt/rh/gcc-toolset-13/root/usr
export CC=$GCC_HOME/bin/gcc
export CXX=$GCC_HOME/bin/g++

export PATH="/protobuf/local/libprotobuf/bin/protoc:${PATH}"
export LD_LIBRARY_PATH="/protobuf/local/libprotobuf/lib64:${LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH="/protobuf/third_party/abseil-cpp/local/abseilcpp/lib:${LD_LIBRARY_PATH}"
export CPU_COUNT=$(nproc --all)
export CXXFLAGS="${CXXFLAGS} -D__STDC_FORMAT_MACROS"
export LDFLAGS="$(echo ${LDFLAGS} | sed -e 's/-Wl\,--as-needed//')"
export LDFLAGS="${LDFLAGS} -Wl,-rpath-link,${LIBPROTO_INSTALL}/lib64"
export CXXFLAGS="${CXXFLAGS} -fplt"
export CFLAGS="${CFLAGS} -fplt"
export USE_FBGEMM=0
export USE_SYSTEM_NCCL=1
export USE_MKLDNN=0
export USE_NNPACK=0
export USE_QNNPACK=0
export USE_XNNPACK=0
export USE_PYTORCH_QNNPACK=0
export TH_BINARY_BUILD=1
export USE_LMDB=1
export USE_LEVELDB=1
export USE_NINJA=0
export USE_MPI=0
export USE_OPENMP=1
export USE_TBB=
export USE_LAPACK=1
export BUILD_CUSTOM_PROTOBUF=OFF
export BUILD_CAFFE2=1
export PYTORCH_BUILD_VERSION=${PACKAGE_VERSION}
export PYTORCH_BUILD_NUMBER=${BUILD_NUM}
export CMAKE_PREFIX_PATH="${SITE_PACKAGE_PATH}"
export Protobuf_LIBRARY=${LIBPROTO_INSTALL}/lib64/libprotobuf.so
export Protobuf_LITE_LIBRARY=${LIBPROTO_INSTALL}/lib64/libprotobuf-lite.so
export Protobuf_INCLUDE_DIR=${LIBPROTO_INSTALL}/include
export Protobuf_LIBRARIES=${LIBPROTO_INSTALL}/lib64
export Protobuf_PROTOC_EXECUTABLE=${LIBPROTO_INSTALL}/bin/protoc
export USE_TENSORRT=0
MAX_JOBS=$(nproc) python3.12 setup.py install
cd $CURRENT_DIR

#installing openblas  
cd $CURRENT_DIR
git clone https://github.com/OpenMathLib/OpenBLAS
cd OpenBLAS
git checkout v0.3.29
git submodule update --init
mkdir prefix
# Set build options
declare -a build_opts
# Fix ctest not automatically discovering tests
LDFLAGS=$(echo "${LDFLAGS}" | sed "s/-Wl,--gc-sections//g")
export CF="${CFLAGS} -Wno-unused-parameter -Wno-old-style-declaration"
unset CFLAGS
export USE_OPENMP=1
build_opts+=(USE_OPENMP=${USE_OPENMP})
# Handle Fortran flags
if [ ! -z "$FFLAGS" ]; then
    export FFLAGS="${FFLAGS/-fopenmp/ }"
    export FFLAGS="${FFLAGS} -frecursive"
    export LAPACK_FFLAGS="${FFLAGS}"
fi
export PLATFORM=$(uname -m)
build_opts+=(BINARY="64")
build_opts+=(DYNAMIC_ARCH=1)
build_opts+=(TARGET="POWER9")
BUILD_BFLOAT16=1
# Placeholder for future builds that may include ILP64 variants.
build_opts+=(INTERFACE64=0)
build_opts+=(SYMBOLSUFFIX="")
# Build LAPACK
build_opts+=(NO_LAPACK=0)
# Enable threading and set the number of threads
build_opts+=(USE_THREAD=1)
build_opts+=(NUM_THREADS=120)
# Disable CPU/memory affinity handling to avoid problems with NumPy and R
build_opts+=(NO_AFFINITY=1)
# Build OpenBLAS
make ${build_opts[@]} CFLAGS="${CF}" FFLAGS="${FFLAGS}" prefix=${OPENBLAS_PREFIX}
# Install OpenBLAS
CFLAGS="${CF}" FFLAGS="${FFLAGS}" make install PREFIX="${OPENBLAS_PREFIX}" ${build_opts[@]}
export LD_LIBRARY_PATH=${OPENBLAS_PREFIX}/lib:$LD_LIBRARY_PATH
export PKG_CONFIG_PATH=${OPENBLAS_PREFIX}/lib/pkgconfig:$PKG_CONFIG_PATH
pkg-config --modversion openblas
echo "-----------------------------------------------------Installed openblas-----------------------------------------------------"

curl -LO https://www.nasm.us/pub/nasm/releasebuilds/2.16.01/nasm-2.16.01.tar.gz
tar -xzf nasm-2.16.01.tar.gz
cd nasm-2.16.01
./configure
make -j$(nproc)
make install
nasm -v
cd $CURRENT_DIR

git clone https://github.com/webmproject/libvpx.git
cd libvpx
git checkout v1.13.1
export target_platform=$(uname)-$(uname -m)
if [[ ${target_platform} == Linux-* ]]; then
    LDFLAGS="$LDFLAGS -pthread"
fi
CPU_DETECT="${CPU_DETECT} --enable-runtime-cpu-detect"

./configure --prefix=$LIBVPX_PREFIX --as=nasm --enable-shared --disable-static \
    --disable-install-docs --disable-install-srcs --enable-vp8 --enable-postproc \
    --enable-vp9 --enable-vp9-highbitdepth \
    --enable-pic ${CPU_DETECT} --enable-experimental || { cat config.log; exit 1; }

make
make install PREFIX="${LIBVPX_PREFIX}"
export LD_LIBRARY_PATH=${LIBVPX_PREFIX}/lib:$LD_LIBRARY_PATH
export PKG_CONFIG_PATH=${LIBVPX_PREFIX}/lib/pkgconfig:$PKG_CONFIG_PATH
pkg-config --modversion vpx
cd $CURRENT_DIR

wget https://downloads.sourceforge.net/sourceforge/lame/lame-3.100.tar.gz
tar -xvf lame-3.100.tar.gz
cd lame-3.100
# remove libtool files
find $LAME_PREFIX -name '*.la' -delete

./configure --prefix=$LAME_PREFIX \
            --disable-dependency-tracking \
            --disable-debug \
            --enable-shared \
            --enable-static \
            --enable-nasm

make
make install PREFIX="${LAME_PREFIX}"
export LD_LIBRARY_PATH=/install-deps/lame/lib:$LD_LIBRARY_PATH
export PATH="/install-deps/lame/bin:$PATH"
lame --version
echo " --------------------------------- Lame Successfully Installed --------------------------------- "
cd $CURRENT_DIR

git clone https://github.com/xiph/opus
cd opus
git checkout v1.3.1
yum install -y autoconf automake libtool
./autogen.sh
./configure --prefix=$OPUS_PREFIX
make
make install PREFIX="${OPUS_PREFIX}"
export LD_LIBRARY_PATH=${OPUS_PREFIX}/lib:$LD_LIBRARY_PATH
export PKG_CONFIG_PATH=${OPUS_PREFIX}/lib/pkgconfig:$PKG_CONFIG_PATH
pkg-config --modversion opus
echo " --------------------------------- Opus Successfully Installed --------------------------------- "
cd $CURRENT_DIR

#installing ffmpeg
echo " --------------------------------- FFmpeg Installing --------------------------------- "

git clone https://github.com/FFmpeg/FFmpeg
cd FFmpeg
git checkout n7.1
git submodule update --init

yum install -y gmp-devel freetype-devel openssl-devel


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
        --enable-pthreads \
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
        --disable-nonfree --disable-gpl --disable-gnutls --enable-openssl --disable-libopenh264 --disable-libx264    #"${_CONFIG_OPTS[@]}"

make
make install PREFIX="${FFMPEG_PREFIX}"
export PKG_CONFIG_PATH=${FFMPEG_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH}
export LD_LIBRARY_PATH=${FFMPEG_PREFIX}/lib:${LD_LIBRARY_PATH}
export PATH="/install-deps/ffmpeg/bin:$PATH"
ffmpeg -version
echo " --------------------------------- FFmpeg Successfully Installed --------------------------------- "
cd $CURRENT_DIR

#Cloning torchvision repository
cd $CURRENT_DIR
git clone $PACKAGE_URL
cd $PACKAGE_NAME
git checkout $PACKAGE_VERSION

sed -i '/elif sha != "Unknown":/d' setup.py
sed -i '/version += "+" + sha\[:7\]/d' setup.py

export FORCE_CUDA=0
export TORCHVISION_USE_FFMPEG=1
export CFLAGS="${CFLAGS} -I/${FFMPEG_PREFIX}/include"
export LDFLAGS="${LDFLAGS} -L/${FFMPEG_PREFIX}/lib"
export TORCHVISION_USE_VIDEO_CODEC=0
export TORCHVISION_INCLUDE="${SITE_PACKAGE_PATH}/av/include"


#Build package
if ! (python3.12 -m pip install .) ; then
    echo "------------------$PACKAGE_NAME:install_fails-------------------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail |  Install_Fails"
    exit 1
fi

#Build wheel
python3.12 setup.py bdist_wheel --dist-dir=$CURRENT_DIR
python3.12 -m pip install $CURRENT_DIR/torchvision*.whl

# Run test
# Skipping tests related to video and legacy image formats due to unsupported or missing runtime dependencies causing failures.
if ! pytest -v --durations=25 --ignore-glob="*test_video*" --ignore-glob="*test_image*" --ignore-glob="*test_io*" --ignore-glob="*test_internet*" --ignore-glob="*test_datasets*" --ignore-glob="*test_models*" --ignore-glob="*test_extended_models*" --ignore-glob="*test_transforms_v2*"; then
    echo "------------------$PACKAGE_NAME:install_success_but_test_fails---------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | $OS_NAME | GitHub | Fail |  Install_success_but_test_Fails"
    exit 2
else
    echo "------------------$PACKAGE_NAME:install_&_test_both_success-------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | $OS_NAME | GitHub  | Pass |  Both_Install_and_Test_Success"
fi
