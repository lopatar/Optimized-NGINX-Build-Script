#!/bin/zsh

unsetopt MULTIOS

##############################
LLVM_VERSION=19
##############################
USE_SWAP=1
SWAP_FACTOR=2
SWAP_MAX_MB=16384
M_TUNE="cortex-a72"
##############################
NGINX_VERSION=1.27.2
PHP_VERSION=8.3
MARIADB_VERSION=11.6.1
REDIS_VERSION=7.4.1

JEMALLOC_VERSION=5.3.0
ZLIB_VERSION=1.2.11
LIBATOMIC_VERSION=7.8.2
PCRE2_VERSION=10.44
GOLANG_VERSION=1.23.2
OPENSSL_VERSION=3.4.0
###################################x

quit()
{
  set -e
  /bin/false
}

printVar()
{
  # shellcheck disable=SC2028
  echo "$1 => \"$(eval echo \$"$1")\""
}

print "--------------------------"
print "Created by Lopatar Jiri"
print "https://github.com/lopatar"
print "https://linkedin.com/in/lopatar-jiri"
print "--------------------------"  

if [[ $EUID != 0 ]]; then
  print "Must be ran as root!"
  quit
fi
  
printVar LLVM_VERSION
printVar USE_NGINX
printVar NGINX_VERSION
printVar JEMALLOC_VERSION
printVar ZLIB_VERSION
printVar LIBATOMIC_VERSION
printVar PCRE2_VERSION
printVar GOLANG_VERSION
printVar USE_REDIS
printVar USE_MARIADB
printVar USE_SWAP
printVar SWAP_FACTOR
printVar SWAP_MAX_MB
printVar M_TUNE  

workDir=$(pwd)

print "Upgrading..."

apt-get update && apt-get upgrade -y

apt-get install -y ca-certificates devscripts build-essential ninja-build libsystemd-dev apt-transport-https curl dpkg-dev gnutls-bin libgnutls28-dev libbrotli-dev clang passwd perl perl-doc python3 certbot python3-certbot python3-certbot-dns-standalone python3-certbot-nginx dphys-swapfile openjdk-17-jre openjdk-17-jdk

print "Installing LLVM $LLVM_VERSION"
wget https://apt.llvm.org/llvm.sh
chmod +x llvm.sh
./llvm.sh $LLVM_VERSION

print "Installing MariaDB $MARIADB_VERSION"
wget https://r.mariadb.com/downloads/mariadb_repo_setup -O mariadb_repo_setup.sh
chmod +x mariadb_repo_setup.sh

./mariadb_repo_setup.sh --mariadb-server-version=$MARIADB_VERSION --skip-maxscale

print "Adding PHP repo"
curl -sSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb
dpkg -i /tmp/debsuryorg-archive-keyring.deb
sh -c 'echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list'

rm llvm.sh
rm mariadb_repo_setup.sh
rm /tmp/debsuryorg-archive-keyring.deb

print "Upgrading..."

apt-get update && apt-get upgrade -y

print "Setting compiler alternatives..."

update-alternatives /usr/bin/clang clang /usr/bin/clang-$LLVM_VERSION
update-alternatives /usr/bin/clang++ clang++ /usr/bin/clang++-$LLVM_VERSION

update-alternatives /usr/bin/gcc gcc /usr/bin/clang 200
update-alternatives /usr/bin/g++ g++ /usr/bin/clang 200

export CC=/usr/bin/clang
export CXX=/usr/bin/clang++

CC=/usr/bin/clang
CXX=/usr/bin/clang++

