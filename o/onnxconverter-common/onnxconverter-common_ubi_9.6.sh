#!/bin/bash -e
# -----------------------------------------------------------------------------
#
# Package          : onnxconverter-common
# Version          : v1.14.0
# Source repo      : https://github.com/microsoft/onnxconverter-common
# Tested on        : UBI:9.6
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

# Variables
set -ex

PACKAGE_NAME=onnxconverter-common
PACKAGE_VERSION=${1:-v1.14.0}
PACKAGE_URL=https://github.com/microsoft/onnxconverter-common
PACKAGE_DIR=onnxconverter-common
CURRENT_DIR=$(pwd)

echo "Installing dependencies..."

yum install -y git wget make libtool gcc-toolset-13 gcc-toolset-13-gcc gcc-toolset-13-gcc-c++ gcc-toolset-13-gcc-gfortran clang libevent-devel zlib-devel openssl-devel python python-devel python3.12 python3.12-devel python3.12-pip cmake patch ninja-build

export PATH=/opt/rh/gcc-toolset-13/root/usr/bin:$PATH
export LD_LIBRARY_PATH=/opt/rh/gcc-toolset-13/root/usr/lib64:$LD_LIBRARY_PATH

pip3.12 install --upgrade pip setuptools wheel ninja packaging tox pytest build mypy stubs
pip3.12 install 'cmake==3.31.6' onnx==1.17.0

# Setting paths and versions
export C_COMPILER=$(which gcc)
export CXX_COMPILER=$(which g++)
echo "C Compiler set to $C_COMPILER"
echo "CXX Compiler set to $CXX_COMPILER"

LIBPROTO_DIR=$CURRENT_DIR
mkdir -p $LIBPROTO_DIR/local/libprotobuf
LIBPROTO_INSTALL=$LIBPROTO_DIR/local/libprotobuf

echo " --------------------------------------------------- Libprotobuf Installing --------------------------------------------------- "

# Clone Source-code
PACKAGE_VERSION_LIB="v4.25.8"
PACKAGE_GIT_URL="https://github.com/protocolbuffers/protobuf"
git clone $PACKAGE_GIT_URL -b $PACKAGE_VERSION_LIB
cd protobuf
git submodule update --init --recursive
rm -rf ./third_party/googletest || true

mkdir build && cd build
cmake -G "Ninja" \
    -DBUILD_SHARED_LIBS=OFF \
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

echo " --------------------------------------------------- Libprotobuf Successfully Installed --------------------------------------------------- "

cd ..
export PROTOC="$LIBPROTO_INSTALL/bin/protoc"
export LD_LIBRARY_PATH="$LIBPROTO_INSTALL/lib64:$LD_LIBRARY_PATH"
export LIBRARY_PATH="$LIBPROTO_INSTALL/lib64:$LD_LIBRARY_PATH"
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=cpp
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION_VERSION=2

# Apply patch
echo "Applying patch from https://raw.githubusercontent.com/i-wheels-cpd/build-scripts/refs/heads/main/p/protobuf/protobuf_v4.25.8.patch"
wget https://raw.githubusercontent.com/i-wheels-cpd/build-scripts/refs/heads/main/p/protobuf/protobuf_v4.25.8.patch
git apply protobuf_v4.25.8.patch

# Build Python package
cd python
python3.12 setup.py install --cpp_implementation
cd $CURRENT_DIR

# Install Pybind11
pip3.12 install pybind11==2.12.0
SITE_PACKAGE_PATH=$(python3.12 -c "import site; print(site.getsitepackages()[0])")
PYBIND11_PREFIX=$SITE_PACKAGE_PATH/pybind11

export CMAKE_PREFIX_PATH="$LIBPROTO_INSTALL;$PYBIND11_PREFIX"
export LD_LIBRARY_PATH="$LIBPROTO_INSTALL/lib64:$LD_LIBRARY_PATH"

# Clone and install onnxconverter-common
echo " --------------------------------------------------- OnnxConverter-Common Cloning --------------------------------------------------- "
git clone $PACKAGE_URL
cd $PACKAGE_NAME
git checkout $PACKAGE_VERSION
git submodule update --init --recursive

# Update pyproject.toml dependencies with >=
sed -i 's/\bprotobuf==[^ ]*\b/protobuf>=4.25.8/g' pyproject.toml
sed -i 's/\"onnx\"/\"onnx>=1.17.0\"/' pyproject.toml
sed -i 's/\"numpy\"/\"numpy>=2.0.2\"/' pyproject.toml
sed -i "/tool.setuptools.dynamic/d" pyproject.toml
sed -i "/onnxconverter_common.__version__/d" pyproject.toml

# Update requirements.txt
sed -i 's/\"numpy\"/\"numpy>=2.0.2\"/' requirements.txt
sed -i 's/\bprotobuf==[^ ]*\b/protobuf>=4.25.8/g' requirements.txt

pip3.12 install flatbuffers onnxmltools

cd $CURRENT_DIR

# Clone and build onnxruntime outside working dir
echo " --------------------------------------------------- Onnxruntime Installing --------------------------------------------------- "
ONNXRUNTIME_SRC=$HOME/onnxruntime_src
rm -rf $ONNXRUNTIME_SRC
git clone https://github.com/microsoft/onnxruntime $ONNXRUNTIME_SRC
cd $ONNXRUNTIME_SRC
git checkout v1.21.0

# Update python version 
PYTHON_VERSION="$1"
sed -i "s/python3/python$PYTHON_VERSION/g" build.sh
#sed -i 's/python3/python3.12/g' build.sh

# Fix NumPy issue
export CXXFLAGS="-Wno-stringop-overflow"
export CFLAGS="-Wno-stringop-overflow"

python3.12 -m pip install packaging wheel
python3.12 -m pip install numpy>=2.0.2
NUMPY_INCLUDE=$(python3.12 -c "import numpy; print(numpy.get_include())")
echo "NumPy include path: $NUMPY_INCLUDE"

# Patch onnxruntime to fix missing Python::NumPy target
sed -i '193i # Fix for Python::NumPy target not found\nif(NOT TARGET Python::NumPy)\n    find_package(Python3 COMPONENTS NumPy REQUIRED)\n    add_library(Python::NumPy INTERFACE IMPORTED)\n    target_include_directories(Python::NumPy INTERFACE ${Python3_NumPy_INCLUDE_DIR})\n    message(STATUS "Manually defined Python::NumPy with include dir: ${Python3_NumPy_INCLUDE_DIR}")\nendif()\n' $ONNXRUNTIME_SRC/cmake/onnxruntime_python.cmake

# Patch hash in deps.txt
sed -i 's|5ea4d05e62d7f954a46b3213f9b2535bdd866803|51982be81bbe52572b54180454df11a3ece9a934|' cmake/deps.txt

# Build onnxruntime
./build.sh \
  --cmake_extra_defines "onnxruntime_PREFER_SYSTEM_LIB=ON" "Protobuf_PROTOC_EXECUTABLE=$PROTOC" "Protobuf_INCLUDE_DIR=$LIBPROTO_INSTALL/include" "onnxruntime_USE_COREML=OFF" "Python3_NumPy_INCLUDE_DIR=$NUMPY_INCLUDE" "CMAKE_POLICY_DEFAULT_CMP0001=NEW" "CMAKE_POLICY_DEFAULT_CMP0002=NEW" "CMAKE_POLICY_VERSION_MINIMUM=3.5" \
  --cmake_generator Ninja \
  --build_shared_lib \
  --config Release \
  --update \
  --build \
  --skip_submodule_sync \
  --allow_running_as_root \
  --compile_no_warning_as_error \
  --build_wheel

# Install the built onnxruntime wheel
echo " --------------------------------------------------- Installing onnxruntime wheel --------------------------------------------------- "
cp ./build/Linux/Release/dist/* ./
python3.12 -m pip install ./*.whl

# Clean up
cd $CURRENT_DIR
rm -rf $ONNXRUNTIME_SRC

# Install onnxconverter-common
cd $PACKAGE_DIR
if ! pip3.12 install .; then
    echo "------------------$PACKAGE_NAME:wheel_built_fails---------------------"
    echo "$PACKAGE_VERSION $PACKAGE_NAME"
    echo "$PACKAGE_NAME  | $PACKAGE_VERSION | $OS_NAME | GitHub | Fail |  wheel_built_fails"
    exit 1
fi

# Build wheel
python3.12 setup.py bdist_wheel --plat-name=linux_x86_64 --dist-dir=$CURRENT_DIR

echo "Running tests for $PACKAGE_NAME..."
if ! pytest --ignore=tests/test_auto_mixed_precision_model_path.py --ignore=tests/test_auto_mixed_precision.py --ignore=tests/test_onnx2py.py --ignore=tests/test_float16.py --tb=short --maxfail=1 ; then
    echo "------------------$PACKAGE_NAME:build_success_but_test_fails---------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME | $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail | Build_success_but_test_Fails"
    exit 2
else
    echo "------------------$PACKAGE_NAME:install_&_test_both_success-------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME | $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Pass | Both_Install_and_Test_Success"
    exit 0
fi

