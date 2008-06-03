=head1 NAME

Git::Object - Object-oriented interface to Git objects (base class).

=cut


use strict;
use warnings;
use 5.6.0;


package Git::Object;

use Git::Repo qw( assert assert_hash assert_opts );  # todo: move those

our (@EXPORT, @EXPORT_OK);

use base qw( Exporter );

@EXPORT = qw( );
@EXPORT_OK = qw ( );

use overload
    '""' => \&stringify;

# Hash indices:
# tags, commits, trees
use constant _REPO => 'R';
use constant _HASH => 'H';

=item new ( REPO, HASH )

Create a new Git::Object object for the object with hash
C<COMMIT_HASH> in the repository C<REPO> (Git::Repo).

Note that C<HASH> must be the hash of a commit object, not a
tag object, and that it must exist in the repository if you use any
methods other than repo and hash.

=cut

sub new {
	my($class, $repo, $hash) = @_;
	assert(ref $repo);
	assert_hash($hash);
	my $self = {_REPO() => $repo, _HASH() => $hash};
	bless $self, $class;
	return $self;
}

sub _load {
	my($self, $type, $raw_text) = shift;
	return if defined $self->{_MESSAGE()};  # already loaded

	if (!defined $raw_text) {
		# TODO: resolve tags
		(my $type, $raw_text) = $self->repo->cat_file($self->hash);
		die "$self->hash not found" unless defined $type;  # TODO test
		die "$self->hash is a $type, not a commit object" unless $type eq 'commit';
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

=item repo

Return the Git::Repo object this object was instantiated with.

=cut

sub repo {
	shift->{_REPO()}
}

=item hash ()

Return the hash this object was instantiated with.  Note that this may
not be hash of the actual object after resolving tag objects.

=cut

sub hash {
	shift->{_HASH()}
}

sub stringify {
	shift->hash
}


1;
