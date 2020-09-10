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
    apt-get install -y --no-install-recommends build-essential cmake wget autoconf ca-certificates automake libpng-dev libfreetype6-dev libfcgi-dev sqlite3 libsqlite3-dev libtool

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
RUN tar xzvf proj-datumgrid-latest.tar.gz

# Build proj
RUN tar xzvf proj-${PROJ_VERSION}.tar.gz && \
    cd /proj-${PROJ_VERSION} && \
    ./configure --prefix=/build/proj && make && make install

# Build gdal
RUN tar xzvf gdal-${GDAL_VERSION}.tar.gz && \
    cd /gdal-${GDAL_VERSION} && \
    ./configure --prefix=/build/gdal --with-proj=/build/proj LDFLAGS="-L/build/proj/lib" CPPFLAGS="-I/build/proj/include" \ 
    --prefix=/builds/gdal --with-threads --with-libtiff=internal --with-geotiff=internal --with-jpeg=internal --with-gif=internal --with-png=internal --with-libz=internal && \ 
    make && make install

# Build mapserver
RUN tar xzvf ${MAPSERVER_VERSION}.tar.gz && \
    cd /${MAPSERVER_VERSION} && \
    mkdir build && cd build && \
    cmake ../ -DCMAKE_PREFIX_PATH=/build/gdal -DWITH_FCGI=1 && \ 
    make && make install DESTDIR="/build/mapserver" && ldconfig

FROM pdok/lighttpd:1.4-1 as service
LABEL maintainer="PDOK dev <pdok@kadaster.nl>"

ENV DEBIAN_FRONTEND noninteractive
ENV TZ Europe/Amsterdam

COPY --from=build-env  /build/proj-datumgrid-latest/ /usr/share/proj
COPY --from=build-env  /build/proj/share/proj/ /usr/share/proj/
COPY --from=build-env  /build/proj/include/ /usr/include/
COPY --from=build-env  /build/proj/bin/ /usr/bin/
COPY --from=build-env  /build/proj/lib/ /usr/lib/

COPY --from=build-env  /build/gdal/ /usr/share/gdal/

COPY --from=build-env /build/mapserver/bin /usr/local/bin
COPY --from=build-env /build/mapserver/lib /usr/local/lib

COPY etc/lighttpd.conf /lighttpd.conf

RUN chmod o+x /usr/local/bin/mapserv
RUN apt-get clean

ENV DEBUG 0
ENV MIN_PROCS 1
ENV MAX_PROCS 3
ENV MAX_LOAD_PER_PROC 4
ENV IDLE_TIMEOUT 20

EXPOSE 80

CMD ["lighttpd", "-D", "-f", "/lighttpd.conf"]
