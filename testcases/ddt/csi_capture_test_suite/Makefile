# MakeFile function     :: MakeFile for compiling CSI capture test suite

top_srcdir              ?= ../../..

include $(top_srcdir)/include/mk/env_pre.mk

SUBDIRS			:= datafiles
KERNEL_DIR		:= $(patsubst %/include,%,$(KERNEL_INC))
INSTALL_DIR             := testcases/bin/ddt

FILTER_OUT_DIRS         :=

# We don't want to copy over the Makefile
UNWANTED_FILES          := Makefile

INSTALL_MODE            := 00755

#INSTALL_TARGETS         := $(filter-out $(UNWANTED_FILES),$(notdir $(patsubst $(abs_srcdir)/%,%,$(wildcard $(abs_srcdir)/*))))

CFLAGS          += -g -Wall -O1 -fomit-frame-pointer -DTCID=\"test_patterns\"
LDFLAGS         += -g -static
INCLUDES        = -I $(KERNEL_USR_INC) -I ../utils/user 


#List of source files- Update this on adding a new C file
SOURCES := \
        src/capture_simple.c \

MAKE_TARGETS            := csi_capture_test

csi_capture_test:
	$(CC) $(CFLAGS) $(LDFLAGS) -o csi_capture_test ${INCLUDES} ${SOURCES}

include $(top_srcdir)/include/mk/generic_trunk_target.mk
