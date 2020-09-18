FROM ubuntu:latest AS build-env
ENV DEBIAN_FRONTEND noninteractive

LABEL maintainer="PDOK dev <pdok@kadaster.nl>"
ENV TZ Europe/Amsterdam

ENV PROJGRID_SHA="3ff6618a0acc9f0b9b4f6a62e7ff0f7bf538fb4f74de47ad04da1317408fcc15"

ENV PROJ_VERSION="7.1.1"
ENV PROJ_SHA="324e7abb5569fb5f787dadf1d4474766915c485a188cf48cf07153b99156b5f9"
ARG PROJ_DOWNLOAD_URL="https://github.com/OSGeo/PROJ/releases/download/${PROJ_VERSION}/proj-${PROJ_VERSION}.tar.gz"

ENV WEBP_VERSION="1.1.0"
ENV WEBP_SHA="98a052268cc4d5ece27f76572a7f50293f439c17a98e67c4ea0c7ed6f50ef043"
ARG WEBP_DOWNLOAD_URL="https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-${WEBP_VERSION}.tar.gz"

ENV LIBTIFF_VERSION="4.1.0"
ENV LIBTIFF_SHA="5d29f32517dadb6dbcd1255ea5bbc93a2b54b94fbf83653b4d65c7d6775b8634"
ARG LIBTIFF_DOWNLOAD_URL="https://download.osgeo.org/libtiff/tiff-${LIBTIFF_VERSION}.tar.gz"

ENV CURL_VERSION="7.72.0"
ENV CURL_SHA="d4d5899a3868fbb6ae1856c3e55a32ce35913de3956d1973caccd37bd0174fa2"
ARG CURL_DOWNLOAD_URL="https://curl.haxx.se/download/curl-${CURL_VERSION}.tar.gz"

ENV GDAL_VERSION="3.1.3"
ENV GDAL_SHA="3156036cd71e54932a4043111793c0d4257d46ca2c1c33ebae7be80665bdc403"
ARG GDAL_DOWNLOAD_URL="https://github.com/OSGeo/gdal/releases/download/v${GDAL_VERSION}/gdal-${GDAL_VERSION}.tar.gz"

ENV MAPSERVER_VERSION="mapserver-7.6.1"
ENV MAPSERVER_SHA="2d250874d55bee44e0dbbb3a38e612f8572730705edada00c6ab8b2c9e890581"
ARG MAPSERVER_DOWNLOAD_URL="https://download.osgeo.org/mapserver/${MAPSERVER_VERSION}.tar.gz"

# Setup build environment
RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential cmake wget autoconf ca-certificates automake \
    curl libxml2-dev libpng-dev libfreetype6-dev libjpeg-dev libfcgi-dev sqlite3 libsqlite3-dev libtool pkg-config \
    libwebp-dev

# Download sources
RUN wget https://download.osgeo.org/proj/proj-datumgrid-latest.tar.gz && \
    echo ${PROJGRID_SHA} proj-datumgrid-latest.tar.gz | sha256sum -c -

RUN wget ${PROJ_DOWNLOAD_URL} && \
    echo ${PROJ_SHA} proj-${PROJ_VERSION}.tar.gz | sha256sum -c -

RUN wget ${WEBP_DOWNLOAD_URL} && \
    echo ${WEBP_SHA} libwebp-${WEBP_VERSION}.tar.gz | sha256sum -c -

RUN wget ${LIBTIFF_DOWNLOAD_URL} && \
    echo ${LIBTIFF_SHA} tiff-${LIBTIFF_VERSION}.tar.gz | sha256sum -c -

RUN wget ${CURL_DOWNLOAD_URL} && \
    echo ${CURL_SHA} curl-${CURL_VERSION}.tar.gz | sha256sum -c -

RUN wget ${GDAL_DOWNLOAD_URL} && \
    echo ${GDAL_SHA} gdal-${GDAL_VERSION}.tar.gz | sha256sum -c -

RUN wget ${MAPSERVER_DOWNLOAD_URL} && \
    echo ${MAPSERVER_SHA} ${MAPSERVER_VERSION}.tar.gz | sha256sum -c -

RUN mkdir /build

# Build webp
RUN tar xzf libwebp-${WEBP_VERSION}.tar.gz && \
    cd libwebp-${WEBP_VERSION} && \
    CFLAGS="-O2 -Wl,-S" ./configure --prefix=/build/webp --enable-silent-rules && \
    make -j$(nproc) && make install

# Build libtiff
RUN tar -xzf tiff-${LIBTIFF_VERSION}.tar.gz && \
    cd tiff-${LIBTIFF_VERSION} && \
    ./configure --prefix=/build/libtiff && \
    make -j$(nproc) && make install

# Build curl
RUN tar -xzf curl-${CURL_VERSION}.tar.gz && cd curl-${CURL_VERSION} && \
    ./configure --prefix=/build/curl && \
    make -j$(nproc) && make install

# Build PROJGRID
RUN mkdir grid && tar xzvf proj-datumgrid-latest.tar.gz -C grid

# Build proj
RUN tar xzvf proj-${PROJ_VERSION}.tar.gz && \
    cd /proj-${PROJ_VERSION} && \
    TIFF_LIBS="-L/build/libtiff/lib -ltiff" TIFF_CFLAGS="-I/build/libtiff/include" ./configure --with-curl="/build/curl/bin/curl-config" --prefix=/build/proj && make -j$(nproc) && make install

# Build gdal
RUN tar xzvf gdal-${GDAL_VERSION}.tar.gz && \
    cd /gdal-${GDAL_VERSION} && \
    ./configure --prefix=/build/gdal --with-proj=/build/proj LDFLAGS="-L/build/proj/lib" CPPFLAGS="-I/build/proj/include" \ 
    --prefix=/build/gdal --with-threads=yes --with-webp=/build/webp --with-libtiff=internal --disable-debug --disable-static \
    --with-geotiff=internal --with-jpeg=internal --with-gif=internal --with-png=internal --with-libz=internal && \ 
    make -j$(nproc) && make install

# Build mapserver
RUN tar xzvf ${MAPSERVER_VERSION}.tar.gz && \
    cd /${MAPSERVER_VERSION} && \
    mkdir build && cd build && \
    cmake -DWITH_GIF=0 -DWITH_POSTGIS=0 -DWITH_PROTOBUFC=0 -DWITH_GEOS=0 \
    -DWITH_FRIBIDI=0 -DWITH_HARFBUZZ=0 -DWITH_CAIRO=0 -DWITH_FCGI=1 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH=/build/curl:/build/libtiff:/build/gdal:/build/proj:/usr/local:/opt -DCMAKE_INSTALL_PREFIX=/build/mapserver \
    -DPROJ_INCLUDE_DIR=/build/proj/include -DPROJ_LIBRARY=/build/proj/lib/libproj.so \ 
    -DGDAL_INCLUDE_DIR=/build/gdal/include -DGDAL_LIBRARY=/build/gdal/lib/libgdal.so \ 
    ../ > ../configure.out.txt && \
    make -j$(nproc) && make install && ldconfig

FROM ubuntu:latest
LABEL maintainer="PDOK dev <pdok@kadaster.nl>"

ENV DEBIAN_FRONTEND noninteractive
ENV TZ Europe/Amsterdam
ENV PATH="/build/libtiff/bin:/build/libtiff/lib:/build/curl/lib:/build/curl/bin:/build/curl:/build/webp/lib:/build/proj/bin:/build/proj/lib:/build/gdal/bin:/build/gdal/lib:/build/mapserver/lib:${PATH}"

RUN apt-get -y update && \
    apt-get install -y --no-install-recommends lighttpd lighttpd-mod-magnet \ 
            libxml2 libpng16-16 libfreetype6 libfcgi sqlite3 && \
    apt clean 

COPY --from=build-env  /grid /usr/share/proj/
COPY --from=build-env /build /build
COPY etc/lighttpd.conf /lighttpd.conf

RUN chmod o+x /build/mapserver/bin/mapserv
ENV DEBUG 0
ENV MIN_PROCS 1
ENV MAX_PROCS 3
ENV MAX_LOAD_PER_PROC 4
ENV IDLE_TIMEOUT 20

EXPOSE 80

CMD ["lighttpd", "-D", "-f", "/lighttpd.conf"]
