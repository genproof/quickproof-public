# tests/qp/cbmc.sh: the toy proof remove_lib
PROOF_UID = remove_lib
PROOF_SOURCES += $(PROOF_STUB)/replaceable_stub.c
REMOVE_FUNCTION_BODY += toy_replaceable
PROOF_SOURCES += $(HARNESS_FILE)
PROJECT_SOURCES += $(SRCDIR)/src/toy.c

include ../Makefile.common
