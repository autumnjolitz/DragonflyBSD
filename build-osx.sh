#!/usr/bin/env bash
OPWD="$PWD"
(2>/dev/null set -o pipefail) && set -o pipefail
# set -x
set -eu

SRC="$(dirname "$(realpath "$0")")"
MAKEOBJDIRPREFIX="${MAKEOBJDIRPREFIX:-${SRC}.obj}"

SDK="${SDK:-}"


if [ -z "${BUILD_SKIP_BREW:-}" ]; then
    brew bundle install --file "$SRC/Brewfile"
fi

CLANG_HOME="$(brew --prefix llvm@21)"


if [ -z "$SDK" ] ; then
    for maybe_sdk in \
        /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
        /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk \
        ; do
        if [ -d "$maybe_sdk" ]; then
            SDK="$maybe_sdk"
            break
        fi
    done
    if [ -z "$SDK" ]; then
        >&2 printf 'error: Unable to locate MacOSX.sdk, please install xcode or Command Line Tools\n'
        exit 1
    fi
fi


_verbose=0
make_args=crossworld

while [ $# -gt 0 ]; do
    case "${1}" in
        -v|--verbose)
            _verbose=$(( _verbose + 1 ))
            shift
        ;;
        -q|--quiet)
            _verbose=$(( _verbose - 1 ))
            shift
            ;;
        -*)
            >&2 printf 'Unknown argument: %s\n' "${1}"
            shift
            exit 1
        ;;
        *)
        make_args="${make_args} ${1}"
        shift
        ;;
    esac
done

if [ ! -d "$MAKEOBJDIRPREFIX" ]; then
    mkdir -p "$MAKEOBJDIRPREFIX"
fi

D="$(mktemp -d /tmp/dragonfly-buildroot.XXXX)"
cd "$D"

cleanup() {
    rm -rf "$D"
}

trap cleanup EXIT

mkdir -p \
    bin \
    etc/defaults \
    lib \
    include/overlay/{sys,machine}

cp $SRC/etc/defaults/compilers.conf \
    etc/defaults/compilers.conf


>assert.c cat <<EOF
#include <sys/param.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>

__attribute__((noreturn)) void __assert(
    const char *funcName,
    const char *fileName,
    int lineNo,
    const char *expression
) {
    char buf[8192] = {0};
    int buf_len = -1;
    buf_len = snprintf(
        buf, sizeof(buf),
        "assertion \"%s\" failed: file \"%s\", line %d\n",
        expression, fileName, lineNo
    );
    write(2, buf, buf_len);
    exit(EXIT_FAILURE);    
}
EOF

>_init.c cat <<EOF
#include <sys/param.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <runetype.h>

/*
 * A cached version of the runes for this thread.
 * Used by ctype.h
 */
__thread const _RuneLocale *_ThreadRuneLocale;

volatile int __isthreaded = 1;

int getosreldate(void) {
    return __DragonFly_version;
};
EOF


>varsym_shim.c cat <<EOF
#include <overlay/sys/varsym.h>

int varsym_get(int mask, const char *wild, char *buf, int bufsize) {
    return -1;
}
EOF
>yywrap.c cat <<EOF
int yywrap(void) {
    return 1;
};
EOF

>include/overlay/fts.h cat <<EOF
#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<fts.h>)
#include_next <fts.h>
#endif
#else
#if __has_include(<fts.h>)
#include <fts.h>
#endif
#endif

#ifndef _FTS_H_
#define _FTS_H_

#endif
EOF

>include/overlay/sys/stdarg.h cat <<EOF
#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<sys/stdarg.h>)
#include_next <sys/stdarg.h>
#endif
#else
#if __has_include(<sys/stdarg.h>)
#include <sys/stdarg.h>
#endif
#endif

#ifndef _SYS_STDARG_H_
#define _SYS_STDARG_H_
#include <machine/stdarg.h>
#endif
EOF
>include/overlay/machine/stdarg.h cat <<EOF
#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<machine/stdarg.h>)
#include_next <machine/stdarg.h>
#endif
#else
#if __has_include(<machine/stdarg.h>)
#include <machine/stdarg.h>
#endif
#endif

#ifndef _MACHINE_STDARG_H_
#define _MACHINE_STDARG_H_

#include <stdarg.h>
#include <sys/cdefs.h>
#include <sys/_types/_va_list.h>
typedef va_list __va_list;

#define va_start(v,l)  __builtin_va_start(v,l)
#define va_end(v)  __builtin_va_end(v)
#define va_arg(v, l)  __builtin_va_arg(v, l)
#define va_copy(v, l)  __builtin_va_copy(v, l)


#endif
EOF
>include/overlay/machine/wchar.h cat <<EOF
#ifdef LIBDARWIN_OVERLAY

#ifndef _MACHINE_WCHAR_H_
#define _MACHINE_WCHAR_H_
#include <sys/cdefs.h>
#include <sys/_types/_wchar_t.h>
#include <sys/_types/_wint_t.h>

typedef wchar_t ___wchar_t;
typedef wint_t __wint_t;

#endif

#endif
EOF

>include/overlay/sys/_clock_id.h cat <<EOF
#ifdef LIBDARWIN_OVERLAY

#ifndef _SYS_CLOCK_ID_H_
#define _SYS_CLOCK_ID_H_
#include <sys/cdefs.h>
#include <sys/_types/_clock_t.h>
#endif

#endif
EOF
>include/overlay/sys/_null.h cat <<EOF
#ifdef LIBDARWIN_OVERLAY

#ifndef _SYS_NULL_H_
#define _SYS_NULL_H_
#include <sys/cdefs.h>
#include <sys/_types/_null.h>
#define NULL (0L)
#endif

#endif
EOF

>include/overlay/sys/device.h cat <<EOF
#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<sys/device.h>)
#include_next <sys/device.h>
#endif
#else
#if __has_include(<sys/device.h>)
#include <sys/device.h>
#endif
#endif

#ifndef _OVERLAY_SYS_DEVICE_H_
#define _OVERLAY_SYS_DEVICE_H_
#include <sys/ioctl.h>
#define D_MEM 0

#endif

EOF



>include/overlay/signal.h cat <<'EOF'
#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<signal.h>)
#include_next <signal.h>
#endif
#else
#if __has_include(<signal.h>)
#include <signal.h>
#endif
#endif

#ifndef OVERLAY_SIGNAL_H
#define OVERLAY_SIGNAL_H
#define sys_nsig 16

#endif
EOF

>include/overlay/assert.h cat <<'EOF'
#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<assert.h>)
#include_next <assert.h>
#endif
#else
#if __has_include(<assert.h>)
#include <assert.h>
#endif
#endif

#ifndef OVERLAY_ASSERT_H
#define OVERLAY_ASSERT_H

#ifndef _DIAGASSERT
#define _DIAGASSERT(e) ((e) ? (void) 0 : assert(e))
#endif

#endif
EOF
>include/overlay/unistd.h cat <<'EOF'
#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<unistd.h>)
#include_next <unistd.h>
#endif
#else
#if __has_include(<unistd.h>)
#include <unistd.h>
#endif
#endif

#ifndef OVERLAY_UNISTD_H_
#define OVERLAY_UNISTD_H_

#include <sys/unistd.h>

#endif
EOF
>include/overlay/sys/unistd.h cat <<'EOF'
#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<sys/unistd.h>)
#include_next <sys/unistd.h>
#endif
#else
#if __has_include(<sys/unistd.h>)
#include <sys/unistd.h>
#endif
#endif

#ifndef OVERLAY_UNISTD_H_
#define OVERLAY_UNISTD_H_

#include <time.h>

int getosreldate(void);
int pipe2(int fildes[2], int flags);
int eaccess(const char *path, int mode);
#endif
EOF

>include/overlay/time.h cat <<'EOF'
#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<time.h>)
#include_next <time.h>
#endif
#else
#if __has_include(<time.h>)
#include <time.h>
#endif
#endif

#ifndef OVERLAY_TIME_H_
#define OVERLAY_TIME_H_

#include <sys/_types/_pid_t.h>
typedef pid_t     lwpid_t;

#endif
EOF

>include/overlay/sys/stat.h cat <<'EOF'
#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<sys/stat.h>)
#include_next <sys/stat.h>
#endif
#else
#if __has_include(<sys/stat.h>)
#include <sys/stat.h>
#endif
#endif

#ifndef OVERLAY_SYS_STAT_H_
#define OVERLAY_SYS_STAT_H_

#define st_atim st_atimespec
#define st_mtim st_mtimespec
#define st_ctim st_ctimespec

#endif
EOF

>include/overlay/sys/mman.h cat <<'EOF'
#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<sys/mman.h>)
#include_next <sys/mman.h>
#endif
#else
#if __has_include(<sys/mman.h>)
#include <sys/mman.h>
#endif
#endif

#ifndef OVERLAY_SYS_STAT_H_
#define OVERLAY_SYS_STAT_H_

#define MAP_NOCORE 0x0
#define MAP_SIZEALIGN 0x0
#define MAP_NOSYNC 0x0

#endif
EOF

>include/overlay/stdlib.h cat <<'EOF'
#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<stdlib.h>)
#include_next <stdlib.h>
#endif
#else
#if __has_include(<stdlib.h>)
#include <stdlib.h>
#endif
#endif

#ifndef OVERLAY_STDLIB_H_
#define OVERLAY_STDLIB_H_
#include <sys/cdefs.h>
#endif
EOF

>include/overlay/sys/param.h cat <<'EOF'
#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<sys/param.h>)
#include_next <sys/param.h>
#endif
#else
#if __has_include(<sys/param.h>)
#include <sys/param.h>
#endif
#endif

#ifndef OVERLAY_SYS_PARAM_H
#define OVERLAY_SYS_PARAM_H

#define __DragonFly_version 600518

#define roundup2(x, y)  (((x)+((y)-1))&(~((y)-1))) /* if y is powers of two */
#define rounddown2(x, y) ((x) & ~((y) - 1))
#define powerof2(x) ((((x)-1)&(x))==0)
#ifndef howmany
#define howmany(x, y)   (((x)+((y)-1))/(y))
#endif
#define NELEM(ary)  (sizeof(ary) / sizeof((ary)[0]))

#endif
EOF

>include/overlay/sys/_termios.h cat <<'EOF'
#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<sys/termios.h>)
#include_next <sys/termios.h>
#endif
#else
#if __has_include(<sys/termios.h>)
#include <sys/termios.h>
#endif
#endif

#ifndef OVERLAY_SYS_TERMIOS_H
#define OVERLAY_SYS_TERMIOS_H

#endif
EOF

>include/overlay/sys/cdefs.h cat <<EOF

#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<sys/cdefs.h>)
#include_next <sys/cdefs.h>
#endif
#else
#if __has_include(<sys/cdefs.h>)
#include <sys/cdefs.h>
#endif
#endif

#ifndef OVERLAY_SYS_CDEFS_H
#define OVERLAY_SYS_CDEFS_H

#define _XOPEN_SOURCE       1
#define _DARWIN_C_SOURCE    1

#define __POSIX_VISIBLE     200809
#define __XSI_VISIBLE       700
#define __BSD_VISIBLE       1
#define __ISO_C_VISIBLE     2011
#define __EXT1_VISIBLE      1
// ARJ: disabled as OSX defines HW_MACHINE_ARCH but it
// returns ENOENT lmao
/* #define HAVE_SYSCTL 1 */

#ifndef __GNUC_PREREQ__
# define __GNUC_PREREQ__(ma, mi) __GNUC_PREREQ(ma, mi)
#endif
#ifndef __GNUC_PREREQ
# define __GNUC_PREREQ(x, y) LLVM_GNUC_PREREQ(x, y, 0)
#endif
#ifndef LLVM_GNUC_PREREQ
# define LLVM_GNUC_PREREQ(maj, min, patch) \
    ((__GNUC__ << 20) + (__GNUC_MINOR__ << 10) + __GNUC_PATCHLEVEL__ >= \
     ((maj) << 20) + ((min) << 10) + (patch))
#endif

#define __malloclike    __attribute__((__malloc__))
#if defined(__APPLE__)
#define __pure 
#endif

#define __nonnull(...)  __attribute__((__nonnull__(__VA_ARGS__)))
#define __aligned(n) __attribute__ ((aligned(n)))
#define _Noreturn __attribute__((noreturn))

#define CTASSERT(x)     _CTASSERT(x, __LINE__)
#define _CTASSERT(x, y)     __CTASSERT(x, y)
#define __CTASSERT(x, y)    typedef char __assert ## y[(x) ? 1 : -1]

#define __printflike(fmtarg, firstvararg) \
            __attribute__((__nonnull__(fmtarg), \
              __format__ (__printf__, fmtarg, firstvararg)))
#define __printf0like(fmtarg, firstvararg) \
            __attribute__((__format__ (__printf__, fmtarg, firstvararg)))
#define __scanflike(fmtarg, firstvararg) \
        __attribute__((__format__ (__scanf__, fmtarg, firstvararg)))
#define __format_arg(fmtarg) \
        __attribute__((__format_arg__ (fmtarg)))
#define __strfmonlike(fmtarg, firstvararg) \
        __attribute__((__format__ (__strfmon__, fmtarg, firstvararg)))
#define __strftimelike(fmtarg, firstvararg) \
        __attribute__((__format__ (__strftime__, fmtarg, firstvararg)))

#define __returns_twice __attribute__((__returns_twice__))
#define __heedresult    __attribute__((__warn_unused_result__))
#define __used      __attribute__((__used__))
#define __always_inline __inline __attribute__((__always_inline__))
#define __noinline  __attribute__((__noinline__))


#define __ATTR_ALLOC_SIZE(x)     __attribute__((__alloc_size__(x)))
#define __ATTR_ALLOC_SIZE2(n, x) __attribute__((__alloc_size__(n, x)))


#define GET_3RD_ARG(x, y, z, ...) z
#define _ATTR_ALLOC_SIZE_CHOOSER(...) \
    GET_3RD_ARG(__VA_ARGS__, __ATTR_ALLOC_SIZE2, __ATTR_ALLOC_SIZE)
#define __alloc_size(...) _ATTR_ALLOC_SIZE_CHOOSER(__VA_ARGS__)(__VA_ARGS__)

#define __alloc_size2(n, x) __attribute__((__alloc_size__(n, x)))

#define __unreachable() __builtin_unreachable()
#define __LONG_LONG_SUPPORTED
#define __restrict  restrict
#define __restrict_arr
#define __predict_true(exp)     __builtin_expect((exp), 1)
#define __predict_false(exp)    __builtin_expect((exp), 0)
#define __offsetof(type, field) __builtin_offsetof(type, field)
#define __constructor(prio) __attribute__((constructor(prio)))

#if !defined(__cplusplus) && \
    (defined(__STDC_VERSION__) && __STDC_VERSION__ >= 199901)
#define __min_size(x)   static (x)
#else
#define __min_size(x)   (x)
#endif
#include <machine/stdint.h>


typedef unsigned int    __darwin_fsfilcnt_t;
typedef unsigned int    __darwin_fsblkcnt_t;
typedef unsigned int    __darwin_useconds_t;
typedef int             __darwin_suseconds_t;
typedef unsigned int    __darwin_uid_t;
typedef int             __darwin_pid_t;
typedef unsigned int    __darwin_id_t;
typedef unsigned int    __darwin_gid_t;

typedef unsigned short  __darwin_mode_t;
typedef unsigned long long  __darwin_ino64_t;
typedef unsigned long long __darwin_ino_t;
typedef int __darwin_blksize_t;
typedef long long __darwin_blkcnt_t;
typedef int __darwin_dev_t;

#define ___CT_RUNE_T_DECLARED
#include <sys/_types/_ct_rune_t.h>
#include <sys/_types/_rune_t.h>

typedef rune_t __rune_t;
typedef rune_t __ct_rune_t;

#ifndef bswap32
#define bswap32 __builtin_bswap32
#endif

#if __LITTLE_ENDIAN__ == 1
#define __htonl __builtin_bswap32
#define __ntohl __builtin_bswap32
#elif __BIG_ENDIAN__ == 1
#define __htonl
#define __ntohl
#endif

/*inherit osx pthread:*/
#define _PTHREAD_T_DECLARED

#endif
EOF

for empty in \
        machine/wchar_limits.h \
        machine/int_const.h \
        machine/int_limits.h \
    ; do
    mkdir -p include/overlay/"$(dirname "$empty")"
    if ! [ -e include/overlay/"$empty" ]; then
        >include/overlay/"$empty" cat <<EOF
EOF
    fi
done

>include/overlay/string.h cat <<EOF
#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<string.h>)
#include_next <string.h>
#endif
#else
#if __has_include(<string.h>)
#include <string.h>
#endif
#endif

#ifndef _OVERLAY_STRING_H_
#define _OVERLAY_STRING_H_
#ifndef memrchr
void *memrchr(const void *b, int c, size_t len);
#endif
#ifndef mempcpy
void *mempcpy(void *dst, const void *src, size_t len);
#endif
#undef stpcpy
char *stpcpy(char * restrict dst, const char * restrict src);
#endif
EOF

>include/overlay/stdio.h cat <<EOF
#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<stdio.h>)
#include_next <stdio.h>
#endif
#else
#if __has_include(<stdio.h>)
#include <stdio.h>
#endif
#endif

#ifdef __cplusplus
extern "C" {
#endif

#ifndef _OVERLAY_STDIO_H_
#define _OVERLAY_STDIO_H_
int fputs_unlocked(const char *str, FILE *stream);

#endif

#ifdef __cplusplus
}
#endif
EOF

>include/overlay/sys/varsym.h cat <<EOF
#ifdef LIBDARWIN_OVERLAY

#ifdef __cplusplus
extern "C" {
#endif

#ifndef _SYS_VARSYM_H_
#define _SYS_VARSYM_H_

#define MAXVARSYM_DATA 1024
#define VARSYM_ALL_MASK 0

int varsym_get(int mask, const char *wild, char *buf, int bufsize);

#endif
#endif

#ifdef __cplusplus
}
#endif
EOF
>include/overlay/sys/timespec.h cat <<EOF
#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<sys/timespec.h>)
#include_next <sys/timespec.h>
#endif
#else
#if __has_include(<sys/timespec.h>)
#include <sys/timespec.h>
#endif
#endif
#ifdef LIBDARWIN_OVERLAY

#ifndef _SYS_TIMESPEC_H_
#define _SYS_TIMESPEC_H_
#include <sys/_types/_time_t.h>
#include <sys/_types/_timespec.h>

#endif
#endif
EOF

>include/overlay/sys/procfs.h cat <<EOF
#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<sys/procfs.h>)
#include_next <sys/procfs.h>
#endif
#else
#if __has_include(<sys/procfs.h>)
#include <sys/procfs.h>
#endif
#endif

#ifndef _SYS_PROCFS_H_
#define _SYS_PROCFS_H_
#endif
EOF

>include/overlay/elf-hints.h cat <<EOF
#ifndef _OVERLAY_ELF_HINTS_H_

#include "$SRC/include/elf-hints.h"
#undef HAVE_PRSTATUS_T

#endif
EOF

>include/overlay/sys/_timespec.h cat <<EOF
#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<sys/_timespec.h>)
#include_next <sys/_timespec.h>
#endif
#else
#if __has_include(<sys/_timespec.h>)
#include <sys/_timespec.h>
#endif
#endif

#ifndef _SYS_TIMESPEC_H_
#define _SYS_TIMESPEC_H_
#include <sys/_types/_time_t.h>
#include <sys/_types/_timespec.h>
#endif
EOF

>include/overlay/sys/_pthread_spinlock.h cat << 'EOF'
#ifndef _PTHREAD_SPINLOCK_H_

#ifdef __cplusplus
extern "C" {
#endif
#if defined(__APPLE__)
#include <os/lock.h>

typedef os_unfair_lock_t pthread_spinlock_t;

int pthread_spin_init(pthread_spinlock_t *lock, int pshared);
int pthread_spin_destroy(pthread_spinlock_t *lock);
int pthread_spin_lock(pthread_spinlock_t *lock);
int pthread_spin_trylock(pthread_spinlock_t *lock);
int pthread_spin_unlock(pthread_spinlock_t *lock);
#endif
#ifdef __cplusplus
}
#endif

#endif
EOF

>pthread_spinlock.c cat <<'EOF'
#include <pthread.h>
#include <sys/_pthread_spinlock.h>
#include <errno.h>

int pthread_spin_init(pthread_spinlock_t *lock, int pshared) {
    if (pshared != PTHREAD_PROCESS_PRIVATE) {
        errno = EINVAL;
        return -1;
    }
    **lock = OS_UNFAIR_LOCK_INIT;
    return 0;
};

int pthread_spin_destroy(pthread_spinlock_t *lock) {
    return 0;
};

int pthread_spin_lock(pthread_spinlock_t *lock) {
    os_unfair_lock_lock(*lock);
    return 0;
};
int pthread_spin_trylock(pthread_spinlock_t *lock) {
    bool locked = os_unfair_lock_trylock(*lock);
    if (locked) {
        return 0;
    }
    return EBUSY;
};

int pthread_spin_unlock(pthread_spinlock_t *lock) {
    os_unfair_lock_unlock(*lock);
    return 0;
};

EOF

>include/overlay/sys/_pthread_barrier.h cat <<EOF
/*
 * Copyright (c) 2015, Aleksey Demakov
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * * Redistributions of source code must retain the above copyright notice, this
 *   list of conditions and the following disclaimer.
 * 
 * * Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#ifndef PTHREAD_BARRIER_H
#define PTHREAD_BARRIER_H

#ifdef __APPLE__

#ifdef __cplusplus
extern "C" {
#endif

#if !defined(PTHREAD_BARRIER_SERIAL_THREAD)
# define PTHREAD_BARRIER_SERIAL_THREAD  (1)
#endif

#if !defined(PTHREAD_PROCESS_PRIVATE)
# define PTHREAD_PROCESS_PRIVATE    (42)
#endif
#if !defined(PTHREAD_PROCESS_SHARED)
# define PTHREAD_PROCESS_SHARED     (43)
#endif

typedef struct {
} pthread_barrierattr_t;

typedef struct {
    pthread_mutex_t mutex;
    pthread_cond_t cond;
    unsigned int limit;
    unsigned int count;
    unsigned int phase;
} pthread_barrier_t;

int pthread_barrierattr_init(pthread_barrierattr_t *attr);
int pthread_barrierattr_destroy(pthread_barrierattr_t *attr);

int pthread_barrierattr_getpshared(const pthread_barrierattr_t *restrict attr,
                   int *restrict pshared);
int pthread_barrierattr_setpshared(pthread_barrierattr_t *attr,
                   int pshared);

int pthread_barrier_init(pthread_barrier_t *restrict barrier,
             const pthread_barrierattr_t *restrict attr,
             unsigned int count);
int pthread_barrier_destroy(pthread_barrier_t *barrier);

int pthread_barrier_wait(pthread_barrier_t *barrier);

#ifdef  __cplusplus
}
#endif

#endif /* __APPLE__ */

#endif /* PTHREAD_BARRIER_H */
EOF

>include/overlay/pthread.h cat <<'EOF'
#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<pthread.h>)
#include_next <pthread.h>
#endif
#else
#if __has_include(<pthread.h>)
#include <pthread.h>
#endif
#endif

#ifndef _OVERLAY_PTHREAD_H_
#define _OVERLAY_PTHREAD_H_

#endif
EOF

>include/overlay/objformat.h cat <<EOF
#include "${SRC}/include/objformat.h"

EOF

>include/overlay/sys/_pthreadtypes.h cat <<'EOF'
#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<sys/_pthreadtypes.h>)
#include_next <sys/_pthreadtypes.h>
#endif
#else
#if __has_include(<sys/_pthreadtypes.h>)
#include <sys/_pthreadtypes.h>
#endif
#endif

#ifndef _OVERLAY_SYS_PTHREADTYPES_H_
#define _OVERLAY_SYS_PTHREADTYPES_H_
#include <sys/_pthread/_pthread_types.h>
#include <sys/_pthread/_pthread_attr_t.h>
#include <sys/_pthread/_pthread_cond_t.h>
#include <sys/_pthread/_pthread_condattr_t.h>
#include <sys/_pthread/_pthread_key_t.h>
#include <sys/_pthread/_pthread_mutex_t.h>
#include <sys/_pthread/_pthread_mutexattr_t.h>
#include <sys/_pthread/_pthread_once_t.h>
#include <sys/_pthread/_pthread_rwlock_t.h>
#include <sys/_pthread/_pthread_rwlockattr_t.h>
#include <sys/_pthread/_pthread_t.h>
#include <sys/_pthread_barrier.h>
#include <sys/_pthread_spinlock.h>
#endif
EOF

>include/overlay/sys/sched.h cat <<'EOF'
#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<pthread/sched.h>)
#include_next <pthread/sched.h>
#endif
#else
#if __has_include(<pthread/sched.h>)
#include <pthread/sched.h>
#endif
#endif

#ifndef _OVERLAY_SYS_SCHED_H_
#define _OVERLAY_SYS_SCHED_H_
#endif
EOF

>include/overlay/sys/cpumask.h cat <<'EOF'
#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<sys/cpumask.h>)
#include_next <sys/cpumask.h>
#endif
#else
#if __has_include(<sys/cpumask.h>)
#include <sys/cpumask.h>
#endif
#endif

#ifndef _OVERLAY_SYS_CPUMASK_H_
#define _OVERLAY_SYS_CPUMASK_H_
#include <sys/cdefs.h>
typedef struct {
    __uint64_t  ary[4];
} __cpumask_t;
#ifndef cpumask_t
typedef __cpumask_t cpumask_t;
#endif
#endif
EOF

>include/overlay/sys/limits.h cat <<'EOF'
#ifdef LIBDARWIN_OVERLAY
#   if defined(__aarch64__) && __has_include_next(<arm/limits.h>)
#     include_next <arm/limits.h>
#   elif defined(__i386__) && __has_include_next(<i386/limits.h>)
#     include_next <i386/limits.h>
#   else
#     error "What arch are you?"
#   endif
# else
#   if defined(__aarch64__) && __has_include(<arm/limits.h>)
#     include <arm/limits.h>
#   elif defined(__i386__) && __has_include(<i386/limits.h>)
#     include <i386/limits.h>
#   else
#     error "What arch are you?"
#   endif
#endif

#ifndef _OVERLAY_SYS_LIMIT_H_
#define _OVERLAY_SYS_LIMIT_H_
#endif
EOF

>include/overlay/machine/atomic.h cat <<EOF
#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<machine/stdatomic.h>)
#include_next <machine/stdatomic.h>
#endif
#else
#if __has_include(<machine/stdatomic.h>)
#include <machine/stdatomic.h>
#endif
#endif
#ifdef LIBDARWIN_OVERLAY

#ifndef _MACHINE_ATOMIC_H_
#define _MACHINE_ATOMIC_H_

#include <libkern/OSAtomic.h>

#define atomic_add_long(P,V) ((void) OSAtomicAdd32Barrier(V,  P))
#define atomic_fetchadd_long(P, V) OSAtomicAdd32Barrier(V,  P)

#endif
#endif
EOF

>include/overlay/machine/inttypes.h cat <<EOF
#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<inttypes.h>)
#include_next <inttypes.h>
#endif
#else
#if __has_include(<inttypes.h>)
#include <inttypes.h>
#endif
#endif
#ifdef LIBDARWIN_OVERLAY

#ifndef _MACHINE_ATOMIC_H_
#define _MACHINE_ATOMIC_H_

#endif
#endif
EOF


>include/overlay/machine/stdint.h cat <<EOF
#ifdef LIBDARWIN_OVERLAY
#if __has_include_next(<stdint.h>)
#include_next <stdint.h>
#endif
#else
#if __has_include(<stdint.h>)
#include <stdint.h>
#endif
#endif


#ifndef _MACHINE_STDINT_H_
#define _MACHINE_STDINT_H_
#include <sys/cdefs.h>

typedef __signed char   __int8_t;
typedef unsigned char   __uint8_t;
typedef short       __int16_t;
typedef unsigned short  __uint16_t;
typedef int     __int32_t;
typedef unsigned int    __uint32_t;

typedef long long            __int64_t;
typedef unsigned long long   __uint64_t;

typedef double      __double_t;
typedef float       __float_t;
typedef long        __intlp_t;
typedef unsigned long   __uintlp_t;
typedef __int64_t   __intmax_t;
typedef __uint64_t  __uintmax_t;

typedef __intlp_t   __intptr_t;
typedef __uintlp_t  __uintptr_t;
typedef __intlp_t   __ptrdiff_t;    /* ptr1 - ptr2 */

typedef __int32_t   __int_fast8_t;
typedef __int32_t   __int_fast16_t;
typedef __int32_t   __int_fast32_t;
typedef __int64_t   __int_fast64_t;
typedef __int8_t    __int_least8_t;
typedef __int16_t   __int_least16_t;
typedef __int32_t   __int_least32_t;
typedef __int64_t   __int_least64_t;
typedef __uint32_t  __uint_fast8_t;
typedef __uint32_t  __uint_fast16_t;
typedef __uint32_t  __uint_fast32_t;
typedef __uint64_t  __uint_fast64_t;
typedef __uint8_t   __uint_least8_t;
typedef __uint16_t  __uint_least16_t;
typedef __uint32_t  __uint_least32_t;
typedef __uint64_t  __uint_least64_t;

/* <sys/types.h> */
typedef unsigned long   __clock_t;  /* ticks in CLOCKS_PER_SEC */
typedef unsigned long   __clockid_t;    /* CLOCK_* identifiers */
#ifndef _SSIZE_T_DECLARED
#define _SSIZE_T_DECLARED
#endif
typedef __int64_t   __off_t;    /* file offset or size */
typedef __int32_t   __pid_t;    /* process [group] id */
typedef __uintlp_t  __size_t;   /* sizes of objects */
typedef __intlp_t   __ssize_t;  /* byte counts or error status */
typedef long        __suseconds_t;  /* microseconds (signed) */
typedef __intlp_t   __time_t;   /* epoch time */
typedef int     __timer_t;  /* POSIX timer identifiers */

typedef int     __register_t __attribute__((__mode__(__word__)));
typedef __int32_t   __sig_atomic_t; /* XXX */
typedef __uint32_t  __socklen_t;
typedef volatile int    __atomic_intr_t;
typedef __int64_t   __rlim_t;

typedef unsigned long long uint64_t;
#ifndef off_t
typedef __off_t     off_t;
#endif
#ifndef __darwin_off_t
typedef __off_t       __darwin_off_t;
#endif


#define  INTPTR_MIN  (-__INTPTR_MAX__-1)
#define  INTPTR_MAX    __INTPTR_MAX__
#define UINTPTR_MAX   __UINTPTR_MAX__
#define PTRDIFF_MIN (-__PTRDIFF_MAX__-1)
#define PTRDIFF_MAX   __PTRDIFF_MAX__
#define    SIZE_MAX      __SIZE_MAX__
 
#endif /* _MACHINE_STDINT_H_ */
EOF

>pthread_barrier.c cat <<'EOF'
/*
 * Copyright (c) 2015, Aleksey Demakov
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * * Redistributions of source code must retain the above copyright notice, this
 *   list of conditions and the following disclaimer.
 * 
 * * Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/* imported from: https://github.com/ademakov/DarwinPthreadBarrier */

#include <pthread.h>
#include <sys/_pthread_barrier.h>

#include <errno.h>

#ifndef __unused
#define __unused __attribute__((unused))
#endif

#ifdef __APPLE__

int pthread_barrierattr_init(pthread_barrierattr_t *attr __unused)
{
    return 0;
}

int
pthread_barrierattr_destroy(pthread_barrierattr_t *attr __unused)
{
    return 0;
}

int
pthread_barrierattr_getpshared(const pthread_barrierattr_t *restrict attr __unused,
                   int *restrict pshared)
{
    *pshared = PTHREAD_PROCESS_PRIVATE;
    return 0;
}

int
pthread_barrierattr_setpshared(pthread_barrierattr_t *attr __unused,
                   int pshared)
{
    if (pshared != PTHREAD_PROCESS_PRIVATE) {
        errno = EINVAL;
        return -1;
    }
    return 0;
}

int
pthread_barrier_init(pthread_barrier_t *restrict barrier,
             const pthread_barrierattr_t *restrict attr __unused,
             unsigned count)
{
    if (count == 0) {
        errno = EINVAL;
        return -1;
    }

    if (pthread_mutex_init(&barrier->mutex, 0) < 0) {
        return -1;
    }
    if (pthread_cond_init(&barrier->cond, 0) < 0) {
        int errno_save = errno;
        pthread_mutex_destroy(&barrier->mutex);
        errno = errno_save;
        return -1;
    }

    barrier->limit = count;
    barrier->count = 0;
    barrier->phase = 0;

    return 0;
}

int
pthread_barrier_destroy(pthread_barrier_t *barrier)
{
    pthread_mutex_destroy(&barrier->mutex);
    pthread_cond_destroy(&barrier->cond);
    return 0;
}

int
pthread_barrier_wait(pthread_barrier_t *barrier)
{
    pthread_mutex_lock(&barrier->mutex);
    barrier->count++;
    if (barrier->count >= barrier->limit) {
        barrier->phase++;
        barrier->count = 0;
        pthread_cond_broadcast(&barrier->cond);
        pthread_mutex_unlock(&barrier->mutex);
        return PTHREAD_BARRIER_SERIAL_THREAD;
    } else {
        unsigned phase = barrier->phase;
        do
            pthread_cond_wait(&barrier->cond, &barrier->mutex);
        while (phase == barrier->phase);
        pthread_mutex_unlock(&barrier->mutex);
        return 0;
    }
}

#endif /* __APPLE__ */

EOF

>eaccess.c cat <<EOF
#include <unistd.h>
#include <fcntl.h>

int eaccess(const char *path, int mode) {
    return faccessat(AT_FDCWD, path, mode, AT_EACCESS);
};
EOF

>pipe2.c cat <<EOF
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <sys/fcntl.h>

#if !defined(O_CLOFORK) && defined(__APPLE__)
#define O_CLOFORK       0x08000000
#endif

int pipe2(int fildes[2], int flags) {
    memset((int*)fildes, '\0', sizeof(int)*2);
    int rv = pipe((int*)fildes);
    if (rv != 0)
        return rv;
    if ((flags & O_CLOEXEC) == O_CLOEXEC) {
        fcntl(fildes[0], F_SETFD, FD_CLOEXEC);
        fcntl(fildes[1], F_SETFD, FD_CLOEXEC);
    }
    if ((flags & O_CLOFORK) == O_CLOFORK) {
        fcntl(fildes[0], F_SETFD, O_CLOFORK);
        fcntl(fildes[1], F_SETFD, O_CLOFORK);
    }
    if ((flags & O_NONBLOCK) == O_NONBLOCK) {
        fcntl(fildes[0], F_SETFL, O_NONBLOCK);
        fcntl(fildes[1], F_SETFL, O_NONBLOCK);
    }
    return 0;
};

EOF
>string.c cat <<EOF
#include <string.h>

char *stpcpy(char * restrict dst, const char * restrict src) {
    return __builtin___stpcpy_chk(dst, src, strlen(dst));
};

EOF

>fpending.c cat <<EOF
#include <stdio.h>
#include <string.h>
#define HASUB(fp) ((fp)->_ub._base != NULL)

ssize_t __fpending(const FILE *fp)
{
    if ((fp)->_bf._base != NULL) {
        if (HASUB(fp))
            return(fp->_ur - (int) fp->_bf._base);
        else
            return(fp->_p - fp->_bf._base);
    }
    return 0;
}
EOF

>fputs_unlocked.c cat <<'EOF'
#include <stdio.h>
int fputs_unlocked(const char *str, FILE *stream) {
    return fputs(str, stream);
};
EOF

>bin/ld-flags-from-script cat <<'EOF'
#!/usr/bin/env python3
import shlex
import re
import sys
from tempfile import NamedTemporaryFile

version_name = None

ops = []
file = sys.argv[1]
with open(file, "r") as fh:
    for oline in fh:
        match (line := oline.strip()).split():
            case ["#", *_]:
                continue
            case list() as maybe_ops:
                ops = [*ops, *maybe_ops]
            case []:
                continue
sections = {"export": [], "unexport": []}
section: str = ""
for op, next_op in zip(ops, (*ops[1:], ";")):
    match (op, next_op):
        case (str(maybe_version), "{") if version_name is None:
            version = re.search(r"(?P<version>([\d\.]+))", maybe_version).groupdict()["version"]
            name = maybe_version[:maybe_version.index(version)].removesuffix("_")
            version_name = (name, version, maybe_version)
        case ("{", _):
            continue
        case ("}" | "};", _):
            version_name = None
            continue
        case ("global:", _):
            section = "export"
        case ("local:", _):
            section = "unexport"
        case ("*;", _) | ("*", ";"):
            sections[section] = "*"
        case (str(maybe_e), _) if version_name and section and (export_name := maybe_e.removesuffix(";")):
            try:
                sections[section].append(export_name)
            except AttributeError:
                print(sections[section], export_name)
                raise
        case _:
            print(f"unknown op: {op!r}", file=sys.stderr)
args = []
match sections["unexport"]:
    case "*":
        pass
    case unexports if len(unexports) > 10:
        with NamedTemporaryFile(mode="w+", delete=False, prefix="hides", suffix=".syms") as fh:
            fh.write(f"# unexports for {file!r}\n")
            for e in unexports:
                fh.write(f"_{e}\n")
            args.append("-unexported_symbols_list")
            args.append(fh.name)
    case unexports:
        for e in unexports:
            args.append("-unexported_symbol")
            args.append(e)

match sections["export"]:
    case "*":
        pass
    case exports if len(exports) > 10:
        with NamedTemporaryFile(mode="w+", delete=False, prefix="exports", suffix=".syms") as fh:
            fh.write(f"# exports for {file!r}\n")
            for e in exports:
                fh.write(f"_{e}\n")
            args.append("-exported_symbols_list")
            args.append(fh.name)
    case exports:
        for e in exports:
            args.append("-exported_symbol")
            args.append(e)

print(shlex.join(args))
EOF
chmod +x bin/ld-flags-from-script


>bin/ld cat <<'EOF'
#!/usr/bin/env sh
OIFS="$IFS"
args=
sep='
'

while [ $# -gt 0 ]; do
    case "${1}" in
        -soname)
        shift
        if [ "${1:-}" = '' ]; then
            >&2 printf 'error: no soname given!\n'
            exit 4
        fi
        soname="${1}"
        shift
        if [ "$args" = '' ]; then
            args="-install_name${sep}${soname}"
        else
            args="${args}${sep}-install_name${sep}${soname}"
        fi
        ;;
        --version-script=*)
        fn="$(printf '%s\n' "${1}" | cut -f2- -d=)"
        shift
        symlist="$(ld-flags-from-script "$fn")"
        if [ "$args" = '' ]; then
            args="${symlist}"
        else
            args="${args}${sep}${symlist}"
        fi

        ;;
        --version-script)
        shift
        if [ "${1:-}" = '' ]; then
            >&2 printf 'error: no soname given!\n'
            exit 4
        fi
        fn="${1}"
        shift
        symlist="$(ld-flags-from-script "$fn")"

        if [ "$args" = '' ]; then
            args="${symlist}"
        else
            args="${args}${sep}${symlist}"
        fi

        ;;
        *)
        if [ "$args" = '' ]; then
            args="${1}"
        else
            args="${args}${sep}${1}"
        fi
        shift
        ;;
    esac
done

>&2 printf 'ld called with: %s\n' "$(printf '%s\n' "$args" | tr '\n' ' ')"
exec /usr/bin/ld $(printf '%s\n' "$args" | tr '\n' ' ')
EOF
chmod +x bin/ld

LIBDARWIN_CFLAGS="-isystem $D/include/overlay -DLIBDARWIN_OVERLAY"
LIBDARWIN_LDFLAGS="-L$D/lib -lDarwin"

${CLANG_HOME}/bin/clang \
    $LIBDARWIN_CFLAGS \
    -c \
    pthread_barrier.c \
    -o lib/pthread_barrier.o


${CLANG_HOME}/bin/clang \
    $LIBDARWIN_CFLAGS \
    -c \
    fpending.c \
    -o lib/fpending.o

${CLANG_HOME}/bin/clang \
    $LIBDARWIN_CFLAGS \
    -c \
    string.c \
    -o lib/string.o
${CLANG_HOME}/bin/clang \
    $LIBDARWIN_CFLAGS \
    -c \
    pipe2.c \
    -o lib/pipe2.o

${CLANG_HOME}/bin/clang \
    $LIBDARWIN_CFLAGS \
    -c \
    fputs_unlocked.c \
    -o lib/fputs_unlocked.o

${CLANG_HOME}/bin/clang \
    $LIBDARWIN_CFLAGS \
    -c \
    eaccess.c \
    -o lib/eaccess.o

${CLANG_HOME}/bin/clang \
    $LIBDARWIN_CFLAGS \
    -c \
    pthread_spinlock.c \
    -o lib/pthread_spinlock.o

${CLANG_HOME}/bin/clang \
    -I "$D/include" \
    -D LIBDARWIN_OVERLAY \
    -c \
    varsym_shim.c \
    -o lib/varsym_shim.o
${CLANG_HOME}/bin/clang -c \
    $SRC/lib/libc/net/base64.c \
    -o lib/base64.o
${CLANG_HOME}/bin/clang -c \
    $SRC/lib/libc/string/memchr.c \
    -o lib/memchr.o
${CLANG_HOME}/bin/clang -c \
    $SRC/lib/libc/string/mempcpy.c \
    -o lib/mempcpy.o
${CLANG_HOME}/bin/clang -c \
    $SRC/lib/libc/string/memrchr.c \
    -o lib/memrchr.o
${CLANG_HOME}/bin/clang -c \
    $SRC/lib/libc/stdlib/reallocarray.c \
    -o lib/reallocarray.o
${CLANG_HOME}/bin/clang -c \
    yywrap.c \
    -o lib/yywrap.o
${CLANG_HOME}/bin/clang \
    $LIBDARWIN_CFLAGS \
    -c \
    assert.c \
    -o lib/assert.o
${CLANG_HOME}/bin/clang \
    $LIBDARWIN_CFLAGS \
    -c \
    _init.c \
    -o lib/_init.o
${CLANG_HOME}/bin/clang \
    $LIBDARWIN_CFLAGS \
    -c \
    $SRC/lib/libc/gen/getobjformat.c \
    -o lib/getobjformat.o

ar rvs $PWD/lib/libDarwin.a \
        lib/_init.o \
        lib/base64.o \
        lib/yywrap.o \
        lib/reallocarray.o \
        lib/varsym_shim.o \
        lib/memrchr.o \
        lib/memchr.o \
        lib/mempcpy.o \
        lib/pthread_barrier.o \
        lib/pthread_spinlock.o \
        lib/fpending.o \
        lib/pipe2.o \
        lib/getobjformat.o \
        lib/string.o \
        lib/eaccess.o \
        lib/assert.o \
        lib/fputs_unlocked.o

rm -f lib/*.o


install -C \
    $SRC/sys/sys/queue.h \
    include/overlay/sys/queue.h

EXTRA_CFLAGS="-Wno-macro-redefined -Wno-nullability-completeness"
EXTRA_CXXFLAGS="-L${CLANG_HOME}/lib/c++ -L${CLANG_HOME}/lib/unwind -lunwind"

cat >etc/compilers.conf <<EOF

clang21_CC=${CLANG_HOME}/bin/clang
clang21_CXX=${CLANG_HOME}/bin/clang++
clang21_CPP=${CLANG_HOME}/bin/clang-cpp
clang21_GCOV=${CLANG_HOME}/bin/clang-cov
clang21_INCOPT="-nostdinc -iwithprefixbefore ${D}/include -iprefix \${INCPREFIX} --include-directory-after ${SDK}/usr/include --include-directory-after ${CLANG_HOME}/lib/clang/21/include ${LIBDARWIN_CFLAGS} $(pkg-config --cflags libbsd-overlay) ${EXTRA_CFLAGS}"
clang21_INCOPTCXX="-nostdinc++ -D_LIBCPP_DISABLE_AVAILABILITY -cxx-isystem ${CLANG_HOME}/include/c++/v1 ${EXTRA_CXXFLAGS}"
clang21_CLANG=\${clang21_CC}
clang21_CLANGCXX=\${clang21_CXX}
clang21_CLANGCPP=\${clang21_CPP}

EOF

>bin/cc.sh \
    sed \
        -e 's|@@INCPREFIX@@|/|g' \
        -e 's|@@MACHARCH@@|x86_64|g' \
        -e 's|@@MACHREL@@|6.5|g' \
        -e 's|/etc|'"$D/etc"'|g' \
        $SRC/libexec/customcc/cc.sh
chmod +x bin/cc.sh
for item in cpp c++ gcc g++ clang-cpp clang++ clang gcov CC
do
    ln -sf $PWD/bin/cc.sh bin/$item
done

YACC="$(command -v yacc)"
cat >bin/yacc <<'EOT'
#!/usr/bin/env sh
M4="${M4:-}"
if [ "$M4" != '' ] && ! [ -x "$M4" ] ; then
    >&2 printf 'warn: M4=%s does not exist, failsafe to sys path\n' "$M4"
    unset M4
fi
exec $YACC $@
EOT
sed -i '' -e 's|$YACC|'"$YACC"'|g' bin/yacc

cp $SRC/etc/defaults/make.conf etc/make.conf

>> etc/make.conf <<'EOF'
CFLAGS+=-Wno-nullability-completeness
EOF

chmod +x bin/yacc

ln -sf "$(command -v make)"     bin/gmake
ln -sf "$(command -v bmake)"    bin/make

export PATH="${D}/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

> bin/mtree cat << 'EOF'
#!/usr/bin/env sh
set -eu

parse_args() {
    while [ $# -gt 0 ]; do
        case "${1}" in
            -f)
            shift
            filename="${1}"
            shift
            processed="$(mktemp)"
            >"$processed" sed 's|nochange||g' "${filename}"
            printf '%s %s\n' '-f' "$processed"
            ;;
            *)
            printf '%s\n' "${1}"
            shift
            ;;
        esac
    done
}

exec /usr/sbin/mtree $(parse_args $@ | tr '\n' ' ')
EOF
chmod +x bin/mtree

install -m0755 \
    $SRC/usr.bin/mkdep/mkdep.sh \
    bin/mkdep

if [ "${1:-}" = '' ]; then
    set -- "crossworld"
fi

LOGFILE="$OPWD/bw.out"
_log=">${LOGFILE} 2>&1"
_background='&'
if [ $_verbose -gt 0 ]; then
    _log=
    _background=
fi
rm -f "$LOGFILE" || true
t_s="$(date +%s)"
rc=0

start-build() {
    env \
    MAKEOBJDIRPREFIX="$MAKEOBJDIRPREFIX" \
    __MAKE_CONF=$D/etc/make.conf \
    MACHINE_PLATFORM=pc64 \
    HOST_BINUTILSVER=binutils234 \
    bmake \
        -e \
        -C "$SRC" \
        BUILD_ARCH=arm64 \
        HOST_CCVER=clang21 \
        CCVER=clang21 \
        NOSHARED=NO \
        NXLDFLAGS='${LDFLAGS}' \
        TARGET_ARCH=x86_64 \
        TARGET_PLATFORM=pc64 \
        CC="$D/bin/cc" \
        _HOSTPATH="${D}/bin:${PATH}" \
        EXTRA_LDADD+="$(pkg-config --libs libbsd-overlay) ${LIBDARWIN_LDFLAGS}" \
        "$make_args"
}



eval "${_log}" start-build \
     "${_background}" || rc="$?"

if [ "${_background}" != '' ]; then
    pid=$!
    >&2 printf 'build pid %s, log at %s\n' "$pid" "${LOGFILE}"
    wait $pid || rc=$?
    t_e="$(date +%s)"
    >&2 printf 'build ended in %ss, return code %s\n' "$((t_e - t_s))" "$rc"
fi

if [ $rc -ne 0 ]; then
    if [ ! -z "$_log" ]; then
        >&2 printf 'examine log at: %s\n' "$LOGFILE"
    fi
    exit $rc
fi
