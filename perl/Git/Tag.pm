=head1 NAME

Git::Commit - Object-oriented interface to Git commits.

=cut


use strict;
use warnings;
use 5.6.0;


package Git::Tag;

use Git::Repo qw( assert assert_hash assert_opts );  # todo: move those

use base qw( Git::Object );

use constant _MESSAGE => 'M';
use constant _ENCODING => 'E';
use constant _TAGGER => 'A';
use constant _TAG => 'T';
use constant _TYPE => 'Y';
use constant _OBJECT => 'O';


sub _load {
	my($self, $raw_text) = shift;
	return if defined $self->{_MESSAGE()};  # already loaded

	if (!defined $raw_text) {
		(my $type, $raw_text) = $self->repo->cat_file($self->hash);
		die "$self->hash not found" unless defined $type;  # TODO test
		die "$self->hash is a $type, not a tag object" unless $type eq 'tag';
	}

	assert($/ eq "\n");  # for chomp
	(my $header, $self->{_MESSAGE()}) = split "\n\n", $raw_text, 2;
	# Parse header.
	for my $line (split "\n", $header) {
		chomp($line);
		assert($line);
		my($key, $value) = split ' ', $line, 2;
		if ($key eq 'object') {
			$self->{_OBJECT()} = $value;
		} elsif ($key eq 'type') {
			$self->{_TYPE()} = $value;
		} elsif ($key eq 'tag') {
			$self->{_TAG()} = $value;
		} elsif ($key eq 'tagger') {
			$self->{_TAGGER()} = $value;
		} elsif ($key eq 'encoding') {
			$self->{_ENCODING()} = $value;
		} else {
			die "unrecognized tag header $key";
		}
	}
	undef;
}

sub object {
	my $self = shift;
	$self->_load;
	$self->{_OBJECT()};
}

sub type {
	my $self = shift;
	$self->_load;
	$self->{_TYPE()} or '';
}

sub tag {
	my $self = shift;
	$self->_load;
	$self->{_TAG()};
}

sub tagger {
	my $self = shift;
	$self->_load;
	$self->{_TAGGER()} or '';
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
