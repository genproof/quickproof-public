# tests/qp/cbmc.sh: the toy proof bounds
PROOF_UID = bounds
MAX_LEN = 4
DEFINES += -DMAX_LEN=$(MAX_LEN)
UNWINDSET += toy_count.0:$(MAX_LEN)
PROOF_SOURCES += $(HARNESS_FILE)
PROJECT_SOURCES += $(SRCDIR)/src/toy.c

include ../Makefile.common
