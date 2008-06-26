=head1 NAME

Git::Commit - Object-oriented interface to Git commits.

=cut


use strict;
use warnings;
use 5.6.0;


package Git::Commit;

use Git::Repo qw( assert assert_sha1 assert_opts );  # todo: move those
use Git::Object;
use Git::Tag;

use base qw( Git::Object );

use constant _MESSAGE => 'M';
use constant _ENCODING => 'E';
use constant _TREE => 'T';
use constant _PARENTS => 'P';
use constant _AUTHOR => 'A';
use constant _COMMITTER => 'C';

sub _load {
	my($self, $raw_text) = shift;
	return if defined $self->{_MESSAGE()};  # already loaded

	my $sha1 = $self->sha1;
	if (!defined $raw_text) {
		(my $type, $raw_text) = $self->repo->cat_file($sha1);
		die "$sha1 not found" unless defined $type;
		die "$sha1 is a $type object (expected a commit object)"
		    unless $type eq 'commit';
	}

	assert($/ eq "\n");  # for chomp
	(my $header, $self->{_MESSAGE()}) = split "\n\n", $raw_text, 2;
	# Parse header.
	for my $line (split "\n", $header) {
		chomp($line);
		assert($line);
		my($key, $value) = split ' ', $line, 2;
		if ($key eq 'tree') {
			$self->{_TREE()} = $value;
		} elsif ($key eq 'parent') {
			push @{$self->{_PARENTS()}}, $value;
		} elsif ($key eq 'author') {
			$self->{_AUTHOR()} = $value;
		} elsif ($key eq 'committer') {
			$self->{_COMMITTER()} = $value;
		} elsif ($key eq 'encoding') {
			$self->{_ENCODING()} = $value;
		} else {
			die "unrecognized commit header $key";
		}
	}
	undef;
}

sub tree {
	my $self = shift;
	$self->_load;
	$self->{_TREE()};
}

sub parents {
	my $self = shift;
	$self->_load;
	#map { ref($self)->new($self->repo, $_) }
	@{$self->{_PARENTS()}};
}

sub author {
	my $self = shift;
	$self->_load;
	$self->{_AUTHOR()} or '';
}

sub committer {
	my $self = shift;
	$self->_load;
	$self->{_COMMITTER()} or '';
}

sub message {
	my $self = shift;
	$self->_load;
	$self->{_MESSAGE()};
}

sub encoding {
	my $self = shift;
	$self->_load;
	$self->{_ENCODING()};
}


1;
