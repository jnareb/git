#!/bin/sh

test_description='Various filesystem issues'

. ./test-lib.sh

auml=`printf '\xc3\xa4'`
aumlcdiar=`printf '\x61\xcc\x88'`

case_insensitive=
test_expect_success 'see if we expect ' '

	test_case=test_expect_success
	test_unicode=test_expect_success
	mkdir junk &&
	echo good >junk/CamelCase &&
	echo bad >junk/camelcase &&
	if test "$(cat junk/CamelCase)" != good
	then
		test_case=test_expect_failure
		case_insensitive=t
		say "will test on a case insensitive filesystem"
	fi &&
	rm -fr junk &&
	mkdir junk &&
	>junk/"$auml" &&
	case "$(cd junk && echo *)" in
	"$aumlcdiar")
		test_unicode=test_expect_failure
		say "will test on a unicode corrupting filesystem"
		;;
	*)	;;
	esac &&
	rm -fr junk
'

if test "$case_insensitive"
then
test_expect_success "detection of case insensitive filesystem during repo init" '

	test $(git config --bool core.ignorecase) = true
'
else
test_expect_success "detection of case insensitive filesystem during repo init" '

	test_must_fail git config --bool core.ignorecase >/dev/null ||
	test $(git config --bool core.ignorecase) = false
'
fi

test_expect_success "setup case tests" '

	git config core.ignorecase true &&
	touch camelcase &&
	git add camelcase &&
	git commit -m "initial" &&
	git tag initial &&
	git checkout -b topic &&
	git mv camelcase tmp &&
	git mv tmp CamelCase &&
	git commit -m "rename" &&
	git checkout -f master

'

$test_case 'rename (case change)' '

	git mv camelcase CamelCase &&
	git commit -m "rename"

'

$test_case 'merge (case change)' '

	rm -f CamelCase &&
	rm -f camelcase &&
	git reset --hard initial &&
	git merge topic

'

$test_case 'add (with different case)' '

	git reset --hard initial &&
	rm camelcase &&
	echo 1 >CamelCase &&
	git add CamelCase &&
	test $(git ls-files | grep -i camelcase | wc -l) = 1

'

test_expect_success "setup unicode normalization tests" '

  test_create_repo unicode &&
  cd unicode &&
  touch "$aumlcdiar" &&
  git add "$aumlcdiar" &&
  git commit -m initial
  git tag initial &&
  git checkout -b topic &&
  git mv $aumlcdiar tmp &&
  git mv tmp "$auml" &&
  git commit -m rename &&
  git checkout -f master

'

$test_unicode 'rename (silent unicode normalization)' '

 git mv "$aumlcdiar" "$auml" &&
 git commit -m rename

'

$test_unicode 'merge (silent unicode normalization)' '

 git reset --hard initial &&
 git merge topic

'

test_done
