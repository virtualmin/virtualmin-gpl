#!/usr/bin/perl

use strict;
use warnings;
no warnings qw(once redefine);
use Test::More;
use FindBin;

do "$FindBin::Bin/../dynip-lib.pl" or die "$@ $!";

my (@requests, @saved);
local %main::config;
local *main::has_command = sub { return undef; };
local *main::parse_http_url = sub {
	my ($url) = @_;
	$url =~ m!^https://([^/]+)(/.*)$! or die "Invalid test URL: $url";
	return ($1, 443, $2, 1);
	};
local *main::check_ipaddress = sub { return $_[0] eq '192.0.2.10'; };
local *main::check_ip6address = sub { return $_[0] eq '2001:db8::10'; };
local *main::save_module_config_keys = sub { push(@saved, { %{$_[0]} }); };
local *main::http_download = sub {
	my ($host, $dest, $error, $family) = @_[0, 3, 4, 14];
	push(@requests, [ $host, $family ]);
	$$dest = $family == 6 ? "2001:db8::10\n" : "192.0.2.10\n";
	$$error = undef;
	};

is(main::get_external_ip_address(1, 6), '2001:db8::10',
	'IPv6 lookup returns an IPv6 address');
is_deeply($requests[0], [ 'v6.download.virtualmin.com', 6 ],
	'IPv6 lookup forces the HTTP connection to use IPv6');

is(main::get_external_ip_address(1, 4), '192.0.2.10',
	'IPv4 lookup returns an IPv4 address');
is_deeply($requests[1], [ 'v4.download.virtualmin.com', 4 ],
	'IPv4 lookup forces the HTTP connection to use IPv4');

is(scalar(@saved), 2, 'both valid addresses are cached');

done_testing();
