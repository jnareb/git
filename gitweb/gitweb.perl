#!/usr/bin/perl

# gitweb - simple web interface to track changes in git repositories
#
# (C) 2005-2006, Kay Sievers <kay.sievers@vrfy.org>
# (C) 2005, Christian Gierke
#
# This program is licensed under the GPLv2

use strict;
use warnings;
use CGI qw(:standard :escapeHTML -nosticky);
use CGI::Util qw(unescape);
use CGI::Carp qw(fatalsToBrowser);
use Encode;
use Fcntl ':mode';
use File::Find qw();
use File::Basename qw(basename);
binmode STDOUT, ':utf8';

our $cgi = new CGI;
our $version = "++GIT_VERSION++";
our $my_url = $cgi->url();
our $my_uri = $cgi->url(-absolute => 1);

# core git executable to use
# this can just be "git" if your webserver has a sensible PATH
our $GIT = "++GIT_BINDIR++/git";

# absolute fs-path which will be prepended to the project path
#our $projectroot = "/pub/scm";
our $projectroot = "++GITWEB_PROJECTROOT++";

# target of the home link on top of all pages
our $home_link = $my_uri || "/";

# string of the home link on top of all pages
our $home_link_str = "++GITWEB_HOME_LINK_STR++";

# name of your site or organization to appear in page titles
# replace this with something more descriptive for clearer bookmarks
our $site_name = "++GITWEB_SITENAME++"
                 || ($ENV{'SERVER_NAME'} || "Untitled") . " Git";

# filename of html text to include at top of each page
our $site_header = "++GITWEB_SITE_HEADER++";
# html text to include at home page
our $home_text = "++GITWEB_HOMETEXT++";
# filename of html text to include at bottom of each page
our $site_footer = "++GITWEB_SITE_FOOTER++";

# URI of stylesheets
our @stylesheets = ("++GITWEB_CSS++");
# URI of a single stylesheet, which can be overridden in GITWEB_CONFIG.
our $stylesheet = undef;
# URI of GIT logo (72x27 size)
our $logo = "++GITWEB_LOGO++";
# URI of GIT favicon, assumed to be image/png type
our $favicon = "++GITWEB_FAVICON++";

# URI and label (title) of GIT logo link
#our $logo_url = "http://www.kernel.org/pub/software/scm/git/docs/";
#our $logo_label = "git documentation";
our $logo_url = "http://git.or.cz/";
our $logo_label = "git homepage";

# source of projects list
our $projects_list = "++GITWEB_LIST++";

# show repository only if this file exists
# (only effective if this variable evaluates to true)
our $export_ok = "++GITWEB_EXPORT_OK++";

# only allow viewing of repositories also shown on the overview page
our $strict_export = "++GITWEB_STRICT_EXPORT++";

# list of git base URLs used for URL to where fetch project from,
# i.e. full URL is "$git_base_url/$project"
our @git_base_url_list = grep { $_ ne '' } ("++GITWEB_BASE_URL++");

# default blob_plain mimetype and default charset for text/plain blob
our $default_blob_plain_mimetype = 'text/plain';
our $default_text_plain_charset  = undef;

# file to use for guessing MIME types before trying /etc/mime.types
# (relative to the current git repository)
our $mimetypes_file = undef;

# You define site-wide feature defaults here; override them with
# $GITWEB_CONFIG as necessary.
our %feature = (
	# feature => {
	# 	'sub' => feature-sub (subroutine),
	# 	'override' => allow-override (boolean),
	# 	'default' => [ default options...] (array reference)}
	#
	# if feature is overridable (it means that allow-override has true value,
	# then feature-sub will be called with default options as parameters;
	# return value of feature-sub indicates if to enable specified feature
	#
	# use gitweb_check_feature(<feature>) to check if <feature> is enabled

	# Enable the 'blame' blob view, showing the last commit that modified
	# each line in the file. This can be very CPU-intensive.

	# To enable system wide have in $GITWEB_CONFIG
	# $feature{'blame'}{'default'} = [1];
	# To have project specific config enable override in $GITWEB_CONFIG
	# $feature{'blame'}{'override'} = 1;
	# and in project config gitweb.blame = 0|1;
	'blame' => {
		'sub' => \&feature_blame,
		'override' => 0,
		'default' => [0]},

	# Enable the 'snapshot' link, providing a compressed tarball of any
	# tree. This can potentially generate high traffic if you have large
	# project.

	# To disable system wide have in $GITWEB_CONFIG
	# $feature{'snapshot'}{'default'} = [undef];
	# To have project specific config enable override in $GITWEB_CONFIG
	# $feature{'blame'}{'override'} = 1;
	# and in project config gitweb.snapshot = none|gzip|bzip2;
	'snapshot' => {
		'sub' => \&feature_snapshot,
		'override' => 0,
		#         => [content-encoding, suffix, program]
		'default' => ['x-gzip', 'gz', 'gzip']},

	# Enable the pickaxe search, which will list the commits that modified
	# a given string in a file. This can be practical and quite faster
	# alternative to 'blame', but still potentially CPU-intensive.

	# To enable system wide have in $GITWEB_CONFIG
	# $feature{'pickaxe'}{'default'} = [1];
	# To have project specific config enable override in $GITWEB_CONFIG
	# $feature{'pickaxe'}{'override'} = 1;
	# and in project config gitweb.pickaxe = 0|1;
	'pickaxe' => {
		'sub' => \&feature_pickaxe,
		'override' => 0,
		'default' => [1]},

	# Make gitweb use an alternative format of the URLs which can be
	# more readable and natural-looking: project name is embedded
	# directly in the path and the query string contains other
	# auxiliary information. All gitweb installations recognize
	# URL in either format; this configures in which formats gitweb
	# generates links.

	# To enable system wide have in $GITWEB_CONFIG
	# $feature{'pathinfo'}{'default'} = [1];
	# Project specific override is not supported.

	# Note that you will need to change the default location of CSS,
	# favicon, logo and possibly other files to an absolute URL. Also,
	# if gitweb.cgi serves as your indexfile, you will need to force
	# $my_uri to contain the script name in your $GITWEB_CONFIG.
	'pathinfo' => {
		'override' => 0,
		'default' => [0]},
);

sub gitweb_check_feature {
	my ($name) = @_;
	return unless exists $feature{$name};
	my ($sub, $override, @defaults) = (
		$feature{$name}{'sub'},
		$feature{$name}{'override'},
		@{$feature{$name}{'default'}});
	if (!$override) { return @defaults; }
	if (!defined $sub) {
		warn "feature $name is not overrideable";
		return @defaults;
	}
	return $sub->(@defaults);
}

sub feature_blame {
	my ($val) = git_get_project_config('blame', '--bool');

	if ($val eq 'true') {
		return 1;
	} elsif ($val eq 'false') {
		return 0;
	}

	return $_[0];
}

sub feature_snapshot {
	my ($ctype, $suffix, $command) = @_;

	my ($val) = git_get_project_config('snapshot');

	if ($val eq 'gzip') {
		return ('x-gzip', 'gz', 'gzip');
	} elsif ($val eq 'bzip2') {
		return ('x-bzip2', 'bz2', 'bzip2');
	} elsif ($val eq 'none') {
		return ();
	}

	return ($ctype, $suffix, $command);
}

sub gitweb_have_snapshot {
	my ($ctype, $suffix, $command) = gitweb_check_feature('snapshot');
	my $have_snapshot = (defined $ctype && defined $suffix);

	return $have_snapshot;
}

sub feature_pickaxe {
	my ($val) = git_get_project_config('pickaxe', '--bool');

	if ($val eq 'true') {
		return (1);
	} elsif ($val eq 'false') {
		return (0);
	}

	return ($_[0]);
}

# checking HEAD file with -e is fragile if the repository was
# initialized long time ago (i.e. symlink HEAD) and was pack-ref'ed
# and then pruned.
sub check_head_link {
	my ($dir) = @_;
	my $headfile = "$dir/HEAD";
	return ((-e $headfile) ||
		(-l $headfile && readlink($headfile) =~ /^refs\/heads\//));
}

sub check_export_ok {
	my ($dir) = @_;
	return (check_head_link($dir) &&
		(!$export_ok || -e "$dir/$export_ok"));
}

# rename detection options for git-diff and git-diff-tree
# - default is '-M', with the cost proportional to
#   (number of removed files) * (number of new files).
# - more costly is '-C' (or '-C', '-M'), with the cost proportional to
#   (number of changed files + number of removed files) * (number of new files)
# - even more costly is '-C', '--find-copies-harder' with cost
#   (number of files in the original tree) * (number of new files)
# - one might want to include '-B' option, e.g. '-B', '-M'
our @diff_opts = ('-M'); # taken from git_commit

our $GITWEB_CONFIG = $ENV{'GITWEB_CONFIG'} || "++GITWEB_CONFIG++";
do $GITWEB_CONFIG if -e $GITWEB_CONFIG;

# version of the core git binary
our $git_version = qx($GIT --version) =~ m/git version (.*)$/ ? $1 : "unknown";

$projects_list ||= $projectroot;

# ======================================================================
# input validation and dispatch
our $action = $cgi->param('a');
if (defined $action) {
	if ($action =~ m/[^0-9a-zA-Z\.\-_]/) {
		die_error(undef, "Invalid action parameter");
	}
}

# parameters which are pathnames
our $project = $cgi->param('p');
if (defined $project) {
	if (!validate_pathname($project) ||
	    !(-d "$projectroot/$project") ||
	    !check_head_link("$projectroot/$project") ||
	    ($export_ok && !(-e "$projectroot/$project/$export_ok")) ||
	    ($strict_export && !project_in_list($project))) {
		undef $project;
		die_error(undef, "No such project");
	}
}

our $file_name = $cgi->param('f');
if (defined $file_name) {
	if (!validate_pathname($file_name)) {
		die_error(undef, "Invalid file parameter");
	}
}

our $file_parent = $cgi->param('fp');
if (defined $file_parent) {
	if (!validate_pathname($file_parent)) {
		die_error(undef, "Invalid file parent parameter");
	}
}

# parameters which are refnames
our $hash = $cgi->param('h');
if (defined $hash) {
	if (!validate_refname($hash)) {
		die_error(undef, "Invalid hash parameter");
	}
}

our $hash_parent = $cgi->param('hp');
if (defined $hash_parent) {
	if (!validate_refname($hash_parent)) {
		die_error(undef, "Invalid hash parent parameter");
	}
}

our $hash_base = $cgi->param('hb');
if (defined $hash_base) {
	if (!validate_refname($hash_base)) {
		die_error(undef, "Invalid hash base parameter");
	}
}

our $hash_parent_base = $cgi->param('hpb');
if (defined $hash_parent_base) {
	if (!validate_refname($hash_parent_base)) {
		die_error(undef, "Invalid hash parent base parameter");
	}
}

# other parameters
our $page = $cgi->param('pg');
if (defined $page) {
	if ($page =~ m/[^0-9]/) {
		die_error(undef, "Invalid page parameter");
	}
}

our $searchtext = $cgi->param('s');
if (defined $searchtext) {
	if ($searchtext =~ m/[^a-zA-Z0-9_\.\/\-\+\:\@ ]/) {
		die_error(undef, "Invalid search parameter");
	}
	$searchtext = quotemeta $searchtext;
}

our $searchtype = $cgi->param('st');
if (defined $searchtype) {
	if ($searchtype =~ m/[^a-z]/) {
		die_error(undef, "Invalid searchtype parameter");
	}
}

# now read PATH_INFO and use it as alternative to parameters
sub evaluate_path_info {
	return if defined $project;
	my $path_info = $ENV{"PATH_INFO"};
	return if !$path_info;
	$path_info =~ s,^/+,,;
	return if !$path_info;
	# find which part of PATH_INFO is project
	$project = $path_info;
	$project =~ s,/+$,,;
	while ($project && !check_head_link("$projectroot/$project")) {
		$project =~ s,/*[^/]*$,,;
	}
	# validate project
	$project = validate_pathname($project);
	if (!$project ||
	    ($export_ok && !-e "$projectroot/$project/$export_ok") ||
	    ($strict_export && !project_in_list($project))) {
		undef $project;
		return;
	}
	# do not change any parameters if an action is given using the query string
	return if $action;
	$path_info =~ s,^$project/*,,;
	my ($refname, $pathname) = split(/:/, $path_info, 2);
	if (defined $pathname) {
		# we got "project.git/branch:filename" or "project.git/branch:dir/"
		# we could use git_get_type(branch:pathname), but it needs $git_dir
		$pathname =~ s,^/+,,;
		if (!$pathname || substr($pathname, -1) eq "/") {
			$action  ||= "tree";
			$pathname =~ s,/$,,;
		} else {
			$action  ||= "blob_plain";
		}
		$hash_base ||= validate_refname($refname);
		$file_name ||= validate_pathname($pathname);
	} elsif (defined $refname) {
		# we got "project.git/branch"
		$action ||= "shortlog";
		$hash   ||= validate_refname($refname);
	}
}
evaluate_path_info();

# path to the current git repository
our $git_dir;
$git_dir = "$projectroot/$project" if $project;

# dispatch
my %actions = (
	"blame" => \&git_blame2,
	"blobdiff" => \&git_blobdiff,
	"blobdiff_plain" => \&git_blobdiff_plain,
	"blob" => \&git_blob,
	"blob_plain" => \&git_blob_plain,
	"commitdiff" => \&git_commitdiff,
	"commitdiff_plain" => \&git_commitdiff_plain,
	"commit" => \&git_commit,
	"heads" => \&git_heads,
	"history" => \&git_history,
	"log" => \&git_log,
	"rss" => \&git_rss,
	"search" => \&git_search,
	"search_help" => \&git_search_help,
	"shortlog" => \&git_shortlog,
	"summary" => \&git_summary,
	"tag" => \&git_tag,
	"tags" => \&git_tags,
	"tree" => \&git_tree,
	"snapshot" => \&git_snapshot,
	# those below don't need $project
	"opml" => \&git_opml,
	"project_list" => \&git_project_list,
	"project_index" => \&git_project_index,
);

if (defined $project) {
	$action ||= 'summary';
} else {
	$action ||= 'project_list';
}
if (!defined($actions{$action})) {
	die_error(undef, "Unknown action");
}
if ($action !~ m/^(opml|project_list|project_index)$/ &&
    !$project) {
	die_error(undef, "Project needed");
}
$actions{$action}->();
exit;

## ======================================================================
## action links

sub href(%) {
	my %params = @_;
	my $href = $my_uri;

	# XXX: Warning: If you touch this, check the search form for updating,
	# too.

	my @mapping = (
		project => "p",
		action => "a",
		file_name => "f",
		file_parent => "fp",
		hash => "h",
		hash_parent => "hp",
		hash_base => "hb",
		hash_parent_base => "hpb",
		page => "pg",
		order => "o",
		searchtext => "s",
		searchtype => "st",
	);
	my %mapping = @mapping;

	$params{'project'} = $project unless exists $params{'project'};

	my ($use_pathinfo) = gitweb_check_feature('pathinfo');
	if ($use_pathinfo) {
		# use PATH_INFO for project name
		$href .= "/$params{'project'}" if defined $params{'project'};
		delete $params{'project'};

		# Summary just uses the project path URL
		if (defined $params{'action'} && $params{'action'} eq 'summary') {
			delete $params{'action'};
		}
	}

	# now encode the parameters explicitly
	my @result = ();
	for (my $i = 0; $i < @mapping; $i += 2) {
		my ($name, $symbol) = ($mapping[$i], $mapping[$i+1]);
		if (defined $params{$name}) {
			push @result, $symbol . "=" . esc_param($params{$name});
		}
	}
	$href .= "?" . join(';', @result) if scalar @result;

	return $href;
}


## ======================================================================
## validation, quoting/unquoting and escaping

sub validate_pathname {
	my $input = shift || return undef;

	# no '.' or '..' as elements of path, i.e. no '.' nor '..'
	# at the beginning, at the end, and between slashes.
	# also this catches doubled slashes
	if ($input =~ m!(^|/)(|\.|\.\.)(/|$)!) {
		return undef;
	}
	# no null characters
	if ($input =~ m!\0!) {
		return undef;
	}
	return $input;
}

sub validate_refname {
	my $input = shift || return undef;

	# textual hashes are O.K.
	if ($input =~ m/^[0-9a-fA-F]{40}$/) {
		return $input;
	}
	# it must be correct pathname
	$input = validate_pathname($input)
		or return undef;
	# restrictions on ref name according to git-check-ref-format
	if ($input =~ m!(/\.|\.\.|[\000-\040\177 ~^:?*\[]|/$)!) {
		return undef;
	}
	return $input;
}

# very thin wrapper for decode("utf8", $str, Encode::FB_DEFAULT);
sub to_utf8 {
	my $str = shift;
	return decode("utf8", $str, Encode::FB_DEFAULT);
}

# quote unsafe chars, but keep the slash, even when it's not
# correct, but quoted slashes look too horrible in bookmarks
sub esc_param {
	my $str = shift;
	$str =~ s/([^A-Za-z0-9\-_.~()\/:@])/sprintf("%%%02X", ord($1))/eg;
	$str =~ s/\+/%2B/g;
	$str =~ s/ /\+/g;
	return $str;
}

# quote unsafe chars in whole URL, so some charactrs cannot be quoted
sub esc_url {
	my $str = shift;
	$str =~ s/([^A-Za-z0-9\-_.~();\/;?:@&=])/sprintf("%%%02X", ord($1))/eg;
	$str =~ s/\+/%2B/g;
	$str =~ s/ /\+/g;
	return $str;
}

# replace invalid utf8 character with SUBSTITUTION sequence
sub esc_html {
	my $str = shift;
	$str = to_utf8($str);
	$str = escapeHTML($str);
	$str =~ s/\014/^L/g; # escape FORM FEED (FF) character (e.g. in COPYING file)
	$str =~ s/\033/^[/g; # "escape" ESCAPE (\e) character (e.g. commit 20a3847d8a5032ce41f90dcc68abfb36e6fee9b1)
	return $str;
}

# quote unsafe characters and escape filename to HTML
sub esc_path {
	my $str = shift;
	$str = esc_html($str);
	$str =~ s/[[:cntrl:]\a\b\e\f\n\r\t\011]/&iquest;/g; # like --hide-control-chars in ls
	return $str;
}

# git may return quoted and escaped filenames
sub unquote {
	my $str = shift;

	sub unq {
		my $seq = shift;
		my %es = (
			't' => "\t", # tab            (HT, TAB)
			'n' => "\n", # newline        (NL)
			'r' => "\r", # return         (CR)
			'f' => "\f", # form feed      (FF)
			'b' => "\b", # backspace      (BS)
			'a' => "\a", # alarm (bell)   (BEL)
			#'e' => "\e", # escape        (ESC)
			'v' => "\011", # vertical tab (VT)
		);

		# octal char sequence
		return chr(oct($seq))  if ($seq =~ m/^[0-7]{1,3}$/);
		# C escape sequence (this includes '\n' (LF) and '\t' (TAB))
		return $es{$seq}       if ($seq =~ m/^[abefnrtv]$/);
		# quted ordinary character (this includes '\\' and '\"')
		return $seq;
	}

	if ($str =~ m/^"(.*)"$/) {
		$str = $1;
		$str =~ s/\\([^0-7]|[0-7]{1,3})/unq($1)/eg;
	}
	return $str;
}

# escape tabs (convert tabs to spaces)
sub untabify {
	my $line = shift;

	while ((my $pos = index($line, "\t")) != -1) {
		if (my $count = (8 - ($pos % 8))) {
			my $spaces = ' ' x $count;
			$line =~ s/\t/$spaces/;
		}
	}

	return $line;
}

sub project_in_list {
	my $project = shift;
	my @list = git_get_projects_list();
	return @list && scalar(grep { $_->{'path'} eq $project } @list);
}

## ----------------------------------------------------------------------
## HTML aware string manipulation

sub chop_str {
	my $str = shift;
	my $len = shift;
	my $add_len = shift || 10;

	# allow only $len chars, but don't cut a word if it would fit in $add_len
	# if it doesn't fit, cut it if it's still longer than the dots we would add
	$str =~ m/^(.{0,$len}[^ \/\-_:\.@]{0,$add_len})(.*)/;
	my $body = $1;
	my $tail = $2;
	if (length($tail) > 4) {
		$tail = " ...";
		$body =~ s/&[^;]*$//; # remove chopped character entities
	}
	return "$body$tail";
}

## ----------------------------------------------------------------------
## functions returning short strings

# CSS class for given age value (in seconds)
sub age_class {
	my $age = shift;

	if ($age < 60*60*2) {
		return "age0";
	} elsif ($age < 60*60*24*2) {
		return "age1";
	} else {
		return "age2";
	}
}

# convert age in seconds to "nn units ago" string
sub age_string {
	my $age = shift;
	my $age_str;

	if ($age > 60*60*24*365*2) {
		$age_str = (int $age/60/60/24/365);
		$age_str .= " years ago";
	} elsif ($age > 60*60*24*(365/12)*2) {
		$age_str = int $age/60/60/24/(365/12);
		$age_str .= " months ago";
	} elsif ($age > 60*60*24*7*2) {
		$age_str = int $age/60/60/24/7;
		$age_str .= " weeks ago";
	} elsif ($age > 60*60*24*2) {
		$age_str = int $age/60/60/24;
		$age_str .= " days ago";
	} elsif ($age > 60*60*2) {
		$age_str = int $age/60/60;
		$age_str .= " hours ago";
	} elsif ($age > 60*2) {
		$age_str = int $age/60;
		$age_str .= " min ago";
	} elsif ($age > 2) {
		$age_str = int $age;
		$age_str .= " sec ago";
	} else {
		$age_str .= " right now";
	}
	return $age_str;
}

# convert file mode in octal to symbolic file mode string
sub mode_str {
	my $mode = oct shift;

	if (S_ISDIR($mode & S_IFMT)) {
		return 'drwxr-xr-x';
	} elsif (S_ISLNK($mode)) {
		return 'lrwxrwxrwx';
	} elsif (S_ISREG($mode)) {
		# git cares only about the executable bit
		if ($mode & S_IXUSR) {
			return '-rwxr-xr-x';
		} else {
			return '-rw-r--r--';
		};
	} else {
		return '----------';
	}
}

# convert file mode in octal to file type string
sub file_type {
	my $mode = shift;

	if ($mode !~ m/^[0-7]+$/) {
		return $mode;
	} else {
		$mode = oct $mode;
	}

	if (S_ISDIR($mode & S_IFMT)) {
		return "directory";
	} elsif (S_ISLNK($mode)) {
		return "symlink";
	} elsif (S_ISREG($mode)) {
		return "file";
	} else {
		return "unknown";
	}
}

## ----------------------------------------------------------------------
## functions returning short HTML fragments, or transforming HTML fragments
## which don't beling to other sections

# format line of commit message or tag comment
sub format_log_line_html {
	my $line = shift;

	$line = esc_html($line);
	$line =~ s/ /&nbsp;/g;
	if ($line =~ m/([0-9a-fA-F]{40})/) {
		my $hash_text = $1;
		if (git_get_type($hash_text) eq "commit") {
			my $link =
				$cgi->a({-href => href(action=>"commit", hash=>$hash_text),
				        -class => "text"}, $hash_text);
			$line =~ s/$hash_text/$link/;
		}
	}
	return $line;
}

# format marker of refs pointing to given object
sub format_ref_marker {
	my ($refs, $id) = @_;
	my $markers = '';

	if (defined $refs->{$id}) {
		foreach my $ref (@{$refs->{$id}}) {
			my ($type, $name) = qw();
			# e.g. tags/v2.6.11 or heads/next
			if ($ref =~ m!^(.*?)s?/(.*)$!) {
				$type = $1;
				$name = $2;
			} else {
				$type = "ref";
				$name = $ref;
			}

			$markers .= " <span class=\"$type\">" . esc_html($name) . "</span>";
		}
	}

	if ($markers) {
		return ' <span class="refs">'. $markers . '</span>';
	} else {
		return "";
	}
}

# format, perhaps shortened and with markers, title line
sub format_subject_html {
	my ($long, $short, $href, $extra) = @_;
	$extra = '' unless defined($extra);

	if (length($short) < length($long)) {
		return $cgi->a({-href => $href, -class => "list subject",
		                -title => to_utf8($long)},
		       esc_html($short) . $extra);
	} else {
		return $cgi->a({-href => $href, -class => "list subject"},
		       esc_html($long)  . $extra);
	}
}

sub format_diff_line {
	my $line = shift;
	my $char = substr($line, 0, 1);
	my $diff_class = "";

	chomp $line;

	if ($char eq '+') {
		$diff_class = " add";
	} elsif ($char eq "-") {
		$diff_class = " rem";
	} elsif ($char eq "@") {
		$diff_class = " chunk_header";
	} elsif ($char eq "\\") {
		$diff_class = " incomplete";
	}
	$line = untabify($line);
	return "<div class=\"diff$diff_class\">" . esc_html($line) . "</div>\n";
}

## ----------------------------------------------------------------------
## git utility subroutines, invoking git commands

# returns path to the core git executable and the --git-dir parameter as list
sub git_cmd {
	return $GIT, '--git-dir='.$git_dir;
}

# returns path to the core git executable and the --git-dir parameter as string
sub git_cmd_str {
	return join(' ', git_cmd());
}

# get HEAD ref of given project as hash
sub git_get_head_hash {
	my $project = shift;
	my $o_git_dir = $git_dir;
	my $retval = undef;
	$git_dir = "$projectroot/$project";
	if (open my $fd, "-|", git_cmd(), "rev-parse", "--verify", "HEAD") {
		my $head = <$fd>;
		close $fd;
		if (defined $head && $head =~ /^([0-9a-fA-F]{40})$/) {
			$retval = $1;
		}
	}
	if (defined $o_git_dir) {
		$git_dir = $o_git_dir;
	}
	return $retval;
}

# get type of given object
sub git_get_type {
	my $hash = shift;

	open my $fd, "-|", git_cmd(), "cat-file", '-t', $hash or return;
	my $type = <$fd>;
	close $fd or return;
	chomp $type;
	return $type;
}

sub git_get_project_config {
	my ($key, $type) = @_;

	return unless ($key);
	$key =~ s/^gitweb\.//;
	return if ($key =~ m/\W/);

	my @x = (git_cmd(), 'repo-config');
	if (defined $type) { push @x, $type; }
	push @x, "--get";
	push @x, "gitweb.$key";
	my $val = qx(@x);
	chomp $val;
	return ($val);
}

# get hash of given path at given ref
sub git_get_hash_by_path {
	my $base = shift;
	my $path = shift || return undef;
	my $type = shift;

	$path =~ s,/+$,,;

	open my $fd, "-|", git_cmd(), "ls-tree", $base, "--", $path
		or die_error(undef, "Open git-ls-tree failed");
	my $line = <$fd>;
	close $fd or return undef;

	#'100644 blob 0fa3f3a66fb6a137f6ec2c19351ed4d807070ffa	panic.c'
	$line =~ m/^([0-9]+) (.+) ([0-9a-fA-F]{40})\t(.+)$/;
	if (defined $type && $type ne $2) {
		# type doesn't match
		return undef;
	}
	return $3;
}

## ......................................................................
## git utility functions, directly accessing git repository

sub git_get_project_description {
	my $path = shift;

	open my $fd, "$projectroot/$path/description" or return undef;
	my $descr = <$fd>;
	close $fd;
	chomp $descr;
	return $descr;
}

sub git_get_project_url_list {
	my $path = shift;

	open my $fd, "$projectroot/$path/cloneurl" or return;
	my @git_project_url_list = map { chomp; $_ } <$fd>;
	close $fd;

	return wantarray ? @git_project_url_list : \@git_project_url_list;
}

sub git_get_projects_list {
	my @list;

	if (-d $projects_list) {
		# search in directory
		my $dir = $projects_list;
		my $pfxlen = length("$dir");

		File::Find::find({
			follow_fast => 1, # follow symbolic links
			dangling_symlinks => 0, # ignore dangling symlinks, silently
			wanted => sub {
				# skip project-list toplevel, if we get it.
				return if (m!^[/.]$!);
				# only directories can be git repositories
				return unless (-d $_);

				my $subdir = substr($File::Find::name, $pfxlen + 1);
				# we check related file in $projectroot
				if (check_export_ok("$projectroot/$subdir")) {
					push @list, { path => $subdir };
					$File::Find::prune = 1;
				}
			},
		}, "$dir");

	} elsif (-f $projects_list) {
		# read from file(url-encoded):
		# 'git%2Fgit.git Linus+Torvalds'
		# 'libs%2Fklibc%2Fklibc.git H.+Peter+Anvin'
		# 'linux%2Fhotplug%2Fudev.git Greg+Kroah-Hartman'
		open my ($fd), $projects_list or return;
		while (my $line = <$fd>) {
			chomp $line;
			my ($path, $owner) = split ' ', $line;
			$path = unescape($path);
			$owner = unescape($owner);
			if (!defined $path) {
				next;
			}
			if (check_export_ok("$projectroot/$path")) {
				my $pr = {
					path => $path,
					owner => to_utf8($owner),
				};
				push @list, $pr
			}
		}
		close $fd;
	}
	@list = sort {$a->{'path'} cmp $b->{'path'}} @list;
	return @list;
}

sub git_get_project_owner {
	my $project = shift;
	my $owner;

	return undef unless $project;

	# read from file (url-encoded):
	# 'git%2Fgit.git Linus+Torvalds'
	# 'libs%2Fklibc%2Fklibc.git H.+Peter+Anvin'
	# 'linux%2Fhotplug%2Fudev.git Greg+Kroah-Hartman'
	if (-f $projects_list) {
		open (my $fd , $projects_list);
		while (my $line = <$fd>) {
			chomp $line;
			my ($pr, $ow) = split ' ', $line;
			$pr = unescape($pr);
			$ow = unescape($ow);
			if ($pr eq $project) {
				$owner = to_utf8($ow);
				last;
			}
		}
		close $fd;
	}
	if (!defined $owner) {
		$owner = get_file_owner("$projectroot/$project");
	}

	return $owner;
}

sub git_get_last_activity {
	my ($path) = @_;
	my $fd;

	$git_dir = "$projectroot/$path";
	open($fd, "-|", git_cmd(), 'for-each-ref',
	     '--format=%(refname) %(committer)',
	     '--sort=-committerdate',
	     'refs/heads') or return;
	my $most_recent = <$fd>;
	close $fd or return;
	if ($most_recent =~ / (\d+) [-+][01]\d\d\d$/) {
		my $timestamp = $1;
		my $age = time - $timestamp;
		return ($age, age_string($age));
	}
}

sub git_get_references {
	my $type = shift || "";
	my %refs;
	# 5dc01c595e6c6ec9ccda4f6f69c131c0dd945f8c	refs/tags/v2.6.11
	# c39ae07f393806ccf406ef966e9a15afc43cc36a	refs/tags/v2.6.11^{}
	open my $fd, "-|", $GIT, "peek-remote", "$projectroot/$project/"
		or return;

	while (my $line = <$fd>) {
		chomp $line;
		if ($line =~ m/^([0-9a-fA-F]{40})\trefs\/($type\/?[^\^]+)/) {
			if (defined $refs{$1}) {
				push @{$refs{$1}}, $2;
			} else {
				$refs{$1} = [ $2 ];
			}
		}
	}
	close $fd or return;
	return \%refs;
}

sub git_get_rev_name_tags {
	my $hash = shift || return undef;

	open my $fd, "-|", git_cmd(), "name-rev", "--tags", $hash
		or return;
	my $name_rev = <$fd>;
	close $fd;

	if ($name_rev =~ m|^$hash tags/(.*)$|) {
		return $1;
	} else {
		# catches also '$hash undefined' output
		return undef;
	}
}

## ----------------------------------------------------------------------
## parse to hash functions

sub parse_date {
	my $epoch = shift;
	my $tz = shift || "-0000";

	my %date;
	my @months = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec");
	my @days = ("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat");
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = gmtime($epoch);
	$date{'hour'} = $hour;
	$date{'minute'} = $min;
	$date{'mday'} = $mday;
	$date{'day'} = $days[$wday];
	$date{'month'} = $months[$mon];
	$date{'rfc2822'} = sprintf "%s, %d %s %4d %02d:%02d:%02d +0000",
	                   $days[$wday], $mday, $months[$mon], 1900+$year, $hour ,$min, $sec;
	$date{'mday-time'} = sprintf "%d %s %02d:%02d",
	                     $mday, $months[$mon], $hour ,$min;

	$tz =~ m/^([+\-][0-9][0-9])([0-9][0-9])$/;
	my $local = $epoch + ((int $1 + ($2/60)) * 3600);
	($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = gmtime($local);
	$date{'hour_local'} = $hour;
	$date{'minute_local'} = $min;
	$date{'tz_local'} = $tz;
	$date{'iso-tz'} = sprintf ("%04d-%02d-%02d %02d:%02d:%02d %s",
				   1900+$year, $mon+1, $mday,
				   $hour, $min, $sec, $tz);
	return %date;
}

sub parse_tag {
	my $tag_id = shift;
	my %tag;
	my @comment;

	open my $fd, "-|", git_cmd(), "cat-file", "tag", $tag_id or return;
	$tag{'id'} = $tag_id;
	while (my $line = <$fd>) {
		chomp $line;
		if ($line =~ m/^object ([0-9a-fA-F]{40})$/) {
			$tag{'object'} = $1;
		} elsif ($line =~ m/^type (.+)$/) {
			$tag{'type'} = $1;
		} elsif ($line =~ m/^tag (.+)$/) {
			$tag{'name'} = $1;
		} elsif ($line =~ m/^tagger (.*) ([0-9]+) (.*)$/) {
			$tag{'author'} = $1;
			$tag{'epoch'} = $2;
			$tag{'tz'} = $3;
		} elsif ($line =~ m/--BEGIN/) {
			push @comment, $line;
			last;
		} elsif ($line eq "") {
			last;
		}
	}
	push @comment, <$fd>;
	$tag{'comment'} = \@comment;
	close $fd or return;
	if (!defined $tag{'name'}) {
		return
	};
	return %tag
}

sub parse_commit {
	my $commit_id = shift;
	my $commit_text = shift;

	my @commit_lines;
	my %co;

	if (defined $commit_text) {
		@commit_lines = @$commit_text;
	} else {
		local $/ = "\0";
		open my $fd, "-|", git_cmd(), "rev-list", "--header", "--parents", "--max-count=1", $commit_id
			or return;
		@commit_lines = split '\n', <$fd>;
		close $fd or return;
		pop @commit_lines;
	}
	my $header = shift @commit_lines;
	if (!($header =~ m/^[0-9a-fA-F]{40}/)) {
		return;
	}
	($co{'id'}, my @parents) = split ' ', $header;
	$co{'parents'} = \@parents;
	$co{'parent'} = $parents[0];
	while (my $line = shift @commit_lines) {
		last if $line eq "\n";
		if ($line =~ m/^tree ([0-9a-fA-F]{40})$/) {
			$co{'tree'} = $1;
		} elsif ($line =~ m/^author (.*) ([0-9]+) (.*)$/) {
			$co{'author'} = $1;
			$co{'author_epoch'} = $2;
			$co{'author_tz'} = $3;
			if ($co{'author'} =~ m/^([^<]+) </) {
				$co{'author_name'} = $1;
			} else {
				$co{'author_name'} = $co{'author'};
			}
		} elsif ($line =~ m/^committer (.*) ([0-9]+) (.*)$/) {
			$co{'committer'} = $1;
			$co{'committer_epoch'} = $2;
			$co{'committer_tz'} = $3;
			$co{'committer_name'} = $co{'committer'};
			$co{'committer_name'} =~ s/ <.*//;
		}
	}
	if (!defined $co{'tree'}) {
		return;
	};

	foreach my $title (@commit_lines) {
		$title =~ s/^    //;
		if ($title ne "") {
			$co{'title'} = chop_str($title, 80, 5);
			# remove leading stuff of merges to make the interesting part visible
			if (length($title) > 50) {
				$title =~ s/^Automatic //;
				$title =~ s/^merge (of|with) /Merge ... /i;
				if (length($title) > 50) {
					$title =~ s/(http|rsync):\/\///;
				}
				if (length($title) > 50) {
					$title =~ s/(master|www|rsync)\.//;
				}
				if (length($title) > 50) {
					$title =~ s/kernel.org:?//;
				}
				if (length($title) > 50) {
					$title =~ s/\/pub\/scm//;
				}
			}
			$co{'title_short'} = chop_str($title, 50, 5);
			last;
		}
	}
	if ($co{'title'} eq "") {
		$co{'title'} = $co{'title_short'} = '(no commit message)';
	}
	# remove added spaces
	foreach my $line (@commit_lines) {
		$line =~ s/^    //;
	}
	$co{'comment'} = \@commit_lines;

	my $age = time - $co{'committer_epoch'};
	$co{'age'} = $age;
	$co{'age_string'} = age_string($age);
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = gmtime($co{'committer_epoch'});
	if ($age > 60*60*24*7*2) {
		$co{'age_string_date'} = sprintf "%4i-%02u-%02i", 1900 + $year, $mon+1, $mday;
		$co{'age_string_age'} = $co{'age_string'};
	} else {
		$co{'age_string_date'} = $co{'age_string'};
		$co{'age_string_age'} = sprintf "%4i-%02u-%02i", 1900 + $year, $mon+1, $mday;
	}
	return %co;
}

# parse ref from ref_file, given by ref_id, with given type
sub parse_ref {
	my $ref_file = shift;
	my $ref_id = shift;
	my $type = shift || git_get_type($ref_id);
	my %ref_item;

	$ref_item{'type'} = $type;
	$ref_item{'id'} = $ref_id;
	$ref_item{'epoch'} = 0;
	$ref_item{'age'} = "unknown";
	if ($type eq "tag") {
		my %tag = parse_tag($ref_id);
		$ref_item{'comment'} = $tag{'comment'};
		if ($tag{'type'} eq "commit") {
			my %co = parse_commit($tag{'object'});
			$ref_item{'epoch'} = $co{'committer_epoch'};
			$ref_item{'age'} = $co{'age_string'};
		} elsif (defined($tag{'epoch'})) {
			my $age = time - $tag{'epoch'};
			$ref_item{'epoch'} = $tag{'epoch'};
			$ref_item{'age'} = age_string($age);
		}
		$ref_item{'reftype'} = $tag{'type'};
		$ref_item{'name'} = $tag{'name'};
		$ref_item{'refid'} = $tag{'object'};
	} elsif ($type eq "commit"){
		my %co = parse_commit($ref_id);
		$ref_item{'reftype'} = "commit";
		$ref_item{'name'} = $ref_file;
		$ref_item{'title'} = $co{'title'};
		$ref_item{'refid'} = $ref_id;
		$ref_item{'epoch'} = $co{'committer_epoch'};
		$ref_item{'age'} = $co{'age_string'};
	} else {
		$ref_item{'reftype'} = $type;
		$ref_item{'name'} = $ref_file;
		$ref_item{'refid'} = $ref_id;
	}

	return %ref_item;
}

# parse line of git-diff-tree "raw" output
sub parse_difftree_raw_line {
	my $line = shift;
	my %res;

	# ':100644 100644 03b218260e99b78c6df0ed378e59ed9205ccc96d 3b93d5e7cc7f7dd4ebed13a5cc1a4ad976fc94d8 M	ls-files.c'
	# ':100644 100644 7f9281985086971d3877aca27704f2aaf9c448ce bc190ebc71bbd923f2b728e505408f5e54bd073a M	rev-tree.c'
	if ($line =~ m/^:([0-7]{6}) ([0-7]{6}) ([0-9a-fA-F]{40}) ([0-9a-fA-F]{40}) (.)([0-9]{0,3})\t(.*)$/) {
		$res{'from_mode'} = $1;
		$res{'to_mode'} = $2;
		$res{'from_id'} = $3;
		$res{'to_id'} = $4;
		$res{'status'} = $5;
		$res{'similarity'} = $6;
		if ($res{'status'} eq 'R' || $res{'status'} eq 'C') { # renamed or copied
			($res{'from_file'}, $res{'to_file'}) = map { unquote($_) } split("\t", $7);
		} else {
			$res{'file'} = unquote($7);
		}
	}
	# 'c512b523472485aef4fff9e57b229d9d243c967f'
	elsif ($line =~ m/^([0-9a-fA-F]{40})$/) {
		$res{'commit'} = $1;
	}

	return wantarray ? %res : \%res;
}

# parse line of git-ls-tree output
sub parse_ls_tree_line ($;%) {
	my $line = shift;
	my %opts = @_;
	my %res;

	#'100644 blob 0fa3f3a66fb6a137f6ec2c19351ed4d807070ffa	panic.c'
	$line =~ m/^([0-9]+) (.+) ([0-9a-fA-F]{40})\t(.+)$/;

	$res{'mode'} = $1;
	$res{'type'} = $2;
	$res{'hash'} = $3;
	if ($opts{'-z'}) {
		$res{'name'} = $4;
	} else {
		$res{'name'} = unquote($4);
	}

	return wantarray ? %res : \%res;
}

## ......................................................................
## parse to array of hashes functions

sub git_get_refs_list {
	my $type = shift || "";
	my %refs;
	my @reflist;

	my @refs;
	open my $fd, "-|", $GIT, "peek-remote", "$projectroot/$project/"
		or return;
	while (my $line = <$fd>) {
		chomp $line;
		if ($line =~ m/^([0-9a-fA-F]{40})\trefs\/($type\/?([^\^]+))(\^\{\})?$/) {
			if (defined $refs{$1}) {
				push @{$refs{$1}}, $2;
			} else {
				$refs{$1} = [ $2 ];
			}

			if (! $4) { # unpeeled, direct reference
				push @refs, { hash => $1, name => $3 }; # without type
			} elsif ($3 eq $refs[-1]{'name'}) {
				# most likely a tag is followed by its peeled
				# (deref) one, and when that happens we know the
				# previous one was of type 'tag'.
				$refs[-1]{'type'} = "tag";
			}
		}
	}
	close $fd;

	foreach my $ref (@refs) {
		my $ref_file = $ref->{'name'};
		my $ref_id   = $ref->{'hash'};

		my $type = $ref->{'type'} || git_get_type($ref_id) || next;
		my %ref_item = parse_ref($ref_file, $ref_id, $type);

		push @reflist, \%ref_item;
	}
	# sort refs by age
	@reflist = sort {$b->{'epoch'} <=> $a->{'epoch'}} @reflist;
	return (\@reflist, \%refs);
}

## ----------------------------------------------------------------------
## filesystem-related functions

sub get_file_owner {
	my $path = shift;

	my ($dev, $ino, $mode, $nlink, $st_uid, $st_gid, $rdev, $size) = stat($path);
	my ($name, $passwd, $uid, $gid, $quota, $comment, $gcos, $dir, $shell) = getpwuid($st_uid);
	if (!defined $gcos) {
		return undef;
	}
	my $owner = $gcos;
	$owner =~ s/[,;].*$//;
	return to_utf8($owner);
}

## ......................................................................
## mimetype related functions

sub mimetype_guess_file {
	my $filename = shift;
	my $mimemap = shift;
	-r $mimemap or return undef;

	my %mimemap;
	open(MIME, $mimemap) or return undef;
	while (<MIME>) {
		next if m/^#/; # skip comments
		my ($mime, $exts) = split(/\t+/);
		if (defined $exts) {
			my @exts = split(/\s+/, $exts);
			foreach my $ext (@exts) {
				$mimemap{$ext} = $mime;
			}
		}
	}
	close(MIME);

	$filename =~ /\.([^.]*)$/;
	return $mimemap{$1};
}

sub mimetype_guess {
	my $filename = shift;
	my $mime;
	$filename =~ /\./ or return undef;

	if ($mimetypes_file) {
		my $file = $mimetypes_file;
		if ($file !~ m!^/!) { # if it is relative path
			# it is relative to project
			$file = "$projectroot/$project/$file";
		}
		$mime = mimetype_guess_file($filename, $file);
	}
	$mime ||= mimetype_guess_file($filename, '/etc/mime.types');
	return $mime;
}

sub blob_mimetype {
	my $fd = shift;
	my $filename = shift;

	if ($filename) {
		my $mime = mimetype_guess($filename);
		$mime and return $mime;
	}

	# just in case
	return $default_blob_plain_mimetype unless $fd;

	if (-T $fd) {
		return 'text/plain' .
		       ($default_text_plain_charset ? '; charset='.$default_text_plain_charset : '');
	} elsif (! $filename) {
		return 'application/octet-stream';
	} elsif ($filename =~ m/\.png$/i) {
		return 'image/png';
	} elsif ($filename =~ m/\.gif$/i) {
		return 'image/gif';
	} elsif ($filename =~ m/\.jpe?g$/i) {
		return 'image/jpeg';
	} else {
		return 'application/octet-stream';
	}
}

## ======================================================================
## functions printing HTML: header, footer, error page

sub git_header_html {
	my $status = shift || "200 OK";
	my $expires = shift;

	my $title = "$site_name";
	if (defined $project) {
		$title .= " - $project";
		if (defined $action) {
			$title .= "/$action";
			if (defined $file_name) {
				$title .= " - " . esc_path($file_name);
				if ($action eq "tree" && $file_name !~ m|/$|) {
					$title .= "/";
				}
			}
		}
	}
	my $content_type;
	# require explicit support from the UA if we are to send the page as
	# 'application/xhtml+xml', otherwise send it as plain old 'text/html'.
	# we have to do this because MSIE sometimes globs '*/*', pretending to
	# support xhtml+xml but choking when it gets what it asked for.
	if (defined $cgi->http('HTTP_ACCEPT') &&
	    $cgi->http('HTTP_ACCEPT') =~ m/(,|;|\s|^)application\/xhtml\+xml(,|;|\s|$)/ &&
	    $cgi->Accept('application/xhtml+xml') != 0) {
		$content_type = 'application/xhtml+xml';
	} else {
		$content_type = 'text/html';
	}
	print $cgi->header(-type=>$content_type, -charset => 'utf-8',
	                   -status=> $status, -expires => $expires);
	print <<EOF;
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en-US" lang="en-US">
<!-- git web interface version $version, (C) 2005-2006, Kay Sievers <kay.sievers\@vrfy.org>, Christian Gierke -->
<!-- git core binaries version $git_version -->
<head>
<meta http-equiv="content-type" content="$content_type; charset=utf-8"/>
<meta name="generator" content="gitweb/$version git/$git_version"/>
<meta name="robots" content="index, nofollow"/>
<title>$title</title>
EOF
# print out each stylesheet that exist
	if (defined $stylesheet) {
#provides backwards capability for those people who define style sheet in a config file
		print '<link rel="stylesheet" type="text/css" href="'.$stylesheet.'"/>'."\n";
	} else {
		foreach my $stylesheet (@stylesheets) {
			next unless $stylesheet;
			print '<link rel="stylesheet" type="text/css" href="'.$stylesheet.'"/>'."\n";
		}
	}
	if (defined $project) {
		printf('<link rel="alternate" title="%s log" '.
		       'href="%s" type="application/rss+xml"/>'."\n",
		       esc_param($project), href(action=>"rss"));
	} else {
		printf('<link rel="alternate" title="%s projects list" '.
		       'href="%s" type="text/plain; charset=utf-8"/>'."\n",
		       $site_name, href(project=>undef, action=>"project_index"));
		printf('<link rel="alternate" title="%s projects logs" '.
		       'href="%s" type="text/x-opml"/>'."\n",
		       $site_name, href(project=>undef, action=>"opml"));
	}
	if (defined $favicon) {
		print qq(<link rel="shortcut icon" href="$favicon" type="image/png"/>\n);
	}

	print "</head>\n" .
	      "<body>\n";

	if (-f $site_header) {
		open (my $fd, $site_header);
		print <$fd>;
		close $fd;
	}

	print "<div class=\"page_header\">\n" .
	      $cgi->a({-href => esc_url($logo_url),
	               -title => $logo_label},
	              qq(<img src="$logo" width="72" height="27" alt="git" class="logo"/>));
	print $cgi->a({-href => esc_url($home_link)}, $home_link_str) . " / ";
	if (defined $project) {
		print $cgi->a({-href => href(action=>"summary")}, esc_html($project));
		if (defined $action) {
			print " / $action";
		}
		print "\n";
		if (!defined $searchtext) {
			$searchtext = "";
		}
		my $search_hash;
		if (defined $hash_base) {
			$search_hash = $hash_base;
		} elsif (defined $hash) {
			$search_hash = $hash;
		} else {
			$search_hash = "HEAD";
		}
		$cgi->param("a", "search");
		$cgi->param("h", $search_hash);
		$cgi->param("p", $project);
		print $cgi->startform(-method => "get", -action => $my_uri) .
		      "<div class=\"search\">\n" .
		      $cgi->hidden(-name => "p") . "\n" .
		      $cgi->hidden(-name => "a") . "\n" .
		      $cgi->hidden(-name => "h") . "\n" .
		      $cgi->popup_menu(-name => 'st', -default => 'commit',
				       -values => ['commit', 'author', 'committer', 'pickaxe']) .
		      $cgi->sup($cgi->a({-href => href(action=>"search_help")}, "?")) .
		      " search:\n",
		      $cgi->textfield(-name => "s", -value => $searchtext) . "\n" .
		      "</div>" .
		      $cgi->end_form() . "\n";
	}
	print "</div>\n";
}

sub git_footer_html {
	print "<div class=\"page_footer\">\n";
	if (defined $project) {
		my $descr = git_get_project_description($project);
		if (defined $descr) {
			print "<div class=\"page_footer_text\">" . esc_html($descr) . "</div>\n";
		}
		print $cgi->a({-href => href(action=>"rss"),
		              -class => "rss_logo"}, "RSS") . "\n";
	} else {
		print $cgi->a({-href => href(project=>undef, action=>"opml"),
		              -class => "rss_logo"}, "OPML") . " ";
		print $cgi->a({-href => href(project=>undef, action=>"project_index"),
		              -class => "rss_logo"}, "TXT") . "\n";
	}
	print "</div>\n" ;

	if (-f $site_footer) {
		open (my $fd, $site_footer);
		print <$fd>;
		close $fd;
	}

	print "</body>\n" .
	      "</html>";
}

sub die_error {
	my $status = shift || "403 Forbidden";
	my $error = shift || "Malformed query, file missing or permission denied";

	git_header_html($status);
	print <<EOF;
<div class="page_body">
<br /><br />
$status - $error
<br />
</div>
EOF
	git_footer_html();
	exit;
}

## ----------------------------------------------------------------------
## functions printing or outputting HTML: navigation

sub git_print_page_nav {
	my ($current, $suppress, $head, $treehead, $treebase, $extra) = @_;
	$extra = '' if !defined $extra; # pager or formats

	my @navs = qw(summary shortlog log commit commitdiff tree);
	if ($suppress) {
		@navs = grep { $_ ne $suppress } @navs;
	}

	my %arg = map { $_ => {action=>$_} } @navs;
	if (defined $head) {
		for (qw(commit commitdiff)) {
			$arg{$_}{hash} = $head;
		}
		if ($current =~ m/^(tree | log | shortlog | commit | commitdiff | search)$/x) {
			for (qw(shortlog log)) {
				$arg{$_}{hash} = $head;
			}
		}
	}
	$arg{tree}{hash} = $treehead if defined $treehead;
	$arg{tree}{hash_base} = $treebase if defined $treebase;

	print "<div class=\"page_nav\">\n" .
		(join " | ",
		 map { $_ eq $current ?
		       $_ : $cgi->a({-href => href(%{$arg{$_}})}, "$_")
		 } @navs);
	print "<br/>\n$extra<br/>\n" .
	      "</div>\n";
}

sub format_paging_nav {
	my ($action, $hash, $head, $page, $nrevs) = @_;
	my $paging_nav;


	if ($hash ne $head || $page) {
		$paging_nav .= $cgi->a({-href => href(action=>$action)}, "HEAD");
	} else {
		$paging_nav .= "HEAD";
	}

	if ($page > 0) {
		$paging_nav .= " &sdot; " .
			$cgi->a({-href => href(action=>$action, hash=>$hash, page=>$page-1),
			         -accesskey => "p", -title => "Alt-p"}, "prev");
	} else {
		$paging_nav .= " &sdot; prev";
	}

	if ($nrevs >= (100 * ($page+1)-1)) {
		$paging_nav .= " &sdot; " .
			$cgi->a({-href => href(action=>$action, hash=>$hash, page=>$page+1),
			         -accesskey => "n", -title => "Alt-n"}, "next");
	} else {
		$paging_nav .= " &sdot; next";
	}

	return $paging_nav;
}

## ......................................................................
## functions printing or outputting HTML: div

sub git_print_header_div {
	my ($action, $title, $hash, $hash_base) = @_;
	my %args = ();

	$args{action} = $action;
	$args{hash} = $hash if $hash;
	$args{hash_base} = $hash_base if $hash_base;

	print "<div class=\"header\">\n" .
	      $cgi->a({-href => href(%args), -class => "title"},
	      $title ? $title : $action) .
	      "\n</div>\n";
}

#sub git_print_authorship (\%) {
sub git_print_authorship {
	my $co = shift;

	my %ad = parse_date($co->{'author_epoch'}, $co->{'author_tz'});
	print "<div class=\"author_date\">" .
	      esc_html($co->{'author_name'}) .
	      " [$ad{'rfc2822'}";
	if ($ad{'hour_local'} < 6) {
		printf(" (<span class=\"atnight\">%02d:%02d</span> %s)",
		       $ad{'hour_local'}, $ad{'minute_local'}, $ad{'tz_local'});
	} else {
		printf(" (%02d:%02d %s)",
		       $ad{'hour_local'}, $ad{'minute_local'}, $ad{'tz_local'});
	}
	print "]</div>\n";
}

sub git_print_page_path {
	my $name = shift;
	my $type = shift;
	my $hb = shift;


	print "<div class=\"page_path\">";
	print $cgi->a({-href => href(action=>"tree", hash_base=>$hb),
	              -title => 'tree root'}, "[$project]");
	print " / ";
	if (defined $name) {
		my @dirname = split '/', $name;
		my $basename = pop @dirname;
		my $fullname = '';

		foreach my $dir (@dirname) {
			$fullname .= ($fullname ? '/' : '') . $dir;
			print $cgi->a({-href => href(action=>"tree", file_name=>$fullname,
			                             hash_base=>$hb),
			              -title => $fullname}, esc_path($dir));
			print " / ";
		}
		if (defined $type && $type eq 'blob') {
			print $cgi->a({-href => href(action=>"blob_plain", file_name=>$file_name,
			                             hash_base=>$hb),
			              -title => $name}, esc_path($basename));
		} elsif (defined $type && $type eq 'tree') {
			print $cgi->a({-href => href(action=>"tree", file_name=>$file_name,
			                             hash_base=>$hb),
			              -title => $name}, esc_path($basename));
			print " / ";
		} else {
			print esc_path($basename);
		}
	}
	print "<br/></div>\n";
}

# sub git_print_log (\@;%) {
sub git_print_log ($;%) {
	my $log = shift;
	my %opts = @_;

	if ($opts{'-remove_title'}) {
		# remove title, i.e. first line of log
		shift @$log;
	}
	# remove leading empty lines
	while (defined $log->[0] && $log->[0] eq "") {
		shift @$log;
	}

	# print log
	my $signoff = 0;
	my $empty = 0;
	foreach my $line (@$log) {
		if ($line =~ m/^ *(signed[ \-]off[ \-]by[ :]|acked[ \-]by[ :]|cc[ :])/i) {
			$signoff = 1;
			$empty = 0;
			if (! $opts{'-remove_signoff'}) {
				print "<span class=\"signoff\">" . esc_html($line) . "</span><br/>\n";
				next;
			} else {
				# remove signoff lines
				next;
			}
		} else {
			$signoff = 0;
		}

		# print only one empty line
		# do not print empty line after signoff
		if ($line eq "") {
			next if ($empty || $signoff);
			$empty = 1;
		} else {
			$empty = 0;
		}

		print format_log_line_html($line) . "<br/>\n";
	}

	if ($opts{'-final_empty_line'}) {
		# end with single empty line
		print "<br/>\n" unless $empty;
	}
}

# print tree entry (row of git_tree), but without encompassing <tr> element
sub git_print_tree_entry {
	my ($t, $basedir, $hash_base, $have_blame) = @_;

	my %base_key = ();
	$base_key{hash_base} = $hash_base if defined $hash_base;

	# The format of a table row is: mode list link.  Where mode is
	# the mode of the entry, list is the name of the entry, an href,
	# and link is the action links of the entry.

	print "<td class=\"mode\">" . mode_str($t->{'mode'}) . "</td>\n";
	if ($t->{'type'} eq "blob") {
		print "<td class=\"list\">" .
			$cgi->a({-href => href(action=>"blob", hash=>$t->{'hash'},
			                       file_name=>"$basedir$t->{'name'}", %base_key),
			        -class => "list"}, esc_path($t->{'name'})) . "</td>\n";
		print "<td class=\"link\">";
		print $cgi->a({-href => href(action=>"blob", hash=>$t->{'hash'},
					     file_name=>"$basedir$t->{'name'}", %base_key)},
			      "blob");
		if ($have_blame) {
			print " | " .
			      $cgi->a({-href => href(action=>"blame", hash=>$t->{'hash'},
				                           file_name=>"$basedir$t->{'name'}", %base_key)},
				            "blame");
		}
		if (defined $hash_base) {
			print " | " .
			      $cgi->a({-href => href(action=>"history", hash_base=>$hash_base,
			                             hash=>$t->{'hash'}, file_name=>"$basedir$t->{'name'}")},
			              "history");
		}
		print " | " .
			$cgi->a({-href => href(action=>"blob_plain", hash_base=>$hash_base,
			                       file_name=>"$basedir$t->{'name'}")},
			        "raw");
		print "</td>\n";

	} elsif ($t->{'type'} eq "tree") {
		print "<td class=\"list\">";
		print $cgi->a({-href => href(action=>"tree", hash=>$t->{'hash'},
		                             file_name=>"$basedir$t->{'name'}", %base_key)},
		              esc_path($t->{'name'}));
		print "</td>\n";
		print "<td class=\"link\">";
		print $cgi->a({-href => href(action=>"tree", hash=>$t->{'hash'},
					     file_name=>"$basedir$t->{'name'}", %base_key)},
			      "tree");
		if (defined $hash_base) {
			print " | " .
			      $cgi->a({-href => href(action=>"history", hash_base=>$hash_base,
			                             file_name=>"$basedir$t->{'name'}")},
			              "history");
		}
		print "</td>\n";
	}
}

## ......................................................................
## functions printing large fragments of HTML

sub git_difftree_body {
	my ($difftree, $hash, $parent) = @_;

	print "<div class=\"list_head\">\n";
	if ($#{$difftree} > 10) {
		print(($#{$difftree} + 1) . " files changed:\n");
	}
	print "</div>\n";

	print "<table class=\"diff_tree\">\n";
	my $alternate = 1;
	my $patchno = 0;
	foreach my $line (@{$difftree}) {
		my %diff = parse_difftree_raw_line($line);

		if ($alternate) {
			print "<tr class=\"dark\">\n";
		} else {
			print "<tr class=\"light\">\n";
		}
		$alternate ^= 1;

		my ($to_mode_oct, $to_mode_str, $to_file_type);
		my ($from_mode_oct, $from_mode_str, $from_file_type);
		if ($diff{'to_mode'} ne ('0' x 6)) {
			$to_mode_oct = oct $diff{'to_mode'};
			if (S_ISREG($to_mode_oct)) { # only for regular file
				$to_mode_str = sprintf("%04o", $to_mode_oct & 0777); # permission bits
			}
			$to_file_type = file_type($diff{'to_mode'});
		}
		if ($diff{'from_mode'} ne ('0' x 6)) {
			$from_mode_oct = oct $diff{'from_mode'};
			if (S_ISREG($to_mode_oct)) { # only for regular file
				$from_mode_str = sprintf("%04o", $from_mode_oct & 0777); # permission bits
			}
			$from_file_type = file_type($diff{'from_mode'});
		}

		if ($diff{'status'} eq "A") { # created
			my $mode_chng = "<span class=\"file_status new\">[new $to_file_type";
			$mode_chng   .= " with mode: $to_mode_str" if $to_mode_str;
			$mode_chng   .= "]</span>";
			print "<td>";
			print $cgi->a({-href => href(action=>"blob", hash=>$diff{'to_id'},
			                             hash_base=>$hash, file_name=>$diff{'file'}),
			              -class => "list"}, esc_path($diff{'file'}));
			print "</td>\n";
			print "<td>$mode_chng</td>\n";
			print "<td class=\"link\">";
			if ($action eq 'commitdiff') {
				# link to patch
				$patchno++;
				print $cgi->a({-href => "#patch$patchno"}, "patch");
			}
			print "</td>\n";

		} elsif ($diff{'status'} eq "D") { # deleted
			my $mode_chng = "<span class=\"file_status deleted\">[deleted $from_file_type]</span>";
			print "<td>";
			print $cgi->a({-href => href(action=>"blob", hash=>$diff{'from_id'},
			                             hash_base=>$parent, file_name=>$diff{'file'}),
			               -class => "list"}, esc_path($diff{'file'}));
			print "</td>\n";
			print "<td>$mode_chng</td>\n";
			print "<td class=\"link\">";
			if ($action eq 'commitdiff') {
				# link to patch
				$patchno++;
				print $cgi->a({-href => "#patch$patchno"}, "patch");
				print " | ";
			}
			print $cgi->a({-href => href(action=>"blob", hash=>$diff{'from_id'},
			                             hash_base=>$parent, file_name=>$diff{'file'})},
				      "blob") . " | ";
			print $cgi->a({-href => href(action=>"blame", hash_base=>$parent,
			                             file_name=>$diff{'file'})},
			              "blame") . " | ";
			print $cgi->a({-href => href(action=>"history", hash_base=>$parent,
			                             file_name=>$diff{'file'})},
			              "history");
			print "</td>\n";

		} elsif ($diff{'status'} eq "M" || $diff{'status'} eq "T") { # modified, or type changed
			my $mode_chnge = "";
			if ($diff{'from_mode'} != $diff{'to_mode'}) {
				$mode_chnge = "<span class=\"file_status mode_chnge\">[changed";
				if ($from_file_type != $to_file_type) {
					$mode_chnge .= " from $from_file_type to $to_file_type";
				}
				if (($from_mode_oct & 0777) != ($to_mode_oct & 0777)) {
					if ($from_mode_str && $to_mode_str) {
						$mode_chnge .= " mode: $from_mode_str->$to_mode_str";
					} elsif ($to_mode_str) {
						$mode_chnge .= " mode: $to_mode_str";
					}
				}
				$mode_chnge .= "]</span>\n";
			}
			print "<td>";
			print $cgi->a({-href => href(action=>"blob", hash=>$diff{'to_id'},
			                             hash_base=>$hash, file_name=>$diff{'file'}),
			              -class => "list"}, esc_path($diff{'file'}));
			print "</td>\n";
			print "<td>$mode_chnge</td>\n";
			print "<td class=\"link\">";
			if ($diff{'to_id'} ne $diff{'from_id'}) { # modified
				if ($action eq 'commitdiff') {
					# link to patch
					$patchno++;
					print $cgi->a({-href => "#patch$patchno"}, "patch");
				} else {
					print $cgi->a({-href => href(action=>"blobdiff",
					                             hash=>$diff{'to_id'}, hash_parent=>$diff{'from_id'},
					                             hash_base=>$hash, hash_parent_base=>$parent,
					                             file_name=>$diff{'file'})},
					              "diff");
				}
				print " | ";
			}
			print $cgi->a({-href => href(action=>"blob", hash=>$diff{'to_id'},
						     hash_base=>$hash, file_name=>$diff{'file'})},
				      "blob") . " | ";
			print $cgi->a({-href => href(action=>"blame", hash_base=>$hash,
			                             file_name=>$diff{'file'})},
			              "blame") . " | ";
			print $cgi->a({-href => href(action=>"history", hash_base=>$hash,
			                             file_name=>$diff{'file'})},
			              "history");
			print "</td>\n";

		} elsif ($diff{'status'} eq "R" || $diff{'status'} eq "C") { # renamed or copied
			my %status_name = ('R' => 'moved', 'C' => 'copied');
			my $nstatus = $status_name{$diff{'status'}};
			my $mode_chng = "";
			if ($diff{'from_mode'} != $diff{'to_mode'}) {
				# mode also for directories, so we cannot use $to_mode_str
				$mode_chng = sprintf(", mode: %04o", $to_mode_oct & 0777);
			}
			print "<td>" .
			      $cgi->a({-href => href(action=>"blob", hash_base=>$hash,
			                             hash=>$diff{'to_id'}, file_name=>$diff{'to_file'}),
			              -class => "list"}, esc_path($diff{'to_file'})) . "</td>\n" .
			      "<td><span class=\"file_status $nstatus\">[$nstatus from " .
			      $cgi->a({-href => href(action=>"blob", hash_base=>$parent,
			                             hash=>$diff{'from_id'}, file_name=>$diff{'from_file'}),
			              -class => "list"}, esc_path($diff{'from_file'})) .
			      " with " . (int $diff{'similarity'}) . "% similarity$mode_chng]</span></td>\n" .
			      "<td class=\"link\">";
			if ($diff{'to_id'} ne $diff{'from_id'}) {
				if ($action eq 'commitdiff') {
					# link to patch
					$patchno++;
					print $cgi->a({-href => "#patch$patchno"}, "patch");
				} else {
					print $cgi->a({-href => href(action=>"blobdiff",
					                             hash=>$diff{'to_id'}, hash_parent=>$diff{'from_id'},
					                             hash_base=>$hash, hash_parent_base=>$parent,
					                             file_name=>$diff{'to_file'}, file_parent=>$diff{'from_file'})},
					              "diff");
				}
				print " | ";
			}
			print $cgi->a({-href => href(action=>"blob", hash=>$diff{'from_id'},
						     hash_base=>$parent, file_name=>$diff{'from_file'})},
				      "blob") . " | ";
			print $cgi->a({-href => href(action=>"blame", hash_base=>$parent,
			                             file_name=>$diff{'from_file'})},
			              "blame") . " | ";
			print $cgi->a({-href => href(action=>"history", hash_base=>$parent,
			                            file_name=>$diff{'from_file'})},
			              "history");
			print "</td>\n";

		} # we should not encounter Unmerged (U) or Unknown (X) status
		print "</tr>\n";
	}
	print "</table>\n";
}

sub git_patchset_body {
	my ($fd, $difftree, $hash, $hash_parent) = @_;

	my $patch_idx = 0;
	my $in_header = 0;
	my $patch_found = 0;
	my $diffinfo;

	print "<div class=\"patchset\">\n";

	LINE:
	while (my $patch_line = <$fd>) {
		chomp $patch_line;

		if ($patch_line =~ m/^diff /) { # "git diff" header
			# beginning of patch (in patchset)
			if ($patch_found) {
				# close previous patch
				print "</div>\n"; # class="patch"
			} else {
				# first patch in patchset
				$patch_found = 1;
			}
			print "<div class=\"patch\" id=\"patch". ($patch_idx+1) ."\">\n";

			if (ref($difftree->[$patch_idx]) eq "HASH") {
				$diffinfo = $difftree->[$patch_idx];
			} else {
				$diffinfo = parse_difftree_raw_line($difftree->[$patch_idx]);
			}
			$patch_idx++;

			# for now, no extended header, hence we skip empty patches
			# companion to	next LINE if $in_header;
			if ($diffinfo->{'from_id'} eq $diffinfo->{'to_id'}) { # no change
				$in_header = 1;
				next LINE;
			}

			if ($diffinfo->{'status'} eq "A") { # added
				print "<div class=\"diff_info\">" . file_type($diffinfo->{'to_mode'}) . ":" .
				      $cgi->a({-href => href(action=>"blob", hash_base=>$hash,
				                             hash=>$diffinfo->{'to_id'}, file_name=>$diffinfo->{'file'})},
				              $diffinfo->{'to_id'}) . " (new)" .
				      "</div>\n"; # class="diff_info"

			} elsif ($diffinfo->{'status'} eq "D") { # deleted
				print "<div class=\"diff_info\">" . file_type($diffinfo->{'from_mode'}) . ":" .
				      $cgi->a({-href => href(action=>"blob", hash_base=>$hash_parent,
				                             hash=>$diffinfo->{'from_id'}, file_name=>$diffinfo->{'file'})},
				              $diffinfo->{'from_id'}) . " (deleted)" .
				      "</div>\n"; # class="diff_info"

			} elsif ($diffinfo->{'status'} eq "R" || # renamed
			         $diffinfo->{'status'} eq "C" || # copied
			         $diffinfo->{'status'} eq "2") { # with two filenames (from git_blobdiff)
				print "<div class=\"diff_info\">" .
				      file_type($diffinfo->{'from_mode'}) . ":" .
				      $cgi->a({-href => href(action=>"blob", hash_base=>$hash_parent,
				                             hash=>$diffinfo->{'from_id'}, file_name=>$diffinfo->{'from_file'})},
				              $diffinfo->{'from_id'}) .
				      " -> " .
				      file_type($diffinfo->{'to_mode'}) . ":" .
				      $cgi->a({-href => href(action=>"blob", hash_base=>$hash,
				                             hash=>$diffinfo->{'to_id'}, file_name=>$diffinfo->{'to_file'})},
				              $diffinfo->{'to_id'});
				print "</div>\n"; # class="diff_info"

			} else { # modified, mode changed, ...
				print "<div class=\"diff_info\">" .
				      file_type($diffinfo->{'from_mode'}) . ":" .
				      $cgi->a({-href => href(action=>"blob", hash_base=>$hash_parent,
				                             hash=>$diffinfo->{'from_id'}, file_name=>$diffinfo->{'file'})},
				              $diffinfo->{'from_id'}) .
				      " -> " .
				      file_type($diffinfo->{'to_mode'}) . ":" .
				      $cgi->a({-href => href(action=>"blob", hash_base=>$hash,
				                             hash=>$diffinfo->{'to_id'}, file_name=>$diffinfo->{'file'})},
				              $diffinfo->{'to_id'});
				print "</div>\n"; # class="diff_info"
			}

			#print "<div class=\"diff extended_header\">\n";
			$in_header = 1;
			next LINE;
		} # start of patch in patchset


		if ($in_header && $patch_line =~ m/^---/) {
			#print "</div>\n"; # class="diff extended_header"
			$in_header = 0;

			my $file = $diffinfo->{'from_file'};
			$file  ||= $diffinfo->{'file'};
			$file = $cgi->a({-href => href(action=>"blob", hash_base=>$hash_parent,
			                               hash=>$diffinfo->{'from_id'}, file_name=>$file),
			                -class => "list"}, esc_path($file));
			$patch_line =~ s|a/.*$|a/$file|g;
			print "<div class=\"diff from_file\">$patch_line</div>\n";

			$patch_line = <$fd>;
			chomp $patch_line;

			#$patch_line =~ m/^+++/;
			$file    = $diffinfo->{'to_file'};
			$file  ||= $diffinfo->{'file'};
			$file = $cgi->a({-href => href(action=>"blob", hash_base=>$hash,
			                               hash=>$diffinfo->{'to_id'}, file_name=>$file),
			                -class => "list"}, esc_path($file));
			$patch_line =~ s|b/.*|b/$file|g;
			print "<div class=\"diff to_file\">$patch_line</div>\n";

			next LINE;
		}
		next LINE if $in_header;

		print format_diff_line($patch_line);
	}
	print "</div>\n" if $patch_found; # class="patch"

	print "</div>\n"; # class="patchset"
}

# . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .

sub git_shortlog_body {
	# uses global variable $project
	my ($revlist, $from, $to, $refs, $extra) = @_;

	$from = 0 unless defined $from;
	$to = $#{$revlist} if (!defined $to || $#{$revlist} < $to);

	print "<table class=\"shortlog\" cellspacing=\"0\">\n";
	my $alternate = 1;
	for (my $i = $from; $i <= $to; $i++) {
		my $commit = $revlist->[$i];
		#my $ref = defined $refs ? format_ref_marker($refs, $commit) : '';
		my $ref = format_ref_marker($refs, $commit);
		my %co = parse_commit($commit);
		if ($alternate) {
			print "<tr class=\"dark\">\n";
		} else {
			print "<tr class=\"light\">\n";
		}
		$alternate ^= 1;
		# git_summary() used print "<td><i>$co{'age_string'}</i></td>\n" .
		print "<td title=\"$co{'age_string_age'}\"><i>$co{'age_string_date'}</i></td>\n" .
		      "<td><i>" . esc_html(chop_str($co{'author_name'}, 10)) . "</i></td>\n" .
		      "<td>";
		print format_subject_html($co{'title'}, $co{'title_short'},
		                          href(action=>"commit", hash=>$commit), $ref);
		print "</td>\n" .
		      "<td class=\"link\">" .
		      $cgi->a({-href => href(action=>"commit", hash=>$commit)}, "commit") . " | " .
		      $cgi->a({-href => href(action=>"commitdiff", hash=>$commit)}, "commitdiff") . " | " .
		      $cgi->a({-href => href(action=>"tree", hash=>$commit, hash_base=>$commit)}, "tree");
		if (gitweb_have_snapshot()) {
			print " | " . $cgi->a({-href => href(action=>"snapshot", hash=>$commit)}, "snapshot");
		}
		print "</td>\n" .
		      "</tr>\n";
	}
	if (defined $extra) {
		print "<tr>\n" .
		      "<td colspan=\"4\">$extra</td>\n" .
		      "</tr>\n";
	}
	print "</table>\n";
}

sub git_history_body {
	# Warning: assumes constant type (blob or tree) during history
	my ($revlist, $from, $to, $refs, $hash_base, $ftype, $extra) = @_;

	$from = 0 unless defined $from;
	$to = $#{$revlist} unless (defined $to && $to <= $#{$revlist});

	print "<table class=\"history\" cellspacing=\"0\">\n";
	my $alternate = 1;
	for (my $i = $from; $i <= $to; $i++) {
		if ($revlist->[$i] !~ m/^([0-9a-fA-F]{40})/) {
			next;
		}

		my $commit = $1;
		my %co = parse_commit($commit);
		if (!%co) {
			next;
		}

		my $ref = format_ref_marker($refs, $commit);

		if ($alternate) {
			print "<tr class=\"dark\">\n";
		} else {
			print "<tr class=\"light\">\n";
		}
		$alternate ^= 1;
		print "<td title=\"$co{'age_string_age'}\"><i>$co{'age_string_date'}</i></td>\n" .
		      # shortlog uses      chop_str($co{'author_name'}, 10)
		      "<td><i>" . esc_html(chop_str($co{'author_name'}, 15, 3)) . "</i></td>\n" .
		      "<td>";
		# originally git_history used chop_str($co{'title'}, 50)
		print format_subject_html($co{'title'}, $co{'title_short'},
		                          href(action=>"commit", hash=>$commit), $ref);
		print "</td>\n" .
		      "<td class=\"link\">" .
		      $cgi->a({-href => href(action=>$ftype, hash_base=>$commit, file_name=>$file_name)}, $ftype) . " | " .
		      $cgi->a({-href => href(action=>"commitdiff", hash=>$commit)}, "commitdiff");

		if ($ftype eq 'blob') {
			my $blob_current = git_get_hash_by_path($hash_base, $file_name);
			my $blob_parent  = git_get_hash_by_path($commit, $file_name);
			if (defined $blob_current && defined $blob_parent &&
					$blob_current ne $blob_parent) {
				print " | " .
					$cgi->a({-href => href(action=>"blobdiff",
					                       hash=>$blob_current, hash_parent=>$blob_parent,
					                       hash_base=>$hash_base, hash_parent_base=>$commit,
					                       file_name=>$file_name)},
					        "diff to current");
			}
		}
		print "</td>\n" .
		      "</tr>\n";
	}
	if (defined $extra) {
		print "<tr>\n" .
		      "<td colspan=\"4\">$extra</td>\n" .
		      "</tr>\n";
	}
	print "</table>\n";
}

sub git_tags_body {
	# uses global variable $project
	my ($taglist, $from, $to, $extra) = @_;
	$from = 0 unless defined $from;
	$to = $#{$taglist} if (!defined $to || $#{$taglist} < $to);

	print "<table class=\"tags\" cellspacing=\"0\">\n";
	my $alternate = 1;
	for (my $i = $from; $i <= $to; $i++) {
		my $entry = $taglist->[$i];
		my %tag = %$entry;
		my $comment_lines = $tag{'comment'};
		my $comment = shift @$comment_lines;
		my $comment_short;
		if (defined $comment) {
			$comment_short = chop_str($comment, 30, 5);
		}
		if ($alternate) {
			print "<tr class=\"dark\">\n";
		} else {
			print "<tr class=\"light\">\n";
		}
		$alternate ^= 1;
		print "<td><i>$tag{'age'}</i></td>\n" .
		      "<td>" .
		      $cgi->a({-href => href(action=>$tag{'reftype'}, hash=>$tag{'refid'}),
		               -class => "list name"}, esc_html($tag{'name'})) .
		      "</td>\n" .
		      "<td>";
		if (defined $comment) {
			print format_subject_html($comment, $comment_short,
			                          href(action=>"tag", hash=>$tag{'id'}));
		}
		print "</td>\n" .
		      "<td class=\"selflink\">";
		if ($tag{'type'} eq "tag") {
			print $cgi->a({-href => href(action=>"tag", hash=>$tag{'id'})}, "tag");
		} else {
			print "&nbsp;";
		}
		print "</td>\n" .
		      "<td class=\"link\">" . " | " .
		      $cgi->a({-href => href(action=>$tag{'reftype'}, hash=>$tag{'refid'})}, $tag{'reftype'});
		if ($tag{'reftype'} eq "commit") {
			print " | " . $cgi->a({-href => href(action=>"shortlog", hash=>$tag{'name'})}, "shortlog") .
			      " | " . $cgi->a({-href => href(action=>"log", hash=>$tag{'refid'})}, "log");
		} elsif ($tag{'reftype'} eq "blob") {
			print " | " . $cgi->a({-href => href(action=>"blob_plain", hash=>$tag{'refid'})}, "raw");
		}
		print "</td>\n" .
		      "</tr>";
	}
	if (defined $extra) {
		print "<tr>\n" .
		      "<td colspan=\"5\">$extra</td>\n" .
		      "</tr>\n";
	}
	print "</table>\n";
}

sub git_heads_body {
	# uses global variable $project
	my ($headlist, $head, $from, $to, $extra) = @_;
	$from = 0 unless defined $from;
	$to = $#{$headlist} if (!defined $to || $#{$headlist} < $to);

	print "<table class=\"heads\" cellspacing=\"0\">\n";
	my $alternate = 1;
	for (my $i = $from; $i <= $to; $i++) {
		my $entry = $headlist->[$i];
		my %tag = %$entry;
		my $curr = $tag{'id'} eq $head;
		if ($alternate) {
			print "<tr class=\"dark\">\n";
		} else {
			print "<tr class=\"light\">\n";
		}
		$alternate ^= 1;
		print "<td><i>$tag{'age'}</i></td>\n" .
		      ($tag{'id'} eq $head ? "<td class=\"current_head\">" : "<td>") .
		      $cgi->a({-href => href(action=>"shortlog", hash=>$tag{'name'}),
		               -class => "list name"},esc_html($tag{'name'})) .
		      "</td>\n" .
		      "<td class=\"link\">" .
		      $cgi->a({-href => href(action=>"shortlog", hash=>$tag{'name'})}, "shortlog") . " | " .
		      $cgi->a({-href => href(action=>"log", hash=>$tag{'name'})}, "log") . " | " .
		      $cgi->a({-href => href(action=>"tree", hash=>$tag{'name'}, hash_base=>$tag{'name'})}, "tree") .
		      "</td>\n" .
		      "</tr>";
	}
	if (defined $extra) {
		print "<tr>\n" .
		      "<td colspan=\"3\">$extra</td>\n" .
		      "</tr>\n";
	}
	print "</table>\n";
}

## ======================================================================
## ======================================================================
## actions

sub git_project_list {
	my $order = $cgi->param('o');
	if (defined $order && $order !~ m/project|descr|owner|age/) {
		die_error(undef, "Unknown order parameter");
	}

	my @list = git_get_projects_list();
	my @projects;
	if (!@list) {
		die_error(undef, "No projects found");
	}
	foreach my $pr (@list) {
		my (@aa) = git_get_last_activity($pr->{'path'});
		unless (@aa) {
			next;
		}
		($pr->{'age'}, $pr->{'age_string'}) = @aa;
		if (!defined $pr->{'descr'}) {
			my $descr = git_get_project_description($pr->{'path'}) || "";
			$pr->{'descr'} = chop_str($descr, 25, 5);
		}
		if (!defined $pr->{'owner'}) {
			$pr->{'owner'} = get_file_owner("$projectroot/$pr->{'path'}") || "";
		}
		push @projects, $pr;
	}

	git_header_html();
	if (-f $home_text) {
		print "<div class=\"index_include\">\n";
		open (my $fd, $home_text);
		print <$fd>;
		close $fd;
		print "</div>\n";
	}
	print "<table class=\"project_list\">\n" .
	      "<tr>\n";
	$order ||= "project";
	if ($order eq "project") {
		@projects = sort {$a->{'path'} cmp $b->{'path'}} @projects;
		print "<th>Project</th>\n";
	} else {
		print "<th>" .
		      $cgi->a({-href => href(project=>undef, order=>'project'),
		               -class => "header"}, "Project") .
		      "</th>\n";
	}
	if ($order eq "descr") {
		@projects = sort {$a->{'descr'} cmp $b->{'descr'}} @projects;
		print "<th>Description</th>\n";
	} else {
		print "<th>" .
		      $cgi->a({-href => href(project=>undef, order=>'descr'),
		               -class => "header"}, "Description") .
		      "</th>\n";
	}
	if ($order eq "owner") {
		@projects = sort {$a->{'owner'} cmp $b->{'owner'}} @projects;
		print "<th>Owner</th>\n";
	} else {
		print "<th>" .
		      $cgi->a({-href => href(project=>undef, order=>'owner'),
		               -class => "header"}, "Owner") .
		      "</th>\n";
	}
	if ($order eq "age") {
		@projects = sort {$a->{'age'} <=> $b->{'age'}} @projects;
		print "<th>Last Change</th>\n";
	} else {
		print "<th>" .
		      $cgi->a({-href => href(project=>undef, order=>'age'),
		               -class => "header"}, "Last Change") .
		      "</th>\n";
	}
	print "<th></th>\n" .
	      "</tr>\n";
	my $alternate = 1;
	foreach my $pr (@projects) {
		if ($alternate) {
			print "<tr class=\"dark\">\n";
		} else {
			print "<tr class=\"light\">\n";
		}
		$alternate ^= 1;
		print "<td>" . $cgi->a({-href => href(project=>$pr->{'path'}, action=>"summary"),
		                        -class => "list"}, esc_html($pr->{'path'})) . "</td>\n" .
		      "<td>" . esc_html($pr->{'descr'}) . "</td>\n" .
		      "<td><i>" . chop_str($pr->{'owner'}, 15) . "</i></td>\n";
		print "<td class=\"". age_class($pr->{'age'}) . "\">" .
		      $pr->{'age_string'} . "</td>\n" .
		      "<td class=\"link\">" .
		      $cgi->a({-href => href(project=>$pr->{'path'}, action=>"summary")}, "summary")   . " | " .
		      $cgi->a({-href => href(project=>$pr->{'path'}, action=>"shortlog")}, "shortlog") . " | " .
		      $cgi->a({-href => href(project=>$pr->{'path'}, action=>"log")}, "log") . " | " .
		      $cgi->a({-href => href(project=>$pr->{'path'}, action=>"tree")}, "tree") .
		      "</td>\n" .
		      "</tr>\n";
	}
	print "</table>\n";
	git_footer_html();
}

sub git_project_index {
	my @projects = git_get_projects_list();

	print $cgi->header(
		-type => 'text/plain',
		-charset => 'utf-8',
		-content_disposition => 'inline; filename="index.aux"');

	foreach my $pr (@projects) {
		if (!exists $pr->{'owner'}) {
			$pr->{'owner'} = get_file_owner("$projectroot/$project");
		}

		my ($path, $owner) = ($pr->{'path'}, $pr->{'owner'});
		# quote as in CGI::Util::encode, but keep the slash, and use '+' for ' '
		$path  =~ s/([^a-zA-Z0-9_.\-\/ ])/sprintf("%%%02X", ord($1))/eg;
		$owner =~ s/([^a-zA-Z0-9_.\-\/ ])/sprintf("%%%02X", ord($1))/eg;
		$path  =~ s/ /\+/g;
		$owner =~ s/ /\+/g;

		print "$path $owner\n";
	}
}

sub git_summary {
	my $descr = git_get_project_description($project) || "none";
	my $head = git_get_head_hash($project);
	my %co = parse_commit($head);
	my %cd = parse_date($co{'committer_epoch'}, $co{'committer_tz'});

	my $owner = git_get_project_owner($project);

	my ($reflist, $refs) = git_get_refs_list();

	my @taglist;
	my @headlist;
	foreach my $ref (@$reflist) {
		if ($ref->{'name'} =~ s!^heads/!!) {
			push @headlist, $ref;
		} else {
			$ref->{'name'} =~ s!^tags/!!;
			push @taglist, $ref;
		}
	}

	git_header_html();
	git_print_page_nav('summary','', $head);

	print "<div class=\"title\">&nbsp;</div>\n";
	print "<table cellspacing=\"0\">\n" .
	      "<tr><td>description</td><td>" . esc_html($descr) . "</td></tr>\n" .
	      "<tr><td>owner</td><td>$owner</td></tr>\n" .
	      "<tr><td>last change</td><td>$cd{'rfc2822'}</td></tr>\n";
	# use per project git URL list in $projectroot/$project/cloneurl
	# or make project git URL from git base URL and project name
	my $url_tag = "URL";
	my @url_list = git_get_project_url_list($project);
	@url_list = map { "$_/$project" } @git_base_url_list unless @url_list;
	foreach my $git_url (@url_list) {
		next unless $git_url;
		print "<tr><td>$url_tag</td><td>$git_url</td></tr>\n";
		$url_tag = "";
	}
	print "</table>\n";

	if (-s "$projectroot/$project/README.html") {
		if (open my $fd, "$projectroot/$project/README.html") {
			print "<div class=\"title\">readme</div>\n";
			print $_ while (<$fd>);
			close $fd;
		}
	}

	open my $fd, "-|", git_cmd(), "rev-list", "--max-count=17",
		git_get_head_hash($project)
		or die_error(undef, "Open git-rev-list failed");
	my @revlist = map { chomp; $_ } <$fd>;
	close $fd;
	git_print_header_div('shortlog');
	git_shortlog_body(\@revlist, 0, 15, $refs,
	                  $cgi->a({-href => href(action=>"shortlog")}, "..."));

	if (@taglist) {
		git_print_header_div('tags');
		git_tags_body(\@taglist, 0, 15,
		              $cgi->a({-href => href(action=>"tags")}, "..."));
	}

	if (@headlist) {
		git_print_header_div('heads');
		git_heads_body(\@headlist, $head, 0, 15,
		               $cgi->a({-href => href(action=>"heads")}, "..."));
	}

	git_footer_html();
}

sub git_tag {
	my $head = git_get_head_hash($project);
	git_header_html();
	git_print_page_nav('','', $head,undef,$head);
	my %tag = parse_tag($hash);
	git_print_header_div('commit', esc_html($tag{'name'}), $hash);
	print "<div class=\"title_text\">\n" .
	      "<table cellspacing=\"0\">\n" .
	      "<tr>\n" .
	      "<td>object</td>\n" .
	      "<td>" . $cgi->a({-class => "list", -href => href(action=>$tag{'type'}, hash=>$tag{'object'})},
	                       $tag{'object'}) . "</td>\n" .
	      "<td class=\"link\">" . $cgi->a({-href => href(action=>$tag{'type'}, hash=>$tag{'object'})},
	                                      $tag{'type'}) . "</td>\n" .
	      "</tr>\n";
	if (defined($tag{'author'})) {
		my %ad = parse_date($tag{'epoch'}, $tag{'tz'});
		print "<tr><td>author</td><td>" . esc_html($tag{'author'}) . "</td></tr>\n";
		print "<tr><td></td><td>" . $ad{'rfc2822'} .
			sprintf(" (%02d:%02d %s)", $ad{'hour_local'}, $ad{'minute_local'}, $ad{'tz_local'}) .
			"</td></tr>\n";
	}
	print "</table>\n\n" .
	      "</div>\n";
	print "<div class=\"page_body\">";
	my $comment = $tag{'comment'};
	foreach my $line (@$comment) {
		print esc_html($line) . "<br/>\n";
	}
	print "</div>\n";
	git_footer_html();
}

sub git_blame2 {
	my $fd;
	my $ftype;

	my ($have_blame) = gitweb_check_feature('blame');
	if (!$have_blame) {
		die_error('403 Permission denied', "Permission denied");
	}
	die_error('404 Not Found', "File name not defined") if (!$file_name);
	$hash_base ||= git_get_head_hash($project);
	die_error(undef, "Couldn't find base commit") unless ($hash_base);
	my %co = parse_commit($hash_base)
		or die_error(undef, "Reading commit failed");
	if (!defined $hash) {
		$hash = git_get_hash_by_path($hash_base, $file_name, "blob")
			or die_error(undef, "Error looking up file");
	}
	$ftype = git_get_type($hash);
	if ($ftype !~ "blob") {
		die_error("400 Bad Request", "Object is not a blob");
	}
	open ($fd, "-|", git_cmd(), "blame", '-p', '--',
	      $file_name, $hash_base)
		or die_error(undef, "Open git-blame failed");
	git_header_html();
	my $formats_nav =
		$cgi->a({-href => href(action=>"blob", hash=>$hash, hash_base=>$hash_base, file_name=>$file_name)},
		        "blob") .
		" | " .
		$cgi->a({-href => href(action=>"history", hash=>$hash, hash_base=>$hash_base, file_name=>$file_name)},
			"history") .
		" | " .
		$cgi->a({-href => href(action=>"blame", file_name=>$file_name)},
		        "HEAD");
	git_print_page_nav('','', $hash_base,$co{'tree'},$hash_base, $formats_nav);
	git_print_header_div('commit', esc_html($co{'title'}), $hash_base);
	git_print_page_path($file_name, $ftype, $hash_base);
	my @rev_color = (qw(light2 dark2));
	my $num_colors = scalar(@rev_color);
	my $current_color = 0;
	my $last_rev;
	print <<HTML;
<div class="page_body">
<table class="blame">
<tr><th>Commit</th><th>Line</th><th>Data</th></tr>
HTML
	my %metainfo = ();
	while (1) {
		$_ = <$fd>;
		last unless defined $_;
		my ($full_rev, $orig_lineno, $lineno, $group_size) =
		    /^([0-9a-f]{40}) (\d+) (\d+)(?: (\d+))?$/;
		if (!exists $metainfo{$full_rev}) {
			$metainfo{$full_rev} = {};
		}
		my $meta = $metainfo{$full_rev};
		while (<$fd>) {
			last if (s/^\t//);
			if (/^(\S+) (.*)$/) {
				$meta->{$1} = $2;
			}
		}
		my $data = $_;
		my $rev = substr($full_rev, 0, 8);
		my $author = $meta->{'author'};
		my %date = parse_date($meta->{'author-time'},
				      $meta->{'author-tz'});
		my $date = $date{'iso-tz'};
		if ($group_size) {
			$current_color = ++$current_color % $num_colors;
		}
		print "<tr class=\"$rev_color[$current_color]\">\n";
		if ($group_size) {
			print "<td class=\"sha1\"";
			print " title=\"$author, $date\"";
			print " rowspan=\"$group_size\"" if ($group_size > 1);
			print ">";
			print $cgi->a({-href => href(action=>"commit",
						     hash=>$full_rev,
						     file_name=>$file_name)},
				      esc_html($rev));
			print "</td>\n";
		}
		my $blamed = href(action => 'blame',
				  file_name => $meta->{'filename'},
				  hash_base => $full_rev);
		print "<td class=\"linenr\">";
		print $cgi->a({ -href => "$blamed#l$orig_lineno",
				-id => "l$lineno",
				-class => "linenr" },
			      esc_html($lineno));
		print "</td>";
		print "<td class=\"pre\">" . esc_html($data) . "</td>\n";
		print "</tr>\n";
	}
	print "</table>\n";
	print "</div>";
	close $fd
		or print "Reading blob failed\n";
	git_footer_html();
}

sub git_blame {
	my $fd;

	my ($have_blame) = gitweb_check_feature('blame');
	if (!$have_blame) {
		die_error('403 Permission denied', "Permission denied");
	}
	die_error('404 Not Found', "File name not defined") if (!$file_name);
	$hash_base ||= git_get_head_hash($project);
	die_error(undef, "Couldn't find base commit") unless ($hash_base);
	my %co = parse_commit($hash_base)
		or die_error(undef, "Reading commit failed");
	if (!defined $hash) {
		$hash = git_get_hash_by_path($hash_base, $file_name, "blob")
			or die_error(undef, "Error lookup file");
	}
	open ($fd, "-|", git_cmd(), "annotate", '-l', '-t', '-r', $file_name, $hash_base)
		or die_error(undef, "Open git-annotate failed");
	git_header_html();
	my $formats_nav =
		$cgi->a({-href => href(action=>"blob", hash=>$hash, hash_base=>$hash_base, file_name=>$file_name)},
		        "blob") .
		" | " .
		$cgi->a({-href => href(action=>"history", hash=>$hash, hash_base=>$hash_base, file_name=>$file_name)},
			"history") .
		" | " .
		$cgi->a({-href => href(action=>"blame", file_name=>$file_name)},
		        "HEAD");
	git_print_page_nav('','', $hash_base,$co{'tree'},$hash_base, $formats_nav);
	git_print_header_div('commit', esc_html($co{'title'}), $hash_base);
	git_print_page_path($file_name, 'blob', $hash_base);
	print "<div class=\"page_body\">\n";
	print <<HTML;
<table class="blame">
  <tr>
    <th>Commit</th>
    <th>Age</th>
    <th>Author</th>
    <th>Line</th>
    <th>Data</th>
  </tr>
HTML
	my @line_class = (qw(light dark));
	my $line_class_len = scalar (@line_class);
	my $line_class_num = $#line_class;
	while (my $line = <$fd>) {
		my $long_rev;
		my $short_rev;
		my $author;
		my $time;
		my $lineno;
		my $data;
		my $age;
		my $age_str;
		my $age_class;

		chomp $line;
		$line_class_num = ($line_class_num + 1) % $line_class_len;

		if ($line =~ m/^([0-9a-fA-F]{40})\t\(\s*([^\t]+)\t(\d+) [+-]\d\d\d\d\t(\d+)\)(.*)$/) {
			$long_rev = $1;
			$author   = $2;
			$time     = $3;
			$lineno   = $4;
			$data     = $5;
		} else {
			print qq(  <tr><td colspan="5" class="error">Unable to parse: $line</td></tr>\n);
			next;
		}
		$short_rev  = substr ($long_rev, 0, 8);
		$age        = time () - $time;
		$age_str    = age_string ($age);
		$age_str    =~ s/ /&nbsp;/g;
		$age_class  = age_class($age);
		$author     = esc_html ($author);
		$author     =~ s/ /&nbsp;/g;

		$data = untabify($data);
		$data = esc_html ($data);

		print <<HTML;
  <tr class="$line_class[$line_class_num]">
    <td class="sha1"><a href="${\href (action=>"commit", hash=>$long_rev)}" class="text">$short_rev..</a></td>
    <td class="$age_class">$age_str</td>
    <td>$author</td>
    <td class="linenr"><a id="$lineno" href="#$lineno" class="linenr">$lineno</a></td>
    <td class="pre">$data</td>
  </tr>
HTML
	} # while (my $line = <$fd>)
	print "</table>\n\n";
	close $fd
		or print "Reading blob failed.\n";
	print "</div>";
	git_footer_html();
}

sub git_tags {
	my $head = git_get_head_hash($project);
	git_header_html();
	git_print_page_nav('','', $head,undef,$head);
	git_print_header_div('summary', $project);

	my ($taglist) = git_get_refs_list("tags");
	if (@$taglist) {
		git_tags_body($taglist);
	}
	git_footer_html();
}

sub git_heads {
	my $head = git_get_head_hash($project);
	git_header_html();
	git_print_page_nav('','', $head,undef,$head);
	git_print_header_div('summary', $project);

	my ($headlist) = git_get_refs_list("heads");
	if (@$headlist) {
		git_heads_body($headlist, $head);
	}
	git_footer_html();
}

sub git_blob_plain {
	my $expires;

	if (!defined $hash) {
		if (defined $file_name) {
			my $base = $hash_base || git_get_head_hash($project);
			$hash = git_get_hash_by_path($base, $file_name, "blob")
				or die_error(undef, "Error lookup file");
		} else {
			die_error(undef, "No file name defined");
		}
	} elsif ($hash =~ m/^[0-9a-fA-F]{40}$/) {
		# blobs defined by non-textual hash id's can be cached
		$expires = "+1d";
	}

	my $type = shift;
	open my $fd, "-|", git_cmd(), "cat-file", "blob", $hash
		or die_error(undef, "Couldn't cat $file_name, $hash");

	$type ||= blob_mimetype($fd, $file_name);

	# save as filename, even when no $file_name is given
	my $save_as = "$hash";
	if (defined $file_name) {
		$save_as = $file_name;
	} elsif ($type =~ m/^text\//) {
		$save_as .= '.txt';
	}

	print $cgi->header(
		-type => "$type",
		-expires=>$expires,
		-content_disposition => 'inline; filename="' . "$save_as" . '"');
	undef $/;
	binmode STDOUT, ':raw';
	print <$fd>;
	binmode STDOUT, ':utf8'; # as set at the beginning of gitweb.cgi
	$/ = "\n";
	close $fd;
}

sub git_blob {
	my $expires;

	if (!defined $hash) {
		if (defined $file_name) {
			my $base = $hash_base || git_get_head_hash($project);
			$hash = git_get_hash_by_path($base, $file_name, "blob")
				or die_error(undef, "Error lookup file");
		} else {
			die_error(undef, "No file name defined");
		}
	} elsif ($hash =~ m/^[0-9a-fA-F]{40}$/) {
		# blobs defined by non-textual hash id's can be cached
		$expires = "+1d";
	}

	my ($have_blame) = gitweb_check_feature('blame');
	open my $fd, "-|", git_cmd(), "cat-file", "blob", $hash
		or die_error(undef, "Couldn't cat $file_name, $hash");
	my $mimetype = blob_mimetype($fd, $file_name);
	if ($mimetype !~ m/^text\//) {
		close $fd;
		return git_blob_plain($mimetype);
	}
	git_header_html(undef, $expires);
	my $formats_nav = '';
	if (defined $hash_base && (my %co = parse_commit($hash_base))) {
		if (defined $file_name) {
			if ($have_blame) {
				$formats_nav .=
					$cgi->a({-href => href(action=>"blame", hash_base=>$hash_base,
					                       hash=>$hash, file_name=>$file_name)},
					        "blame") .
					" | ";
			}
			$formats_nav .=
				$cgi->a({-href => href(action=>"history", hash_base=>$hash_base,
				                       hash=>$hash, file_name=>$file_name)},
				        "history") .
				" | " .
				$cgi->a({-href => href(action=>"blob_plain",
				                       hash=>$hash, file_name=>$file_name)},
				        "raw") .
				" | " .
				$cgi->a({-href => href(action=>"blob",
				                       hash_base=>"HEAD", file_name=>$file_name)},
				        "HEAD");
		} else {
			$formats_nav .=
				$cgi->a({-href => href(action=>"blob_plain", hash=>$hash)}, "raw");
		}
		git_print_page_nav('','', $hash_base,$co{'tree'},$hash_base, $formats_nav);
		git_print_header_div('commit', esc_html($co{'title'}), $hash_base);
	} else {
		print "<div class=\"page_nav\">\n" .
		      "<br/><br/></div>\n" .
		      "<div class=\"title\">$hash</div>\n";
	}
	git_print_page_path($file_name, "blob", $hash_base);
	print "<div class=\"page_body\">\n";
	my $nr;
	while (my $line = <$fd>) {
		chomp $line;
		$nr++;
		$line = untabify($line);
		printf "<div class=\"pre\"><a id=\"l%i\" href=\"#l%i\" class=\"linenr\">%4i</a> %s</div>\n",
		       $nr, $nr, $nr, esc_html($line);
	}
	close $fd
		or print "Reading blob failed.\n";
	print "</div>";
	git_footer_html();
}

sub git_tree {
	my $have_snapshot = gitweb_have_snapshot();

	if (!defined $hash_base) {
		$hash_base = "HEAD";
	}
	if (!defined $hash) {
		if (defined $file_name) {
			$hash = git_get_hash_by_path($hash_base, $file_name, "tree");
		} else {
			$hash = $hash_base;
		}
	}
	$/ = "\0";
	open my $fd, "-|", git_cmd(), "ls-tree", '-z', $hash
		or die_error(undef, "Open git-ls-tree failed");
	my @entries = map { chomp; $_ } <$fd>;
	close $fd or die_error(undef, "Reading tree failed");
	$/ = "\n";

	my $refs = git_get_references();
	my $ref = format_ref_marker($refs, $hash_base);
	git_header_html();
	my $basedir = '';
	my ($have_blame) = gitweb_check_feature('blame');
	if (defined $hash_base && (my %co = parse_commit($hash_base))) {
		my @views_nav = ();
		if (defined $file_name) {
			push @views_nav,
				$cgi->a({-href => href(action=>"history", hash_base=>$hash_base,
				                       hash=>$hash, file_name=>$file_name)},
				        "history"),
				$cgi->a({-href => href(action=>"tree",
				                       hash_base=>"HEAD", file_name=>$file_name)},
				        "HEAD"),
		}
		if ($have_snapshot) {
			# FIXME: Should be available when we have no hash base as well.
			push @views_nav,
				$cgi->a({-href => href(action=>"snapshot", hash=>$hash)},
				        "snapshot");
		}
		git_print_page_nav('tree','', $hash_base, undef, undef, join(' | ', @views_nav));
		git_print_header_div('commit', esc_html($co{'title'}) . $ref, $hash_base);
	} else {
		undef $hash_base;
		print "<div class=\"page_nav\">\n";
		print "<br/><br/></div>\n";
		print "<div class=\"title\">$hash</div>\n";
	}
	if (defined $file_name) {
		$basedir = $file_name;
		if ($basedir ne '' && substr($basedir, -1) ne '/') {
			$basedir .= '/';
		}
	}
	git_print_page_path($file_name, 'tree', $hash_base);
	print "<div class=\"page_body\">\n";
	print "<table cellspacing=\"0\">\n";
	my $alternate = 1;
	# '..' (top directory) link if possible
	if (defined $hash_base &&
	    defined $file_name && $file_name =~ m![^/]+$!) {
		if ($alternate) {
			print "<tr class=\"dark\">\n";
		} else {
			print "<tr class=\"light\">\n";
		}
		$alternate ^= 1;

		my $up = $file_name;
		$up =~ s!/?[^/]+$!!;
		undef $up unless $up;
		# based on git_print_tree_entry
		print '<td class="mode">' . mode_str('040000') . "</td>\n";
		print '<td class="list">';
		print $cgi->a({-href => href(action=>"tree", hash_base=>$hash_base,
		                             file_name=>$up)},
		              "..");
		print "</td>\n";
		print "<td class=\"link\"></td>\n";

		print "</tr>\n";
	}
	foreach my $line (@entries) {
		my %t = parse_ls_tree_line($line, -z => 1);

		if ($alternate) {
			print "<tr class=\"dark\">\n";
		} else {
			print "<tr class=\"light\">\n";
		}
		$alternate ^= 1;

		git_print_tree_entry(\%t, $basedir, $hash_base, $have_blame);

		print "</tr>\n";
	}
	print "</table>\n" .
	      "</div>";
	git_footer_html();
}

sub git_snapshot {
	my ($ctype, $suffix, $command) = gitweb_check_feature('snapshot');
	my $have_snapshot = (defined $ctype && defined $suffix);
	if (!$have_snapshot) {
		die_error('403 Permission denied', "Permission denied");
	}

	if (!defined $hash) {
		$hash = git_get_head_hash($project);
	}

	my $filename = basename($project) . "-$hash.tar.$suffix";

	print $cgi->header(
		-type => 'application/x-tar',
		-content_encoding => $ctype,
		-content_disposition => 'inline; filename="' . "$filename" . '"',
		-status => '200 OK');

	my $git = git_cmd_str();
	my $name = $project;
	$name =~ s/\047/\047\\\047\047/g;
	open my $fd, "-|",
	"$git archive --format=tar --prefix=\'$name\'/ $hash | $command"
		or die_error(undef, "Execute git-tar-tree failed.");
	binmode STDOUT, ':raw';
	print <$fd>;
	binmode STDOUT, ':utf8'; # as set at the beginning of gitweb.cgi
	close $fd;

}

sub git_log {
	my $head = git_get_head_hash($project);
	if (!defined $hash) {
		$hash = $head;
	}
	if (!defined $page) {
		$page = 0;
	}
	my $refs = git_get_references();

	my $limit = sprintf("--max-count=%i", (100 * ($page+1)));
	open my $fd, "-|", git_cmd(), "rev-list", $limit, $hash
		or die_error(undef, "Open git-rev-list failed");
	my @revlist = map { chomp; $_ } <$fd>;
	close $fd;

	my $paging_nav = format_paging_nav('log', $hash, $head, $page, $#revlist);

	git_header_html();
	git_print_page_nav('log','', $hash,undef,undef, $paging_nav);

	if (!@revlist) {
		my %co = parse_commit($hash);

		git_print_header_div('summary', $project);
		print "<div class=\"page_body\"> Last change $co{'age_string'}.<br/><br/></div>\n";
	}
	for (my $i = ($page * 100); $i <= $#revlist; $i++) {
		my $commit = $revlist[$i];
		my $ref = format_ref_marker($refs, $commit);
		my %co = parse_commit($commit);
		next if !%co;
		my %ad = parse_date($co{'author_epoch'});
		git_print_header_div('commit',
		               "<span class=\"age\">$co{'age_string'}</span>" .
		               esc_html($co{'title'}) . $ref,
		               $commit);
		print "<div class=\"title_text\">\n" .
		      "<div class=\"log_link\">\n" .
		      $cgi->a({-href => href(action=>"commit", hash=>$commit)}, "commit") .
		      " | " .
		      $cgi->a({-href => href(action=>"commitdiff", hash=>$commit)}, "commitdiff") .
		      " | " .
		      $cgi->a({-href => href(action=>"tree", hash=>$commit, hash_base=>$commit)}, "tree") .
		      "<br/>\n" .
		      "</div>\n" .
		      "<i>" . esc_html($co{'author_name'}) .  " [$ad{'rfc2822'}]</i><br/>\n" .
		      "</div>\n";

		print "<div class=\"log_body\">\n";
		git_print_log($co{'comment'}, -final_empty_line=> 1);
		print "</div>\n";
	}
	git_footer_html();
}

sub git_commit {
	my %co = parse_commit($hash);
	if (!%co) {
		die_error(undef, "Unknown commit object");
	}
	my %ad = parse_date($co{'author_epoch'}, $co{'author_tz'});
	my %cd = parse_date($co{'committer_epoch'}, $co{'committer_tz'});

	my $parent = $co{'parent'};
	if (!defined $parent) {
		$parent = "--root";
	}
	open my $fd, "-|", git_cmd(), "diff-tree", '-r', "--no-commit-id",
		@diff_opts, $parent, $hash
		or die_error(undef, "Open git-diff-tree failed");
	my @difftree = map { chomp; $_ } <$fd>;
	close $fd or die_error(undef, "Reading git-diff-tree failed");

	# non-textual hash id's can be cached
	my $expires;
	if ($hash =~ m/^[0-9a-fA-F]{40}$/) {
		$expires = "+1d";
	}
	my $refs = git_get_references();
	my $ref = format_ref_marker($refs, $co{'id'});

	my $have_snapshot = gitweb_have_snapshot();

	my @views_nav = ();
	if (defined $file_name && defined $co{'parent'}) {
		push @views_nav,
			$cgi->a({-href => href(action=>"blame", hash_parent=>$parent, file_name=>$file_name)},
			        "blame");
	}
	git_header_html(undef, $expires);
	git_print_page_nav('commit', '',
	                   $hash, $co{'tree'}, $hash,
	                   join (' | ', @views_nav));

	if (defined $co{'parent'}) {
		git_print_header_div('commitdiff', esc_html($co{'title'}) . $ref, $hash);
	} else {
		git_print_header_div('tree', esc_html($co{'title'}) . $ref, $co{'tree'}, $hash);
	}
	print "<div class=\"title_text\">\n" .
	      "<table cellspacing=\"0\">\n";
	print "<tr><td>author</td><td>" . esc_html($co{'author'}) . "</td></tr>\n".
	      "<tr>" .
	      "<td></td><td> $ad{'rfc2822'}";
	if ($ad{'hour_local'} < 6) {
		printf(" (<span class=\"atnight\">%02d:%02d</span> %s)",
		       $ad{'hour_local'}, $ad{'minute_local'}, $ad{'tz_local'});
	} else {
		printf(" (%02d:%02d %s)",
		       $ad{'hour_local'}, $ad{'minute_local'}, $ad{'tz_local'});
	}
	print "</td>" .
	      "</tr>\n";
	print "<tr><td>committer</td><td>" . esc_html($co{'committer'}) . "</td></tr>\n";
	print "<tr><td></td><td> $cd{'rfc2822'}" .
	      sprintf(" (%02d:%02d %s)", $cd{'hour_local'}, $cd{'minute_local'}, $cd{'tz_local'}) .
	      "</td></tr>\n";
	print "<tr><td>commit</td><td class=\"sha1\">$co{'id'}</td></tr>\n";
	print "<tr>" .
	      "<td>tree</td>" .
	      "<td class=\"sha1\">" .
	      $cgi->a({-href => href(action=>"tree", hash=>$co{'tree'}, hash_base=>$hash),
	               class => "list"}, $co{'tree'}) .
	      "</td>" .
	      "<td class=\"link\">" .
	      $cgi->a({-href => href(action=>"tree", hash=>$co{'tree'}, hash_base=>$hash)},
	              "tree");
	if ($have_snapshot) {
		print " | " .
		      $cgi->a({-href => href(action=>"snapshot", hash=>$hash)}, "snapshot");
	}
	print "</td>" .
	      "</tr>\n";
	my $parents = $co{'parents'};
	foreach my $par (@$parents) {
		print "<tr>" .
		      "<td>parent</td>" .
		      "<td class=\"sha1\">" .
		      $cgi->a({-href => href(action=>"commit", hash=>$par),
		               class => "list"}, $par) .
		      "</td>" .
		      "<td class=\"link\">" .
		      $cgi->a({-href => href(action=>"commit", hash=>$par)}, "commit") .
		      " | " .
		      $cgi->a({-href => href(action=>"commitdiff", hash=>$hash, hash_parent=>$par)}, "diff") .
		      "</td>" .
		      "</tr>\n";
	}
	print "</table>".
	      "</div>\n";

	print "<div class=\"page_body\">\n";
	git_print_log($co{'comment'});
	print "</div>\n";

	git_difftree_body(\@difftree, $hash, $parent);

	git_footer_html();
}

sub git_blobdiff {
	my $format = shift || 'html';

	my $fd;
	my @difftree;
	my %diffinfo;
	my $expires;

	# preparing $fd and %diffinfo for git_patchset_body
	# new style URI
	if (defined $hash_base && defined $hash_parent_base) {
		if (defined $file_name) {
			# read raw output
			open $fd, "-|", git_cmd(), "diff-tree", '-r', @diff_opts, $hash_parent_base, $hash_base,
				"--", $file_name
				or die_error(undef, "Open git-diff-tree failed");
			@difftree = map { chomp; $_ } <$fd>;
			close $fd
				or die_error(undef, "Reading git-diff-tree failed");
			@difftree
				or die_error('404 Not Found', "Blob diff not found");

		} elsif (defined $hash &&
		         $hash =~ /[0-9a-fA-F]{40}/) {
			# try to find filename from $hash

			# read filtered raw output
			open $fd, "-|", git_cmd(), "diff-tree", '-r', @diff_opts, $hash_parent_base, $hash_base
				or die_error(undef, "Open git-diff-tree failed");
			@difftree =
				# ':100644 100644 03b21826... 3b93d5e7... M	ls-files.c'
				# $hash == to_id
				grep { /^:[0-7]{6} [0-7]{6} [0-9a-fA-F]{40} $hash/ }
				map { chomp; $_ } <$fd>;
			close $fd
				or die_error(undef, "Reading git-diff-tree failed");
			@difftree
				or die_error('404 Not Found', "Blob diff not found");

		} else {
			die_error('404 Not Found', "Missing one of the blob diff parameters");
		}

		if (@difftree > 1) {
			die_error('404 Not Found', "Ambiguous blob diff specification");
		}

		%diffinfo = parse_difftree_raw_line($difftree[0]);
		$file_parent ||= $diffinfo{'from_file'} || $file_name || $diffinfo{'file'};
		$file_name   ||= $diffinfo{'to_file'}   || $diffinfo{'file'};

		$hash_parent ||= $diffinfo{'from_id'};
		$hash        ||= $diffinfo{'to_id'};

		# non-textual hash id's can be cached
		if ($hash_base =~ m/^[0-9a-fA-F]{40}$/ &&
		    $hash_parent_base =~ m/^[0-9a-fA-F]{40}$/) {
			$expires = '+1d';
		}

		# open patch output
		open $fd, "-|", git_cmd(), "diff-tree", '-r', @diff_opts,
			'-p', $hash_parent_base, $hash_base,
			"--", $file_name
			or die_error(undef, "Open git-diff-tree failed");
	}

	# old/legacy style URI
	if (!%diffinfo && # if new style URI failed
	    defined $hash && defined $hash_parent) {
		# fake git-diff-tree raw output
		$diffinfo{'from_mode'} = $diffinfo{'to_mode'} = "blob";
		$diffinfo{'from_id'} = $hash_parent;
		$diffinfo{'to_id'}   = $hash;
		if (defined $file_name) {
			if (defined $file_parent) {
				$diffinfo{'status'} = '2';
				$diffinfo{'from_file'} = $file_parent;
				$diffinfo{'to_file'}   = $file_name;
			} else { # assume not renamed
				$diffinfo{'status'} = '1';
				$diffinfo{'from_file'} = $file_name;
				$diffinfo{'to_file'}   = $file_name;
			}
		} else { # no filename given
			$diffinfo{'status'} = '2';
			$diffinfo{'from_file'} = $hash_parent;
			$diffinfo{'to_file'}   = $hash;
		}

		# non-textual hash id's can be cached
		if ($hash =~ m/^[0-9a-fA-F]{40}$/ &&
		    $hash_parent =~ m/^[0-9a-fA-F]{40}$/) {
			$expires = '+1d';
		}

		# open patch output
		open $fd, "-|", git_cmd(), "diff", '-p', @diff_opts, $hash_parent, $hash
			or die_error(undef, "Open git-diff failed");
	} else  {
		die_error('404 Not Found', "Missing one of the blob diff parameters")
			unless %diffinfo;
	}

	# header
	if ($format eq 'html') {
		my $formats_nav =
			$cgi->a({-href => href(action=>"blobdiff_plain",
			                       hash=>$hash, hash_parent=>$hash_parent,
			                       hash_base=>$hash_base, hash_parent_base=>$hash_parent_base,
			                       file_name=>$file_name, file_parent=>$file_parent)},
			        "raw");
		git_header_html(undef, $expires);
		if (defined $hash_base && (my %co = parse_commit($hash_base))) {
			git_print_page_nav('','', $hash_base,$co{'tree'},$hash_base, $formats_nav);
			git_print_header_div('commit', esc_html($co{'title'}), $hash_base);
		} else {
			print "<div class=\"page_nav\"><br/>$formats_nav<br/></div>\n";
			print "<div class=\"title\">$hash vs $hash_parent</div>\n";
		}
		if (defined $file_name) {
			git_print_page_path($file_name, "blob", $hash_base);
		} else {
			print "<div class=\"page_path\"></div>\n";
		}

	} elsif ($format eq 'plain') {
		print $cgi->header(
			-type => 'text/plain',
			-charset => 'utf-8',
			-expires => $expires,
			-content_disposition => 'inline; filename="' . "$file_name" . '.patch"');

		print "X-Git-Url: " . $cgi->self_url() . "\n\n";

	} else {
		die_error(undef, "Unknown blobdiff format");
	}

	# patch
	if ($format eq 'html') {
		print "<div class=\"page_body\">\n";

		git_patchset_body($fd, [ \%diffinfo ], $hash_base, $hash_parent_base);
		close $fd;

		print "</div>\n"; # class="page_body"
		git_footer_html();

	} else {
		while (my $line = <$fd>) {
			$line =~ s!a/($hash|$hash_parent)!'a/'.esc_path($diffinfo{'from_file'})!eg;
			$line =~ s!b/($hash|$hash_parent)!'b/'.esc_path($diffinfo{'to_file'})!eg;

			print $line;

			last if $line =~ m!^\+\+\+!;
		}
		local $/ = undef;
		print <$fd>;
		close $fd;
	}
}

sub git_blobdiff_plain {
	git_blobdiff('plain');
}

sub git_commitdiff {
	my $format = shift || 'html';
	my %co = parse_commit($hash);
	if (!%co) {
		die_error(undef, "Unknown commit object");
	}

	# we need to prepare $formats_nav before any parameter munging
	my $formats_nav;
	if ($format eq 'html') {
		$formats_nav =
			$cgi->a({-href => href(action=>"commitdiff_plain",
			                       hash=>$hash, hash_parent=>$hash_parent)},
			        "raw");

		if (defined $hash_parent) {
			# commitdiff with two commits given
			my $hash_parent_short = $hash_parent;
			if ($hash_parent =~ m/^[0-9a-fA-F]{40}$/) {
				$hash_parent_short = substr($hash_parent, 0, 7);
			}
			$formats_nav .=
				' (from: ' .
				$cgi->a({-href => href(action=>"commitdiff",
				                       hash=>$hash_parent)},
				        esc_html($hash_parent_short)) .
				')';
		} elsif (!$co{'parent'}) {
			# --root commitdiff
			$formats_nav .= ' (initial)';
		} elsif (scalar @{$co{'parents'}} == 1) {
			# single parent commit
			$formats_nav .=
				' (parent: ' .
				$cgi->a({-href => href(action=>"commitdiff",
				                       hash=>$co{'parent'})},
				        esc_html(substr($co{'parent'}, 0, 7))) .
				')';
		} else {
			# merge commit
			$formats_nav .=
				' (merge: ' .
				join(' ', map {
					$cgi->a({-href => href(action=>"commitdiff",
					                       hash=>$_)},
					        esc_html(substr($_, 0, 7)));
				} @{$co{'parents'}} ) .
				')';
		}
	}

	if (!defined $hash_parent) {
		$hash_parent = $co{'parent'} || '--root';
	}

	# read commitdiff
	my $fd;
	my @difftree;
	if ($format eq 'html') {
		open $fd, "-|", git_cmd(), "diff-tree", '-r', @diff_opts,
			"--no-commit-id",
			"--patch-with-raw", "--full-index", $hash_parent, $hash
			or die_error(undef, "Open git-diff-tree failed");

		while (chomp(my $line = <$fd>)) {
			# empty line ends raw part of diff-tree output
			last unless $line;
			push @difftree, $line;
		}

	} elsif ($format eq 'plain') {
		open $fd, "-|", git_cmd(), "diff-tree", '-r', @diff_opts,
			'-p', $hash_parent, $hash
			or die_error(undef, "Open git-diff-tree failed");

	} else {
		die_error(undef, "Unknown commitdiff format");
	}

	# non-textual hash id's can be cached
	my $expires;
	if ($hash =~ m/^[0-9a-fA-F]{40}$/) {
		$expires = "+1d";
	}

	# write commit message
	if ($format eq 'html') {
		my $refs = git_get_references();
		my $ref = format_ref_marker($refs, $co{'id'});

		git_header_html(undef, $expires);
		git_print_page_nav('commitdiff','', $hash,$co{'tree'},$hash, $formats_nav);
		git_print_header_div('commit', esc_html($co{'title'}) . $ref, $hash);
		git_print_authorship(\%co);
		print "<div class=\"page_body\">\n";
		if (@{$co{'comment'}} > 1) {
			print "<div class=\"log\">\n";
			git_print_log($co{'comment'}, -final_empty_line=> 1, -remove_title => 1);
			print "</div>\n"; # class="log"
		}

	} elsif ($format eq 'plain') {
		my $refs = git_get_references("tags");
		my $tagname = git_get_rev_name_tags($hash);
		my $filename = basename($project) . "-$hash.patch";

		print $cgi->header(
			-type => 'text/plain',
			-charset => 'utf-8',
			-expires => $expires,
			-content_disposition => 'inline; filename="' . "$filename" . '"');
		my %ad = parse_date($co{'author_epoch'}, $co{'author_tz'});
		print <<TEXT;
From: $co{'author'}
Date: $ad{'rfc2822'} ($ad{'tz_local'})
Subject: $co{'title'}
TEXT
		print "X-Git-Tag: $tagname\n" if $tagname;
		print "X-Git-Url: " . $cgi->self_url() . "\n\n";

		foreach my $line (@{$co{'comment'}}) {
			print "$line\n";
		}
		print "---\n\n";
	}

	# write patch
	if ($format eq 'html') {
		git_difftree_body(\@difftree, $hash, $hash_parent);
		print "<br/>\n";

		git_patchset_body($fd, \@difftree, $hash, $hash_parent);
		close $fd;
		print "</div>\n"; # class="page_body"
		git_footer_html();

	} elsif ($format eq 'plain') {
		local $/ = undef;
		print <$fd>;
		close $fd
			or print "Reading git-diff-tree failed\n";
	}
}

sub git_commitdiff_plain {
	git_commitdiff('plain');
}

sub git_history {
	if (!defined $hash_base) {
		$hash_base = git_get_head_hash($project);
	}
	if (!defined $page) {
		$page = 0;
	}
	my $ftype;
	my %co = parse_commit($hash_base);
	if (!%co) {
		die_error(undef, "Unknown commit object");
	}

	my $refs = git_get_references();
	my $limit = sprintf("--max-count=%i", (100 * ($page+1)));

	if (!defined $hash && defined $file_name) {
		$hash = git_get_hash_by_path($hash_base, $file_name);
	}
	if (defined $hash) {
		$ftype = git_get_type($hash);
	}

	open my $fd, "-|",
		git_cmd(), "rev-list", $limit, "--full-history", $hash_base, "--", $file_name
			or die_error(undef, "Open git-rev-list-failed");
	my @revlist = map { chomp; $_ } <$fd>;
	close $fd
		or die_error(undef, "Reading git-rev-list failed");

	my $paging_nav = '';
	if ($page > 0) {
		$paging_nav .=
			$cgi->a({-href => href(action=>"history", hash=>$hash, hash_base=>$hash_base,
			                       file_name=>$file_name)},
			        "first");
		$paging_nav .= " &sdot; " .
			$cgi->a({-href => href(action=>"history", hash=>$hash, hash_base=>$hash_base,
			                       file_name=>$file_name, page=>$page-1),
			         -accesskey => "p", -title => "Alt-p"}, "prev");
	} else {
		$paging_nav .= "first";
		$paging_nav .= " &sdot; prev";
	}
	if ($#revlist >= (100 * ($page+1)-1)) {
		$paging_nav .= " &sdot; " .
			$cgi->a({-href => href(action=>"history", hash=>$hash, hash_base=>$hash_base,
			                       file_name=>$file_name, page=>$page+1),
			         -accesskey => "n", -title => "Alt-n"}, "next");
	} else {
		$paging_nav .= " &sdot; next";
	}
	my $next_link = '';
	if ($#revlist >= (100 * ($page+1)-1)) {
		$next_link =
			$cgi->a({-href => href(action=>"history", hash=>$hash, hash_base=>$hash_base,
			                       file_name=>$file_name, page=>$page+1),
			         -title => "Alt-n"}, "next");
	}

	git_header_html();
	git_print_page_nav('history','', $hash_base,$co{'tree'},$hash_base, $paging_nav);
	git_print_header_div('commit', esc_html($co{'title'}), $hash_base);
	git_print_page_path($file_name, $ftype, $hash_base);

	git_history_body(\@revlist, ($page * 100), $#revlist,
	                 $refs, $hash_base, $ftype, $next_link);

	git_footer_html();
}

sub git_search {
	if (!defined $searchtext) {
		die_error(undef, "Text field empty");
	}
	if (!defined $hash) {
		$hash = git_get_head_hash($project);
	}
	my %co = parse_commit($hash);
	if (!%co) {
		die_error(undef, "Unknown commit object");
	}

	$searchtype ||= 'commit';
	if ($searchtype eq 'pickaxe') {
		# pickaxe may take all resources of your box and run for several minutes
		# with every query - so decide by yourself how public you make this feature
		my ($have_pickaxe) = gitweb_check_feature('pickaxe');
		if (!$have_pickaxe) {
			die_error('403 Permission denied', "Permission denied");
		}
	}

	git_header_html();
	git_print_page_nav('','', $hash,$co{'tree'},$hash);
	git_print_header_div('commit', esc_html($co{'title'}), $hash);

	print "<table cellspacing=\"0\">\n";
	my $alternate = 1;
	if ($searchtype eq 'commit' or $searchtype eq 'author' or $searchtype eq 'committer') {
		$/ = "\0";
		open my $fd, "-|", git_cmd(), "rev-list", "--header", "--parents", $hash or next;
		while (my $commit_text = <$fd>) {
			if (!grep m/$searchtext/i, $commit_text) {
				next;
			}
			if ($searchtype eq 'author' && !grep m/\nauthor .*$searchtext/i, $commit_text) {
				next;
			}
			if ($searchtype eq 'committer' && !grep m/\ncommitter .*$searchtext/i, $commit_text) {
				next;
			}
			my @commit_lines = split "\n", $commit_text;
			my %co = parse_commit(undef, \@commit_lines);
			if (!%co) {
				next;
			}
			if ($alternate) {
				print "<tr class=\"dark\">\n";
			} else {
				print "<tr class=\"light\">\n";
			}
			$alternate ^= 1;
			print "<td title=\"$co{'age_string_age'}\"><i>$co{'age_string_date'}</i></td>\n" .
			      "<td><i>" . esc_html(chop_str($co{'author_name'}, 15, 5)) . "</i></td>\n" .
			      "<td>" .
			      $cgi->a({-href => href(action=>"commit", hash=>$co{'id'}), -class => "list subject"},
			               esc_html(chop_str($co{'title'}, 50)) . "<br/>");
			my $comment = $co{'comment'};
			foreach my $line (@$comment) {
				if ($line =~ m/^(.*)($searchtext)(.*)$/i) {
					my $lead = esc_html($1) || "";
					$lead = chop_str($lead, 30, 10);
					my $match = esc_html($2) || "";
					my $trail = esc_html($3) || "";
					$trail = chop_str($trail, 30, 10);
					my $text = "$lead<span class=\"match\">$match</span>$trail";
					print chop_str($text, 80, 5) . "<br/>\n";
				}
			}
			print "</td>\n" .
			      "<td class=\"link\">" .
			      $cgi->a({-href => href(action=>"commit", hash=>$co{'id'})}, "commit") .
			      " | " .
			      $cgi->a({-href => href(action=>"tree", hash=>$co{'tree'}, hash_base=>$co{'id'})}, "tree");
			print "</td>\n" .
			      "</tr>\n";
		}
		close $fd;
	}

	if ($searchtype eq 'pickaxe') {
		$/ = "\n";
		my $git_command = git_cmd_str();
		open my $fd, "-|", "$git_command rev-list $hash | " .
			"$git_command diff-tree -r --stdin -S\'$searchtext\'";
		undef %co;
		my @files;
		while (my $line = <$fd>) {
			if (%co && $line =~ m/^:([0-7]{6}) ([0-7]{6}) ([0-9a-fA-F]{40}) ([0-9a-fA-F]{40}) (.)\t(.*)$/) {
				my %set;
				$set{'file'} = $6;
				$set{'from_id'} = $3;
				$set{'to_id'} = $4;
				$set{'id'} = $set{'to_id'};
				if ($set{'id'} =~ m/0{40}/) {
					$set{'id'} = $set{'from_id'};
				}
				if ($set{'id'} =~ m/0{40}/) {
					next;
				}
				push @files, \%set;
			} elsif ($line =~ m/^([0-9a-fA-F]{40})$/){
				if (%co) {
					if ($alternate) {
						print "<tr class=\"dark\">\n";
					} else {
						print "<tr class=\"light\">\n";
					}
					$alternate ^= 1;
					print "<td title=\"$co{'age_string_age'}\"><i>$co{'age_string_date'}</i></td>\n" .
					      "<td><i>" . esc_html(chop_str($co{'author_name'}, 15, 5)) . "</i></td>\n" .
					      "<td>" .
					      $cgi->a({-href => href(action=>"commit", hash=>$co{'id'}),
					              -class => "list subject"},
					              esc_html(chop_str($co{'title'}, 50)) . "<br/>");
					while (my $setref = shift @files) {
						my %set = %$setref;
						print $cgi->a({-href => href(action=>"blob", hash_base=>$co{'id'},
						                             hash=>$set{'id'}, file_name=>$set{'file'}),
						              -class => "list"},
						              "<span class=\"match\">" . esc_path($set{'file'}) . "</span>") .
						      "<br/>\n";
					}
					print "</td>\n" .
					      "<td class=\"link\">" .
					      $cgi->a({-href => href(action=>"commit", hash=>$co{'id'})}, "commit") .
					      " | " .
					      $cgi->a({-href => href(action=>"tree", hash=>$co{'tree'}, hash_base=>$co{'id'})}, "tree");
					print "</td>\n" .
					      "</tr>\n";
				}
				%co = parse_commit($1);
			}
		}
		close $fd;
	}
	print "</table>\n";
	git_footer_html();
}

sub git_search_help {
	git_header_html();
	git_print_page_nav('','', $hash,$hash,$hash);
	print <<EOT;
<dl>
<dt><b>commit</b></dt>
<dd>The commit messages and authorship information will be scanned for the given string.</dd>
<dt><b>author</b></dt>
<dd>Name and e-mail of the change author and date of birth of the patch will be scanned for the given string.</dd>
<dt><b>committer</b></dt>
<dd>Name and e-mail of the committer and date of commit will be scanned for the given string.</dd>
EOT
	my ($have_pickaxe) = gitweb_check_feature('pickaxe');
	if ($have_pickaxe) {
		print <<EOT;
<dt><b>pickaxe</b></dt>
<dd>All commits that caused the string to appear or disappear from any file (changes that
added, removed or "modified" the string) will be listed. This search can take a while and
takes a lot of strain on the server, so please use it wisely.</dd>
EOT
	}
	print "</dl>\n";
	git_footer_html();
}

sub git_shortlog {
	my $head = git_get_head_hash($project);
	if (!defined $hash) {
		$hash = $head;
	}
	if (!defined $page) {
		$page = 0;
	}
	my $refs = git_get_references();

	my $limit = sprintf("--max-count=%i", (100 * ($page+1)));
	open my $fd, "-|", git_cmd(), "rev-list", $limit, $hash
		or die_error(undef, "Open git-rev-list failed");
	my @revlist = map { chomp; $_ } <$fd>;
	close $fd;

	my $paging_nav = format_paging_nav('shortlog', $hash, $head, $page, $#revlist);
	my $next_link = '';
	if ($#revlist >= (100 * ($page+1)-1)) {
		$next_link =
			$cgi->a({-href => href(action=>"shortlog", hash=>$hash, page=>$page+1),
			         -title => "Alt-n"}, "next");
	}


	git_header_html();
	git_print_page_nav('shortlog','', $hash,$hash,$hash, $paging_nav);
	git_print_header_div('summary', $project);

	git_shortlog_body(\@revlist, ($page * 100), $#revlist, $refs, $next_link);

	git_footer_html();
}

## ......................................................................
## feeds (RSS, OPML)

sub git_rss {
	# http://www.notestips.com/80256B3A007F2692/1/NAMO5P9UPQ
	open my $fd, "-|", git_cmd(), "rev-list", "--max-count=150", git_get_head_hash($project)
		or die_error(undef, "Open git-rev-list failed");
	my @revlist = map { chomp; $_ } <$fd>;
	close $fd or die_error(undef, "Reading git-rev-list failed");
	print $cgi->header(-type => 'text/xml', -charset => 'utf-8');
	print <<XML;
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
<channel>
<title>$project $my_uri $my_url</title>
<link>${\esc_html("$my_url?p=$project;a=summary")}</link>
<description>$project log</description>
<language>en</language>
XML

	for (my $i = 0; $i <= $#revlist; $i++) {
		my $commit = $revlist[$i];
		my %co = parse_commit($commit);
		# we read 150, we always show 30 and the ones more recent than 48 hours
		if (($i >= 20) && ((time - $co{'committer_epoch'}) > 48*60*60)) {
			last;
		}
		my %cd = parse_date($co{'committer_epoch'});
		open $fd, "-|", git_cmd(), "diff-tree", '-r', @diff_opts,
			$co{'parent'}, $co{'id'}
			or next;
		my @difftree = map { chomp; $_ } <$fd>;
		close $fd
			or next;
		print "<item>\n" .
		      "<title>" .
		      sprintf("%d %s %02d:%02d", $cd{'mday'}, $cd{'month'}, $cd{'hour'}, $cd{'minute'}) . " - " . esc_html($co{'title'}) .
		      "</title>\n" .
		      "<author>" . esc_html($co{'author'}) . "</author>\n" .
		      "<pubDate>$cd{'rfc2822'}</pubDate>\n" .
		      "<guid isPermaLink=\"true\">" . esc_html("$my_url?p=$project;a=commit;h=$commit") . "</guid>\n" .
		      "<link>" . esc_html("$my_url?p=$project;a=commit;h=$commit") . "</link>\n" .
		      "<description>" . esc_html($co{'title'}) . "</description>\n" .
		      "<content:encoded>" .
		      "<![CDATA[\n";
		my $comment = $co{'comment'};
		foreach my $line (@$comment) {
			$line = to_utf8($line);
			print "$line<br/>\n";
		}
		print "<br/>\n";
		foreach my $line (@difftree) {
			if (!($line =~ m/^:([0-7]{6}) ([0-7]{6}) ([0-9a-fA-F]{40}) ([0-9a-fA-F]{40}) (.)([0-9]{0,3})\t(.*)$/)) {
				next;
			}
			my $file = esc_path(unquote($7));
			$file = to_utf8($file);
			print "$file<br/>\n";
		}
		print "]]>\n" .
		      "</content:encoded>\n" .
		      "</item>\n";
	}
	print "</channel></rss>";
}

sub git_opml {
	my @list = git_get_projects_list();

	print $cgi->header(-type => 'text/xml', -charset => 'utf-8');
	print <<XML;
<?xml version="1.0" encoding="utf-8"?>
<opml version="1.0">
<head>
  <title>$site_name OPML Export</title>
</head>
<body>
<outline text="git RSS feeds">
XML

	foreach my $pr (@list) {
		my %proj = %$pr;
		my $head = git_get_head_hash($proj{'path'});
		if (!defined $head) {
			next;
		}
		$git_dir = "$projectroot/$proj{'path'}";
		my %co = parse_commit($head);
		if (!%co) {
			next;
		}

		my $path = esc_html(chop_str($proj{'path'}, 25, 5));
		my $rss  = "$my_url?p=$proj{'path'};a=rss";
		my $html = "$my_url?p=$proj{'path'};a=summary";
		print "<outline type=\"rss\" text=\"$path\" title=\"$path\" xmlUrl=\"$rss\" htmlUrl=\"$html\"/>\n";
	}
	print <<XML;
</outline>
</body>
</opml>
XML
}
