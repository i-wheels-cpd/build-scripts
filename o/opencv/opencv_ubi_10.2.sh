#!/bin/bash -e
# -----------------------------------------------------------------------------
#
# Package          : opencv-python-headless
# Version          : 5.0.0.93
# Source repo      : https://github.com/opencv/opencv-python
# Tested on        : UBI:10.2
# Language         : Python
# Travis-Check     : True
# Script License   : Apache License, Version 2 or later
# Maintainer       : Arcahna Shinde <Archana.Shinde2@ibm.com>
#
# Disclaimer: This script has been tested in root mode on given
# ==========  platform using the mentioned version of the package.
#             It may not work as expected with newer versions of the
#             package and/or distribution. In such case, please
#             contact "Maintainer" of this script.
#
# ----------------------------------------------------------------------------
set -ex

PACKAGE_NAME=opencv-python-headless
PACKAGE_VERSION=${1:-93}
PACKAGE_URL=https://github.com/opencv/opencv-python
GIT_TAG="${PACKAGE_VERSION##*.}"
PACKAGE_DIR="opencv-python"
WORK_DIR=$(pwd)

# Install system-level build dependencies required for Open-CV
yum install -y make libtool cmake git wget xz zlib-devel openssl-devel bzip2-devel libffi-devel libevent-devel patch python3.14 python3.14-devel python3.14-pip ninja-build gcc-toolset-15

# Install Python build and test dependencies
python3.14 -m pip install --upgrade cmake pip setuptools wheel ninja packaging


# Configure GCC Toolset 15 as the default C/C++ compiler toolchain
export PATH=/opt/rh/gcc-toolset-15/root/usr/bin:$PATH

export C_COMPILER=$(which gcc)
export CXX_COMPILER=$(which g++)
export AR="$(command -v ar)"
export RANLIB="$(command -v ranlib)"

echo "------------ libprotobuf Building-------------------"

git clone https://github.com/protocolbuffers/protobuf
cd protobuf
git checkout v33.6

LIBPROTO_DIR=$(pwd)
mkdir -p $LIBPROTO_DIR/local/libprotobuf
LIBPROTO_INSTALL=$LIBPROTO_DIR/local/libprotobuf

git submodule update --init --recursive
rm -rf ./third_party/googletest | true

mkdir build
cd build

#Building and testing is performed through the same command
if ! (cmake -G "Ninja" \
   ${CMAKE_ARGS} \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_STANDARD=17 \
    -DCMAKE_C_COMPILER=$C_COMPILER \
    -DCMAKE_CXX_COMPILER=$CXX_COMPILER \
    -DCMAKE_INSTALL_PREFIX=$LIBPROTO_INSTALL \
    -Dprotobuf_BUILD_TESTS=OFF \
    -Dprotobuf_BUILD_SHARED_LIBS=ON \
    -Dprotobuf_ABSL_PROVIDER="module" \
    -Dprotobuf_JSONCPP_PROVIDER="package" \
    -Dprotobuf_USE_EXTERNAL_GTEST=OFF \
    ..) ; then
    echo "------------------$PACKAGE_NAME:install_&_test_both_fails---------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail |  Install_success_but_test_Fails"
    exit 2
else
    echo "------------------$PACKAGE_NAME:install_&_test_both_success-------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub  | Pass |  Both_Install_and_Test_Success"
fi

cmake --build . --verbose
cmake --install .

cd ..
wget https://raw.githubusercontent.com/i-wheels-cpd/build-scripts/refs/heads/main/l/libprotobuf/pyproject.toml
sed -i "s/{PACKAGE_VERSION}/$PACKAGE_VERSION/g" pyproject.toml

python3.14 -m pip wheel -w $WORK_DIR -vv --no-build-isolation --no-deps .

echo " protobuf installed success at end $PWD"

# -----------------------------------------------------------------------------
# Verify protobuf installation
# -----------------------------------------------------------------------------

PROTOC_BIN="${LIBPROTO_INSTALL}/bin/protoc"

if [ ! -x "$PROTOC_BIN" ]; then
    echo "ERROR: protoc was not installed"
    exit 1
fi

if [ -f "${LIBPROTO_INSTALL}/lib64/libprotobuf.so" ]; then
    PROTOBUF_LIB_DIR="${LIBPROTO_INSTALL}/lib64"
elif [ -f "${LIBPROTO_INSTALL}/lib/libprotobuf.so" ]; then
    PROTOBUF_LIB_DIR="${LIBPROTO_INSTALL}/lib"
else
    echo "ERROR: libprotobuf.so was not installed"
    exit 1
fi

echo "-----------------------------------------------------"
echo "Protobuf installation successful"
echo "-----------------------------------------------------"
echo "protoc:"
"$PROTOC_BIN" --version
echo "PROTOBUF_PREFIX=${LIBPROTO_INSTALL}"
echo "PROTOBUF_LIB_DIR=${PROTOBUF_LIB_DIR}"

export PATH="${LIBPROTO_INSTALL}/bin:${PATH}"
export LD_LIBRARY_PATH="${PROTOBUF_LIB_DIR}:${LD_LIBRARY_PATH}"

export Protobuf_DIR="${PROTOBUF_LIB_DIR}/cmake/protobuf"

if [ -d "${PROTOBUF_LIB_DIR}/cmake/absl" ]; then
    export ABSL_DIR="${PROTOBUF_LIB_DIR}/cmake/absl"
fi

cd ../
python3.14 -m pip install --no-cache-dir setuptools "numpy==2.5.0" scikit-build build

echo "-----------opencv-python-headless Building-------------------"

git clone $PACKAGE_URL
cd $PACKAGE_DIR
git -c advice.detachedHead=false checkout "$GIT_TAG"
git submodule update --init --recursive

# OpenCV configuration

export ENABLE_HEADLESS=1

export CMAKE_ARGS="-DCMAKE_BUILD_TYPE=Release
                   -DCMAKE_C_STANDARD=11
                   -DCMAKE_CXX_STANDARD=17
                   -DCMAKE_CXX_STANDARD_REQUIRED=ON
                   -DCMAKE_C_COMPILER=${C_COMPILER}
                   -DCMAKE_CXX_COMPILER=${CXX_COMPILER}
                   -DCMAKE_AR=${AR}
                   -DCMAKE_RANLIB=${RANLIB}
                   -DWITH_EIGEN=1
                   -DBUILD_TESTS=0
                   -DBUILD_DOCS=0
                   -DBUILD_PERF_TESTS=0
                   -DBUILD_ZLIB=0
                   -DBUILD_TIFF=0
                   -DBUILD_PNG=0
                   -DBUILD_OPENEXR=0
                   -DWITH_OPENEXR=0
                   -DBUILD_OPENJPEG=0
                   -DWITH_OPENJPEG=1
                   -DBUILD_JASPER=0
                   -DWITH_ITT=1
                   -DBUILD_JPEG=0
                   -DBUILD_PROTOBUF=OFF
                   -DBUILD_LIBPROTOBUF_FROM_SOURCES=OFF
                   -DPROTOBUF_UPDATE_FILES=ON
                   -DProtobuf_LIBRARY=${PROTOBUF_LIB_DIR}/libprotobuf.so
                   -DProtobuf_INCLUDE_DIR=${LIBPROTO_INSTALL}/include
                   -DProtobuf_PROTOC_EXECUTABLE=${PROTOC_BIN}
                   -DProtobuf_DIR=${PROTOBUF_LIB_DIR}/cmake/protobuf
                   -DCMAKE_PREFIX_PATH=${LIBPROTO_INSTALL}:${PROTOBUF_LIB_DIR}
                   -DBUILD_opencv_dnn=OFF
                   -DWITH_V4L=1
                   -DWITH_OPENCL=0
                   -DWITH_OPENCLAMDFFT=0
                   -DWITH_OPENCLAMDBLAS=0
                   -DWITH_OPENCL_D3D11_NV=0
                   -DWITH_1394=0
                   -DWITH_CARBON=0
                   -DWITH_OPENNI=0
                   -DWITH_FFMPEG=0
                   -DHAVE_FFMPEG=0
                   -DWITH_JASPER=0
                   -DWITH_VA=0
                   -DWITH_VA_INTEL=0
                   -DWITH_GSTREAMER=0
                   -DWITH_MATLAB=0
                   -DWITH_TESSERACT=0
                   -DWITH_VTK=0
                   -DWITH_GTK=0
                   -DWITH_QT=0
                   -DWITH_GPHOTO2=0
                   -DINSTALL_C_EXAMPLES=0
                   -DWITH_LAPACK=0
                   -DHAVE_LAPACK=0
                   -DLAPACK_LAPACKE_H=${OpenBLAS_HOME}/include/lapacke.h
                   -DLAPACK_CBLAS_H=${OpenBLAS_HOME}/include/cblas.h
                   -DOPENCV_DISABLE_OPTIMIZATION=ON
                   -DWITH_VSX=OFF
                   -DENABLE_VSX=OFF
                   -DCPU_DISPATCH=
                   -DCPU_BASELINE="

# NumPy include paths

export C_INCLUDE_PATH="$(python3.14 -c "import numpy; print(numpy.get_include())")"
export CPLUS_INCLUDE_PATH="$C_INCLUDE_PATH"

echo "NumPy include: $C_INCLUDE_PATH"

# -----------------------------------------------------------------------------
# OpenCV test data
# -----------------------------------------------------------------------------

if [ -f "$WORK_DIR/$PACKAGE_DIR/tests/SampleVideo_1280x720_1mb.mp4" ]; then
    ln -sf \
        "$WORK_DIR/$PACKAGE_DIR/tests/SampleVideo_1280x720_1mb.mp4" \
        SampleVideo_1280x720_1mb.mp4
fi

echo "Building the wheel"

python3.14 setup.py bdist_wheel \
    --plat-name=linux_$(uname -m) \
    --dist-dir="$WORK_DIR"

# Install locally built wheel for validation
if ! (pip install ${OUTPUT_FOLDER}/opencv-*.whl  --no-deps); then
    echo "------------------$PACKAGE_NAME:Install_fails-------------------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME | $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail | Install_Fails"
    exit 1
fi

echo "Build and installation completed successfully."

exit 0
