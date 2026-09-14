#!/usr/bin/perl

use strict;
use warnings;
no warnings qw(once redefine);
use Test::More;
use FindBin;

do "$FindBin::Bin/../feature-dns.pl" or die "$@ $!";

# Load the bundled suffix data without refreshing it over the network.
local $main::public_dns_suffix_file = "$FindBin::Bin/../public_suffix_list.dat";
local $main::public_dns_suffix_cache = $main::public_dns_suffix_file;
local @main::list_public_dns_suffixes_cache;
local @main::list_icann_dns_suffixes_cache;
local $main::list_public_dns_suffixes_loaded;
local %main::public_dns_suffix_rules_cache;
local *main::parse_http_url = sub { return ('example.test', 443, '/', 1) };
local *main::http_download = sub { };
local *main::read_file_lines = sub {
	open(my $fh, '<', $_[0]) or die "open $_[0]: $!";
	my @lines = <$fh>;
	close($fh);
	chomp(@lines);
	return \@lines;
	};

subtest 'Public suffix matching' => sub {
	is_deeply([ main::under_public_dns_suffix('example.com') ],
		[ 'example', 'com' ], 'direct domain matches its suffix');
	is_deeply([ main::under_public_dns_suffix('www.example.com') ],
		[ 'www.example', 'com' ], 'nested labels remain in the prefix');
	is_deeply([ main::under_public_dns_suffix('example.co.uk') ],
		[ 'example', 'co.uk' ], 'longest exact suffix wins');
	is_deeply([ main::under_public_dns_suffix('www.ck') ],
		[ 'www', 'ck' ], 'exception rule makes www.ck registrable');
	is_deeply([ main::under_public_dns_suffix('foo.www.ck') ],
		[ 'foo.www', 'ck' ], 'exception rule also applies to subdomains');
	is_deeply([ main::under_public_dns_suffix('foo.bar.ck') ],
		[ 'foo', 'bar.ck' ], 'wildcard label becomes part of the suffix');
	is_deeply([ main::under_public_dns_suffix('site.blogspot.com') ],
		[ 'site', 'blogspot.com' ], 'private suffix is used by default');
	is_deeply([ main::under_public_dns_suffix('site.blogspot.com', 1) ],
		[ 'site.blogspot', 'com' ], 'ICANN-only matching excludes private rules');
	is_deeply([ main::under_public_dns_suffix('example.invalid') ],
		[], 'unknown suffix does not match');

	is_deeply([ main::under_public_dns_suffix(
		'xn--e1afmkfd.xn--p1ai') ],
		[ 'xn--e1afmkfd', 'xn--p1ai' ],
		'Punycode suffix matches a Unicode rule and preserves its input form');
	is_deeply([ main::under_public_dns_suffix(
		'example.xn--vermgensberater-ctb') ],
		[ 'example', 'xn--vermgensberater-ctb' ],
		'Punycode with a Latin-1 character matches its UTF-8 rule');
	};

done_testing();
