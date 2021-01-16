# "Dummy" initial Makefile for GNU Emacs Lisp Package Archive.

setup: GNUmakefile admin

GNUmakefile: admin
	ln -s admin/GNUmakefile ./

admin:
	git worktree add -b elpa-admin admin origin/entropy-elpa-admin
