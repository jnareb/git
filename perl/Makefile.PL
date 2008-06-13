use ExtUtils::MakeMaker;

sub MY::postamble {
	return <<'MAKE_FRAG';
instlibdir:
	@echo '$(INSTALLSITELIB)'

MAKE_FRAG
}

# Note that when changing %pm, you'll have to remove pm_to_blib rather
# than the blib directory to .force the .pm files to be re-installed
# to blib/lib.
my %pm = ('Git.pm' => '$(INST_LIBDIR)/Git.pm',
	  'Git/Repo.pm' => '$(INST_LIBDIR)/Git/Repo.pm',
	  'Git/Commit.pm' => '$(INST_LIBDIR)/Git/Commit.pm',
	  'Git/Tag.pm' => '$(INST_LIBDIR)/Git/Tag.pm',
	  'Git/Object.pm' => '$(INST_LIBDIR)/Git/Object.pm');

# We come with our own bundled Error.pm. It's not in the set of default
# Perl modules so install it if it's not available on the system yet.
eval { require Error };
if ($@ || $Error::VERSION < 0.15009) {
	$pm{'private-Error.pm'} = '$(INST_LIBDIR)/Error.pm';
}

# redirect stdout, otherwise the message "Writing perl.mak for Git"
# disrupts the output for the target 'instlibdir'
open STDOUT, ">&STDERR";

WriteMakefile(
	NAME            => 'Git',
	VERSION_FROM    => 'Git.pm',
	PM		=> \%pm,
	MAKEFILE	=> 'perl.mak',
	INSTALLSITEMAN3DIR => '$(SITEPREFIX)/share/man/man3'
);
