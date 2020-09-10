FROM ubuntu:latest AS build-env
ENV DEBIAN_FRONTEND noninteractive

LABEL maintainer="PDOK dev <pdok@kadaster.nl>"
ENV TZ Europe/Amsterdam

ENV GDAL_VERSION="3.1.3"
ENV GDAL_SHA="3156036cd71e54932a4043111793c0d4257d46ca2c1c33ebae7be80665bdc403"
ARG GDAL_DOWNLOAD_URL="https://github.com/OSGeo/gdal/releases/download/v${GDAL_VERSION}/gdal-${GDAL_VERSION}.tar.gz"

ENV MAPSERVER_VERSION="mapserver-7.6.1"
ENV MAPSERVER_SHA="2d250874d55bee44e0dbbb3a38e612f8572730705edada00c6ab8b2c9e890581"
ARG MAPSERVER_DOWNLOAD_URL="https://download.osgeo.org/mapserver/${MAPSERVER_VERSION}.tar.gz"

# Setup build environment
RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential wget autoconf ca-certificates automake libpng-dev libproj-dev libfreetype6-dev libfcgi-dev

# Download sources
RUN wget ${GDAL_DOWNLOAD_URL} && \
    echo ${GDAL_SHA} gdal-${GDAL_VERSION}.tar.gz | sha256sum -c -

RUN wget ${MAPSERVER_DOWNLOAD_URL} && \
    echo ${MAPSERVER_SHA} ${MAPSERVER_VERSION}.tar.gz | sha256sum -c -

# Build gdal
RUN tar xzvf gdal-${GDAL_VERSION}.tar.gz && \
    cd /gdal-${GDAL_VERSION} && \
    ./configure --with-libtiff=internal && make && make install

# Build mapserver
RUN tar xzvf ${MAPSERVER_VERSION}.tar.gz && \
    cd /${MAPSERVER_VERSION} && \
    mkdir build && cd build && \
    cmake -DCMAKE_PREFIX_PATH=/opt/gdal -DWITH_FCGI=1 && \ 
    make && make install && ldconfig

FROM pdok/lighttpd:1.4-1 as service
LABEL maintainer="PDOK dev <pdok@kadaster.nl>"

ENV DEBIAN_FRONTEND noninteractive
ENV TZ Europe/Amsterdam

COPY --from=build-env /usr/local/bin /usr/local/bin
COPY --from=build-env /usr/local/lib /usr/local/lib

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
