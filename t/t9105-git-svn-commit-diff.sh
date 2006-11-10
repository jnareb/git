#!/bin/sh
#
# Copyright (c) 2006 Eric Wong
test_description='git-svn commit-diff'
. ./lib-git-svn.sh

if test -n "$GIT_SVN_NO_LIB" && test "$GIT_SVN_NO_LIB" -ne 0
then
	echo 'Skipping: commit-diff needs SVN libraries'
	test_done
	exit 0
fi

test_expect_success 'initialize repo' "
	mkdir import &&
	cd import &&
	echo hello > readme &&
	svn import -m 'initial' . $svnrepo &&
	cd .. &&
	echo hello > readme &&
	git update-index --add readme &&
	git commit -a -m 'initial' &&
	echo world >> readme &&
	git commit -a -m 'another'
	"

head=`git rev-parse --verify HEAD^0`
prev=`git rev-parse --verify HEAD^1`

# the internals of the commit-diff command are the same as the regular
# commit, so only a basic test of functionality is needed since we've
# already tested commit extensively elsewhere

test_expect_success 'test the commit-diff command' "
	test -n '$prev' && test -n '$head' &&
	git-svn commit-diff -r1 '$prev' '$head' '$svnrepo' &&
	svn co $svnrepo wc &&
	cmp readme wc/readme
	"

test_done
