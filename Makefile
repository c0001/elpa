# "Dummy" initial Makefile for GNU Emacs Lisp Package Archive.

setup: GNUmakefile manifest.scm admin

GNUmakefile: admin
	ln -s admin/GNUmakefile ./

manifest.scm: admin
	ln -s admin/elpa-manifest.scm $@

admin:
	git worktree add -b elpa-admin admin origin/entropy-elpa-admin
