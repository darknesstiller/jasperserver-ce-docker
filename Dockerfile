FROM openjdk:8-jdk

# TOMCAT
ENV CATALINA_HOME /usr/local/tomcat
ENV PATH $CATALINA_HOME/bin:$PATH
RUN mkdir -p "$CATALINA_HOME"
WORKDIR $CATALINA_HOME

# let "Tomcat Native" live somewhere isolated
ENV TOMCAT_NATIVE_LIBDIR $CATALINA_HOME/native-jni-lib
ENV LD_LIBRARY_PATH ${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}$TOMCAT_NATIVE_LIBDIR

# runtime dependencies for Tomcat Native Libraries
# Tomcat Native 1.2+ requires a newer version of OpenSSL than debian:jessie has available
# > checking OpenSSL library version >= 1.0.2...
# > configure: error: Your version of OpenSSL is not compatible with this version of tcnative
# see http://tomcat.10.x6.nabble.com/VOTE-Release-Apache-Tomcat-8-0-32-tp5046007p5046024.html (and following discussion)
# and https://github.com/docker-library/tomcat/pull/31
ENV OPENSSL_VERSION 1.1.0f-3+deb9u2
RUN set -ex; \
  currentVersion="$(dpkg-query --show --showformat '${Version}\n' openssl)"; \
  if dpkg --compare-versions "$currentVersion" '<<' "$OPENSSL_VERSION"; then \
  if ! grep -q stretch /etc/apt/sources.list; then \
  # only add stretch if we're not already building from within stretch
  { \
  echo 'deb http://deb.debian.org/debian stretch main'; \
  echo 'deb http://security.debian.org stretch/updates main'; \
  echo 'deb http://deb.debian.org/debian stretch-updates main'; \
  } > /etc/apt/sources.list.d/stretch.list; \
  { \
  # add a negative "Pin-Priority" so that we never ever get packages from stretch unless we explicitly request them
  echo 'Package: *'; \
  echo 'Pin: release n=stretch*'; \
  echo 'Pin-Priority: -10'; \
  echo; \
  # ... except OpenSSL, which is the reason we're here
  echo 'Package: openssl libssl*'; \
  echo "Pin: version $OPENSSL_VERSION"; \
  echo 'Pin-Priority: 990'; \
  } > /etc/apt/preferences.d/stretch-openssl; \
  fi; \
  apt-get update; \
  apt-get install -y --no-install-recommends openssl="$OPENSSL_VERSION"; \
  rm -rf /var/lib/apt/lists/*; \
  fi
# ttf-mscorefonts-installer
RUN apt-get update && apt-get install -y --no-install-recommends \
  libapr1  \
  && rm -rf /var/lib/apt/lists/*
RUN fc-cache
# see https://www.apache.org/dist/tomcat/tomcat-$TOMCAT_MAJOR/KEYS
# see also "update.sh" (https://github.com/docker-library/tomcat/blob/master/update.sh)

ENV TOMCAT_MAJOR 8
ENV TOMCAT_VERSION 8.0.52
ENV TOMCAT_SHA512 23ba3c005d2e1bff30360a7aca5882ba7acaef0001395b1f77eb182c1f9c6a48db7f39b9f71ebdfb20668eca32c5f03bf00364f77d47e368850a794f6d65ea56

ENV TOMCAT_TGZ_URLS \
  # https://issues.apache.org/jira/browse/INFRA-8753?focusedCommentId=14735394#comment-14735394
  https://www.apache.org/dyn/closer.cgi?action=download&filename=tomcat/tomcat-$TOMCAT_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz \
  # if the version is outdated, we might have to pull from the dist/archive :/
  https://www-us.apache.org/dist/tomcat/tomcat-$TOMCAT_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz \
  https://www.apache.org/dist/tomcat/tomcat-$TOMCAT_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz \
  https://archive.apache.org/dist/tomcat/tomcat-$TOMCAT_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz

ENV TOMCAT_ASC_URLS \
  https://www.apache.org/dyn/closer.cgi?action=download&filename=tomcat/tomcat-$TOMCAT_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz.asc \
  # not all the mirrors actually carry the .asc files :'(
  https://www-us.apache.org/dist/tomcat/tomcat-$TOMCAT_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz.asc \
  https://www.apache.org/dist/tomcat/tomcat-$TOMCAT_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz.asc \
  https://archive.apache.org/dist/tomcat/tomcat-$TOMCAT_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz.asc

RUN set -eux; \
  \
  savedAptMark="$(apt-mark showmanual)"; \
  apt-get update; \
  \
  apt-get install -y --no-install-recommends gnupg dirmngr; \
  \
  export GNUPGHOME="$(mktemp -d)"; \
  \
  apt-get install -y --no-install-recommends wget ca-certificates; \
  \
  success=; \
  for url in $TOMCAT_TGZ_URLS; do \
  if wget -O tomcat.tar.gz "$url"; then \
  success=1; \
  break; \
  fi; \
  done; \
  [ -n "$success" ]; \
  \
  echo "$TOMCAT_SHA512 *tomcat.tar.gz" | sha512sum -c -; \
  \
  success=; \
  for url in $TOMCAT_ASC_URLS; do \
  if wget -O tomcat.tar.gz.asc "$url"; then \
  success=1; \
  break; \
  fi; \
  done; \
  [ -n "$success" ]; \
  \
  tar -xvf tomcat.tar.gz --strip-components=1; \
  rm bin/*.bat; \
  rm tomcat.tar.gz*; \
  rm -rf "$GNUPGHOME"; \
  \
  nativeBuildDir="$(mktemp -d)"; \
  tar -xvf bin/tomcat-native.tar.gz -C "$nativeBuildDir" --strip-components=1; \
  apt-get install -y --no-install-recommends \
  dpkg-dev \
  gcc \
  libapr1-dev \
  libssl-dev \
  make \
  "openjdk-${JAVA_VERSION%%[.~bu-]*}-jdk=$JAVA_DEBIAN_VERSION" \
  ; \
  ( \
  export CATALINA_HOME="$PWD"; \
  cd "$nativeBuildDir/native"; \
  gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
  ./configure \
  --build="$gnuArch" \
  --libdir="$TOMCAT_NATIVE_LIBDIR" \
  --prefix="$CATALINA_HOME" \
  --with-apr="$(which apr-1-config)" \
  --with-java-home="$(docker-java-home)" \
  --with-ssl=yes; \
  make -j "$(nproc)"; \
  make install; \
  ); \
  rm -rf "$nativeBuildDir"; \
  rm bin/tomcat-native.tar.gz; \
  \
  # reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
  apt-mark auto '.*' > /dev/null; \
  [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; \
  apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
  rm -rf /var/lib/apt/lists/*; \
  \
  # sh removes env vars it doesn't support (ones with periods)
  # https://github.com/docker-library/tomcat/issues/77
  find ./bin/ -name '*.sh' -exec sed -ri 's|^#!/bin/sh$|#!/usr/bin/env bash|' '{}' +

# verify Tomcat Native is working properly
RUN set -e \
  && nativeLines="$(catalina.sh configtest 2>&1)" \
  && nativeLines="$(echo "$nativeLines" | grep 'Apache Tomcat Native')" \
  && nativeLines="$(echo "$nativeLines" | sort -u)" \
  && if ! echo "$nativeLines" | grep 'INFO: Loaded APR based Apache Tomcat Native library' >&2; then \
  echo >&2 "$nativeLines"; \
  exit 1; \
  fi
COPY . .
# RUN mvn package
# RUN cp ./target/casanova_pco.war /usr/local/tomcat/webapps/casanova_pco.war
ENV CATALINA_OPTS "-Xms512m -Xmx1024m -XX:PermSize=640m -XX:MaxPermSize=1024m -Xss512m -DforceReal=true"
EXPOSE 8080
ENTRYPOINT [ "/bin/bash","entrypoint.sh" ]