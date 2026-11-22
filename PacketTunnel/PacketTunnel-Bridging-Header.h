// Packet tunnel: find the utun file descriptor that NetworkExtension opened for us, so
// hev-socks5-tunnel can read and write device packets directly.
//
// iOS SDK does not export <sys/kern_control.h>; the structs below mirror it (same layout as
// macOS), the approach WireGuard's iOS client uses. Our own names avoid clashes if the SDK
// ever exports the originals.

#include <stdint.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>

struct fvpn_ctl_info {
    uint32_t ctl_id;
    char ctl_name[96];
};

struct fvpn_sockaddr_ctl {
    uint8_t sc_len;
    uint8_t sc_family;
    uint16_t ss_sysaddr;
    uint32_t sc_id;
    uint32_t sc_unit;
    uint32_t sc_reserved[5];
};

#define FVPN_CTLIOCGINFO 0xc0644e03UL
#define FVPN_AF_SYSTEM 32

static inline int fvpn_find_utun_fd(void) {
    struct fvpn_ctl_info info;
    memset(&info, 0, sizeof(info));
    strncpy(info.ctl_name, "com.apple.net.utun_control", sizeof(info.ctl_name) - 1);
    for (int fd = 0; fd < 1024; fd++) {
        struct fvpn_sockaddr_ctl addr;
        socklen_t len = sizeof(addr);
        memset(&addr, 0, sizeof(addr));
        if (getpeername(fd, (struct sockaddr *)&addr, &len) != 0 || addr.sc_family != FVPN_AF_SYSTEM) {
            continue;
        }
        if (info.ctl_id == 0 && ioctl(fd, FVPN_CTLIOCGINFO, &info) != 0) {
            continue;
        }
        if (addr.sc_id == info.ctl_id) {
            return fd;
        }
    }
    return -1;
}
