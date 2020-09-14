FROM ubuntu:latest AS build-env
ENV DEBIAN_FRONTEND noninteractive

LABEL maintainer="PDOK dev <pdok@kadaster.nl>"
ENV TZ Europe/Amsterdam

ENV PROJGRID_SHA="3ff6618a0acc9f0b9b4f6a62e7ff0f7bf538fb4f74de47ad04da1317408fcc15"

ENV PROJ_VERSION="7.1.1"
ENV PROJ_SHA="324e7abb5569fb5f787dadf1d4474766915c485a188cf48cf07153b99156b5f9"
ARG PROJ_DOWNLOAD_URL="https://github.com/OSGeo/PROJ/releases/download/${PROJ_VERSION}/proj-${PROJ_VERSION}.tar.gz"

ENV GDAL_VERSION="3.1.3"
ENV GDAL_SHA="3156036cd71e54932a4043111793c0d4257d46ca2c1c33ebae7be80665bdc403"
ARG GDAL_DOWNLOAD_URL="https://github.com/OSGeo/gdal/releases/download/v${GDAL_VERSION}/gdal-${GDAL_VERSION}.tar.gz"

ENV MAPSERVER_VERSION="mapserver-7.6.1"
ENV MAPSERVER_SHA="2d250874d55bee44e0dbbb3a38e612f8572730705edada00c6ab8b2c9e890581"
ARG MAPSERVER_DOWNLOAD_URL="https://download.osgeo.org/mapserver/${MAPSERVER_VERSION}.tar.gz"

# Setup build environment
RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential cmake wget autoconf ca-certificates automake curl libxml2-dev libpng-dev libfreetype6-dev libfcgi-dev libtiff-dev libcurl4-openssl-dev sqlite3 libsqlite3-dev libtool pkg-config

# Download sources
RUN wget https://download.osgeo.org/proj/proj-datumgrid-latest.tar.gz && \
    echo ${PROJGRID_SHA} proj-datumgrid-latest.tar.gz | sha256sum -c -

RUN wget ${PROJ_DOWNLOAD_URL} && \
    echo ${PROJ_SHA} proj-${PROJ_VERSION}.tar.gz | sha256sum -c -

RUN wget ${GDAL_DOWNLOAD_URL} && \
    echo ${GDAL_SHA} gdal-${GDAL_VERSION}.tar.gz | sha256sum -c -

RUN wget ${MAPSERVER_DOWNLOAD_URL} && \
    echo ${MAPSERVER_SHA} ${MAPSERVER_VERSION}.tar.gz | sha256sum -c -

RUN mkdir /build

# Build PROJGRID
RUN mkdir grid && tar xzvf proj-datumgrid-latest.tar.gz -C grid

# Build proj
RUN tar xzvf proj-${PROJ_VERSION}.tar.gz && \
    cd /proj-${PROJ_VERSION} && \
    ./configure --prefix=/build/proj && make -j$(nproc) && make install

# Build gdal
RUN tar xzvf gdal-${GDAL_VERSION}.tar.gz && \
    cd /gdal-${GDAL_VERSION} && \
    ./configure --prefix=/build/gdal --with-proj=/build/proj LDFLAGS="-L/build/proj/lib" CPPFLAGS="-I/build/proj/include" \ 
    --prefix=/build/gdal --with-threads --with-libtiff=internal --with-geotiff=internal --with-jpeg=internal --with-gif=internal --with-png=internal --with-libz=internal && \ 
    make -j$(nproc) && make install

# Build mapserver
RUN tar xzvf ${MAPSERVER_VERSION}.tar.gz && \
    cd /${MAPSERVER_VERSION} && \
    mkdir build && cd build && \
    cmake -DWITH_GIF=0 -DWITH_POSTGIS=0 -DWITH_PROTOBUFC=0 -DWITH_GEOS=0 \
    -DWITH_FRIBIDI=0 -DWITH_HARFBUZZ=0 -DWITH_CAIRO=0 -DWITH_FCGI=1 \
    -DCMAKE_PREFIX_PATH=/build/gdal:/build/proj:/usr/local:/opt -DCMAKE_INSTALL_PREFIX=/build/mapserver \
    -DPROJ_INCLUDE_DIR=/build/proj/include -DPROJ_LIBRARY=/build/proj/lib/libproj.so \ 
    -DGDAL_INCLUDE_DIR=/build/gdal/include -DGDAL_LIBRARY=/build/gdal/lib/libgdal.so \ 
    ../ > ../configure.out.txt && \
    make -j$(nproc) && make install && ldconfig

FROM ubuntu:latest
LABEL maintainer="PDOK dev <pdok@kadaster.nl>"

ENV DEBIAN_FRONTEND noninteractive
ENV TZ Europe/Amsterdam
ENV PATH="/build/proj/bin:/build/proj/lib:/build/gdal/bin:/build/gdal/lib:/build/mapserver/lib:${PATH}"

RUN apt-get -y update && \
    apt-get install -y --no-install-recommends lighttpd lighttpd-mod-magnet && \
    apt-get install -y --no-install-recommends libxml2-dev libpng-dev libfreetype6-dev libfcgi-dev libtiff-dev libcurl4-openssl-dev sqlite3 libsqlite3-dev && \
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
