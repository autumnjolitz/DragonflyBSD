GCC_NO_PATH=	yes
LOCAL_CONFIG=	yes
.include "../Makefile.inc"
.PATH: ${GCCDIR}/libiberty

LIB=		iberty

GOOD_CONFIG=	${.CURDIR}/../../support-libs/libiberty/config.h

SRCS=	concat.c cp-demangle.c cp-demint.c cplus-dem.c dyn-string.c \
	fibheap.c fopen_unlocked.c getpwd.c getruntime.c hashtab.c hex.c \
	lbasename.c lrealpath.c make-relative-prefix.c make-temp-file.c \
	md5.c obstack.c partition.c pex-unix.c physmem.c safe-ctype.c \
	splay-tree.c xexit.c xmalloc.c xmemdup.c xstrdup.c xstrerror.c \
	filename_cmp.c regex.c xstrndup.c xasprintf.c xvasprintf.c \
	vprintf-support.c

.ifdef ${.MAKE.OS} == "Darwin"
# we don't have these function in native OSX:
#  pex_init_common, dlang_demangle, 
#  rust_is_mangled, rust_demangle_sym
# so please build these for us ;)
SRCS+= rust-demangle.c d-demangle.c pex-common.c
.endif

config.h: ${GOOD_CONFIG}
	cp ${.ALLSRC} .

beforedepend: config.h
afterdepend: libiberty.na

CLEANFILES=	config.h

.include <bsd.hostlib.mk>
