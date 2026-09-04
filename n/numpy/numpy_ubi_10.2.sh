#!/bin/bash -e
# -----------------------------------------------------------------------------
#
# Package       : numpy
# Version       : v2.5.0
# Source repo   : https://github.com/numpy/numpy
# Tested on     : UBI:10.2
# Language      : Python
# Travis-Check  : True
# Script License: Apache License, Version 2 or later
# Maintainer    : Rushikesh Sathe <Rushikesh.Sathe1@ibm.com>
#
# Disclaimer: This script has been tested in root mode on given
# ==========  platform using the mentioned version of the package.
#             It may not work as expected with newer versions of the
#             package and/or distribution. In such case, please
#             contact "Maintainer" of this script.
#
# ----------------------------------------------------------------------------

set -ex

PACKAGE_NAME=numpy
PACKAGE_VERSION=${1:-v2.5.0}
PACKAGE_URL=https://github.com/numpy/numpy
PACKAGE_DIR=numpy
CURRENT_DIR=$(pwd)

echo "Installing system dependencies..."
yum install -y git make cmake wget \
    python3.14 python3.14-devel python3.14-pip \
    gcc-toolset-15 \
    pkgconfig

export PATH=/opt/rh/gcc-toolset-15/root/usr/bin:$PATH
export LD_LIBRARY_PATH=/opt/rh/gcc-toolset-15/root/usr/lib64:$LD_LIBRARY_PATH

export CC=gcc
export CXX=g++

# -----------------------------------------------------------------------------
# Build OpenBLAS v0.3.33 from source  (numpy BLAS/LAPACK dependency)
# -----------------------------------------------------------------------------
echo " --------------------------------- OpenBLAS Installing --------------------------------- "

OPENBLAS_VERSION=${OPENBLAS_VERSION:-v0.3.33}

git clone -b ${OPENBLAS_VERSION} https://github.com/xianyi/OpenBLAS
cd OpenBLAS
git submodule update --init
# Strip linker flag that breaks the OpenBLAS build
LDFLAGS=$(echo "${LDFLAGS}" | sed "s/-Wl,--gc-sections//g")

# See this workaround
# ( https://github.com/xianyi/OpenBLAS/issues/818#issuecomment-207365134 ).
export CF="${CFLAGS} -Wno-unused-parameter -Wno-old-style-declaration"
unset CFLAGS
export USE_OPENMP=1

export PREFIX=${CURRENT_DIR}/local/openblas

#build options
build_opts=()
build_opts+=(USE_OPENMP=${USE_OPENMP})

if [ -n "${FFLAGS}" ]; then
    # Don't use GNU OpenMP, which is not fork-safe
    export FFLAGS="${FFLAGS/-fopenmp/ }"
    export FFLAGS="${FFLAGS} -frecursive"
    export LAPACK_FFLAGS="${FFLAGS}"
fi

build_opts+=(BINARY="64")
build_opts+=(DYNAMIC_ARCH=1)

# Set target platform-/CPU-specific options
# only setting option for x86-cpu platform
build_opts+=(TARGET="PRESCOTT")

# Placeholder for future builds that may include ILP64 variants.
build_opts+=(INTERFACE64=0)
build_opts+=(SYMBOLSUFFIX="")

# Build LAPACK.
build_opts+=(NO_LAPACK=0)

# Enable threading. This can be controlled to a certain number by
# setting OPENBLAS_NUM_THREADS before loading the library.
build_opts+=(USE_THREAD=1)
build_opts+=(NUM_THREADS=64)

# Disable CPU/memory affinity handling to avoid problems with NumPy and R
build_opts+=(NO_AFFINITY=1)

make -j8 "${build_opts[@]}" HOST=${HOST} CROSS_SUFFIX="${HOST}-" CFLAGS="${CF}" FFLAGS="${FFLAGS}"
CFLAGS="${CF}" FFLAGS="${FFLAGS}" make install PREFIX="${PREFIX}" "${build_opts[@]}"

# Verify installation succeeded
[ -d "${PREFIX}" ] || { echo "ERROR: OpenBLAS make install failed — PREFIX dir not created: ${PREFIX}"; exit 1; }

export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH}"
export LD_LIBRARY_PATH="${PREFIX}/lib:${PREFIX}/lib64:${LD_LIBRARY_PATH}"

cd $CURRENT_DIR
echo " --------------------------------- OpenBLAS Successfully Installed --------------------------------- "

# -----------------------------------------------------------------------------
# Build numpy from source against the source-built OpenBLAS
# -----------------------------------------------------------------------------
echo " --------------------------------- Numpy Installing --------------------------------- "

# Install Python build-time tools
python3.14 -m pip install --upgrade pip setuptools wheel
python3.14 -m pip install build==1.5.0 meson==1.11.1 meson-python==0.19.0 \
    Cython==3.2.0 pybind11 packaging pyproject-metadata ninja "patchelf>=0.11.0" pytest hypothesis

git clone -b $PACKAGE_VERSION $PACKAGE_URL
cd $PACKAGE_DIR
git submodule update --init

# Explicitly point numpy's meson build at the source-built OpenBLAS.
# PKG_CONFIG_PATH is already set above; also set the direct lib/include vars
# so meson finds openblas even if pkg-config fallback is skipped.
export OPENBLAS_INCLUDE="${PREFIX}/include"
export NPY_BLAS_LIBS="-L${PREFIX}/lib -lopenblas"
export NPY_LAPACK_LIBS="-L${PREFIX}/lib -lopenblas"
export CFLAGS="-I${OPENBLAS_INCLUDE}"

# Build numpy wheel
python3.14 -m build --wheel

# Install the built wheel
NUMPY_WHL=$(ls dist/numpy-*.whl | head -1)

if ! python3.14 -m pip install "${NUMPY_WHL}" ; then
    echo "------------------$PACKAGE_NAME:Install_fails-------------------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME | $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail | Install_Fails"
    exit 1
fi

cd $CURRENT_DIR
echo " --------------------------------- Numpy Successfully Installed --------------------------------- "

# Run core tests against the *installed* package.
# Use --pyargs so pytest resolves tests via the installed numpy, not the local
# source tree — avoids the circular-import conftest error caused by running
# pytest from inside the cloned repo directory.
if ! python3.14 -m pytest --pyargs numpy._core.tests.test_multiarray \
    numpy._core.tests.test_numeric \
    -x -q --no-header ; then
    echo "------------------$PACKAGE_NAME:Install_success_but_test_Fails-------------------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME | $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail | Install_success_but_test_Fails"
    exit 2
else
    echo "------------------$PACKAGE_NAME:Install_&_test_both_success-------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME | $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Pass | Both_Install_and_Test_Success"
    exit 0
fi

