#!/usr/bin/env python3
"""tests/qp/test_cbmc_make.py: the Makefile reader and small helpers of tools/importers/cbmc.py (qp import-cbmc).

Offline, no toolchain: Makefiles in a temporary directory are read as text (never run), and the results are
compared with what make would compute.  Exit 0 iff every check passes."""
import importlib.util
import os
import sys
import tempfile

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('cbmc', os.path.join(HERE, '..', '..', 'tools', 'importers', 'cbmc.py'))
cbmc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cbmc)

fails = 0


def check(what, got, want):
    global fails
    if got == want:
        print('ok   %s' % what)
    else:
        fails += 1
        print('FAIL %s: got %r, want %r' % (what, got, want))


with tempfile.TemporaryDirectory() as d:
    root = os.path.join(d, 'cbmc', 'proofs')
    proof = os.path.join(root, 'p')
    os.makedirs(proof)
    marker = os.path.join(d, 'shell-was-run')
    open(os.path.join(root, 'Makefile-project-defines'), 'w').write(
        '# project defines\n'
        'INCLUDES += -I$(SRCDIR)/include\n'
        'DEFINES += -DPROJECT=1\n'
        'MAX ?= 99          # a default the proof overrides\n'
        'DEFINES += -DMAXV=$(MAX)\n'
        'LITANI ?= $(shell touch %s)\n'
        'ifneq ($(shell which kissat),)\n'
        '  DEFINES += -DNEVER=1\n'
        'else\n'
        '  DEFINES += -DNEVER_EITHER=1\n'
        'endif\n'
        'define RECIPE\n'
        'DEFINES += -DIN_DEFINE=1\n'
        'endef\n' % marker)
    open(os.path.join(root, 'Makefile.common'), 'w').write(
        'sinclude $(PROOF_ROOT)/Makefile-project-defines\n'
        'sinclude $(PROOF_ROOT)/Makefile-does-not-exist\n'
        'SRCDIR ?= $(abspath $(PROOF_ROOT)/../..)\n'
        'IMMEDIATE := [$(LATE)]\n'
        'DEFERRED = [$(LATE)]\n'
        'LATE = late\n'
        'CHECKFLAGS += --bounds-check \\\n'
        '              --pointer-check\n'
        'all:\n'
        '\tDEFINES += -DRECIPE_LINE=1\n')
    open(os.path.join(proof, 'Makefile'), 'w').write(
        'PROOF_UID = p\n'
        'MAX = 4\n'
        'DEFINES += -DQUOTED="(a b)" -D SPACED=2\n'
        'SRCS = a.c b.c\n'
        'OBJS = $(SRCS:.c=.o)\n'
        'PATS = $(patsubst %.c,%.goto,$(SRCS))\n'
        'PREFIXED = $(addprefix src/,$(SRCS))\n'
        'ONLY_A = $(filter a.%,$(SRCS))\n'
        'include ../Makefile.common\n'
        'DEFINES += -DLAST=$(MAX)\n')
    fixed = {'PROOFDIR': proof, 'PROOF_ROOT': root, 'CBMC_ROOT': os.path.dirname(root)}
    m = cbmc.Make(proof, fixed)
    m.read(os.path.join(proof, 'Makefile'))
    check('include and sinclude followed, a missing sinclude skipped',
          [os.path.basename(f) for f in m.files], ['Makefile', 'Makefile.common', 'Makefile-project-defines'])
    check('?= does not override an earlier = (MAX = 4 before MAX ?= 99)', m.value('MAX'), '4')
    check('+= in order, quoted -D one word, "-D X" kept as two words, conditionals and define blocks skipped',
          m.get('DEFINES'), ['-DQUOTED=(a b)', '-D', 'SPACED=2', '-DPROJECT=1', '-DMAXV=4', '-DLAST=4'])
    check('cbmc.tokens joins "-D X"', cbmc.tokens(m.get('DEFINES'))[1], '-DSPACED=2')
    check('$(shell ...) not run, value empty', (m.value('LITANI'), os.path.exists(marker)), ('', False))
    check('a skipped conditional that sets DEFINES is noted',
          any('DEFINES' in n and 'conditional' in n for n in m.notes), True)
    check(':= expands at once, = when used', (m.value('IMMEDIATE'), m.value('DEFERRED')), ('[]', '[late]'))
    check('line continuation', m.get('CHECKFLAGS'), ['--bounds-check', '--pointer-check'])
    check('recipe lines ignored', 'RECIPE_LINE' in m.value('DEFINES'), False)
    check('abspath relative to the proof directory', m.value('SRCDIR'), d)
    check('substitution reference', m.value('OBJS'), 'a.o b.o')
    check('patsubst', m.value('PATS'), 'a.goto b.goto')
    check('addprefix', m.value('PREFIXED'), 'src/a.c src/b.c')
    check('filter', m.value('ONLY_A'), 'a.c')
    m2 = cbmc.Make(proof, dict(fixed, MAX='65536'))
    m2.read(os.path.join(proof, 'Makefile'))
    check('a fixed variable (--set) wins over every assignment', m2.get('DEFINES')[-1], '-DLAST=65536')
    check('the first value assigned is recorded (the upstream value for the claim)', m2.assigned.get('MAX'), '4')
    m3 = cbmc.Make(proof, fixed, follow=False)
    m3.read(os.path.join(proof, 'Makefile'))
    check('follow=False reads the proof Makefile alone', [os.path.basename(f) for f in m3.files], ['Makefile'])

check('define_name', [cbmc.define_name(x) for x in ('-DA=1', '-DB', '-UC', '-DF(x)=0', 'junk')],
      [('A', 'D'), ('B', 'D'), ('C', 'U'), ('F', 'D'), (None, None)])
check('define_line', [cbmc.define_line(x) for x in ('-DA=1', '-DB', '-UC', '-DF(x)=(x)')],
      ['#define A 1', '#define B 1', '#undef C', '#define F(x) (x)'])
check('early: C library types and struct tags', [cbmc.early(s, 'f') for s in (
    'uint64_t f(void)', 'bool f(const void *const qp_a0)', 'struct s *f(void)', 'MQTTStatus_t f(void)')],
      [True, True, True, False])
check('unit_out', cbmc.unit_out('source/core-mqtt.c'), 'src/source_core_mqtt')
t = cbmc.Types()
check('resolve', [t.resolve(x)['k'] for x in ('const char *', 'int (*)(int)', 'uint8_t[4]', 'bool', 'double',
                                               'unsigned long', 'struct nowhere', 'char *const')],
      ['ptr', 'fptr', 'array', 'bool', 'float', 'int', 'incomplete', 'ptr'])
check('resolve: signed char and short are not picked', [t.resolve(x).get('how') for x in ('char', 'short', 'int')],
      ['schar', 'short', 'pick'])
check('resolve: multi-dimensional arrays, the first dimension outermost',
      (t.resolve('int[2][3]')['dim'], t.resolve('int[2][3]')['elem']), ('2', 'int[3]'))
sys.exit(1 if fails else 0)
