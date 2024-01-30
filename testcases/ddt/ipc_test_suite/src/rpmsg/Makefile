# MakeFile function     :: MakeFile for compiling rpc_test

top_srcdir              ?= ../../../../..

include $(top_srcdir)/include/mk/env_pre.mk

INSTALL_DIR             := testcases/bin/ddt

FILTER_OUT_DIRS         :=

#List of source files- Update this on adding a new C file

PRU_SOURCES := \
        rpmsg_pru_user_space_echo.c

# We don't want to copy over the Makefile
UNWANTED_FILES          := Makefile \
                           rpmsg-rpc-stress.use \
                           ${SOURCES}

INSTALL_MODE            := 00755

CFLAGS          += -g -Wall -O1 -fomit-frame-pointer
LDFLAGS         += -g
LDLIBS          += -lpthread
INCLUDES        = -I $(KERNEL_USR_INC)

MAKE_TARGETS            := test_rpmsg_pru

test_rpmsg_pru:
	$(CC) -o test_rpmsg_pru ${INCLUDES} ${PRU_SOURCES} ${CFLAGS} ${LDFLAGS} $(LDLIBS)

include $(top_srcdir)/include/mk/generic_leaf_target.mk
