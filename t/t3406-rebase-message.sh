#!/bin/sh

test_description='messages from rebase operation'

. ./test-lib.sh

quick_one () {
	echo "$1" >"file$1" &&
	git add "file$1" &&
	test_tick &&
	git commit -m "$1"
}

test_expect_success setup '
	quick_one O &&
	git branch topic &&
	quick_one X &&
	quick_one A &&
	quick_one B &&
	quick_one Y &&

	git checkout topic &&
	quick_one A &&
	quick_one B &&
	quick_one Z

'

cat >expect <<\EOF
Already applied: 0001 A
Already applied: 0002 B
Committed: 0003 Z
EOF

test_expect_success 'rebase -m' '

	git rebase -m master >report &&
	sed -n -e "/^Already applied: /p" \
		-e "/^Committed: /p" report >actual &&
	diff -u expect actual

'

test_done
