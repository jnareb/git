# gitweb - simple web interface to track changes in git repositories
#
# (C) 2006, John 'Warthog9' Hawley <warthog19@eaglescrag.net>
# (C) 2010, Jakub Narebski <jnareb@gmail.com>
#
# This program is licensed under the GPLv2

#
# Gitweb caching engine, simple file-based cache
#

# Minimalistic cache that stores data in the filesystem, without serialization
# and currently without any kind of cache expiration (all keys last forever till
# they got explicitely removed).
#
# It follows Cache::Cache and CHI interfaces (but does not implement it fully)

package GitwebCache::SimpleFileCache;

use strict;
use warnings;

use File::Path qw(mkpath);
use File::Temp qw(tempfile);
use Digest::MD5 qw(md5_hex);

# by default, the cache nests all entries on the filesystem single
# directory deep, i.e. '60/b725f10c9c85c70d97880dfe8191b3' for
# key name (key digest) 60b725f10c9c85c70d97880dfe8191b3.
#
our $DEFAULT_CACHE_DEPTH = 1;

# by default, the root of the cache is located in 'cache'.
#
our $DEFAULT_CACHE_ROOT = "cache";

# by default we don't use cache namespace (empty namespace);
# empty namespace does not allow for simple implementation of clear() method.
#
our $DEFAULT_NAMESPACE = '';

# ......................................................................
# constructor

# The options are set by passing in a reference to a hash containing
# any of the following keys:
#  * 'namespace'
#    The namespace associated with this cache.  This allows easy separation of
#    multiple, distinct caches without worrying about key collision.  Defaults
#    to $DEFAULT_NAMESPACE.
#  * 'cache_root' (Cache::FileCache compatibile),
#    'root_dir' (CHI::Driver::File compatibile),
#    The location in the filesystem that will hold the root of the cache.
#    Defaults to $DEFAULT_CACHE_ROOT.
#  * 'cache_depth' (Cache::FileCache compatibile),
#    'depth' (CHI::Driver::File compatibile),
#    The number of subdirectories deep to cache object item.  This should be
#    large enough that no cache directory has more than a few hundred objects.
#    Defaults to $DEFAULT_CACHE_DEPTH unless explicitly set.
#  * 'default_expires_in' (Cache::Cache compatibile),
#    'expires_in' (CHI compatibile) [seconds]
#    The expiration time for objects place in the cache.
#    Defaults to -1 (never expire) if not explicitly set.
sub new {
	my $class = shift;
	my %opts = ref $_[0] ? %{ $_[0] } : @_;

	my $self = {};
	$self = bless($self, $class);

	my ($root, $depth, $ns, $expires_in);
	if (%opts) {
		$root =
			$opts{'cache_root'} ||
			$opts{'root_dir'};
		$depth =
			$opts{'cache_depth'} ||
			$opts{'depth'};
		$ns = $opts{'namespace'};
		$expires_in =
			$opts{'default_expires_in'} ||
			$opts{'expires_in'};
	}
	$root  = $DEFAULT_CACHE_ROOT  unless defined($root);
	$depth = $DEFAULT_CACHE_DEPTH unless defined($depth);
	$ns    = $DEFAULT_NAMESPACE   unless defined($ns);
	$expires_in = -1 unless defined($expires_in); # <0 means never

	$self->set_root($root);
	$self->set_depth($depth);
	$self->set_namespace($ns);
	$self->set_expires_in($expires_in);

	return $self;
}


# ......................................................................
# accessors

# http://perldesignpatterns.com/perldesignpatterns.html#AccessorPattern

# creates get_depth() and set_depth($depth) etc. methods
foreach my $i (qw(depth root namespace expires_in)) {
	my $field = $i;
	no strict 'refs';
	*{"get_$field"} = sub {
		my $self = shift;
		return $self->{$field};
	};
	*{"set_$field"} = sub {
		my ($self, $value) = @_;
		$self->{$field} = $value;
	};
}


# ----------------------------------------------------------------------
# utility functions and methods

# Return root dir for namespace (lazily built, cached)
sub path_to_namespace {
	my ($self) = @_;

	if (!exists $self->{'path_to_namespace'}) {
		if (defined $self->{'namespace'} &&
		    $self->{'namespace'} ne '') {
			$self->{'path_to_namespace'} = "$self->{'root'}/$self->{'namespace'}";
		} else {
			$self->{'path_to_namespace'} =  $self->{'root'};
		}
	}
	return $self->{'path_to_namespace'};
}

# $path = $cache->path_to_key($key);
# $path = $cache->path_to_key($key, \$dir);
#
# Take an human readable key, and return file path.
# Puts dirname of file path in second argument, if it is provided.
sub path_to_key {
	my ($self, $key, $dir_ref) = @_;

	my @paths = ( $self->path_to_namespace() );

	# Create a unique (hashed) key from human readable key
	my $filename = md5_hex($key); # or $digester->add($key)->hexdigest();

	# Split filename so that it have DEPTH subdirectories,
	# where each subdirectory has a two-letter name
	push @paths, unpack("(a2)[$self->{'depth'}] a*", $filename);
	$filename = pop @paths;

	# Join paths together, computing dir separately if $dir_ref was passed.
	my $filepath;
	if (defined $dir_ref && ref($dir_ref)) {
		my $dir = join('/', @paths);
		$filepath = "$dir/$filename";
		$$dir_ref = $dir;
	} else {
		$filepath = join('/', @paths, $filename);
	}

	return $filepath;
}

sub read_file {
	my $filename = shift;

	# Fast slurp, adapted from File::Slurp::read, with unnecessary options removed
	# via CHI::Driver::File (from CHI-0.33)
	my $buf = '';
	open my $read_fh, '<', $filename
		or return;
	binmode $read_fh, ':raw';

	my $size_left = -s $read_fh;

	while ($size_left > 0) {
		my $read_cnt = sysread($read_fh, $buf, $size_left, length($buf));
		return unless defined $read_cnt;

		last if $read_cnt == 0;
		$size_left -= $read_cnt;
		#last if $size_left <= 0;
	}

	close $read_fh
		or die "Couldn't close file '$filename' opened for reading: $!";
	return $buf;
}

sub write_fh {
	my ($write_fh, $filename, $data) = @_;

	# Fast spew, adapted from File::Slurp::write, with unnecessary options removed
	# via CHI::Driver::File (from CHI-0.33)
	binmode $write_fh, ':raw';

	my $size_left = length($data);
	my $offset = 0;

	while ($size_left > 0) {
		my $write_cnt = syswrite($write_fh, $data, $size_left, $offset);
		return unless defined $write_cnt;

		$size_left -= $write_cnt;
		$offset += $write_cnt; # == length($data);
	}

	close $write_fh
		or die "Couldn't close file '$filename' opened for writing: $!";
}

# ----------------------------------------------------------------------
# "private" utility functions and methods

# take a file path to cache entry, and its directory
# return filehandle and filename of open temporary file,
# like File::Temp::tempfile
sub _tempfile_to_path {
	my ($file, $dir) = @_;

	# tempfile will croak() if there is an error
	return tempfile("${file}_XXXXX",
		#DIR => $dir,
		'UNLINK' => 0, # ensure that we don't unlink on close; file is renamed
		'SUFFIX' => '.tmp');
}


# ----------------------------------------------------------------------
# worker methods

sub fetch {
	my ($self, $key) = @_;

	my $file = $self->path_to_key($key);
	return unless (defined $file && -f $file);

	return read_file($file);
}

sub store {
	my ($self, $key, $data) = @_;

	my $dir;
	my $file = $self->path_to_key($key, \$dir);
	return unless (defined $file && defined $dir);

	# ensure that directory leading to cache file exists
	if (!-d $dir) {
		# mkpath will croak()/die() if there is an error
		mkpath($dir, 0, 0777);
	}

	# generate a temporary file
	my ($temp_fh, $tempname) = _tempfile_to_path($file, $dir);
	chmod 0666, $tempname
		or warn "Couldn't change permissions to 0666 / -rw-rw-rw- for '$tempname': $!";

	write_fh($temp_fh, $tempname, $data);

	rename($tempname, $file)
		or die "Couldn't rename temporary file '$tempname' to '$file': $!";
}

# get size of an element associated with the $key (not the size of whole cache)
sub get_size {
	my ($self, $key) = @_;

	my $path = $self->path_to_key($key)
		or return undef;
	if (-f $path) {
		return -s $path;
	}
	return 0;
}


# ......................................................................
# interface methods

# Removing and expiring

# $cache->remove($key)
#
# Remove the data associated with the $key from the cache.
sub remove {
	my ($self, $key) = @_;

	my $file = $self->path_to_key($key)
		or return;
	return unless -f $file;
	unlink($file)
		or die "Couldn't remove file '$file': $!";
}

# $cache->is_valid($key)
#
# Returns a boolean indicating whether $key exists in the cache
# and has not expired (global per-cache 'expires_in').
sub is_valid {
	my ($self, $key) = @_;

	my $path = $self->path_to_key($key);

	# does file exists in cache?
	return 0 unless -f $path;
	# get its modification time
	my $mtime = (stat(_))[9] # _ to reuse stat structure used in -f test
		or die "Couldn't stat file '$path': $!";

	# expire time can be set to never
	my $expires_in = $self->get_expires_in();
	return 1 unless (defined $expires_in && $expires_in >= 0);

	# is file expired?
	my $now = time();

	return (($now - $mtime) < $expires_in);
}

# Getting and setting

# $cache->set($key, $data);
#
# Associates $data with $key in the cache, overwriting any existing entry.
# Returns $data.
sub set {
	my ($self, $key, $data) = @_;

	return unless (defined $key && defined $data);

	$self->store($key, $data);

	return $data;
}

# $data = $cache->get($key);
#
# Returns the data associated with $key.  If $key does not exist
# or has expired, returns undef.
sub get {
	my ($self, $key) = @_;

	return unless $self->is_valid($key);

	return $self->fetch($key);;
}

# $data = $cache->compute($key, $code);
#
# Combines the get and set operations in a single call.  Attempts to
# get $key; if successful, returns the value.  Otherwise, calls $code
# and uses the return value as the new value for $key, which is then
# returned.
sub compute {
	my ($self, $key, $code) = @_;

	my $data = $self->get($key);
	if (!defined $data) {
		$data = $code->();
		$self->set($key, $data);
	}

	return $data;
}

1;
__END__
# end of package GitwebCache::SimpleFileCache;
