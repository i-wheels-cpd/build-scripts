#!/bin/bash -e
# -----------------------------------------------------------------------------
#
# Package          : tensorflow
# Version          : v2.21.0
# Source repo      : https://github.com/tensorflow/tensorflow
# Tested on        : UBI:10.1
# Language         : Python
# Travis-Check     : True
# Script License   : Apache License, Version 2 or later
# Maintainer       : Vibhav Dhaimode <Vibhav.Dhaimode3@ibm.com>
#
# Disclaimer       : This script has been tested in root mode on given
# ==========         platform using the mentioned version of the package.
#                    It may not work as expected with newer versions of the
#                    package and/or distribution. In such case, please
#                    contact "Maintainer" of this script.
#
# ----------------------------------------------------------------------------

set -xe

PACKAGE_NAME=tensorflow
PACKAGE_VERSION=${1:-v2.21.0}
PACKAGE_URL=https://github.com/tensorflow/tensorflow
PACKAGE_DIR=tensorflow

WORK_DIR=${PWD}

yum install -y git python3.12 python3.12-devel python3.12-pip  java-21-openjdk java-21-openjdk-devel clang vim-common openssl openssl-devel cmake --exclude gstreamer1 --skip-broken

python3.12 -m pip install wheel

export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
export PATH=$PATH:$JAVA_HOME/bin

# Use clang as the compiler
export CC=/usr/bin/clang
export CXX=/usr/bin/clang++

INSTALL_ROOT="${WORK_DIR}/install-deps"
mkdir -p $INSTALL_ROOT

for package in openblas hdf5 tensorflow ; do
    mkdir -p ${INSTALL_ROOT}/${package}
    export "${package^^}_PREFIX=${INSTALL_ROOT}/${package}"
    echo "Exported ${package^^}_PREFIX=${INSTALL_ROOT}/${package}"
done

mkdir wheels

echo " --------------------------------- Bazel Installing --------------------------------- "
curl -LO https://github.com/bazelbuild/bazel/releases/download/7.7.0/bazel-7.7.0-linux-x86_64
chmod +x bazel-7.7.0-linux-x86_64
mv bazel-7.7.0-linux-x86_64 /usr/local/bin/bazel

echo " --------------------------------- Bazel Successfully Installed --------------------------------- "

cd $WORK_DIR

echo " --------------------------------- Openblas Installing --------------------------------- "

git clone -b v0.3.33 https://github.com/xianyi/OpenBLAS
cd OpenBLAS
git submodule update --init
python3.12 -m pip install setuptools==82.0.1
LDFLAGS=$(echo "${LDFLAGS}" | sed "s/-Wl,--gc-sections//g")
# See this workaround
# ( https://github.com/xianyi/OpenBLAS/issues/818#issuecomment-207365134 ).
export CF="${CFLAGS} -Wno-unused-parameter -Wno-old-style-declaration"
unset CFLAGS
export USE_OPENMP=1
#TODO: Pass path
build_opts+=(USE_OPENMP=${USE_OPENMP})
if [ ! -z "$FFLAGS" ]; then
    # Don't use GNU OpenMP, which is not fork-safe
    export FFLAGS="${FFLAGS/-fopenmp/ }"
    export FFLAGS="${FFLAGS} -frecursive"
    export LAPACK_FFLAGS="${FFLAGS}"
fi
build_opts+=(BINARY="64")
build_opts+=(DYNAMIC_ARCH=1)
# Set target platform-/CPU-specific options
build_opts+=(TARGET="PRESCOTT")
# Placeholder for future builds that may include ILP64 variants.
build_opts+=(INTERFACE64=0)
build_opts+=(SYMBOLSUFFIX="")
# Build LAPACK.
build_opts+=(NO_LAPACK=0)
# Enable threading. This can be controlled to a certain number by
# setting OPENBLAS_NUM_THREADS before loading the library.
build_opts+=(USE_THREAD=1)
build_opts+=(NUM_THREADS=8)
# Disable CPU/memory affinity handling to avoid problems with NumPy and R
build_opts+=(NO_AFFINITY=1)
#Build:-
make -j8 ${build_opts[@]} \
     HOST=${HOST} CROSS_SUFFIX="${HOST}-" \
     CFLAGS="${CF}" FFLAGS="${FFLAGS}"

CFLAGS="${CF}" FFLAGS="${FFLAGS}" \
    make install PREFIX="${OPENBLAS_PREFIX}" ${build_opts[@]}

cat << 'EOF' > pyproject.toml
[build-system]
requires = [
    "setuptools",
    "wheel",
]
build-backend = "setuptools.build_meta"

[project]
name = "openblas"
version = "0.3.33"
requires-python = ">=3.10"
description = "Provides OpenBLAS for python packaging"
readme = "README.md"
classifiers = [
  "Development Status :: 5 - Production/Stable",
  "Programming Language :: C++",
  "License :: Apache License 2.0",
]
license = {file = "LICENSE.txt"}

[project.urls]
homepage = "https://github.com/xianyi/OpenBLAS"
upstream = "https://github.com/xianyi/OpenBLAS"

[tool.setuptools.packages.find]
namespaces = true
where = ["../install-deps"]

[tool.setuptools.package-data]
openblas = ["lib/*", "include/*", "lib/pkgconfig/*", "lib/cmake/openblas/*"]
EOF

python3.12 -m pip wheel -w dist -v . --no-build-isolation

cp dist/openblas-0.3.33-py3-none-any.whl ../wheels
python3.12 -m pip install dist/openblas-0.3.33-py3-none-any.whl

echo " --------------------------------- OpenBLAS Successfully Installed --------------------------------- "

cd $WORK_DIR

echo " --------------------------------- Numpy Installing --------------------------------- "

# Clone numpy repository
git clone -b v2.2.6 https://github.com/numpy/numpy
cd numpy
git submodule update --init

# Use clang as the compiler (consistent with the rest of the build)
export CC=/usr/bin/clang
export CXX=/usr/bin/clang++
export AR=/usr/bin/ar
export LD=/usr/bin/ld
export NM=/usr/bin/nm
export OBJCOPY=/usr/bin/objcopy
export OBJDUMP=/usr/bin/objdump
export RANLIB=/usr/bin/ranlib
export STRIP=/usr/bin/strip

# Set OpenBLAS paths for numpy
export PKG_CONFIG_PATH="${OPENBLAS_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH}"
export LD_LIBRARY_PATH="${OPENBLAS_PREFIX}/lib:${LD_LIBRARY_PATH}"

# Install numpy build dependencies
python3.12 -m pip install build==1.5.0 meson==1.11.1 meson-python==0.19.0

# Build numpy wheel
python3.12 -m build --wheel

# Install the built numpy wheel
python3.12 -m pip install dist/numpy-2.2.6-cp312-cp312-linux_x86_64.whl
cp dist/numpy-2.2.6-cp312-cp312-linux_x86_64.whl ../wheels

# Verify numpy installation (change directory to avoid importing from source)
cd $WORK_DIR
python3.12 -c "import numpy; print(f'NumPy version: {numpy.__version__}')"

echo " --------------------------------- Numpy Successfully Installed --------------------------------- "

cd $WORK_DIR

# Build SciPy from source using custom OpenBLAS (already built earlier)
echo " --------------------------------- SciPy Installing --------------------------------- "
SCIPY_VERSION="v1.17.1"
SCIPY_URL="https://github.com/scipy/scipy"
git clone $SCIPY_URL
cd scipy
git checkout $SCIPY_VERSION
git submodule update --init

# Set environment variables for SciPy to find custom OpenBLAS
export OpenBLAS_HOME="${OPENBLAS_PREFIX}"
export PKG_CONFIG_PATH="${OPENBLAS_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH}"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${OPENBLAS_PREFIX}/lib"

# Install SciPy build dependencies
python3.12 -m pip install beniget==0.4.2.post1 Cython>=3.1.2 gast==0.6.0 meson==1.6.0 meson-python==0.17.1 packaging pybind11 pyproject-metadata pythran==0.17.0 setuptools==75.3.0 pooch build wheel ninja

# Build and install SciPy from source
if ! python3.12 -m pip wheel . -w dist -v --no-build-isolation; then
    echo "Failed to build SciPy from source with custom OpenBLAS"
    exit 1
fi

python3.12 -m pip install dist/scipy-1.17.1-cp312-cp312-linux_x86_64.whl
cp dist/scipy-1.17.1-cp312-cp312-linux_x86_64.whl ../wheels

echo " --------------------------------- SciPy Successfully Installed --------------------------------- "

cd $WORK_DIR

# Installing Hdf5 from source
echo " --------------------------------- Hdf5 Installing --------------------------------- "

git clone https://github.com/HDFGroup/hdf5
cd hdf5/
git checkout hdf5_2.1.0
git submodule update --init

yum install -y zlib zlib-devel

# Install ninja fo building hdf5
python3.12 -m pip install ninja==1.13.0
# HDF5 2.1.0+ uses CMake build system
mkdir -p build
cd build

cmake -G "Ninja" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=$HDF5_PREFIX \
    -DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
    -DBUILD_SHARED_LIBS=ON \
    -DHDF5_ENABLE_Z_LIB_SUPPORT=ON \
    -DHDF5_BUILD_CPP_LIB=ON \
    -DHDF5_BUILD_FORTRAN=OFF \
    -DHDF5_ENABLE_PARALLEL=OFF \
    -DHDF5_ENABLE_THREADSAFE=ON \
    -DHDF5_ALLOW_UNSUPPORTED=ON \
    -DHDF5_BUILD_HL_LIB=ON \
    -DHDF5_BUILD_TOOLS=ON \
    -DHDF5_BUILD_EXAMPLES=OFF \
    -DBUILD_TESTING=OFF \
    -DHDF5_ENABLE_SZIP_SUPPORT=OFF \
    ..

cmake --build . --parallel $(nproc)
cmake --install .

export LD_LIBRARY_PATH=${HDF5_PREFIX}/lib:$LD_LIBRARY_PATH

cat << 'EOF' > pyproject.toml
[build-system]
requires = [
    "setuptools",
    "wheel",
]
build-backend = "setuptools.build_meta"

#Project name an version
[project]
name = "hdf5"
version = "2.1.0"
requires-python = ">=3.10"

#One line description
description = "Provides hdf5"

#Classifiers to improve package discoverability
classifiers = [
  "Programming Language :: C++",
  "License :: Apache License 2.0",
]

#Project URLs
[project.urls]
homepage = "https://github.com/HDFGroup/hdf5"
upstream = "https://github.com/HDFGroup/hdf5/"

#Find packages files in local folder, this is needed as we are not following standar directory structure of setuptools
[tool.setuptools.packages.find]
# scanning for namespace packages is true by default in pyproject.toml, so
# # you do NOT need to include the following line.
namespaces = true
where = ["../../install-deps"]

[tool.setuptools.package-data]
hdf5 = ["lib/*", "include/*", "bin/", "share/*"]
EOF
python3.12 -m pip wheel -w dist -v . --no-build-isolation
cp dist/hdf5-2.1.0-py3-none-any.whl ../../wheels/
python3.12 -m pip install dist/hdf5-2.1.0-py3-none-any.whl

echo " --------------------------------- Hdf5 Successfully Installed --------------------------------- "

cd $WORK_DIR

#Build h5py from source
echo " --------------------------------- H5py Installing --------------------------------- "

git clone https://github.com/h5py/h5py.git
cd h5py/
git checkout 3.14.0

HDF5_DIR=${HDF5_PREFIX} python3.12 -m pip wheel -w dist -v . --no-build-isolation
cp dist/h5py-3.14.0-cp312-cp312-linux_x86_64.whl ../wheels

cd $WORK_DIR

echo " --------------------------------- H5py Successfully Installed --------------------------------- "


echo " --------------------------------- Libprotobuf Installing --------------------------------- "

# Export library paths for consistent compiler usage across the build
python3.12 -m pip install --upgrade pip==26.1.2 setuptools==82.0.1 wheel==0.47.0 ninja==1.13.0 packaging==26.2 tox==4.55.1 pytest==9.0.3 build==1.5.0 mypy==2.1.0 stubs==1.0.0

export C_COMPILER=$(which clang) CXX_COMPILER=$(which clang++)
echo "C Compiler set to $C_COMPILER"
echo "CXX Compiler set to $CXX_COMPILER"

mkdir -p $(pwd)/local/libprotobuf
LIBPROTO_INSTALL=$(pwd)/local/libprotobuf
echo "LIBPROTO_INSTALL set to $LIBPROTO_INSTALL"

# Clone Source-code

PACKAGE_VERSION_LIB="v6.31.1"
PACKAGE_GIT_URL="https://github.com/protocolbuffers/protobuf"
git clone $PACKAGE_GIT_URL -b $PACKAGE_VERSION_LIB

# Build libprotobuf
echo "protobuf build starts!!"
cd protobuf
git submodule update --init --recursive
rm -rf ./third_party/googletest | true

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
    -Dprotobuf_BUILD_LIBUPB=ON \
    -Dprotobuf_BUILD_SHARED_LIBS=ON \
    -Dprotobuf_ABSL_PROVIDER="module" \
    -Dprotobuf_JSONCPP_PROVIDER="package" \
    -Dprotobuf_USE_EXTERNAL_GTEST=OFF \
    ..

cmake --build . --verbose
cmake --install .


#Build the wheel package
cat << 'EOF' > pyproject.toml
[build-system]
requires = [
    "setuptools",
    "wheel",
]
build-backend = "setuptools.build_meta"

#Project name an version
[project]
name = "libprotobuf"
version = "6.31.1"

#One line description
description = "Provides protoc compiler and C++ files for protobuf"

#Classifiers to improve pacakage discoverability
classifiers = [
  "Development Status :: 5 - Production/Stable",
  "Programming Language :: C++",
  "License :: Apache License 2.0",
]

#During the TF build, it gets pypi protobuf using bazel, and pypi protobuf has no dependencies on abseil_cpp.It fails on complaining that abseil_cpp is not found.
#dependencies = [
#    "abseil_cpp==20240116.2",
#]
#Project URLs
[project.urls]
homepage = "https://github.com/protocolbuffers/protobuf/tree/v4.25.3"
upstream = "https://github.com/protocolbuffers/protobuf/tree/v4.25.3"

#Find packages files in local folder, this is needed as we are not following standar directory structure of setuptools
[tool.setuptools.packages.find]
# scanning for namespace packages is true by default in pyproject.toml, so
# # you do NOT need to include the following line.
namespaces = true
where = ["../../local"]

#Package data to add bazel in wheel, this is needed as its not a .py file
[tool.setuptools.package-data]
libprotobuf = ["bin/**/*", "lib64/**/*", "include/**/*"]
EOF
python3.12 -m pip wheel -w dist -v . --no-build-isolation
cp dist/libprotobuf-6.31.1-py3-none-any.whl ../../wheels/
python3.12 -m pip install dist/libprotobuf-6.31.1-py3-none-any.whl



echo " --------------------------------- Libprotobuf Successfully Installed --------------------------------- "

cd $WORK_DIR

echo " --------------------------------- Protobuf Installing --------------------------------- "

export PROTOC="$LIBPROTO_INSTALL/bin/protoc"
export LD_LIBRARY_PATH="$LIBPROTO_INSTALL/lib64:$LD_LIBRARY_PATH"
export LIBRARY_PATH="$LIBPROTO_INSTALL/lib64:$LD_LIBRARY_PATH"
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=cpp
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION_VERSION=2

python3.12 -m pip install protobuf==6.31.1
python3.12 -m pip download protobuf==6.31.1
cp protobuf-6.31.1-cp39-abi3-manylinux2014_x86_64.whl wheels 

python3.12 -m pip install pybind11==3.0.4
PYBIND11_PREFIX=${VIRTUAL_ENV}/lib/python3.12/site-packages/pybind11

export CMAKE_PREFIX_PATH="$LIBPROTO_INSTALL;$PYBIND11_PREFIX"
echo "Updated CMAKE_PREFIX_PATH after OpenBLAS: $CMAKE_PREFIX_PATH"
export LD_LIBRARY_PATH="$LIBPROTO_INSTALL/lib64:$LD_LIBRARY_PATH"
echo "Updated LD_LIBRARY_PATH : $LD_LIBRARY_PATH"
export LD_LIBRARY_PATH="$(pwd)/../build:$LD_LIBRARY_PATH"

echo " --------------------------------- Protobuf Successfully Installed --------------------------------- "

cd $WORK_DIR

#Build ml_dtypes from source
echo " --------------------------------- ML-Dtypes Installing --------------------------------- "

git clone https://github.com/jax-ml/ml_dtypes.git
cd ml_dtypes
git checkout v0.5.1
git submodule update --init

python3.12 setup.py bdist_wheel
cp dist/ml_dtypes-0.5.1-cp312-cp312-linux_x86_64.whl ../wheels

echo " --------------------------------- ML-Dtypes Successfully Installed --------------------------------- "


cd $WORK_DIR

# Installing Grpc from source
echo " --------------------------------- GRPC Installing --------------------------------- "

git clone https://github.com/grpc/grpc.git
cd grpc
git checkout v1.71.0
git submodule update --init --recursive
# set the variable, when grpcio fails to compile on the system.
export GRPC_PYTHON_BUILD_SYSTEM_OPENSSL=true;
export LDFLAGS="${LDFLAGS} -lrt"
export HDF5_DIR="${HDF5_PREFIX}"
export CFLAGS="-I${HDF5_DIR}/include"
export LDFLAGS="-L${HDF5_DIR}/lib"

python3.12 -m pip install pytest==9.0.3 hypothesis==6.155.1 build==1.5.0 six==1.17.0 coverage==7.14.1 cython==3.2.5 wheel==0.47.0

# Install the package
GRPC_PYTHON_BUILD_SYSTEM_OPENSSL=1 python3.12 setup.py bdist_wheel
python3.12 -m pip install dist/grpcio-1.71.0-cp312-cp312-linux_x86_64.whl
cp dist/grpcio-1.71.0-cp312-cp312-linux_x86_64.whl ../wheels

echo " --------------------------------- GRPC Successfully Installed --------------------------------- "

cd $WORK_DIR

echo " --------------------------------- Tensorflow Installing --------------------------------- "

export CC=/usr/bin/clang
export CXX=/usr/bin/clang++

git clone -b $PACKAGE_VERSION $PACKAGE_URL
cd tensorflow
SRC_DIR=$(pwd)

#Apply patch
wget https://raw.githubusercontent.com/i-wheels-cpd/build-scripts/refs/heads/main/t/tensorflow/tf_2.21.0_fix.patch
git apply tf_2.21.0_fix.patch


#Build the bazelrc
cat <<EOF > ".tf_configure_bazelrc"
build --action_env PYTHON_BIN_PATH="${VIRTUAL_ENV}/bin/python"
build --action_env PYTHON_LIB_PATH="${VIRTUAL_ENV}/lib/python3.12/site-packages"
build --python_path="${VIRTUAL_ENV}/bin/python"
build --action_env CLANG_COMPILER_PATH="/usr/bin/clang"
build --repo_env=CC="/usr/bin/clang"
build --repo_env=BAZEL_COMPILER="/usr/bin/clang"
build:opt --copt=-Wno-sign-compare
build:opt --host_copt=-Wno-sign-compare
test --test_size_filters=small,medium
test:v1 --test_tag_filters=-benchmark-test,-no_oss,-oss_excluded,-gpu,-oss_serial
test:v1 --build_tag_filters=-benchmark-test,-no_oss,-oss_excluded,-gpu
test:v2 --test_tag_filters=-benchmark-test,-no_oss,-oss_excluded,-gpu,-oss_serial,-v1only
test:v2 --build_tag_filters=-benchmark-test,-no_oss,-oss_excluded,-gpu,-v1only
EOF

BAZEL_JOBS="32"
HOST_CPUS=$(nproc --all)

# copy all dependency wheels to dist folder
mkdir -p dist
cp -r ../wheels/*.whl dist

# build using bazel
export BUILD_TARGET="//tensorflow/tools/pip_package:wheel --repo_env=USE_PYWRAP_RULES=1 --repo_env=WHEEL_NAME=tensorflow"

#Build package
cd $SRC_DIR && bazel --bazelrc=$SRC_DIR/.tf_configure_bazelrc build --local_resources=cpu=HOST_CPUS*0.50 --local_resources=ram=HOST_RAM*0.50 --jobs=$BAZEL_JOBS ${BUILD_TARGET}

#Install package
if ! (python3.12 -m pip install bazel-bin/tensorflow/tools/pip_package/wheel_house/tensorflow_cpu-2.21.0-cp312-cp312-linux_x86_64.whl) ; then
    echo "------------------$PACKAGE_NAME:install_fails-------------------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail |  Install_Fails"
    exit 1
fi

echo "-------------------------------tensorflow installation successful-------------------------------------"
 
