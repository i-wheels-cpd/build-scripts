#!/bin/bash -e
# -----------------------------------------------------------------------------
#
# Package       : xgboost
# Version       : 2.1.4
# Source repo   : https://github.com/dmlc/xgboost
# Tested on     : UBI:9.3
# Language      : Python
# Travis-Check  : True
# Script License: Apache License, Version 2 or later
# Maintainer    : Aastha Sharma <aastha.sharma4@ibm.com>
#
# Disclaimer: This script has been tested in root mode on the given
# platform using the mentioned version of the package.
# It may not work as expected with newer versions of the
# package and/or distribution. In such a case, please
# contact the "Maintainer" of this script.
#
# -----------------------------------------------------------------------------
# Exit immediately if a command exits with a non-zero status
set -ex

# Variables
PACKAGE_NAME=xgboost
PACKAGE_VERSION=${1:-v2.1.4}
PACKAGE_URL=https://github.com/dmlc/xgboost
PACKAGE_DIR=xgboost/python-package
OUTPUT_FOLDER="$(pwd)/output"
SCRIPT_DIR=$(pwd)

echo "PACKAGE_NAME: $PACKAGE_NAME"
echo "PACKAGE_VERSION: $PACKAGE_VERSION"
echo "PACKAGE_URL: $PACKAGE_URL"
echo "OUTPUT_FOLDER: $OUTPUT_FOLDER"

# Install dependencies
echo "Installing dependencies..."
yum install -y git wget gcc-toolset-13 gcc-toolset-13-gcc-gfortran python3.12 python3.12-devel python3.12-pip openssl-devel make cmake
export PATH=/opt/rh/gcc-toolset-13/root/usr/bin:$PATH
export LD_LIBRARY_PATH=/opt/rh/gcc-toolset-13/root/usr/lib64:$LD_LIBRARY_PATH

# #clone and install openblas from source
git clone https://github.com/OpenMathLib/OpenBLAS
cd OpenBLAS
git checkout v0.3.29
git submodule update --init

PREFIX=local/openblas
OPENBLAS_SOURCE=$(pwd)

# Set build options
declare -a build_opts
# Fix ctest not automatically discovering tests
LDFLAGS=$(echo "${LDFLAGS}" | sed "s/-Wl,--gc-sections//g")
export CF="${CFLAGS} -Wno-unused-parameter -Wno-old-style-declaration"

unset CFLAGS
export USE_OPENMP=1
build_opts+=(USE_OPENMP=${USE_OPENMP})
export PREFIX=${PREFIX}

# Handle Fortran flags
if [ ! -z "$FFLAGS" ]; then
    export FFLAGS="${FFLAGS/-fopenmp/ }"
    export FFLAGS="${FFLAGS} -frecursive"
    export LAPACK_FFLAGS="${FFLAGS}"
fi

export PLATFORM=$(uname -m)
build_opts+=(BINARY="64")
build_opts+=(DYNAMIC_ARCH=1)
build_opts+=(TARGET="CORE2")
BUILD_BFLOAT16=1

# Placeholder for future builds that may include ILP64 variants.
build_opts+=(INTERFACE64=0)
build_opts+=(SYMBOLSUFFIX="")

# Build LAPACK
build_opts+=(NO_LAPACK=0)

# Enable threading and set the number of threads
build_opts+=(USE_THREAD=1)
build_opts+=(NUM_THREADS=8)

# Disable CPU/memory affinity handling to avoid problems with NumPy and R
build_opts+=(NO_AFFINITY=1)

# Build OpenBLAS
make -j8 ${build_opts[@]} CFLAGS="${CF}" FFLAGS="${FFLAGS}" prefix=${PREFIX}

# Install OpenBLAS
CFLAGS="${CF}" FFLAGS="${FFLAGS}" make install PREFIX="${PREFIX}" ${build_opts[@]}
OpenBLASInstallPATH=$(pwd)/$PREFIX
OpenBLASConfigFile=$(find . -name OpenBLASConfig.cmake)
OpenBLASPCFile=$(find . -name openblas.pc)

sed -i "/OpenBLAS_INCLUDE_DIRS/c\SET(OpenBLAS_INCLUDE_DIRS ${OpenBLASInstallPATH}/include)" ${OpenBLASConfigFile}
sed -i "/OpenBLAS_LIBRARIES/c\SET(OpenBLAS_INCLUDE_DIRS ${OpenBLASInstallPATH}/include)" ${OpenBLASConfigFile}
sed -i "s|libdir=local/openblas/lib|libdir=${OpenBLASInstallPATH}/lib|" ${OpenBLASPCFile}
sed -i "s|includedir=local/openblas/include|includedir=${OpenBLASInstallPATH}/include|" ${OpenBLASPCFile}

export LD_LIBRARY_PATH="$OpenBLASInstallPATH/lib"
export PKG_CONFIG_PATH="$OpenBLASInstallPATH/lib/pkgconfig:${PKG_CONFIG_PATH}"

echo " ------------------------------------------ Openblas Successfully Installed ------------------------------------------ "

cd ${SCRIPT_DIR}

pip3.12 install numpy==2.0.2 packaging pathspec pluggy scipy==1.15.2 scikit-learn==1.6.1 trove-classifiers wheel build hatchling joblib threadpoolctl
pip3.12 install pytest hypothesis pandas matplotlib pyarrow dask modin shap  pyspark

# Clone the repository
echo "Cloning the repository..."
mkdir -p output
git clone $PACKAGE_URL
cd $PACKAGE_NAME/
git checkout $PACKAGE_VERSION
git submodule update --init
export SRC_DIR=$(pwd)
echo "SRC_DIR: $SRC_DIR"

# Apply the patch
echo "------------------------Applying patch-------------------"
PATCH_FILE="$SCRIPT_DIR/0001-renaming-the-package-name.patch"
wget -O "$PATCH_FILE" https://raw.githubusercontent.com/i-wheels-cpd/build-scripts/refs/heads/main/x/xgboost/0001-renaming-the-package-name.patch

cd "$SRC_DIR"
if git apply "$PATCH_FILE"; then
    echo "Patch applied successfully."
else
    echo "Patch failed to apply. Injecting wheel section manually..."
    PYPROJECT_FILE="$SRC_DIR/python-package/pyproject.toml"
    if ! grep -q "\[tool.hatch.build.targets.wheel\]" "$PYPROJECT_FILE"; then
        echo -e "\n[tool.hatch.build.targets.wheel]\npackages = [\"xgboost/\"]" >> "$PYPROJECT_FILE"
    fi
fi

# Verify patch effect
grep -A 2 '\[tool.hatch.build.targets.wheel\]' "$SRC_DIR/python-package/pyproject.toml" || {
    echo "Patch section not found. Failing build."
    exit 1
}

echo "-----------------------Patch application completed---------------------------------------"

#build xgboost cpp artifacts
cd ${SCRIPT_DIR} && mkdir output && OUTPUT_FOLDER=$(pwd)
cd ${SRC_DIR}
mkdir -p build
cd build
cmake -DCMAKE_INSTALL_PREFIX=${OUTPUT_FOLDER} ..
make -j$(nproc)
LIBDIR=${OUTPUT_FOLDER}/lib
INCDIR=${OUTPUT_FOLDER}/include
BINDIR=${OUTPUT_FOLDER}/bin
SODIR=${LIBDIR}
XGBOOSTDSO=libxgboost.so
EXEEXT=
mkdir -p ${LIBDIR} ${INCDIR}/xgboost ${BINDIR} || true
cp ${SRC_DIR}/lib/${XGBOOSTDSO} ${SODIR}
cp -Rf ${SRC_DIR}/include/xgboost ${INCDIR}/
cp -Rf ${SRC_DIR}/rabit/include/rabit ${INCDIR}/xgboost/
cp -f ${SRC_DIR}/src/c_api/*.h ${INCDIR}/xgboost/
cd ../../

# Build xgboost python artifacts and wheel
echo "Building xgboost Python artifacts and wheel..."
cd "$(pwd)/$PACKAGE_DIR"
echo "Current directory: $(pwd)"

# Remove the nvidia-nccl-cu12 dependency in pyproject.toml (not required for Power)
echo "Removing nvidia-nccl-cu12 dependency from pyproject.toml..."
sed -i '/nvidia-nccl-cu12/d' pyproject.toml

# install package
if ! (pip3.12 install .); then
    echo "------------------$PACKAGE_NAME:Install_fails-------------------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME | $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail | Install_Fails"
    exit 1
fi
echo "Build and installation completed successfully."

cd $SCRIPT_DIR
cd $PACKAGE_NAME
echo "Current directory: $(pwd)"

#skipping tests related to gpu and other server setups
if pytest tests/ --ignore=tests/ci_build/test_r_package.py --ignore=tests/python/test_cli.py --ignore=tests/python/test_demos.py --ignore=tests/python/test_openmp.py --ignore=tests/python/test_tracker.py --ignore=tests/python-gpu/ --ignore=tests/test_distributed/test_gpu_with_dask --ignore=tests/test_distributed/test_with_dask/test_demos.py --ignore=tests/test_distributed/test_with_dask/test_with_dask.py --ignore=tests/test_distributed/test_with_spark --ignore=tests/test_distributed/test_gpu_with_spark --ignore=tests/test_distributed/test_federated/test_federated.py --ignore=tests/test_distributed/test_gpu_federated/test_gpu_federated.py; then
    echo " ------------------------ $PACKAGE_NAME:Both_Install_and_Test_Success ------------------------ "
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Pass |  Both_Install_and_Test_Success"
    exit 2
else
    echo " ------------------------ $PACKAGE_NAME:Install_success_but_test_Fails ------------------------ "
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub  | Fail |  Install_success_but_test_Fails"
    exit 0
fi
cd $PACKAGE_DIR
