#!/bin/bash -e
# -----------------------------------------------------------------------------
#
# Package          : torchaudio
# Version          : v2.6.0
# Source repo      : https://github.com/pytorch/audio.git
# Tested on        : UBI:9.3
# Language         : Python
# Travis-Check     : True
# Script License   : Apache License, Version 2 or later
# Maintainer       : Aastha Sharma <aastha.sharma4@ibm.com>
#
# Disclaimer       : This script has been tested in root mode on given
# ==========         platform using the mentioned version of the package.
#                    It may not work as expected with newer versions of the
#                    package and/or distribution. In such case, please
#                    contact "Maintainer" of this script.
#
# ---------------------------------------------------------------------------

set -ex

# Variables
PACKAGE_NAME=audio
PACKAGE_URL=https://github.com/pytorch/audio.git
PACKAGE_VERSION=${1:-v2.6.0}
PACKAGE_DIR=audio
SCRIPT_DIR=$(pwd)

# Install dependencies
yum install -y git make wget python3.12 python3.12-devel python3.12-pip pkgconfig atlas libtool xz zlib-devel openssl-devel bzip2-devel libffi-devel libevent-devel patch ninja-build gcc-toolset-13 pkg-config cmake gcc-toolset-13-libatomic-devel

#export path for gcc-13
export PATH=/opt/rh/gcc-toolset-13/root/usr/bin:$PATH
export LD_LIBRARY_PATH=/opt/rh/gcc-toolset-13/root/usr/lib64:$LD_LIBRARY_PATH

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

cp -r $SCRIPT_DIR/abseil-cpp ./third_party/

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
echo "building libprotobuf...."
cmake --build . --verbose
echo "Installing libprotobuf...."
cmake --install .

cd ..

#Build protobuf
export PROTOC=$LIBPROTO_DIR/build/protoc
export LD_LIBRARY_PATH=$SCRIPT_DIR/abseil-cpp/abseilcpp/lib:$(pwd)/build/libprotobuf.so:$LD_LIBRARY_PATH
export LIBRARY_PATH=$(pwd)/build/libprotobuf.so:$LD_LIBRARY_PATH
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=cpp
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION_VERSION=2

#Apply patch
wget https://raw.githubusercontent.com/i-wheels-cpd/build-scripts/refs/heads/main/p/protobuf/protobuf_v4.25.8.patch
git apply protobuf_v4.25.8.patch

echo "Installing protobuf...."
cd python
python3.12 -m pip install .
cd $SCRIPT_DIR

echo "------------ libprotobuf,protobuf installed--------------"

echo "----Installing rust------"
curl https://sh.rustup.rs -sSf | sh -s -- -y
source "$HOME/.cargo/env"

echo "------------cloning pytorch----------------"
git clone https://github.com/pytorch/pytorch.git
cd pytorch
git checkout $PACKAGE_VERSION
git submodule sync
git submodule update --init --recursive

python3.12 -m pip install pytest numpy==2.0.2 scikit_learn==1.6.1 
python3.12 -m pip install librosa parameterized setuptools ninja scipy==1.15.2 llvmlite numba

echo "------------applying patch----------------"
wget https://raw.githubusercontent.com/i-wheels-cpd/build-scripts/refs/heads/main/p/pytorch/pytorch_v2.6.0.patch
git apply pytorch_v2.6.0.patch

ARCH=`uname -p`
BUILD_NUM="1"
export build_type="cpu"
export CPU_COUNT=$(nproc --all)
export CXXFLAGS="${CXXFLAGS} -D__STDC_FORMAT_MACROS"
export LDFLAGS="$(echo ${LDFLAGS} | sed -e 's/-Wl\,--as-needed//')"
export LDFLAGS="${LDFLAGS} -Wl,-rpath-link,${VIRTUAL_ENV}/lib"
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
export USE_CUDNN=0
export USE_TENSORRT=0
export Protobuf_INCLUDE_DIR=${LIBPROTO_INSTALL}/include
export Protobuf_LIBRARIES=${LIBPROTO_INSTALL}/lib64
export Protobuf_LIBRARY=${LIBPROTO_INSTALL}/lib64/libprotobuf.so
export Protobuf_LITE_LIBRARY=${LIBPROTO_INSTALL}/lib64/libprotobuf-lite.so
export Protobuf_PROTOC_EXECUTABLE=${LIBPROTO_INSTALL}/bin/protoc
export PATH="/protobuf/local/libprotobuf/bin/protoc:${PATH}"
export LD_LIBRARY_PATH="/protobuf/local/libprotobuf/lib64:${LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH="/protobuf/third_party/abseil-cpp/local/abseilcpp/lib:${LD_LIBRARY_PATH}"
if [ "$build_type" == "cuda" ]
then
  export USE_CUDA=1
  export TORCH_CUDA_ARCH_LIST="6.0;7.0;7.5;8.0;8.6;9.0"
fi

sed -i "s/cmake/cmake==3.*/g" requirements.txt

python3.12 -m pip install -r requirements.txt
MAX_JOBS=$(nproc) python3.12 setup.py install
cd $SCRIPT_DIR

echo "------------------------clone and build torchaudio-------------------"
git clone $PACKAGE_URL
cd $PACKAGE_NAME
git checkout $PACKAGE_VERSION

# Apply the patch
echo "------------------------Applying patch-------------------"
wget https://raw.githubusercontent.com/i-wheels-cpd/build-scripts/refs/heads/main/t/torchaudio/torchaudio_v2.6.0.patch
git apply torchaudio_v2.6.0.patch
echo "-----------------------Applied patch successfully---------------------------------------"

SRC_DIR=$(pwd)

export USE_FFMPEG=OFF
export BUILD_SOX=OFF
export USE_OPENMP=OFF
export BUILD_TORCHAUDIO_PYTHON_EXTENSION=ON
export LIBPROTO_INSTALL=${SCRIPT_DIR}/protobuf/local/libprotobuf
export Protobuf_INCLUDE_DIR=${LIBPROTO_INSTALL}/include
export Protobuf_LIBRARIES=${LIBPROTO_INSTALL}/lib64
export Protobuf_LIBRARY=${LIBPROTO_INSTALL}/lib64/libprotobuf.so
export Protobuf_LITE_LIBRARY=${LIBPROTO_INSTALL}/lib64/libprotobuf-lite.so
export Protobuf_PROTOC_EXECUTABLE=${LIBPROTO_INSTALL}/bin/protoc
export PATH="${SCRIPT_DIR}/protobuf/local/libprotobuf/bin/protoc:${PATH}"
export LD_LIBRARY_PATH="${SCRIPT_DIR}/protobuf/third_party/abseil-cpp/local/abseilcpp/lib:${LD_LIBRARY_PATH}"

echo "Installing torchaudio..."
if ! (python3.12 -m pip install -v . --no-build-isolation --no-deps);then
    echo "------------------$PACKAGE_NAME:Install_fails-------------------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail |  Install_Fails"
    exit 1
fi

#test
if ! (pytest test/torchaudio_unittest/ -p no:warnings --ignore=test/torchaudio_unittest/transforms/ --ignore=test/torchaudio_unittest/functional/ --ignore=test/torchaudio_unittest/models/wav2vec2/model_test.py --ignore=test/torchaudio_unittest/kaldi_io_test.py
); then
     echo "--------------------$PACKAGE_NAME:Install_success_but_test_fails--------------------"
     echo "$PACKAGE_URL $PACKAGE_NAME"
     echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail |  Install_success_but__Import_Fails"
     exit 2
else
     echo "------------------$PACKAGE_NAME:Install_&_test_both_success-------------------------"
     echo "$PACKAGE_URL $PACKAGE_NAME"
     echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub  | Pass |  Both_Install_and_Import_Success"
     exit 0
fi
