#!/usr/bin/perl

use strict;
use warnings;
no warnings qw(once redefine);
use Test::More;
use FindBin;

# Load address selection without initializing Webmin or any host services.
do "$FindBin::Bin/../feature-web.pl" or die "$@ $!";
local *main::require_apache = sub { };
local %apache::httpd_modules = ( 'core' => 2.4 );
local *apache::find_directive_struct = sub { @{$_[1]} };
my ($ip, $ip6) = ('192.0.2.10', '2001:db8::10');
my ($other, $other6) = ('192.0.2.20', '2001:db8::20');
local *main::is_shared_ip = sub { $_[0] eq $ip || $_[0] eq $ip6 };
my $dual = { ip => $ip, ip6 => $ip6 };

# check_sequence(label, steps, [existing-addresses])
# Create successive hosts using real address detection and check every result.
# Each step contains a domain and its expected addresses without port suffixes.
sub check_sequence
{
my ($label, $steps, $existing) = @_;
subtest $label => sub {
	foreach my $port (80, 443) {
		my @conf = map { { words => [ map { "$_:$port" } @$_ ] } }
			@{$existing || []};
		foreach my $step (@$steps) {
			my ($d, $expected) = @$step;
			my $star4 = $d->{'ip'} ?
				main::add_name_virtual($d, \@conf, $port, 1, $d->{'ip'}) : undef;
			my $star6 = $d->{'ip6'} ?
				main::add_name_virtual($d, \@conf, $port, 1, $d->{'ip6'}) : undef;
			my $value = main::get_apache_vhost_ips($d, $star4, $star6, $port);
			is($value, join(' ', map { "$_:$port" } @$expected),
				'host '.(scalar(@conf) + 1)." on port $port");
			push(@conf, { words => [ split(/ /, $value) ] });
			}
		}
	};
}

# Empty configurations keep the wildcard default, including IPv6-only hosts.
check_sequence('shared dual-stack hosts', [ [ $dual, [ '*' ] ], [ $dual, [ '*' ] ] ]);
check_sequence('IPv4-only then dual-stack', [
	[ { ip => $ip }, [ '*' ] ], [ $dual, [ '*' ] ] ]);
check_sequence('IPv6-only then dual-stack', [
	[ { ip6 => $ip6 }, [ '*' ] ], [ $dual, [ '*' ] ] ]);

# Reproduce the reported first mixed host followed by the hostname site.
my $mixed = { ip => $ip, ip6 => $other6 };
check_sequence('non-shared IPv6 does not switch IPv4', [
	[ $mixed, [ '*', "[$other6]" ] ],
	[ $mixed, [ '*', "[$other6]" ] ], [ $dual, [ '*' ] ] ]);

# A later dedicated address must not move the other family out of its group.
check_sequence('shared hosts around a dedicated IPv6 host', [
	[ $dual, [ '*' ] ],
	[ { ip => $ip, ip6 => $other6, virt6 => 1 }, [ '*', "[$other6]" ] ],
	[ $dual, [ '*' ] ] ]);
check_sequence('shared hosts around a dedicated IPv4 host', [
	[ $dual, [ '*' ] ],
	[ { ip => $other, ip6 => $ip6, virt => 1 }, [ $other, '*' ] ],
	[ $dual, [ '*' ] ] ]);

# Existing explicit groups remain explicit, independently for each family.
check_sequence('explicit IPv4 with wildcard IPv6',
	[ [ $dual, [ $ip, '*' ] ], [ $dual, [ $ip, '*' ] ] ], [ [ $ip, '*' ] ]);
check_sequence('wildcard IPv4 with explicit IPv6',
	[ [ $dual, [ '*', "[$ip6]" ] ], [ $dual, [ '*', "[$ip6]" ] ] ],
	[ [ '*', "[$ip6]" ] ]);
check_sequence('both addresses explicit',
	[ [ $dual, [ $ip, "[$ip6]" ] ] ], [ [ $ip, "[$ip6]" ] ]);
check_sequence('both addresses dedicated',
	[ [ { %$dual, virt => 1, virt6 => 1 }, [ $ip, "[$ip6]" ] ] ]);

# Bindings on another port must not change this port's wildcard selection.
foreach my $port (80, 443) {
	my $conf = [ { words => [ "$ip:8080", "[$ip6]:8443" ] } ];
	my $star4 = main::add_name_virtual($dual, $conf, $port, 1, $ip);
	my $star6 = main::add_name_virtual($dual, $conf, $port, 1, $ip6);
	is(main::get_apache_vhost_ips($dual, $star4, $star6, $port), "*:$port",
		"other ports do not affect port $port");
	}

done_testing();
