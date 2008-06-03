#!/usr/bin/perl
use lib (split(/:/, $ENV{GITPERLLIB}));

use warnings;
use strict;

use Test::More qw(no_plan);
use Test::Exception;
use Carp::Always;

use Cwd;
use File::Basename;
use File::Temp;
use IO::String;
use Data::Dumper; # for debugging

BEGIN { use_ok('Git::Repo') }

our $old_stderr;
sub discard_stderr {
	open our $old_stderr, ">&", STDERR or die "cannot save STDERR";
	close STDERR;
}
sub restore_stderr {
	open STDERR, ">&", $old_stderr or die "cannot restore STDERR";
}

# set up
our $repo_dir = "trash directory";
our $abs_repo_dir = Cwd->cwd;
die "this must be run by calling the t/t97* shell script(s)\n"
    if basename(Cwd->cwd) ne $repo_dir;
ok(our $r = Git::Repo->new(directory => "./.git"), 'open repository');
ok((open REVISIONS, 'revisions.test' and chomp(our @revisions = <REVISIONS>)),
   '(read revisions)');
our $head = $revisions[-1];

# command methods
is($r->cmd_output(cmd => ['cat-file', '-t', 'HEAD']), "commit\n", 'cmd_output: basic');
discard_stderr;
dies_ok { $r->cmd_output(cmd => ['bad-cmd']); } 'cmd_output: die on error';
restore_stderr;
my $bad_output;
lives_ok { $bad_output = $r->cmd_output(
		   cmd => ['rev-parse', '--verify', '--quiet', 'badrev'],
		   max_exit_code => 1); }
    'cmd_output: max_error';
is($bad_output, '', 'cmd_output: return string on non-zero exit');
is($r->cmd_oneline(cmd => ['cat-file', '-t', 'HEAD']), "commit", 'cmd_oneline: basic');
# untested: get_bidi_pipe

# get_hash
is_deeply($r->get_hashes(['HEAD', 'HEAD^', 'badname']),
	  [@revisions[-1, -2], undef], 'get_hash: array');
is($r->get_hash('HEAD'), $revisions[-1], 'get_hash: scalar, repeated');

# cat_file
is_deeply([$r->cat_file($r->get_hash("$revisions[0]:file1"))], ['blob', "test file 1\n"], 'cat_file: blob');
is_deeply([$r->cat_file($r->get_hash("$revisions[0]:file1"))], ['blob', "test file 1\n"], 'cat_file: blob, repeated');
is($r->cat_file('0' x 40), undef, 'cat_file: non-existent hash');

# get_commit
isa_ok($r->get_commit($revisions[0]), 'Git::Commit');

# get_tag
isa_ok($r->get_tag($r->get_hash('tag-object-1')), 'Git::Tag');

# get_path
is($r->get_path($head, $r->get_hash('HEAD:directory1/file')),
   'directory1/file', 'get_path: file');
is($r->get_path($head, $r->get_hash('HEAD:directory1')),
   'directory1', 'get_path: directory');
is($r->get_path($head, '0' x 40), undef, 'get_path: nonexistent');

# ls_tree
our @lstree = @{$r->ls_tree($revisions[0])};
is_deeply([map { $_->[4] } @lstree],
	  [qw( .gitignore directory1 directory2 file1 file2 )],
	  'ls_tree: order');
like($lstree[1]->[2], qr/^[0-9a-f]{40}$/, 'ls_tree: hash');
$lstree[1]->[2] = $lstree[3]->[2] = 'SHA1';
is_deeply($lstree[1], ['040000', 'tree', 'SHA1', undef, 'directory1'],
	  'ls_tree: structure (directories)');
is_deeply($lstree[3], ['100644', 'blob', 'SHA1', 12, 'file1'],
	  'ls_tree: structure (files)');

# get_refs
my @refs = @{$r->get_refs()};
is((grep { $_->[2] eq 'refs/heads/branch-2' } @refs), 1,
   'get_refs: branch existence and uniqueness');
my @branch2_info = @{(grep { $_->[2] eq 'refs/heads/branch-2' } @refs)[0]};
is_deeply([@branch2_info], [$revisions[1], 'commit', 'refs/heads/branch-2'],
	  'get_heads: sub-array contents');
@refs = @{$r->get_refs('refs/tags')};
ok(@refs, 'get_refs: pattern');
is((grep { $_->[2] eq 'refs/heads/branch-2' } @refs), 0, 'get_refs: pattern');

# name_rev
is($r->name_rev($revisions[1]), 'branch-2', 'name_rev: branch');
is($r->name_rev($head, 1), undef, 'name_rev: branch, tags only');
is($r->name_rev($revisions[0]), 'tags/tag-object-1^0', 'name_rev: tag object');
is($r->name_rev($revisions[0], 1), 'tag-object-1^0', 'name_rev: tag object, tags only');



# Git::Commmit
print "Git::Commit:\n";

BEGIN { use_ok('Git::Commit') }

my $invalid_commit = Git::Commit->new($r, '0' x 40);
is($invalid_commit->hash, '0' x 40, 'new, hash: accept invalid hashes');
dies_ok { $invalid_commit->tree } 'die on accessing properties of invalid hashes';

$invalid_commit = Git::Commit->new($r, $r->get_hash('HEAD:')); # tree, not commit
dies_ok { $invalid_commit->tree } 'die on accessing properties of non-commit objects';

my $c = Git::Commit->new($r, $revisions[1]);
is($c->repo, $r, 'repo: basic');
is($c->hash, $revisions[1], 'hash: basic');
is($c->{Git::Commit::_PARENTS}, undef,
   'lazy loading: not loaded after reading hash');
is($c->tree, $r->get_hash("$revisions[1]:"), 'tree: basic');
ok($c->{Git::Commit::_PARENTS}, 'lazy loading: loaded after reading tree');
is_deeply([$c->parents], [$revisions[0]], 'parents: basic');
like($c->author, qr/A U Thor <author\@example.com> [0-9]+ \+0000/, 'author: basic');
like($c->committer, qr/C O Mitter <committer\@example.com> [0-9]+ \+0000/, 'committer: basic');
is($c->encoding, undef, 'encoding: undef');
is($c->message, "second commit\n", 'message: basic');
is($c, $c->hash, 'stringify: basic');

# use tags instead of commits
my $indirect_commit = Git::Commit->new($r, $r->get_hash('tag-object-3'));
is($indirect_commit->tree, $r->get_hash('tag-object-3:'));


# Git::Tag
print "Git::Tag:\n";

BEGIN { use_ok('Git::Tag') }

# We don't test functionality inherited from Git::Object that we
# already tested in the Git::Commit tests.

my $t = Git::Tag->new($r, $r->get_hash('tag-object-1'));
is($t->tag, 'tag-object-1', 'tag: basic');
is($t->object, $revisions[0], 'object: basic');
is($t->type, 'commit', 'tag: type');
like($t->tagger, qr/C O Mitter <committer\@example.com> [0-9]+ \+0000/, 'tagger: basic');
is($t->encoding, undef, 'encoding: undef');
is($t->message, "tag message 1\n", 'message: basic');
