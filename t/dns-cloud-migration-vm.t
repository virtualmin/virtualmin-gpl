#!/usr/bin/perl

use strict;
use warnings;
no warnings qw(once redefine);
use Test::More;
use FindBin;
use Storable qw(dclone);

plan skip_all => 'Set VIRTUALMIN_DNS_VM_TEST=1 on a disposable Virtualmin Pro VM'
	unless $ENV{'VIRTUALMIN_DNS_VM_TEST'};

$ENV{'WEBMIN_CONFIG'} = '/etc/webmin';
$ENV{'WEBMIN_VAR'} = '/var/webmin';
open(my $mc, '<', '/etc/webmin/miniserv.conf') or die $!;
my ($root) = map { /^root=(.*)/ ? $1 : () } <$mc>;
close($mc);
chdir("$root/virtual-server") or die $!;
$0 = "$root/virtual-server/dns-cloud-migration-test.pl";
unshift(@INC, $root);
require WebminCore;
WebminCore->import();
init_config();
foreign_require('virtual-server');

# Load the candidate without replacing the VM's installed module.
my $source = "$FindBin::Bin/../feature-dns.pl";
{
	package virtual_server;
	do $source or die $@ || $!;
}

my $name = "codex-dns-migration-$$.invalid";
my ($created, $d);
END {
	# DNS-only fixtures have no Unix account, home directory or website.
	if ($created) {
		# Never let cleanup contact the real cloud API after a failed test.
		if ($d) {
			delete @{$d}{qw(dns_cloud dns_cloud_id dns_cloud_location alias)};
			virtual_server::save_domain($d);
			virtual_server::release_lock_dns($d);
			}
		run_cli('delete-domain', '--domain', $name);
		}
}
my ($status, $output) = run_cli('create-domain', '--domain', $name,
	'--pass', 'unused-dns-only-fixture', '--dns', '--cloud-dns', 'local',
	'--skip-warnings');
$created = !$status;
BAIL_OUT("Cannot create DNS fixture: $output") if $status;
virtual_server::flush_virtualmin_caches();
$d = virtual_server::get_domain_by('dom', $name);
BAIL_OUT('DNS fixture not found') unless $d;

my $get_template = \&virtual_server::get_template;
my $get_domain = \&virtual_server::get_domain;
my $template = { %{$get_template->($d->{'template'})},
	'dns_cloud' => 'cloudflare', 'dnssec' => 'no', 'dns_sub' => 'no' };
my ($cloud_records, $cloud_reads, $cloud_creates, $fail_create) = ([], 0, 0, 0);

{
	local *virtual_server::get_template = sub { return $template; };
	local *virtual_server::get_domain = sub {
		return { 'id' => 'test-alias-target', 'dom' => 'alias-target.invalid',
			'dns' => 1, 'dns_cloud' => 'cloudflare' }
			if $_[0] eq 'test-alias-target';
		return $get_domain->(@_);
		};
	local $virtual_server::first_print = sub { };
	local $virtual_server::second_print = sub { };

	# Simulate only the cloud provider. Zone files, migration, saving domains,
	# record parsing and local BIND configuration use the real implementation.
	local *virtual_server::dnscloud_cloudflare_check = sub { return undef; };
	local *virtual_server::dnscloud_cloudflare_get_state = sub { return { 'ok' => 1 }; };
	local *virtual_server::dnscloud_cloudflare_test = sub { return undef; };
	local *virtual_server::dnscloud_cloudflare_valid_domain = sub { return undef; };
	local *virtual_server::dnscloud_cloudflare_create_domain = sub {
		$cloud_creates++;
		return (0, 'simulated create failure') if $fail_create;
		$cloud_records = dclone($_[1]->{'recs'} || []);
		return (1, 'test-zone-id');
		};
	local *virtual_server::dnscloud_cloudflare_delete_domain = sub {
		$cloud_records = [];
		return (1, undef);
		};
	local *virtual_server::dnscloud_cloudflare_get_records = sub {
		$cloud_reads++;
		return (1, dclone($cloud_records));
		};
	local *virtual_server::dnscloud_cloudflare_put_records = sub {
		$cloud_records = dclone($_[1]->{'recs'});
		return (1, undef);
		};
	local *virtual_server::dnscloud_cloudflare_get_nameservers = sub { return []; };

	# Include a custom TXT record to detect migrations that silently replace
	# the old records with template defaults.
	my ($records, $file) = virtual_server::get_domain_dns_records_and_file($d);
	virtual_server::create_dns_record($records, $file, {
		'name' => "migration.$name.", 'type' => 'TXT', 'class' => 'IN',
		'ttl' => 300, 'values' => ['preserve-this-record'] });
	my $err = virtual_server::post_records_change($d, $records, $file);
	BAIL_OUT($err) if $err;
	my $expected = record_values($records);

	foreach my $alias (0, 1) {
		$template->{'dns_cloud'} = $alias ? 'local' : 'cloudflare';
		subtest $alias ? 'alias target cannot override local migration' :
			'Cloudflare template cannot override local migration' => sub {
			$d->{'alias'} = 'test-alias-target' if $alias;
			$d->{'aliasdns'} = 1 if $alias;
			is(virtual_server::modify_dns_cloud($d, 'cloudflare'), undef,
				'moves fixture records to the simulated cloud');
			is($d->{'dns_cloud'}, 'cloudflare', 'cloud provider selected');
			my $creates = $cloud_creates;
			is(virtual_server::modify_dns_cloud($d, 'local'), undef,
				'migration to local succeeds');
			is($cloud_creates, $creates, 'does not recreate the cloud zone');
			ok(!$d->{'dns_cloud'} && !$d->{'dns_cloud_id'},
				'cloud provider and zone ID are cleared');
			my $saved = $get_domain->($d->{'id'}, undef, 1);
			ok(!$saved->{'dns_cloud'}, 'local provider is saved to disk');

			$cloud_reads = 0;
			my ($recs, $zone) = virtual_server::get_domain_dns_records_and_file($saved, 1);
			my $local_zone = virtual_server::get_domain_dns_file_from_bind($saved);
			ok($zone && -f $zone && $local_zone && $zone eq $local_zone,
				'DNS Records reads the zone configured in local BIND');
			is($cloud_reads, 0, 'listing local records makes no cloud calls');
			is_deeply(record_values($recs), $expected, 'original records survive');
			system('named-checkzone', '-q', $name, $zone);
			is($? >> 8, 0, 'BIND accepts the migrated zone');
			};
		}

	# A failed migration must restore local DNS even with a cloud template.
	delete($d->{'alias'});
	delete($d->{'aliasdns'});
	$template->{'dns_cloud'} = 'cloudflare';
	$fail_create = 1;
	$err = virtual_server::modify_dns_cloud($d, 'cloudflare');
	like($err, qr/Failed to setup new DNS zone/, 'reports destination setup failure');
	ok(!$d->{'dns_cloud'}, 'rollback restores the original local provider');
	my ($recs, $zone) = virtual_server::get_domain_dns_records_and_file($d, 1);
	is_deeply(record_values($recs), $expected, 'rollback restores the original records');
	virtual_server::save_domain($d);
}

done_testing();

sub record_values
{
my ($records) = @_;
return [ sort map { join('|', $_->{'name'}, $_->{'type'}, @{$_->{'values'}}) }
	grep { $_->{'name'} && $_->{'type'} && $_->{'type'} !~ /^(SOA|NS)$/ }
	@$records ];
}

sub run_cli
{
open(my $fh, '-|', 'virtualmin', @_) or die $!;
my $output = do { local $/; <$fh> };
close($fh);
my $status = $? >> 8;
diag($output) if $status;
return ($status, $output);
}
