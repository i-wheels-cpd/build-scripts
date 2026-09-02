#!/bin/bash -e
# -----------------------------------------------------------------------------
#
# Package          : liblightgbm
# Version          : v4.6.0
# Source repo      : https://github.com/microsoft/LightGBM
# Tested on        : UBI:10.1
# Language         : C++
# Travis-Check     : True
# Script License   : Apache License, Version 2 or later
# Maintainer       : Rushikesh Sathe <Rushikesh.Sathe1@ibm.com>
#
# Disclaimer       : This script has been tested in root mode on given
# ==========         platform using the mentioned version of the package.
#                    It may not work as expected with newer versions of the
#                    package and/or distribution. In such case, please
# ----------------------------------------------------------------------------

PACKAGE_NAME=liblightgbm
PACKAGE_VERSION=${1:-v4.6.0}
build_type=${2:-cpu}
PACKAGE_URL=https://github.com/microsoft/LightGBM

OPENMPI_VERSION=5.0.6
OPENMPI_URL=https://download.open-mpi.org/release/open-mpi/v5.0/openmpi-${OPENMPI_VERSION}.tar.gz

CURRENT_DIR=${PWD}

dnf install -y git make cmake gcc gcc-c++ \
    zlib-devel openssl openssl-devel \
    autoconf automake libtool \
    python3.12 python3.12-devel python3.12-pip

python3.12 -m pip install --upgrade pip setuptools wheel

# -----------------------------------------------------------------------------
# Build OpenMPI
# -----------------------------------------------------------------------------
cd $CURRENT_DIR
wget $OPENMPI_URL
tar -xzf openmpi-${OPENMPI_VERSION}.tar.gz
cd openmpi-${OPENMPI_VERSION}

OPENMPI_PREFIX=$CURRENT_DIR/openmpi-install
./configure --prefix=$OPENMPI_PREFIX --enable-shared --disable-static
make -j$(nproc)
make install

export PATH=${OPENMPI_PREFIX}/bin:${PATH}
export LD_LIBRARY_PATH=${OPENMPI_PREFIX}/lib:${LD_LIBRARY_PATH}
export OPAL_PREFIX=${OPENMPI_PREFIX}
export CMAKE_PREFIX_PATH=${OPENMPI_PREFIX}

cd $CURRENT_DIR

# -----------------------------------------------------------------------------
# Clone and build lib_lightgbm.so
# -----------------------------------------------------------------------------
cd $CURRENT_DIR
git clone $PACKAGE_URL
cd LightGBM
git checkout $PACKAGE_VERSION
git submodule update --init --recursive

mkdir -p prefix
export PREFIX=$(pwd)/prefix

BUILD_OPTION="-DUSE_MPI=ON -DUSE_OPENMP=ON"

if [[ "$build_type" == "cuda" ]]; then
    export CUDA_HOME=/usr/local/cuda
    export PATH=${CUDA_HOME}/bin:${PATH}
    export LD_LIBRARY_PATH=${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}
    CUDA_LEVELS="7.5,8.0,8.6,8.9,9.0"
    CMAKE_CUDA_ARCHS=$(echo $CUDA_LEVELS | tr ',' ';' | tr -d '.')
    BUILD_OPTION+=" -DUSE_CUDA=ON -DCMAKE_CUDA_COMPILER=${CUDA_HOME}/bin/nvcc -DCMAKE_CUDA_HOST_COMPILER=$(which g++)"
    BUILD_OPTION+=" -DCMAKE_CUDA_ARCHITECTURES=${CMAKE_CUDA_ARCHS}"
    echo "CMAKE_CUDA_ARCHITECTURES=${CMAKE_CUDA_ARCHS}"

    mkdir -p ${CURRENT_DIR}/cuda-include
    find /usr/include -name 'cublas*.h' -exec ln -sf "{}" "${CURRENT_DIR}/cuda-include/" ';'
    export CXXFLAGS="${CXXFLAGS} -I${CUDA_HOME}/include -I${CURRENT_DIR}/cuda-include"
fi

mkdir -p build
cd build
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=$(which gcc) \
    -DCMAKE_CXX_COMPILER=$(which g++) \
    -DCMAKE_INSTALL_PREFIX=$PREFIX \
    ${BUILD_OPTION}

make -j$(nproc)
make install
cd $CURRENT_DIR

# -----------------------------------------------------------------------------
# Bundle into a Python wheel
# -----------------------------------------------------------------------------
mkdir -p $CURRENT_DIR/local/liblightgbm
cp -r LightGBM/prefix/* $CURRENT_DIR/local/liblightgbm/

cd $CURRENT_DIR


wget https://raw.githubusercontent.com/i-wheels-cpd/build-scripts/refs/heads/main/l/liblightgbm/pyproject.toml

sed -i "s/{PACKAGE_VERSION}/${PACKAGE_VERSION#v}/g" pyproject.toml

if ! python3.12 -m pip wheel -w $CURRENT_DIR -vv --no-build-isolation --no-deps . ; then
    echo "------------------$PACKAGE_NAME:Install_fails-------------------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail |  Install_Fails"
    exit 1
fi

# -----------------------------------------------------------------------------
# Test — install wheel and verify the .so and headers are present
# -----------------------------------------------------------------------------
python3.12 -m pip install ${PACKAGE_NAME}-*.whl

SITE_PACKAGE_PATH=$(python3.12 -m pip show liblightgbm | grep ^Location | awk '{print $2}')
if ! test -f ${SITE_PACKAGE_PATH}/liblightgbm/lib/lib_lightgbm.so ; then
    echo "------------------$PACKAGE_NAME:install_success_but_test_fails---------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail |  Install_success_but_test_Fails"
    exit 2
fi

if ! test -f ${SITE_PACKAGE_PATH}/liblightgbm/include/LightGBM/tree_learner.h ; then
    echo "------------------$PACKAGE_NAME:install_success_but_test_fails---------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail |  Install_success_but_test_Fails"
    exit 2
fi

echo "lib_lightgbm.so path : ${SITE_PACKAGE_PATH}/liblightgbm/lib/lib_lightgbm.so"
echo "headers path         : ${SITE_PACKAGE_PATH}/liblightgbm/include/LightGBM/"

echo "------------------$PACKAGE_NAME:install_&_test_both_success-------------------------"
echo "$PACKAGE_URL $PACKAGE_NAME"
echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Pass |  Both_Install_and_Test_Success"
exit 0

