#!/usr/bin/env python3
"""quickproof tools/conf.py FILE...: check that a quickproof.conf is data, before anything sources it.

quickproof.conf is read by bash (`source`), so that it can use arrays, `+=`, quoting and variables.  A proof
repository comes from someone else, and `qp verify` must not run its code: a conf that ran a command could,
for example, rewrite the framework after qp verify has compared it with its own.  So every tool that sources
a conf first checks that it contains nothing but assignments, in this grammar:

    line       := blank | comment | NAME=VALUE | NAME+=VALUE | NAME=( WORDS ) | NAME+=( WORDS )
    WORDS      := words, comments and newlines, up to the closing parenthesis
    word       := one or more of: an unquoted run of [A-Za-z0-9_./,:=+@%-], '...', "...", $NAME, ${NAME},
                  and the one command substitution $(gcc -print-file-name=include)
    "..."      := text without ", \\ and `, in which $ appears only as $NAME, ${NAME} or the substitution above

NAME starts with an upper-case letter (UNITS_<law> carries a law's name) and is one that bash, the environment and the scripts that source the conf do not use (PATH,
IFS, GP, ... are refused).  A conf is part of what a law means, since its flags reach the preprocessor, so two
kinds of flag that could silently change a harness are refused as well: -include and -imacros, and -D or -U of
QuickProof's own names (qp_assert, qp_assume, gp_assert, gp_assume, nondet_*, pick, the allocator, quickproof_*); write -DNAME as
one word.  Exits 0 if every FILE passes; otherwise prints the first offending line of each
and exits 1."""
import re
import sys

SUBST = '$(gcc -print-file-name=include)'
NAME = r'[A-Z][A-Za-z0-9_]*'   # upper-case first: UNITS_<law> may hold a law's lower-case name
RESERVED = {
    # bash and the environment of the commands that the scripts run
    'PATH', 'HOME', 'IFS', 'ENV', 'CDPATH', 'GLOBIGNORE', 'PS1', 'PS2', 'PS3', 'PS4', 'SHELLOPTS', 'BASHOPTS',
    'PROMPT_COMMAND', 'TERM', 'LANG', 'TMPDIR', 'PWD', 'OLDPWD', 'SHELL', 'USER', 'LOGNAME', 'HOSTNAME',
    'EUID', 'UID', 'PPID', 'RANDOM', 'SECONDS', 'LINENO', 'OPTIND', 'OPTARG', 'REPLY', 'FUNCNAME', 'PIPESTATUS',
    'MAIL', 'MAILPATH', 'HISTFILE', 'INPUTRC', 'EXECIGNORE', 'FIGNORE', 'TIMEFORMAT', 'TZ', 'POSIXLY_CORRECT',
    # the variables of the scripts that source a conf (tools/clight.sh, tools/interp.sh, tools/qp, ...)
    'GP', 'CONFIG', 'ALLOC', 'TMP', 'RENAME', 'OUTS', 'SAN', 'SRC', 'OUT', 'CC', 'CFLAGS', 'LDFLAGS', 'CPPFLAGS',
}
RESERVED_PREFIXES = ('BASH', 'LC_', 'LD_', 'OPAM', 'COQ', 'ROCQ', 'QP_', 'GIT_', 'OCAML', 'CAML', 'PYTHON',
                     'ASAN', 'UBSAN', 'MSAN', 'LSAN', 'TSAN', 'DYLD_')
FLAG_REFUSED = re.compile(r'^(?:--?include|--?imacros)\b|^-[DU]$|^-[DU]\s*(?:qp_assert|qp_assume|gp_assert|gp_assume|nondet_\w*|pick|malloc|free|'
                          r'calloc|realloc|quickproof_\w*)\b')
UNQUOTED = re.compile(r'[A-Za-z0-9_./,:=+@%-]+')
VAR = re.compile(r'\$(?:%s|\{%s\})' % (NAME, NAME))
VAR_ANY = re.compile(r'\$(?:[A-Za-z_][A-Za-z0-9_]*|\{[A-Za-z_][A-Za-z0-9_]*(?:\[@\])?\})')


class Bad(Exception):
    pass


def name_ok(n):
    return re.fullmatch(NAME, n) and n not in RESERVED and not n.startswith(RESERVED_PREFIXES)


def dquoted(s):
    """The inside of a "..." string: only plain text, variables and the one substitution."""
    if re.search(r'[\\`]', s):
        raise Bad('a backslash or a backquote in a "..." string')
    rest = s.replace(SUBST, '')
    rest = VAR_ANY.sub('', rest)
    if '$' in rest:
        raise Bad('a $ in a "..." string that is not $NAME, ${NAME} or %s' % SUBST)


def word(text, i):
    """Read one word at text[i]; return the index after it."""
    start = i
    while i < len(text):
        c = text[i]
        if text.startswith(SUBST, i):
            i += len(SUBST)
        elif c == '"':
            j = text.find('"', i + 1)
            if j < 0:
                raise Bad('an unterminated "..." string')
            dquoted(text[i + 1:j])
            i = j + 1
        elif c == "'":
            j = text.find("'", i + 1)
            if j < 0:
                raise Bad("an unterminated '...' string")
            i = j + 1
        elif c == '$':
            m = VAR_ANY.match(text, i)
            if not m:
                raise Bad('a $ that is not $NAME, ${NAME} or %s' % SUBST)
            i = m.end()
        else:
            m = UNQUOTED.match(text, i)
            if not m:
                break
            i = m.end()
    if i == start:
        raise Bad('unexpected %r' % text[i])
    w = re.sub(r'["\']', '', text[start:i])
    if FLAG_REFUSED.match(w):
        raise Bad('%s: a flag that could change what a harness means' % w)
    return i


def check(text):
    """Raise Bad (with the line number) unless text is a conf in the grammar above."""
    i, n = 0, len(text)

    def line_of(k):
        return text.count('\n', 0, k) + 1

    try:
        while i < n:
            # between statements: blanks, newlines and comments
            m = re.compile(r'[ \t]*(#[^\n]*)?\n?').match(text, i)
            if m.end() > i:
                i = m.end()
                continue
            m = re.compile(r'(%s)\+?=' % NAME).match(text, i)
            if not m:
                raise Bad('not an assignment NAME=... (only assignments are allowed)')
            if not name_ok(m.group(1)):
                raise Bad('%s may not be set in a conf' % m.group(1))
            i = m.end()
            if i < n and text[i] == '(':
                i += 1
                while True:
                    m = re.compile(r'(?:[ \t\n]|#[^\n]*)*').match(text, i)
                    i = m.end()
                    if i >= n:
                        raise Bad('an array without its closing parenthesis')
                    if text[i] == ')':
                        i += 1
                        break
                    i = word(text, i)
                    if i < n and text[i] not in ' \t\n)':
                        raise Bad('unexpected %r after a word' % text[i])
            elif i < n and text[i] not in ' \t\n#':
                i = word(text, i)
            # the rest of the line: blanks and a comment
            m = re.compile(r'[ \t]*(#[^\n]*)?(\n|$)').match(text, i)
            if not m:
                raise Bad('more than one assignment on a line, or a command after one')
            i = m.end()
    except Bad as e:
        raise Bad('line %d: %s' % (line_of(i), e))


def main(files):
    bad = 0
    for f in files:
        try:
            check(open(f).read())
        except Bad as e:
            print('%s: refused: %s' % (f, e), file=sys.stderr)
            bad += 1
        except OSError as e:
            print('%s: %s' % (f, e), file=sys.stderr)
            bad += 1
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
