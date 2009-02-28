#!/bin/sh
#
# Copyright (c) 2009 Vitaly Shukela
# Copyright (c) 2009 Eric Wong
#

test_description='git svn property tests'
. ./lib-git-svn.sh

test_expect_success 'setup test repository' '
	svn co "$svnrepo" s &&
	(
		cd s &&
		mkdir qqq www &&
		echo test_qqq > qqq/test_qqq.txt &&
		echo test_www > www/test_www.txt &&
		svn add qqq &&
		svn add www &&
		svn commit -m "create some files" &&
		svn up &&
		echo hi >> www/test_www.txt &&
		svn commit -m "modify www/test_www.txt" &&
		svn up
	)
'

test_expect_success 'clone an SVN repository with ignored www directory' '
	git svn clone --ignore-paths="^www" "$svnrepo" g &&
	echo test_qqq > expect &&
	for i in g/*/*.txt; do cat $i >> expect2; done &&
	test_cmp expect expect2
'

test_expect_success 'SVN-side change outside of www' '
	(
		cd s &&
		echo b >> qqq/test_qqq.txt &&
		svn commit -m "SVN-side change outside of www" &&
		svn up &&
		svn log -v | fgrep "SVN-side change outside of www"
	)
'

test_expect_success 'update git svn-cloned repo' '
	(
		cd g &&
		git svn rebase --ignore-paths="^www" &&
		printf "test_qqq\nb\n" > expect &&
		for i in */*.txt; do cat $i >> expect2; done &&
		test_cmp expect2 expect &&
		rm expect expect2
	)
'

test_expect_success 'SVN-side change inside of ignored www' '
	(
		cd s &&
		echo zaq >> www/test_www.txt
		svn commit -m "SVN-side change inside of www/test_www.txt" &&
		svn up &&
		svn log -v | fgrep "SVN-side change inside of www/test_www.txt"
	)
'

test_expect_success 'update git svn-cloned repo' '
	(
		cd g &&
		git svn rebase --ignore-paths="^www" &&
		printf "test_qqq\nb\n" > expect &&
		for i in */*.txt; do cat $i >> expect2; done &&
		test_cmp expect2 expect &&
		rm expect expect2
	)
'

test_expect_success 'SVN-side change in and out of ignored www' '
	(
		cd s &&
		echo cvf >> www/test_www.txt
		echo ygg >> qqq/test_qqq.txt
		svn commit -m "SVN-side change in and out of ignored www" &&
		svn up &&
		svn log -v | fgrep "SVN-side change in and out of ignored www"
	)
'

test_expect_success 'update git svn-cloned repo again' '
	(
		cd g &&
		git svn rebase --ignore-paths="^www" &&
		printf "test_qqq\nb\nygg\n" > expect &&
		for i in */*.txt; do cat $i >> expect2; done &&
		test_cmp expect2 expect &&
		rm expect expect2
	)
'

test_done
