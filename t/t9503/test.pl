#!/usr/bin/perl

use lib (split(/:/, $ENV{GITPERLLIB}));

use warnings;
use strict;

use Cwd qw(abs_path);
use File::Spec;
use XML::Parser;
use Test::More qw(no_plan);
use Test::WWW::Mechanize::CGI;

eval { require HTML::Lint; };
my $lint_installed = !$@;
diag('HTML::Lint is not installed; no HTML validation tests')
	unless $lint_installed;

eval { require XML::Parser; };
my $xml_parser_installed = !$@;
diag('XML::Parser is not installed; no tests for well-formed XML')
	unless $xml_parser_installed;


my $gitweb = File::Spec->catfile('..','..','gitweb','gitweb.perl');
# the followin two lines of code are workaround for bug in
# Test::WWW::Mechanize::CGI::cgi_application version up to 0.3
# (http://rt.cpan.org/Ticket/Display.html?id=36654)
# for pathnames with spaces (because of "trash directory")
$gitweb = File::Spec->rel2abs($gitweb);
$gitweb = Cwd::abs_path($gitweb);

my $mech = new Test::WWW::Mechanize::CGI;
$mech->env(
	GITWEB_CONFIG => $ENV{'GITWEB_CONFIG'},
);
$mech->cgi_application($gitweb);

my $xml_parser;
if ($xml_parser_installed) {
	$xml_parser = new XML::Parser;
}

# import config, predeclaring config variables
our $site_name = '';
require_ok($ENV{'GITWEB_CONFIG'})
	or diag('Could not load gitweb config; some tests would fail');

my $pagename = '';
my $get_ok;
SKIP: {
	$pagename = 'project list (implicit)';
	skip "Could not get $pagename", 2 + $lint_installed
		unless $mech->get_ok('http://localhost/', "GET $pagename");
	$mech->html_lint_ok('page validates') if $lint_installed;
	$mech->title_like(qr!$site_name!,
		"title contains $site_name");
	$mech->content_contains('./t9503-gitweb-Mechanize.sh test repository', 
		'lists test repository (by description)');
}

$mech->get_ok('http://localhost/?p=.git',
	'GET test repository summary (implicit)');
$mech->get_ok('http://localhost/.git',
	'GET test repository summary (implicit, pathinfo)');
$get_ok = 0;
SKIP: {
	$pagename = 'test repository summary (explicit)';
	$get_ok = $mech->get_ok('http://localhost/?p=.git;a=summary',
		"GET $pagename");
	skip "Could not get $pagename", 1 + $lint_installed
		unless $get_ok;
	$mech->html_lint_ok('page validates') if $lint_installed;
	$mech->title_like(qr!$site_name.*\.git/summary!,
		'title contains $site_name and ".git/summary"');
}

SKIP: {
	skip "Could not get starting page $pagename", 2 + $lint_installed
		unless $get_ok;
	$pagename = 'search test repository (from search form)';
	$get_ok = $mech->submit_form_ok(
		{form_number=>1,
		 fields=> {'s' => 'Initial commit'}
		},
		"submit search form (default)");
	skip "Could not submit search form", 1 + $lint_installed
		unless $get_ok;
	$mech->html_lint_ok('page validates') if $lint_installed;
	$mech->content_contains('Initial commit',
		'content contains searched text');
}

$pagename = 'non existent project';
$mech->get('http://localhost/?p=non-existent.git');
like($mech->status, qr/40[0-9]/, "40x status response for $pagename");
$mech->html_lint_ok('page validates') if $lint_installed;

$pagename = 'non existent commit';
$mech->get('http://localhost/?p=.git;a=commit;h=non-existent');
like($mech->status, qr/40[0-9]/, "40x status response for $pagename");
$mech->html_lint_ok('page validates') if $lint_installed;

$pagename = 'HEAD commit in non existent repository';
$mech->get('http://localhost/?p=non-existent.git;a=commit;h=HEAD');
like($mech->status, qr/40[0-9]/, "40x status response for $pagename");
$mech->html_lint_ok('page validates') if $lint_installed;

SKIP: {
	$pagename = 'test repository RSS feed (default)';
	$get_ok = $mech->get_ok('http://localhost/?p=.git;a=rss',
		"GET $pagename");
	skip "Could not get $pagename", 0 + $xml_parser_installed
		unless $get_ok;

	if ($xml_parser_installed) {
		eval {
			$xml_parser->parse($mech->content());
		};
		ok(! $@, "$pagename is well formed XML")
			or diag($@);
	}
}

SKIP: {
	$pagename = 'test repository Atom feed (default)';
	$get_ok = $mech->get_ok('http://localhost/?p=.git;a=atom',
		"GET $pagename");
	skip "Could not get $pagename", 0 + $xml_parser_installed
		unless $get_ok;

	if ($xml_parser_installed) {
		eval {
			$xml_parser->parse($mech->content());
		};
		ok(! $@, "$pagename is well formed XML")
			or diag($@);
	}
}

SKIP: {
	$pagename = 'list of repositories in OPML format';
	$get_ok = $mech->get_ok('http://localhost/?a=opml',
		"GET $pagename");
	skip "Could not get $pagename", 0 + $xml_parser_installed
		unless $get_ok;

	if ($xml_parser_installed) {
		eval {
			$xml_parser->parse($mech->content());
		};
		ok(! $@, "$pagename is well formed XML")
			or diag($@);
	}
}

1;
__END__
