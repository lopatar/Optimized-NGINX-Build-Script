# Optimized LEMP stack build stack

## ** CURRENTLY NOT PRODUCTION READY **

This script is intended to ease building optimized LEMP stack **and more** using the newest software and libraries.

The script mostly consists of me experimenting with more advanced scripting concepts, please be kind :)

**Architecture/CPU specific optimizations are tuned for Raspberry Pi 4B**

**The script is written in zsh**

# Usage

```zsh
git clone https://github.com/lopatar/LEMP-Optimizations.git
cd LEMP-Optimizations

chmod +x install.sh
./install.sh
```

## Configuration

All configuration options are located
in [config.sh](https://github.com/lopatar/LEMP-Optimizations/blob/master/config.sh)

# Software installed

- NGINX
    - Removing unnecessary modules and focusing strictly on the HTTP part
    - Enabling thread pools
    - Enabling file-aio
    - Prioritizing HTTP3/QUIC
    - [Brotli](https://github.com/google/ngx_brotli) compression
    - Supporting PCRE2 versions higher than officially supported
    - Including hardened TLS configuration
- MariaDB
    - Newer release than default package
    - Architecture specific optimizations
    - Optimized server configuration
- PHP-FPM (**Installed from [deb.sury.org](https://deb.sury.org)**)

# Other optimizations

- OpenSSL/[BoringSSL](https://boringssl.googlesource.com/boringssl) (**BoringSSL** is not currently supported)
- [Jemalloc](https://github.com/jemalloc/jemalloc) (optimized memory allocator preventing heap fragmentation typically
  observed on long-running software)
- Cloudflare's [optimized fork](https://github.com/cloudflare/zlib) of zlib
- Libatomic
- Leveraging GCC optimization features
- Creating new tmpfs file-system mounted at /lemp-tmp **TODO**

# Optional software

- Redis