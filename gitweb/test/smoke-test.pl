#!/usr/bin/perl -w

use strict;

use File::Path;

(my $usage = <<END) =~ s/^[^\S\n]*//gm;
    This script spiders a gitweb site using wget and checks for
    4xx/5xx errors (which happen if invalid links are generated) or
    for "software error" pages (which happen if gitweb dies).

    Usage: smoke-test.pl base_url

    base_url is something like "http://localhost/path/gitweb.cgi",
    where gitweb.pl hosts only *one* *small* test repository (one commit)
    or this will take a very long time to run.

    Warning: This script is a hack in general and assumes an English
    locale (e.g. LANG=en_US) to parse wget\'s output in particular!
END


if (@ARGV != 1 or $ARGV[0] =~ /^-/) {
    print STDERR $usage;
    exit 2;
}

my $base_url = $ARGV[0];
# $output_dir is a temporary directory for wget to store its output
# files.
my $output_dir = "smoke-test.$$.tmp";
my $log_file = "smoke-test.$$.log";
# The option -o- does not work with wget 1.11.2, hence 2>&1.  Don't
# try to use --accept to spider only one test repository and ignore
# others, since it doesn't quite work as advertised (it still spiders,
# but deletes the files afterwards -- pretty useless for us).  Note
# that the "--- Error ---" line needs to match the / error /i regex.
my $command = "(wget --recursive --level=inf --no-verbose \\
    --directory-prefix=$output_dir --no-directories \\
    \"$base_url\" \\
    || echo \"--- Error ---\") &> $log_file";
print "$command\n";
system $command;

# Check for errors:
my $error_message = undef;
# Check for errors in the output files first, since they tend to tell
# us more than 4xx/5xx.
foreach my $output_file (glob "$output_dir/*") {
    open OUTPUT, $output_file or die "Cannot open $output_file: $!";
    my $output = join '', <OUTPUT>;
    if ($output =~ /<h1>Software error/i) {
        $output =~ /<pre>(.*)<\/pre>/ or die "Invalid error format in $output.\n";
        $error_message = "An error occurred (in $output_file):\n$1";
        last;
    }
}
# Check wget's log file for 4xx/5xx errors.
if (not $error_message) {
    open LOG, $log_file or die "Cannot open $log_file: $!";
    my $log = join '', <LOG>;
    $log =~ s/(robots.txt:\s*).* ERROR .*/$1/i;
    if ($log =~ /((.*\n)?.* ERROR .*)/i) {
        $error_message = "An error was detected (in $log_file):\n$1";
    }
}

print "\n";
if ($error_message) {
    print "$error_message\n";
    exit 1
} else {
    print "Everything OK, no error detected.\n";
    print "Log file at $log_file\n";
    # Don't delete $log_file and $output_dir, since we may need to
    # verify if things have been downloaded at all and we may need to
    # diff different trees.  This might become a command-line option.
    #rmtree $output_dir;
    #unlink $log_file;
}
