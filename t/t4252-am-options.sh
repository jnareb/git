#!/bin/sh

test_description='git am not losing options'
. ./test-lib.sh

tm="$TEST_DIRECTORY/t4252"

test_expect_success setup '
	cp "$tm/file-1-0" file-1 &&
	cp "$tm/file-2-0" file-2 &&
	git add file-1 file-2 &&
	test_tick &&
	git commit -m initial &&
	git tag initial
'

test_expect_success 'interrupted am --whitespace=fix' '
	rm -rf .git/rebase-apply &&
	git reset --hard initial &&
	test_must_fail git am --whitespace=fix "$tm"/am-test-1-? &&
	git am --skip &&
	grep 3 file-1 &&
	grep "^Six$" file-2
'

test_expect_success 'interrupted am -C1' '
	rm -rf .git/rebase-apply &&
	git reset --hard initial &&
	test_must_fail git am -C1 "$tm"/am-test-2-? &&
	git am --skip &&
	grep 3 file-1 &&
	grep "^Three$" file-2
'

test_expect_success 'interrupted am -p2' '
	rm -rf .git/rebase-apply &&
	git reset --hard initial &&
	test_must_fail git am -p2 "$tm"/am-test-3-? &&
	git am --skip &&
	grep 3 file-1 &&
	grep "^Three$" file-2
'

test_expect_success 'interrupted am -C1 -p2' '
	rm -rf .git/rebase-apply &&
	git reset --hard initial &&
	test_must_fail git am -p2 -C1 "$tm"/am-test-4-? &&
	git am --skip &&
	grep 3 file-1 &&
	grep "^Three$" file-2
'

test_done
