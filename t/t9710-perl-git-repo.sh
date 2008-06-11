#!/bin/sh
#
# Copyright (c) 2008 Lea Wiemann
#

test_description='perl interface (Git.pm)'
. ./test-lib.sh

# set up test repository

test_expect_success \
    'set up test repository' \
    'echo "*.test" > .gitignore &&

     echo "test file 1" > file1 &&
     echo "test file 2" > file2 &&
     mkdir directory1 &&
     echo "in directory1" >> directory1/file &&
     mkdir directory2 &&
     echo "in directory2" >> directory2/file &&
     git add . &&
     git commit -m "first commit" &&
     git rev-parse HEAD > revisions.test &&

     git tag -a -m "tag message" tag-object-1 &&

     echo "changed file 1" > file1 &&
     git commit -a -m "second commit" &&
     git rev-parse HEAD >> revisions.test

     git branch branch-2 &&

     echo "changed file 2" > file2 &&
     git commit -a -m "third commit" &&
     git rev-parse HEAD >> revisions.test
     '

test_external_without_stderr \
    'Git::Repo API' \
    perl ../t9710/test.pl

test_done
