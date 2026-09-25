#!/usr/bin/perl

use strict;
use warnings;
no warnings qw(once redefine);
use Test::More;
use FindBin;

do "$FindBin::Bin/../feature-dns.pl" or die "$@ $!";
do "$FindBin::Bin/../collect-lib.pl" or die "$@ $!";

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

# Run a refresh against an in-memory domain and record lock boundaries around
# the simulated WHOIS request.
sub run_whois_refresh
{
my ($listed, $stored, $suffix, $during_lookup) = @_;
my (@events, @saved);
my $locked = 0;
local *main::under_public_dns_suffix = sub {
	push(@events, 'suffix');
	return @$suffix;
	};
local *main::lock_domain = sub { push(@events, 'lock'); $locked = 1; };
local *main::unlock_domain = sub { push(@events, 'unlock'); $locked = 0; };
local *main::get_domain = sub {
	push(@events, 'read');
	return $stored ? { %$stored } : undef;
	};
local *main::get_whois_expiry = sub {
	push(@events, 'whois');
	ok(!$locked, 'WHOIS runs without the domain lock');
	&$during_lookup($stored) if ($during_lookup);
	return (123456, undef);
	};
local *main::save_domain = sub {
	push(@events, 'save');
	%$stored = %{$_[0]};
	push(@saved, { %{$_[0]} });
	};
my $result = main::collect_domain_whois($listed, 1000);
return ($result, \@events, \@saved);
}

subtest 'WHOIS lock scope' => sub {
	my $domain = { 'id' => 1, 'dom' => 'example.com' };
	my ($result, $events) = run_whois_refresh(
		{ %$domain }, $domain, [ 'example', 'com' ]);
	ok($result, 'eligible domain is queried');
	is_deeply($events,
		[ 'suffix', 'lock', 'read', 'unlock', 'whois', 'lock',
		  'read', 'save', 'unlock' ],
		'domain lock covers only reads and writes');
	is($domain->{'whois_expiry'}, 123456, 'expiry result is saved');
	is($domain->{'whois_last'}, 1000, 'lookup time is saved');
	ok($domain->{'whois_next'} > 1000, 'next lookup is scheduled');
	};

subtest 'Ineligible domain cache cleanup' => sub {
	my $domain = {
		'id' => 2,
		'dom' => 'sub.example.com',
		'whois_next' => 5,
		'whois_last' => 4,
		'whois_err' => 'old error',
		'whois_expiry' => 3,
		'keep' => 1,
		};
	my ($result, $events) = run_whois_refresh(
		{ %$domain }, $domain, [ 'sub.example', 'com' ]);
	ok(!$result, 'nested domain is not queried');
	is_deeply($events, [ 'suffix', 'lock', 'read', 'save', 'unlock' ],
		'stale cache is removed under a short lock');
	ok(!grep({ exists($domain->{$_}) }
		('whois_next', 'whois_last', 'whois_err', 'whois_expiry')),
		'old WHOIS fields are removed');
	is($domain->{'keep'}, 1, 'unrelated domain data is preserved');

	my $clean = { 'id' => 5, 'dom' => 'sub.example.com' };
	($result, $events) = run_whois_refresh(
		{ %$clean }, $clean, [ 'sub.example', 'com' ]);
	ok(!$result, 'clean nested domain is not queried');
	is_deeply($events, [ 'suffix' ],
		'clean nested domain is skipped before locking');
	};

subtest 'Concurrent domain changes' => sub {
	my $renamed = { 'id' => 3, 'dom' => 'example.com' };
	my ($result, $events) = run_whois_refresh(
		{ %$renamed }, $renamed, [ 'example', 'com' ],
		sub { $_[0]->{'dom'} = 'renamed.com' });
	ok($result, 'lookup completed before the rename was observed');
	ok(!exists($renamed->{'whois_expiry'}),
		'result for the old name is discarded');
	ok(!grep({ $_ eq 'save' } @$events), 'renamed domain is not overwritten');

	my $refreshed = { 'id' => 4, 'dom' => 'example.com' };
	($result, $events) = run_whois_refresh(
		{ %$refreshed }, $refreshed, [ 'example', 'com' ],
		sub {
			$_[0]->{'whois_last'} = 999;
			$_[0]->{'whois_expiry'} = 654321;
			});
	ok($result, 'overlapping lookup completed');
	is($refreshed->{'whois_expiry'}, 654321,
		'newer WHOIS result is preserved');
	ok(!grep({ $_ eq 'save' } @$events), 'newer cache is not overwritten');
	};

done_testing();
