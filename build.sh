#!/bin/zsh
## Configuration

chmod +x ./config.sh
source ./config.sh

## End configuration

PARALLEL_TASKS=$(nproc)

function purgePackage()
{
  local PACKAGE_NAME=${1}
  apt purge "${PACKAGE_NAME}*" -y -q
}

function deleteCache()
{
    for FILE in *
    do
        if [[ $FILE == conf || $FILE == services || $FILE == *.md || $FILE == *.sh ]]; then
            continue
        fi
        
        rm -rf "${FILE}"
    done
}

function buildModule() {
    local FUNC_FOLDER=${1}
    local FUNC_URL=${2}
    local FUNC_BUILD_ARGS=${3}
    
    if [[ $FUNC_URL == *.bz2 ]]; then
        FUNC_ARCHIVE_NAME=${FUNC_FOLDER}.tar.bz2
    elif [[ $FUNC_URL == *.gz ]]; then
        FUNC_ARCHIVE_NAME=${FUNC_FOLDER}.tar.gz
    else
        FUNC_ARCHIVE_NAME=".git.clone"
    fi

    if [[ $FUNC_ARCHIVE_NAME == *.tar.?z* ]]; then
        wget "${FUNC_URL}" -O ${FUNC_ARCHIVE_NAME} --max-redirect=1
        mkdir "${FUNC_FOLDER}"
        tar -xf ${FUNC_ARCHIVE_NAME} -C "./${FUNC_FOLDER}" --strip-components=1
        rm -rf ${FUNC_ARCHIVE_NAME}
    else
        git clone --recurse-submodules -j${PARALLEL_TASKS} ${FUNC_URL}
    fi
    
    if [[ -n $FUNC_BUILD_ARGS ]]; then
        cd "${FUNC_FOLDER}" || exit
        eval "${FUNC_BUILD_ARGS}"
        cd ../
    fi
}

function enableService() {
    local SERVICE_NAME=${1}

    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}"

    systemctl start "${SERVICE_NAME}"
}

function kernelTuning()
{
  # shellcheck disable=SC2155
  local ROOT_MOUNT=$(findmnt -n / | awk '{ print $2 }')
  # shellcheck disable=SC2155
  local SYSTEM_DEVICE=$(lsblk -no pkname "${ROOT_MOUNT}")

  echo mq-deadline > "/sys/block/${SYSTEM_DEVICE}/queue/scheduler"

  ## Configure SWAP

  if [[ $SWAP_ENABLE == 1 ]]; then
      echo -e "CONF_SWAPFACTOR=${SWAP_FACTOR}\nCONF_MAXSWAP=${SWAP_MAX_MB}" > /etc/dphys-swapfile
  else
    dphys-swapfile uninstall
  fi

  systemctl restart dphys-swapfile.service

  ## End configure SWAP

  # shellcheck disable=SC2155
  local SYSCTL_CONFIG=$(sysctl -a)

  if [[ -z $(echo "${SYSCTL_CONFIG}" | grep "vm.overcommit_memory = 1") ]]; then
    echo "vm.overcommit_memory = 1" >> /etc/sysctl.conf
  fi

  if [[ -z $(echo "${SYSCTL_CONFIG}" | grep "vm.swappiness = 1") ]]; then
    echo "vm.swappiness = 1" >> /etc/sysctl.conf
  fi

  if [[ -z $(echo "${SYSCTL_CONFIG}" | grep "net.ipv4.ip_unprivileged_port_start = 1024") ]]; then
    echo "net.ipv4.ip_unprivileged_port_start = 1024" >> /etc/sysctl.conf
  fi

  if [[ -z $(echo "${SYSCTL_CONFIG}" | grep "fs.file-max = 524280") ]]; then
    echo "fs.file-max = 524280" >> /etc/sysctl.conf
  fi

  echo never | tee /sys/kernel/mm/transparent_hugepage/enabled /sys/kernel/mm/transparent_hugepage/defrag > /dev/null

  sysctl -p
}

function installPackages()
{
    apt update && apt upgrade -y
    apt install -y devscripts build-essential ninja-build libsystemd-dev apt-transport-https curl dpkg-dev gnutls-bin libgnutls28-dev libbrotli-dev clang passwd perl perl-doc python3 certbot python3-certbot python3-certbot-dns-standalone python3-certbot-nginx dphys-swapfile
}

INSTALL_PATH=$(pwd)
CONF_PATH="${INSTALL_PATH}/conf"
SERVICES_PATH="${INSTALL_PATH}/services"

SYSTEMD_SERVICES_PATH="/usr/lib/systemd/system"

## End internal utils

## Start module configuration

CC=/usr/bin/clang
CXX=/usr/bin/clang++

JEMALLOC_FOLDER="jemalloc"
JEMALLOC_URL="https://github.com/jemalloc/jemalloc/releases/download/${JEMALLOC_VERSION}/jemalloc-$JEMALLOC_VERSION.tar.bz2"
JEMALLOC_BUILD_ARGS="CC=/usr/bin/clang EXTRA_CFLAGS='-mtune=${M_TUNE} -DADLER32_SIMD_NEON -DINFLATE_CHUNK_SIMD_NEON -DINFLATE_CHUNK_READ_64LE -O3 -D_LARGEFILE64_SOURCE=1 -DHAVE_HIDDEN -funroll-loops -fPIC' CXX=/usr/bin/clang++ EXTRA_CXXFLAGS='-mtune=${M_TUNE} -DADLER32_SIMD_NEON -DINFLATE_CHUNK_SIMD_NEON -DINFLATE_CHUNK_READ_64LE -O3 -D_LARGEFILE64_SOURCE=1 -DHAVE_HIDDEN -funroll-loops -fPIC' ./configure && make -j${PARALLEL_TASKS} && make install -j${PARALLEL_TASKS}"

ZLIB_FOLDER="zlib"
ZLIB_URL="https://github.com/cloudflare/zlib/archive/refs/tags/v${ZLIB_VERSION}.tar.gz"
ZLIB_BUILD_ARGS="CC=/usr/bin/clang CFLAGS='-mtune=${M_TUNE} -DADLER32_SIMD_NEON -DINFLATE_CHUNK_SIMD_NEON -DINFLATE_CHUNK_READ_64LE -D_LARGEFILE64_SOURCE=1 -DHAVE_HIDDEN -Ofast -funroll-loops -flto=auto -ffast-math -fPIC' CPP=/usr/bin/clang++ SFLAGS='-mtune=${M_TUNE} -DADLER32_SIMD_NEON -DINFLATE_CHUNK_SIMD_NEON -DINFLATE_CHUNK_READ_64LE -Ofast -funroll-loops -flto=auto -ffast-math -D_LARGEFILE64_SOURCE=1 -DHAVE_HIDDEN -fPIC' LD_LIBRARY_PATH=/usr/local/lib LDFLAGS='-L/usr/local/lib -l:libjemalloc.a' ./configure && make -j${PARALLEL_TASKS} && make install -j${PARALLEL_TASKS}"

LIBATOMIC_FOLDER="libatomic"
LIBATOMIC_URL="https://github.com/ivmai/libatomic_ops/releases/download/v${LIBATOMIC_VERSION}/libatomic_ops-$LIBATOMIC_VERSION.tar.gz"
LIBATOMIC_BUILD_ARGS="LT_SYS_LIBRARY_PATH=/usr/local/lib LD_LIBRARY_PATH=/usr/local/lib LDFLAGS='-L/usr/local/lib -l:libjemalloc.a' CC=/usr/bin/clang CCAS=/usr/bin/clang CCASFLAGS='-mtune=${M_TUNE} -DADLER32_SIMD_NEON -DINFLATE_CHUNK_SIMD_NEON -Ofast -funroll-loops -flto=auto -ffast-math -fPIC' CFLAGS='-mtune=${M_TUNE} -DADLER32_SIMD_NEON -DINFLATE_CHUNK_SIMD_NEON -Ofast -funroll-loops -flto=auto -ffast-math -fPIC' CPPFLAGS='-mtune=${M_TUNE} -DADLER32_SIMD_NEON -DINFLATE_CHUNK_SIMD_NEON -Ofast -funroll-loops -flto=auto -ffast-math -fPIC' ./configure && make -j${PARALLEL_TASKS} && make install -j${PARALLEL_TASKS}"

PCRE2_FOLDER="libpcre"
PCRE2_URL="https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VERSION}/pcre2-${PCRE2_VERSION}.tar.gz"
PCRE2_BUILD_ARGS="LT_SYS_LIBRARY_PATH=/usr/local/lib LD_LIBRARY_PATH=/usr/local/lib LDFLAGS='-L/usr/local/lib -l:libjemalloc.a -l:libz.a' CC=/usr/bin/clang CFLAGS='-mtune=${M_TUNE} -DADLER32_SIMD_NEON -DINFLATE_CHUNK_SIMD_NEON -DINFLATE_CHUNK_READ_64LE -Ofast -funroll-loops -flto=auto -ffast-math -D_LARGEFILE64_SOURCE=1 -DHAVE_HIDDEN -fPIC' CPPFLAGS='-mtune=${M_TUNE} -DADLER32_SIMD_NEON -DINFLATE_CHUNK_SIMD_NEON -DINFLATE_CHUNK_READ_64LE -Ofast -funroll-loops -flto=auto -ffast-math -D_LARGEFILE64_SOURCE=1 -DHAVE_HIDDEN -fPIC' ./configure --enable-pcre2grep-libz --enable-jit --enable-pcre2-16 --enable-pcre2-32 && make -j${PARALLEL_TASKS} && make install -j${PARALLEL_TASKS}"

GOLANG_FOLDER="golang"
GOLANG_URL="https://dl.google.com/go/go${GOLANG_VERSION}.linux-amd64.tar.gz"
GO_BIN="${INSTALL_PATH}/${GOLANG_FOLDER}/bin"

BORINGSSL_FOLDER="boringssl"
BORINGSSL_URL="https://boringssl.googlesource.com/boringssl"
BORINGSSL_BUILD_ARGS="cmake -GNinja -B build -DOPENSSL_SMALL=1 -DGO_EXECUTABLE=${GO_BIN}/go -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ -DCMAKE_C_FLAGS_INIT='-mtune=${M_TUNE} -DADLER32_SIMD_NEON -DINFLATE_CHUNK_SIMD_NEON -DINFLATE_CHUNK_READ_64LE -Ofast -funroll-loops -flto=auto -D_LARGEFILE64_SOURCE=1 -DHAVE_HIDDEN' -DCMAKE_CXX_FLAGS_INIT='-mtune=${M_TUNE} -DADLER32_SIMD_NEON -DINFLATE_CHUNK_SIMD_NEON -DINFLATE_CHUNK_READ_64LE -Ofast -funroll-loops -flto=auto -D_LARGEFILE64_SOURCE=1 -DHAVE_HIDDEN' -DCMAKE_SHARED_LINKER_FLAGS_INIT='-L/usr/local/lib -l:libjemalloc.a' && ninja -j${PARALLEL_TASKS} -C build"

OPENSSL_FOLDER="openssl"
OPENSSL_URL="https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
OPENSSL_BUILD_ARGS="KERNEL_BITS=64 ./config -Wno-free-nonheap-object no-weak-ssl-ciphers no-docs no-legacy no-ssl3 no-tests enable-brotli enable-ktls no-unit-test threads thread-pool default-thread-pool zlib -DOPENSSL_SMALL=1 -DOPENSSL_NO_HEARTBEATS -Ofast -funroll-loops -flto=auto -mtune=${M_TUNE} -ffunction-sections -fdata-sections -I/usr/local/include -fPIC -Wl,-rpath,/usr/local/lib -Wl,-ljemalloc && make -j${PARALLEL_TASKS} && make install -j${PARALLEL_TASKS}"

NGX_BROTLI_FOLDER="ngx_brotli"
NGX_BROTLI_URL="https://github.com/google/ngx_brotli"

NGINX_FOLDER="nginx"
NGINX_URL="https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"
NGINX_BUILD_ARGS="./configure --with-compat --with-cc-opt='-I/usr/local/include -mtune=${M_TUNE} -fPIE -fstack-protector-strong --param=ssp-buffer-size=4 -Ofast -funroll-loops -flto=auto -ffast-math -Wp,-D_FORTIFY_SOURCE=2 -Wno-implicit-fallthrough -Wno-implicit-function-declaration -Wno-discarded-qualifiers -Wno-unused-variable -Wno-error' --with-ld-opt='-L/usr/local/lib -l:libjemalloc.a -l:libatomic_ops.a -l:libpcre2-8.a -l:libz.a -mtune=${M_TUNE} -Ofast -funroll-loops -flto=auto -ffast-math -fPIE -fstack-protector-strong --param=ssp-buffer-size=4 -Wp,-D_FORTIFY_SOURCE=2 -fPIC' --prefix=/etc/nginx --sbin-path=/usr/sbin/nginx --modules-path=/etc/nginx/modules --conf-path=/etc/nginx/nginx.conf --error-log-path=/var/log/nginx/error.log --http-log-path=/var/log/nginx/access.log --pid-path=/var/run/nginx.pid --lock-path=/var/run/nginx.lock --http-client-body-temp-path=/var/cache/nginx/client_temp --http-proxy-temp-path=/var/cache/nginx/proxy_temp --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp --http-scgi-temp-path=/var/cache/nginx/scgi_temp --user=www-data --group=www-data --with-file-aio --with-threads --with-pcre --with-libatomic --with-pcre-jit --with-http_dav_module --with-http_gunzip_module --with-http_gzip_static_module --with-http_ssl_module --without-select_module --without-poll_module --without-http_mirror_module --without-http_geo_module --without-http_split_clients_module --without-http_uwsgi_module --without-http_scgi_module --without-http_grpc_module --without-http_memcached_module --without-http_empty_gif_module --without-mail_pop3_module --without-mail_imap_module --without-mail_smtp_module --without-stream_limit_conn_module --without-stream_access_module --without-stream_geo_module --without-stream_map_module --without-stream_split_clients_module --without-stream_return_module --without-stream_set_module --without-stream_upstream_hash_module --without-stream_upstream_least_conn_module --without-stream_upstream_random_module --without-stream_upstream_zone_module --with-http_v2_module --with-http_v3_module --add-dynamic-module=${INSTALL_PATH}/ngx_brotli && make -j${PARALLEL_TASKS} && make install -j${PARALLEL_TASKS}"
NGINX_SYSTEMD_SERVICE_PATH="/usr/lib/systemd/system/${NGINX_FOLDER}.service"

REDIS_FOLDER="redis"
REDIS_URL="https://github.com/redis/redis/archive/${REDIS_VERSION}.tar.gz"
REDIS_BUILD_ARGS="make USE_SYSTEMD=yes MALLLOC=jemalloc BUILD_TLS=no REDIS_CFLAGS=\"-I/usr/local/include -Ofast -funroll-loops -flto=auto --param=ssp-buffer-size=4 -mtune=${M_TUNE}\" REDIS_LDFLAGS=\"-L/usr/local/lib -l:libjemalloc.a \" -j${PARALLEL_TASKS} && make install -j${PARALLEL_TASKS}"
REDIS_CONFIG_PATH="/etc/redis/${REDIS_FOLDER}.conf"
REDIS_SYSTEMD_SERVICE_PATH="${SYSTEMD_SERVICES_PATH}/${REDIS_FOLDER}.service"

MARIADB_FOLDER="mariadb"
MARIADB_BUILD_FOLDER="${MARIADB_FOLDER}/${MARIADB_FOLDER}-${MARIADB_VERSION}-build"
MARIADB_SIGNING_KEY_URL="https://mariadb.org/mariadb_release_signing_key.pgp"
MARIADB_BUILD_ARGS="cmake ../ -DCMAKE_C_FLAGS='-I/usr/local/include -O3 -fno-strict-aliasing -funroll-loops --param=ssp-buffer-size=4 -flto=auto -mtune=${M_TUNE}' -DCMAKE_CXX_FLAGS='-I/usr/local/include -O3 -funroll-loops --param=ssp-buffer-size=4 -flto=auto -mtune=${M_TUNE}' -DBUILD_CONFIG=mysql_release -DMYSQL_MAINTAINER_MODE=OFF -DCMAKE_EXE_LINKER_FLAGS='-l:libjemalloc.a -l:libatomic_ops.a -l:libpcre2-8.a -l:libz.a' -DWITH_SAFEMALLOC=OFF && cmake --build . -j${PARALLEL_TASKS} && make install -j${PARALLEL_TASKS}"
MARIADB_CONF_FOLDER="/etc/mysql"
MARIADB_SOCKET_FOLDER="/var/run/mysqld"
MARIADB_CONF_FILE="my.cnf"
MARIADB_INSTALLATION_FOLDER="/usr/local/mysql"

## End module configuration

## Start module utils

function getMariaDbSource()
{
  mkdir -p /etc/apt/keyrings
  wget -O "/etc/apt/keyrings/${MARIADB_FOLDER}-keyring.pgp" ${MARIADB_SIGNING_KEY_URL}
  echo "deb-src [signed-by=/etc/apt/keyrings/${MARIADB_FOLDER}-keyring.pgp] https://deb.${MARIADB_FOLDER}.org/${MARIADB_VERSION}/debian bookworm main" > /etc/apt/sources.list.d/${MARIADB_FOLDER}.list

  apt update && apt upgrade -y
  apt build-dep -y ${MARIADB_FOLDER}-server

  apt source ${MARIADB_FOLDER}-server

  mkdir -p "${MARIADB_BUILD_FOLDER}"
  mv ${MARIADB_FOLDER}-*/* ${MARIADB_FOLDER}

  rm -rf ${MARIADB_FOLDER}*.*

  cd "${MARIADB_BUILD_FOLDER}" || exit
}

## End module utils

deleteCache

deleteManagerPackages
installPackages

kernelTuning

buildModule $JEMALLOC_FOLDER $JEMALLOC_URL "$JEMALLOC_BUILD_ARGS"
buildModule $ZLIB_FOLDER $ZLIB_URL "$ZLIB_BUILD_ARGS"
buildModule $PCRE2_FOLDER $PCRE2_URL "$PCRE2_BUILD_ARGS"
buildModule $OPENSSL_FOLDER $OPENSSL_URL "$OPENSSL_BUILD_ARGS"

## Start NGINX installation

if [[ $USE_NGINX == 1 ]]; then
  buildModule $LIBATOMIC_FOLDER $LIBATOMIC_URL $LIBATOMIC_BUILD_ARGS

  if [[ $USE_OPENSSL == 0 ]]; then
      # Needs to be implemented!!!
      buildModule $GOLANG_FOLDER $GOLANG_URL
      buildModule $BORINGSSL_FOLDER $BORINGSSL_URL $BORINGSSL_BUILD_ARGS
  fi

  buildModule $NGX_BROTLI_FOLDER $NGX_BROTLI_URL

  buildModule $NGINX_FOLDER $NGINX_URL $NGINX_BUILD_ARGS

  cp -rf "${SERVICES_PATH}/${NGINX_FOLDER}.service" ${NGINX_SYSTEMD_SERVICE_PATH}
  cp -rf ${CONF_PATH}/${NGINX_FOLDER}/* "/etc/${NGINX_FOLDER}"

  ## Generate TLS ticket keys

  openssl rand 80 > "/etc/${NGINX_FOLDER}/tls_tickets/first.key"
  openssl rand 80 > "/etc/${NGINX_FOLDER}/tls_tickets/rotate.key"
  chmod -R 644 "/etc/${NGINX_FOLDER}/tls_tickets"

  enableService "${NGINX_FOLDER}.service"
fi

## End NGINX installation

## Start Redis installation

if [[ $USE_REDIS == 1 ]]; then
    buildModule $REDIS_FOLDER $REDIS_URL $REDIS_BUILD_ARGS

    cp -rf "${CONF_PATH}/${REDIS_FOLDER}.conf" ${REDIS_CONFIG_PATH}
    cp -rf "${SERVICES_PATH}/${REDIS_FOLDER}.service" ${REDIS_SYSTEMD_SERVICE_PATH}

    usermod -aG redis www-data

    enableService "${REDIS_FOLDER}.service"
fi

## End Redis installation

## Start MariaDB upgrade
if [[ $USE_MARIADB == 1 ]]; then
  getMariaDbSource
  eval "${MARIADB_BUILD_ARGS}"

  groupadd mysql
  useradd -g mysql mysql

  cd "${MARIADB_INSTALLATION_FOLDER}" || exit

  ln -s "${MARIADB_INSTALLATION_FOLDER}/bin/*" "/usr/sbin/"
  cp -rf "${MARIADB_INSTALLATION_FOLDER}/support-files/systemd/${MARIADB_FOLDER}.service" "/lib/systemd/system/"
  chmod 644 "/lib/systemd/system/${MARIADB_FOLDER}.service"

  mkdir -p "${MARIADB_CONF_FOLDER}/conf.d"
  mkdir -p "${MARIADB_CONF_FOLDER}/mariadb.conf.d"

  cp -rf "${CONF_PATH}/${MARIADB_CONF_FILE}" "${MARIADB_CONF_FOLDER}"

  chown -R mysql:mysql "${MARIADB_CONF_FOLDER}"
  chmod -R 770 "${MARIADB_CONF_FOLDER}"

  mkdir -p "${MARIADB_SOCKET_FOLDER}"
  chown -R mysql:mysql "${MARIADB_SOCKET_FOLDER}"
  chmod -R 755 "${MARIADB_SOCKET_FOLDER}"

  scripts/mysql_install_db --user=mysql

  chown -R mysql:mysql "${MARIADB_INSTALLATION_FOLDER}"

  systemctl daemon-reload
  systemctl enable "${MARIADB_FOLDER}.service"

  systemctl start "${MARIADB_FOLDER}.service"
fi
## End MariaDB upgrade
