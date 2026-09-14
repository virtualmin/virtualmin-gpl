#!/usr/bin/perl

use strict;
use warnings;
no warnings qw(once redefine);
use Test::More;
use FindBin;

do "$FindBin::Bin/../feature-ssl.pl" or die "$@ $!";

# Keep hostname selection real while recording resolver calls without networking.
sub check_names
{
my ($dns, $records, $resolved, $provider, $redirects) = @_;
my $d = { dom => 'example.test', web_port => 80, dns => $dns, mail => 1 };
my $site = {};
my @lookups;
local *main::domain_has_website = sub { $provider || 'web' };
local *main::get_apache_virtual = sub {
	return $site if $_[0] =~ /^(www\.|mail\.|admin\.)?example\.test$/;
	return undef;
	};
local *main::plugin_call = sub { main::get_apache_virtual($_[2]) };
local *main::get_webmail_redirect_directives = sub { @{$redirects || []} };
local *main::get_domain_dns_records = sub { @$records };
local *main::get_autoconfig_hostname = sub {
	return ('autoconfig.example.test', 'autodiscover.example.test');
	};
local *main::get_domain_by = sub { () };
local *main::unique = sub { my %seen; grep { !$seen{$_}++ } @_ };
local *main::to_ipaddress = sub {
	push(@lookups, $_[0]);
	return $resolved->{$_[0]};
	};
my @names = main::get_hostnames_for_ssl($d);
return (\@names, \@lookups);
}

my @records = map { { name => "${_}.example.test.", type => 'AAAA' } }
	qw(www mail admin);
my @expected = qw(example.test www.example.test mail.example.test admin.example.test);
foreach my $provider ('web', 'virtualmin-nginx') {
	subtest "Known records with $provider" => sub {
		my ($names, $lookups) = check_names(1, \@records, {}, $provider);
		is_deeply($names, \@expected, 'IPv6 records include every served hostname');
		is_deeply($lookups, [], 'known records need no resolver lookup');
		};
	}
subtest 'Names missing from the domain DNS records' => sub {
	my ($names, $lookups) = check_names(1, [ $records[0] ],
		{ 'mail.example.test' => '192.0.2.1' });
	is_deeply($names, [ @expected[0..2] ], 'resolver result supplements known records');
	is_deeply($lookups, [ @expected[2..3] ], 'only unknown names reach the resolver');
	};
subtest 'DNS not managed by Virtualmin' => sub {
	my ($names, $lookups) = check_names(0, \@records,
		{ 'mail.example.test' => '192.0.2.1' });
	is_deeply($names, [ @expected[0,2] ], 'unmanaged DNS keeps its existing behavior');
	is_deeply($lookups, [ @expected[1..3] ], 'all served names use the resolver');
	};
subtest 'Unconditional redirects' => sub {
	my ($names, $lookups) = check_names(1, \@records, {}, 'web',
		[ [ 'admin.example.test', '^(.*)' ] ]);
	is_deeply($names, [ @expected[0..2] ], 'redirected hostname remains excluded');
	is_deeply($lookups, [], 'redirects and known records require no lookup');
	};
done_testing();
