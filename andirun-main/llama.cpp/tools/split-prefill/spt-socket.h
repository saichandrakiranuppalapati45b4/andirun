#pragma once

// spt-socket.h - Cross-platform POSIX and WinSock2 socket wrapper for SPTL and PATN protocols.
// Supports: Windows (_WIN32), Linux, Android (Bionic), and Apple (macOS/iOS).

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <basetsd.h>

typedef SSIZE_T ssize_t;
#define fseeko _fseeki64
#define ftello _ftelli64

#pragma comment(lib, "ws2_32.lib")

using socket_t = SOCKET;
constexpr socket_t INVALID_SOCK = INVALID_SOCKET;
constexpr int SOCKET_CALL_ERROR = SOCKET_ERROR;

inline int spt_sock_close(socket_t s) { return closesocket(s); }
inline int spt_sock_errno() { return WSAGetLastError(); }
inline bool spt_sock_would_block(int err) { return err == WSAEWOULDBLOCK; }

inline void spt_sock_init() {
    static bool initialized = false;
    if (!initialized) {
        WSADATA wsa;
        WSAStartup(MAKEWORD(2, 2), &wsa);
        initialized = true;
    }
}

inline int spt_set_nonblocking(socket_t s, bool nonblock) {
    u_long mode = nonblock ? 1 : 0;
    return ioctlsocket(s, FIONBIO, &mode);
}

inline int spt_set_timeout(socket_t s, int seconds) {
    DWORD ms = (DWORD)(seconds * 1000);
    int r1 = setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, (const char*)&ms, sizeof(ms));
    int r2 = setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, (const char*)&ms, sizeof(ms));
    return (r1 == 0 && r2 == 0) ? 0 : -1;
}

inline void spt_sleep_us(unsigned int us) {
    Sleep((us + 999) / 1000);
}

#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>
#include <fcntl.h>
#include <cerrno>

using socket_t = int;
constexpr socket_t INVALID_SOCK = -1;
constexpr int SOCKET_CALL_ERROR = -1;

inline int spt_sock_close(socket_t s) { return ::close(s); }
inline int spt_sock_errno() { return errno; }
inline bool spt_sock_would_block(int err) { return err == EAGAIN || err == EWOULDBLOCK; }
inline void spt_sock_init() { /* no-op on POSIX */ }

inline int spt_set_nonblocking(socket_t s, bool nonblock) {
    int fl = fcntl(s, F_GETFL, 0);
    if (fl < 0) return -1;
    return fcntl(s, F_SETFL, nonblock ? (fl | O_NONBLOCK) : (fl & ~O_NONBLOCK));
}

inline int spt_set_timeout(socket_t s, int seconds) {
    struct timeval tv;
    tv.tv_sec = seconds;
    tv.tv_usec = 0;
    int r1 = setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    int r2 = setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    return (r1 == 0 && r2 == 0) ? 0 : -1;
}

inline void spt_sleep_us(unsigned int us) {
    usleep(us);
}
#endif
