`#!/bin/bash -e
# -----------------------------------------------------------------------------
#
# Package          : tensorflow-datasets
# Version          : v4.9.7
# Source repo      : https://github.com/tensorflow/datasets
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

PACKAGE_NAME=datasets
PACKAGE_VERSION=${1:-v4.9.7}
PACKAGE_URL=https://github.com/tensorflow/datasets
PACKAGE_DIR=datasets

CURRENT_DIR=${PWD}

yum install -y git make cmake zip tar wget python3.12 python3.12-devel python3.12-pip gcc-toolset-13 gcc-toolset-13-gcc-c++ gcc-toolset-13-gcc zlib-devel libjpeg-devel openssl openssl-devel freetype-devel pkgconfig ninja-build sqlite-devel rsync

python3.12 -m pip install setuptools wheel build

export GCC_TOOLSET_PATH=/opt/rh/gcc-toolset-13/root/usr
export PATH=$GCC_TOOLSET_PATH/bin:$PATH

# Set up environment variables for GCC 13
export GCC_HOME=/opt/rh/gcc-toolset-13/root/usr
export CC=$GCC_HOME/bin/gcc
export CXX=$GCC_HOME/bin/g++
export GCC=$CC
export GXX=$CXX

INSTALL_ROOT="/install-deps"
mkdir -p $INSTALL_ROOT

for package in libprotobuf protobuf lame opus libvpx ffmpeg; do
    mkdir -p ${INSTALL_ROOT}/${package}
    export "${package^^}_PREFIX=${INSTALL_ROOT}/${package}"
    echo "Exported ${package^^}_PREFIX=${INSTALL_ROOT}/${package}"
done

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

echo " --------------------------------- Abseil-Cpp Cloning --------------------------------- "

# Set ABSEIL_VERSION and ABSEIL_URL
ABSEIL_VERSION=20240116.2
ABSEIL_URL="https://github.com/abseil/abseil-cpp"

git clone $ABSEIL_URL -b $ABSEIL_VERSION

echo " --------------------------------- Abseil-Cpp Cloned --------------------------------- "

#Building libprotobuf
echo " --------------------------------- Libprotobuf Installing --------------------------------- "

git clone https://github.com/protocolbuffers/protobuf
cd protobuf
git checkout v4.25.8
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
    -DCMAKE_C_COMPILER=$CC \
    -DCMAKE_CXX_COMPILER=$CXX \
    -DCMAKE_INSTALL_PREFIX=$LIBPROTOBUF_PREFIX \
    -Dprotobuf_BUILD_TESTS=OFF \
    -Dprotobuf_BUILD_LIBUPB=OFF \
    -Dprotobuf_BUILD_SHARED_LIBS=ON \
    -Dprotobuf_ABSL_PROVIDER="module" \
    -DCMAKE_PREFIX_PATH=$ABSEIL_PREFIX \
    -Dprotobuf_JSONCPP_PROVIDER="package" \
    -Dprotobuf_USE_EXTERNAL_GTEST=OFF \
    ..

cmake --build . --verbose
cmake --install .
cd ..

export PATH=$LIBPROTOBUF_PREFIX/bin:$PATH
export PROTOC="$LIBPROTOBUF_PREFIX/bin/protoc"
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=cpp
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION_VERSION=2
export LIBRARY_PATH="${LIBPROTOBUF_PREFIX}/lib64:$LD_LIBRARY_PATH"
export LD_LIBRARY_PATH=${LIBPROTOBUF_PREFIX}/lib64:$LD_LIBRARY_PATH
export PKG_CONFIG_PATH=${LIBPROTOBUF_PREFIX}/lib/pkgconfig:$PKG_CONFIG_PATH
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=cpp
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION_VERSION=2
wget https://raw.githubusercontent.com/ppc64le/build-scripts/refs/heads/master/p/protobuf/set_cpp_to_17_v4.25.3.patch
git apply set_cpp_to_17_v4.25.3.patch
echo "----------------libprotobuf patch applied successfully---------------------"

cd python
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=cpp
python3.12 -m pip install . --no-build-isolation
python3.12 setup.py bdist_wheel --cpp_implementation
python3.12 -m pip install dist/*.whl --force-reinstall

protoc --version
python3.12 -c "import google.protobuf; print(google.protobuf.__version__)"
echo " --------------------------------- Libprotobuf Successfully Installed --------------------------------- "
cd $CURRENT_DIR

git clone https://github.com/opencv/opencv-python
cd opencv-python
git checkout 84
git submodule update --init
export ENABLE_HEADLESS=1
export CMAKE_ARGS="-DBUILD_TESTS=ON
                   -DCMAKE_BUILD_TYPE=Release
                   -DWITH_EIGEN=1
                   -DBUILD_TESTS=1
                   -DBUILD_ZLIB=0
                   -DBUILD_TIFF=0
                   -DBUILD_PNG=0
                   -DBUILD_JASPER=0
                   -DWITH_ITT=1
                   -DBUILD_JPEG=0
                   -DBUILD_LIBPROTOBUF_FROM_SOURCES=OFF
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
                   -DWITH_GPHOTO2=0
                   -DINSTALL_C_EXAMPLES=0
                   -DBUILD_PROTOBUF=OFF
                   -DPROTOBUF_UPDATE_FILES=ON"

python3.12 -m pip install numpy==2.0.2 scikit-build setuptools build wheel cython
export C_INCLUDE_PATH=$(python3.12 -c "import numpy; print(numpy.get_include())")
export CPLUS_INCLUDE_PATH=$C_INCLUDE_PATH
sed -i 's/"setuptools==59.2.0"/"setuptools==59.2.0; python_version<\x273.12\x27"/' pyproject.toml
sed -i '/"setuptools==59.2.0; python_version<\x273.12\x27"/a \  "setuptools<70.0.0; python_version>=\x273.12\x27",' pyproject.toml
python3.12 -m pip install .
echo " --------------------------------- Opencv-Python-headless Successfully Installed --------------------------------- "
cd $CURRENT_DIR

# Installing zarr required for tests
git clone https://github.com/zarr-developers/zarr-python.git
cd zarr-python
python3.12 -m pip install -U pip setuptools wheel scikit-image mlcroissant==1.0.12
python3.12 -m pip install -e .
python3.12 -c "import zarr; print(zarr.__version__)"
cd $CURRENT_DIR


# Installing cocoapi required for tests
git clone https://github.com/cocodataset/cocoapi.git
cd cocoapi/PythonAPI
python3.12 -m pip install .
cd $CURRENT_DIR
python3.12 -c "from pycocotools.coco import COCO; print('pycocotools installed successfully')"
cd $CURRENT_DIR

cd $CURRENT_DIR
git clone $PACKAGE_URL
cd $PACKAGE_NAME
git checkout $PACKAGE_VERSION

wget https://raw.githubusercontent.com/i-wheels-cpd/build-scripts/refs/heads/main/t/tensorflow-datasets/tensorflow-datasets_v4.9.7.patch
git apply tensorflow-datasets_v4.9.7.patch


#Build package
if ! (python3.12 -m pip install .) ; then
    echo "------------------$PACKAGE_NAME:install_fails-------------------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail |  Install_Fails"
    exit 1
fi


#Installing test dependencies
python3.12 -m pip install pytest dill pyyaml cloudpickle pydub tensorflow_docs google-auth gcsfs conllu bs4 pretty_midi tifffile tldextract langdetect lxml mwparserfromhell nltk==3.8.1 tensorflow==2.18.1 array-record psutil pyarrow dm-tree attrs etils[enp,epath,etree] numpy==2.0.2 importlib_resources tqdm tensorflow_metadata promise click toml requests termcolor wrapt immutabledict simple_parsing mlcroissant pandas apache_beam pillow jax matplotlib
 
python3.12 -m pip install datasets --use-feature=fast-deps


# Run import test
# Skipping ffmpeg-related tests due to disabled codecs during ffmpeg build;Some require Google Cloud access, and a few pass individually but fail when run with the full test suite.
if ! pytest -k "not test_download_and_prepare_as_dataset and not test_download_and_prepare and not test_read_from_tfds and not test_subsplit_failure_with_batch_size and not test_read_write and not test_load_from_gcs and not test_beam_view_builder_with_configs_load and not test_reading_from_gcs_bucket and not test_compute_split_info and not test_add_dataset_provider_to_start and not test_split_for_jax_process and not test_download_dataset and not test_is_dataset_accessible and not test_mnist and not test_empty_split and not test_write_tfrecord and not test_write_tfrecord_sorted_by_key and not test_write_tfrecord_sorted_by_key_with_holes and not test_write_tfrecord_with_duplicates and not test_write_tfrecord_with_ignored_duplicates and not test_import_tfds_without_loading_tf and not test_internal_datasets_have_versions_on_line_with_the_release_notes and not test_badwords_filter and not test_paragraph_filter and not test_remove_duplicate_text and not test_soft_badwords_filter and not test_baseclass and not test_info and not test_registered and not test_session and not test_tags_are_valid and not test_import2 and not test_video_ffmpeg and not test_video_numpy and not test_video_concatenated_frames and not test_image and not test_image_nested_empty_len and not test_image_unknown_len and not test_protos_did_not_change_on_tensorflow_side"; then
    echo "------------------$PACKAGE_NAME:install_success_but_test_fails---------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | $OS_NAME | GitHub | Fail |  Install_success_but_test_Fails"
    exit 2
else
    echo "------------------$PACKAGE_NAME:install_&_test_both_success-------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | $OS_NAME | GitHub  | Pass |  Both_Install_and_Test_Success"
    exit 0
fi









