=head1 NAME

Git::Repo - Perl low-level access to the Git version control system.

=cut


use strict;
use warnings;
use 5.6.0;


package Git::Repo;

use Scalar::Util qw( reftype );
use Carp qw( carp );
use Carp::Always;
use IPC::Open2 qw( open2 );
use Data::Dumper; # for debugging

our ($VERSION, @EXPORT, @EXPORT_OK);

# Under development, may change at any time.  Don't base any code on
# this.
$VERSION = '0.01';

use base qw( Exporter );

@EXPORT = qw( );
@EXPORT_OK = qw ( );


=head1 SYNOPSIS

  use Git::Repo;

=cut


sub assert_opts {
	die "must have an even number of arguments for named options"
	    unless $#_ % 2;
}

sub assert {
	die 'assertion failed' unless shift;
}

sub assert_hash {
	for my $hash (@_) {
		die 'no hash given' unless defined $hash;
		die "'$hash' is not a hash (need to use get_hash?)"
		    unless $hash =~ /^[a-f0-9]{40}$/;
	}
}

=item new ( OPTIONS )

Return a new repository object.  The following options are supported:

B<directory> - The directory of the repository.

Examples:

    $repo = Git::Repo->new(directory => "/path/to/repository.git");
    $repo = Git::Repo->new(directory => "/path/to/working_copy/.git");
=cut

sub new {
	my $class = shift;
	assert_opts(@_);
	my $self = {@_};
	bless $self, $class;
	assert defined($self->{directory});
	return $self;
}

sub repo_dir {
	shift->{directory}
}

=head2 Calling the Git binary

=item cmd_output ( OPTIONS )

Return the output of the given git command as a string, or as a list
of lines in array context.  Valid options are:

B<cmd> - An array of arguments to pass to git.

B<max_exit_code> - Die if the return value is greater than
C<max_return>.  (default: 0)

To do: Implement base path for git binary (like /usr/local/bin).

To do: According to Git.pm, this might not work with ActiveState Perl
on Win 32.  Need to check or wait for reports.

=cut

sub cmd_output {
	my $self = shift;
	assert_opts @_;
	my %opts = (max_exit_code => 0, @_);
	# We don't support string-commands here unless someone makes a
	# case for them -- they are too dangerous.
	assert(reftype($opts{cmd}) eq 'ARRAY');
	my @cmd = ($self->_get_git_cmd, @{$opts{cmd}});
	open my $fh, '-|', @cmd
	    or die 'cannot open pipe';
	my($output, @lines);
	if(wantarray) {
		@lines = <$fh>;
	} else {
		local $/;
		$output = <$fh>;
	}
	if(not close $fh) {
		if($!) {
			# Close failed.  Git.pm says it is OK to not
			# die here.
			carp "error closing pipe: $!";
		} elsif($? >> 8) {
			my $exit_code = $? >> 8;
			die "Command died with exit code $exit_code: " . join(" ", @cmd)
			    if $exit_code > $opts{max_exit_code};
		}
	}
	return @lines if(wantarray);
	return $output;
}

=item cmd_oneline ( OPTIONS )

Like cmd_output, but only return the first line, without newline.

=cut

sub cmd_oneline {
	my @lines = cmd_output(@_);
	chomp($lines[0]);
	return $lines[0];
}

=item get_bidi_pipe ( OPTIONS ) {

Open a new bidirectional pipe and return the its STDIN and STDOUT file
handles.  Valid options are:

B<cmd> - An array of arguments to pass to git.

B<reuse> - Reuse a previous pipe with the same command line and whose
reuse option was true (default: false).

=cut

sub get_bidi_pipe {
	my $self = shift;
	assert_opts @_;
	my %opts = @_;
	die 'missing or empty cmd option' unless $opts{cmd} and @{$opts{cmd}};
	my($stdin, $stdout);
	my $cmd_str = join ' ', @{$opts{cmd}};  # key for reusing pipes
	if($opts{reuse}) {
		my $pair = $self->{bidi_pipes}->{$cmd_str};
		return @$pair if $pair;
	}
	open2($stdout, $stdin, ($self->_get_git_cmd, @{$opts{cmd}}))
	    or die 'cannot open pipe';
	if($opts{reuse}) {
		$self->{bidi_pipes}->{$cmd_str} = [$stdin, $stdout];
	}
	return ($stdin, $stdout);
}
	
# Return the first items of the git command line, for instance
# qw(/usr/bin/git --git-dir=/path/to/repo.git).
sub _get_git_cmd {
	my $self = shift;
	return ('git', '--git-dir=' . $self->repo_dir);
}



=head2  

=item get_hash ( EXTENDED_OBJECT_IDENTIFIER )

Look up the object referred to by C<EXTENDED_OBJECT_IDENTIFER> and
return its SHA1 hash, or undef if the lookup failed.  When passed a
SHA1 hash, only return it if it exists in the repository.

C<EXTENDED_OBJECT_IDENTIFER> can refer to a commit, file, tree, or tag
object; see "git help rev-parse", section "Specifying Revisions".

=cut

sub get_hash {
	my($self, $object_id) = @_;
	assert(defined $object_id);
	# Implement in terms of get_hashes.
	return ${$self->get_hashes([$object_id])}[0];
}

=item get_hashes ( ARRAY_REF )

Return the hashes of all objects, or undef for any objects that do not
exist.  This can be faster than using map { get_hash $_ } because it
may combines multiple lookups if caching is enabled.

=cut

sub get_hashes {
	my($self, $object_ids) = @_;

	return [map {
		scalar (($self->cat_file_batch_check($_))[0]) } @$object_ids];
}

=item get_blob ( HASH )
Return the contents of the blob identified by C<HASH>.
=cut

# TODO: Add optional $file_handle parameter.

sub get_blob {
	my ($self, $hash) = @_;
	assert_hash($hash);

	return $self->cmd_output(cmd => ['cat-file', 'blob', $hash])
}

=item get_path ( TREEISH_HASH, BLOB_HASH )

Return the path of the blob identified by C<BLOB_HASH> in the tree
identified by C<TREEISH_HASH>, or undef if the blob does not exist in
the given tree.

=cut

sub get_path {
	my ($self, $treeish, $blob_hash) = @_;
	assert_hash($treeish, $blob_hash);

	# TODO: Turn this into a line-by-line pipe and/or reimplement
	# in terms of recursive ls_tree calls.
	my @lines = split "\n", $self->cmd_output(cmd => ['ls-tree', '-r', '-t', $treeish]);
	for (@lines) {
		if(/^[0-9]+ [a-z]+ $blob_hash\t(.+)$/) {
			return $1;
		}
	}
	return undef;
}

=item ls_tree ( TREEISH_HASH )

Return a reference to an array of five-element arrays [$mode, $type,
$hash, $blob_size, $name].  $blob_size is an integer or undef for
tree entries (sub-directories).

=cut

sub ls_tree {
	my($self, $treeish) = @_;
	assert_hash($treeish);

	my @lines = split "\n", $self->cmd_output(cmd => ['ls-tree', '--long', $treeish]);
	return [map { /([0-9]+) ([a-z]+) ([0-9a-f]{40})\s+([0-9-]+)\t(.+)/;
		      [$1, $2, $3, $4 eq '-' ? undef : int($4), $5] } @lines];
}

=item get_refs ( [PATTERN] )

Return a reference to an array of [$hash, $object_type, $ref_name]
triples.  If C<PATTERN> is given, only refs matching the pattern are
returned; see "git help for-each-ref" for details.

=cut

sub get_refs {
	my($self, $pattern) = @_;

	return [ map [ split ], $self->cmd_output(
			 cmd => [ 'for-each-ref',
				  defined $pattern ? $pattern : () ]) ];
}

=item name_rev ( COMMITTISH_HASH [, TAGS_ONLY] )

Return a symbolic name for the commit identified by
C<COMMITTISH_HASH>, or undef if no name can be found; see "git help
name-rev" for details.  If C<TAGS_ONLY> is true, no branch names are
used to name the commit.

=cut

sub name_rev {
	my($self, $hash, $tags_only) = @_;
	assert_hash($hash);

	my $name = $self->cmd_oneline(
		cmd => [ 'name-rev', $tags_only ? '--tags' : (), '--name-only',
			 $hash ]);
	return $name eq 'undefined' ? undef : $name;
}


# TODO: Underscore-prefix the following methods, and exclude them from
# perldoc documentation, so we can change the API in the future?

=head2 Access to low-level Git binary output

=item cat_file_batch_check ( EXTENDED_OBJECT_IDENTIFIER )

Return an array of ($hash, $type, $size) as it is output by cat-file
--batch-check, or an empty array if the given object cannot be found.

=cut

sub cat_file_batch_check {
	my($self, $object_id) = @_;
	my ($in, $out) = $self->get_bidi_pipe(
		cmd => ['cat-file','--batch-check'], reuse => 1);
	print $in "$object_id\n" or die 'cannot write to pipe';
	chomp(my $output = <$out>) or die 'no output from pipe';
	if($output =~ /missing$/) {
		return ();
	} else {
		$output =~ /^([0-9a-f]{40}) ([a-z]+) ([0-9]+)$/
		    or die "invalid response: $output";
		return ($1, $2, $3);
	}
}


1;
