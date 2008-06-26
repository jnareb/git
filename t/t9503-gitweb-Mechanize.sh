#!/bin/sh
#
# Copyright (c) 2008 Jakub Narebski
# Copyright (c) 2008 Lea Wiemann
#

# This test supports the --long-tests option.

# This test only runs on Perl 5.8 and later versions, since
# Test::WWW::Mechanize::CGI requires Perl 5.8.

test_description='gitweb tests (using WWW::Mechanize)

This test uses Test::WWW::Mechanize::CGI to test gitweb.'

# helper functions

safe_chmod () {
	chmod "$1" "$2" &&
	if [ "$(git config --get core.filemode)" = false ]
	then
		git update-index --chmod="$1" "$2"
	fi
}

. ./test-lib.sh

# check if test can be run
"$PERL_PATH" -MEncode -e 'decode_utf8("", Encode::FB_CROAK)' >/dev/null 2>&1 || {
	test_expect_success \
		'skipping gitweb tests, perl version is too old' :
	test_done
	exit
}

"$PERL_PATH" -MTest::WWW::Mechanize::CGI -e '' >/dev/null 2>&1 || {
	test_expect_success \
		'skipping gitweb tests, Test::WWW::Mechanize::CGI not found' :
	test_done
	exit
}

# set up test repository
test_expect_success 'set up test repository' '

	echo "Not an empty file." > file &&
	git add file &&
	test_tick && git commit -a -m "Initial commit." &&
	git branch b &&

	echo "New file" > new_file &&
	git add new_file &&
	test_tick && git commit -a -m "File added." &&

	safe_chmod +x new_file &&
	test_tick && git commit -a -m "Mode changed." &&

	git mv new_file renamed_file &&
	test_tick && git commit -a -m "File renamed." &&

	rm renamed_file &&
	ln -s file renamed_file &&
	test_tick && git commit -a -m "File to symlink." &&
	git tag with-symlink &&

	git rm renamed_file &&
	rm -f renamed_file &&
	test_tick && git commit -a -m "File removed." &&

	cp file file2 &&
	git add file2 &&
	test_tick && git commit -a -m "File copied." &&

	echo "New line" >> file2 &&
	safe_chmod +x file2 &&
	test_tick && git commit -a -m "Mode change and modification." &&

	mkdir dir1 &&
	echo "New file" >> dir1/file1 &&
	git add dir1/file1 &&
	test_tick && git commit -a -m "File added in subdirectory." &&
	git tag -m "creating a tag object" tag-object

	git checkout b &&
	echo "Branch" >> b &&
	git add b &&
	test_tick && git commit -a -m "On branch" &&
	git checkout master &&
	test_tick && git pull . b
'

# set up empty repository
# TODO!

# set up repositories for gitweb
# TODO!

# set up gitweb configuration
safe_pwd="$("$PERL_PATH" -MPOSIX=getcwd -e 'print quotemeta(getcwd)')"
cat >gitweb_config.perl <<EOF
# gitweb configuration for tests

our \$version = "current";
our \$GIT = "$GIT_EXEC_PATH/git";
our \$projectroot = "$safe_pwd";
our \$project_maxdepth = 8;
our \$home_link_str = "projects";
our \$site_name = "[localhost]";
our \$site_header = "";
our \$site_footer = "";
our \$home_text = "indextext.html";
our @stylesheets = ("file:///$safe_pwd/../../gitweb/gitweb.css");
our \$logo = "file:///$safe_pwd/../../gitweb/git-logo.png";
our \$favicon = "file:///$safe_pwd/../../gitweb/git-favicon.png";
our \$projects_list = "";
our \$export_ok = "";
our \$strict_export = "";
our %feature;
\$feature{'blame'}{'default'} = [1];

1;
__END__
EOF

cat >.git/description <<EOF
gitweb test repository
EOF

GITWEB_CONFIG="$(pwd)/gitweb_config.perl"
export GITWEB_CONFIG

# run tests

test_external \
	'test gitweb output' \
	"$PERL_PATH" ../t9503/test.pl

test_done
