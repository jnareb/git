#!/bin/sh
# Copyright (c) 2006, Junio C Hamano.

test_description='Per branch config variables affects "git fetch".

'

. ./test-lib.sh

D=`pwd`

test_expect_success setup '
	echo >file original &&
	git add file &&
	git commit -a -m original'

test_expect_success "clone and setup child repos" '
	git clone . one &&
	cd one &&
	echo >file updated by one &&
	git commit -a -m "updated by one" &&
	cd .. &&
	git clone . two &&
	cd two &&
	git repo-config branch.master.remote one &&
	git repo-config remote.one.url ../one/.git/ &&
	git repo-config remote.one.fetch refs/heads/master:refs/heads/one &&
	cd .. &&
	git clone . three &&
	cd three &&
	git repo-config branch.master.remote two &&
	git repo-config branch.master.merge refs/heads/one &&
	mkdir -p .git/remotes &&
	{
		echo "URL: ../two/.git/"
		echo "Pull: refs/heads/master:refs/heads/two"
		echo "Pull: refs/heads/one:refs/heads/one"
	} >.git/remotes/two
'

test_expect_success "fetch test" '
	cd "$D" &&
	echo >file updated by origin &&
	git commit -a -m "updated by origin" &&
	cd two &&
	git fetch &&
	test -f .git/refs/heads/one &&
	mine=`git rev-parse refs/heads/one` &&
	his=`cd ../one && git rev-parse refs/heads/master` &&
	test "z$mine" = "z$his"
'

test_expect_success "fetch test for-merge" '
	cd "$D" &&
	cd three &&
	git fetch &&
	test -f .git/refs/heads/two &&
	test -f .git/refs/heads/one &&
	master_in_two=`cd ../two && git rev-parse master` &&
	one_in_two=`cd ../two && git rev-parse one` &&
	{
		echo "$master_in_two	not-for-merge"
		echo "$one_in_two	"
	} >expected &&
	cut -f -2 .git/FETCH_HEAD >actual &&
	diff expected actual'

test_expect_success 'fetch following tags' '

	cd "$D" &&
	git tag -a -m 'annotated' anno HEAD &&
	git tag light HEAD &&

	mkdir four &&
	cd four &&
	git init &&

	git fetch .. :track &&
	git show-ref --verify refs/tags/anno &&
	git show-ref --verify refs/tags/light

'

test_done
