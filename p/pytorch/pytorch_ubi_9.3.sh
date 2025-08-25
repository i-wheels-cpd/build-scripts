#!/bin/bash -e
# -----------------------------------------------------------------------------
#
# Package          : torch
# Version          : v2.6.0
# Source repo      : https://github.com/pytorch/pytorch
# Tested on        : UBI:9.3
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

PACKAGE_NAME=pytorch
PACKAGE_VERSION=${1:-v2.6.0}
PACKAGE_URL=https://github.com/pytorch/pytorch
PACKAGE_DIR=pytorch

CURRENT_DIR=${PWD}

#Increment by 1 for each build
BUILD_NUM="1"

yum install -y git make cmake zip tar wget python3.12 python3.12-devel python3.12-pip gcc-toolset-13 gcc-toolset-13-gcc-c++ gcc-toolset-13-gcc zlib-devel libjpeg-devel openssl openssl-devel freetype-devel pkgconfig ninja-build

export GCC_TOOLSET_PATH=/opt/rh/gcc-toolset-13/root/usr
export PATH=$GCC_TOOLSET_PATH/bin:$PATH

#cloning abseil-cpp
ABSEIL_VERSION=20240116.2
ABSEIL_URL="https://github.com/abseil/abseil-cpp"

git clone $ABSEIL_URL -b $ABSEIL_VERSION

echo "------------abseil-cpp cloned--------------"

#building libprotobuf
export C_COMPILER=$(which gcc)
export CXX_COMPILER=$(which g++)

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

echo "Building libprotobuf"
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
echo "building libprotobuf...."
cmake --build . --verbose
echo "Installing libprotobuf...."
cmake --install .

cd ..

echo "Building protobuf"
export PROTOC=$LIBPROTO_DIR/build/protoc
export LD_LIBRARY_PATH=$CURRENT_DIR/abseil-cpp/abseilcpp/lib:$(pwd)/build/libprotobuf.so:$LD_LIBRARY_PATH
export LIBRARY_PATH=$(pwd)/build/libprotobuf.so:$LD_LIBRARY_PATH
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=cpp
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION_VERSION=2

#Apply patch
wget https://raw.githubusercontent.com/i-wheels-cpd/build-scripts/refs/heads/main/p/protobuf/protobuf_v4.25.8.patch
git apply protobuf_v4.25.8.patch

echo "Installing protobuf...."
cd python
python3.12 -m pip install .

echo "------------ libprotobuf,protobuf installed--------------"


cd $CURRENT_DIR
git clone $PACKAGE_URL
cd $PACKAGE_NAME
git checkout $PACKAGE_VERSION

git submodule sync
git submodule update --init --recursive

wget https://raw.githubusercontent.com/i-wheels-cpd/build-scripts/refs/heads/main/p/pytorch/pytorch_v2.6.0.patch
git apply pytorch_v2.6.0.patch

python3.12 -m pip install numpy==2.0.2 scipy==1.15.2
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
export USE_TBB=0
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

#Build package
if ! (MAX_JOBS=$(nproc) python3.12 setup.py install) ; then
    echo "------------------$PACKAGE_NAME:install_fails-------------------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail |  Install_Fails"
    exit 1
fi

python3.12 -m pip install -r .ci/docker/requirements-ci.txt
ln -s $(which python3.12) /usr/bin/python

#Test
if ! (python3.12 test/run_test.py) ; then
    echo "------------------$PACKAGE_NAME:install_success_but_test_fails---------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail |  Install_success_but_test_Fails"
    exit 2
else
    echo "------------------$PACKAGE_NAME:install_&_test_both_success-------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub  | Pass |  Both_Install_and_Test_Success"
    exit 0
fi

