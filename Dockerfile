FROM alpine:3.6

# ensure local python is preferred over distribution python
ENV PATH /usr/local/bin:$PATH

# http://bugs.python.org/issue19846
# > At the moment, setting "LANG=C" on a Linux system *fundamentally breaks Python 3*, and that's not OK.
ENV LANG C.UTF-8

# install ca-certificates so that HTTPS works consistently
# the other runtime dependencies for Python are installed later
RUN apk add --no-cache ca-certificates

ENV GPG_KEY 8417157EDBE73D9EAC1E539B126EB563A74B06BF
ENV PYTHON_VERSION 2.6.9

# if this is called "PIP_VERSION", pip explodes with "ValueError: invalid truth value '<VERSION>'"
ENV PYTHON_PIP_VERSION 8.1.2

RUN mkdir -p /usr/src/python
COPY python-2.6-internal-expat.patch /python-2.6-internal-expat.patch
COPY python-2.6-posix-module.patch /python-2.6-posix-module.patch

RUN set -ex \
    && apk add --no-cache --virtual .fetch-deps \
        openssl \
        gnupg \
        tar \
        xz \
    \
    && wget -O python.tar.xz "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz" \
    && wget -O python.tar.xz.asc "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz.asc" \
    && export GNUPGHOME="$(mktemp -d)" \
    && gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$GPG_KEY" \
    && gpg --batch --verify python.tar.xz.asc python.tar.xz \
    && rm -fr "$GNUPGHOME" python.tar.xz.asc \
    && tar -xJC /usr/src/python --strip-components=1 -f python.tar.xz \
    && rm python.tar.xz

RUN apk add --no-cache --virtual .build-deps  \
        gcc \
        libc-dev \
        linux-headers \
        make \
        openssl \
        readline-dev \
        tcl-dev \
        tk \
        tk-dev \
        expat-dev \
        openssl-dev \
        zlib-dev \
        ncurses-dev \
        bzip2-dev \
        gdbm-dev \
        sqlite-dev \
        libffi-dev \
# add build deps before removing fetch deps in case there's overlap
    && apk del .fetch-deps

RUN cd /usr/src/python \
    && mv /python-2.6-internal-expat.patch python-2.6-internal-expat.patch \
    && mv /python-2.6-posix-module.patch python-2.6-posix-module.patch \
    && ls -la \
    && patch -p1 < python-2.6-internal-expat.patch \
    && patch -p1 < python-2.6-posix-module.patch \
    && ./configure --prefix=/usr \
    --enable-shared \
    --with-threads \
    --with-system-ffi \
    --enable-unicode=ucs4 \
    && make -j$(getconf _NPROCESSORS_ONLN) \
    && make install \
    && ln -s /usr/bin/python2.6 /usr/bin/python2 \
    \
        && wget -O /tmp/get-pip.py 'https://bootstrap.pypa.io/get-pip.py' \
        && python2 /tmp/get-pip.py "pip==$PYTHON_PIP_VERSION" \
        && rm /tmp/get-pip.py \
# we use "--force-reinstall" for the case where the version of pip we're trying to install is the same as the version bundled with Python
# ("Requirement already up-to-date: pip==8.1.2 in /usr/local/lib/python3.6/site-packages")
# https://github.com/docker-library/python/pull/143#issuecomment-241032683
    && pip install --no-cache-dir --upgrade --force-reinstall "pip==$PYTHON_PIP_VERSION" \
# then we use "pip list" to ensure we don't have more than one pip version installed
# https://github.com/docker-library/python/pull/100
    && [ "$(pip list |tac|tac| awk -F '[ ()]+' '$1 == "pip" { print $2; exit }')" = "$PYTHON_PIP_VERSION" ] \
    \
    && find /usr/local -depth \
        \( \
            \( -type d -a -name test -o -name tests \) \
            -o \
            \( -type f -a -name '*.pyc' -o -name '*.pyo' \) \
        \) -exec rm -rf '{}' + \
    && runDeps="$( \
        scanelf --needed --nobanner --recursive /usr/local \
            | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
            | sort -u \
            | xargs -r apk info --installed \
            | sort -u \
    )" \
    && apk add --virtual .python-rundeps $runDeps \
    && apk del .build-deps \
    && rm -rf /usr/src/python ~/.cache

CMD ["python2"]
