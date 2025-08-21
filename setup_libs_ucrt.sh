#!/bin/bash

pushd c_libs/freetype_build
rm -rf buildwin
meson setup buildwin -Dbrotli=disabled -Dbzip2=disabled -Dharfbuzz=disabled -Dpng=disabled -Dzlib=disabled -Ddefault_library=static
meson compile -C buildwin

popd
pushd c_libs/SDL

rm -rf buildwin
rm -rf SDLBUILD

cmake -S "." \
    -B buildwin -G Ninja \
    -D CMAKE_BUILD_TYPE=None \
    -D CMAKE_INSTALL_PREFIX=SDLBUILD \
    -D SDL_STATIC=ON \
    -D SDL_SHARED=OFF \
    -D SDL_RPATH=OFF

cmake --build buildwin


popd

pushd c_libs/libepoxy
rm -rf buildwin
meson setup buildwin  -Ddefault_library=static -Dbuildtype=release
meson compile -C buildwin

popd

pushd c_libs/miniz
rm -rf buildwin
meson setup buildwin
meson compile -C buildwin
popd
