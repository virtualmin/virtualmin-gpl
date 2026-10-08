#!/usr/bin/perl

use strict;
use warnings;
no warnings qw(once redefine);
use Test::More;
use FindBin;
use Storable qw(dclone);

# Load only DNS functions; every system and provider operation is simulated.
do "$FindBin::Bin/../feature-dns.pl" or die $@ || $!;
my $delete_dns = \&main::delete_dns;
my ($template, $zone, $lookup_error, $read_error, $source, $destination);
my (@calls, $saved, $keep_dkim);
# get_template(id): Supply the current template instead of a saved default.
local *main::get_template = sub { return $template; };
# list_dns_clouds(): Limit provider discovery to the test fixture.
local *main::list_dns_clouds = sub {
	return ({ name => 'cloudflare', desc => 'Cloudflare DNS' });
	};
# text(key, [args...]): Keep error keys visible to assertions.
local *main::text = sub { return join(': ', @_); };
# dnscloud_cloudflare_check(): Assume provider dependencies are met.
local *main::dnscloud_cloudflare_check = sub { return undef; };
# dnscloud_cloudflare_get_state(): Make the simulated provider available.
local *main::dnscloud_cloudflare_get_state = sub { return { ok => 1 }; };
# dnscloud_cloudflare_test(): Avoid contacting Cloudflare for a health check.
local *main::dnscloud_cloudflare_test = sub { return undef; };
# dnscloud_cloudflare_valid_domain(&domain, &info): Accept the fixture name.
local *main::dnscloud_cloudflare_valid_domain = sub { return undef; };
# dnscloud_cloudflare_find_zone(&info): Record lookup and return test data.
local *main::dnscloud_cloudflare_find_zone = sub {
	push(@calls, 'lookup');
	return $lookup_error ? (0, $lookup_error) : (1, $zone);
	};
# dnscloud_cloudflare_get_records(&domain, &info): Track reads and failures.
local *main::dnscloud_cloudflare_get_records = sub {
	push(@calls, 'read-destination');
	return $read_error ? (0, $read_error) : (1, dclone($destination));
	};
# get_domain_dns_records(&domain): Return source records without sharing state.
local *main::get_domain_dns_records = sub { return @{dclone($source)}; };
# delete_dns(&domain): Capture the adoption flag without deleting real DNS.
local *main::delete_dns = sub {
	push(@calls, 'delete-source');
	$keep_dkim = delete($_[0]->{'dns_keep_dkim'});
	return 1;
	};
# setup_dns(&domain): Simulate a new zone so migration must copy records.
local *main::setup_dns = sub {
	push(@calls, 'setup');
	$_[0]->{'dns_cloud_id'} = 'created-zone';
	$destination = [];
	return 1;
	};
# get_domain_dns_records_and_file(&domain): Expose the simulated zone.
local *main::get_domain_dns_records_and_file = sub {
	return ($destination, 'simulated-file');
	};
# delete_dns_record(&records, file, &record): Remove one fixture record.
local *main::delete_dns_record = sub {
	my ($recs, $file, $r) = @_;
	@$recs = grep { $_ != $r } @$recs;
	};
# create_dns_record(&records, file, &record): Copy records into the fixture.
local *main::create_dns_record = sub { push(@{$_[0]}, dclone($_[2])); };
# post_records_change(&domain, &records, file): Detect destination writes.
local *main::post_records_change = sub { push(@calls, 'write-destination'); return undef; };
# clear_domain_dns_records_and_file(&domain): Track cache invalidation.
local *main::clear_domain_dns_records_and_file = sub { push(@calls, 'clear-cache'); };
# add_parent_ns_records(&domain): The fixture has no parent zone to update.
local *main::add_parent_ns_records = sub { };
# save_domain(&domain): Capture saved settings without writing files.
local *main::save_domain = sub { $saved = dclone($_[0]); };
# push_all_print(), set_all_capture_print(), pop_all_print():
# Suppress progress output in this isolated test.
local *main::push_all_print = sub { };
local *main::set_all_capture_print = sub { };
local *main::pop_all_print = sub { };
# obtain_lock_dns(&domain), release_lock_dns(&domain),
# reload_bind_records(&domain): In-memory zones need no locks or BIND reloads.
local *main::obtain_lock_dns = sub { };
local *main::release_lock_dns = sub { };
local *main::reload_bind_records = sub { };

# fixture(): Reset the providers and return a local domain with a stale default.
sub fixture
{
$template = { dns_cloud_import => 1 };
$zone = { id => 'existing-zone' };
$lookup_error = $read_error = undef;
$source = [{ name => 'example.com.', type => 'A', values => ['192.0.2.10'] }];
# Destination data intentionally differs from the source and has no A record.
$destination = [{ name => 'app.example.com.', type => 'CNAME', ttl => 300,
	values => ['external.example.net.'], proxied => 1, id => 'remote-record' }];
@calls = ();
$saved = $keep_dkim = undef;
return { dom => 'example.com', id => 123, template => 456, dns => 1,
	dns_cloud_import => 0 };
}

subtest 'takeover preserves existing destination data and uses the current template' => sub {
	for my $empty (0, 1) {
		my $d = fixture();
		# Preserve both empty and populated zones during adoption.
		$destination = [] if $empty;
		my $before = dclone($destination);
		is(modify_dns_cloud($d, 'cloudflare'), undef, 'switch succeeds');
		is($saved->{'dns_cloud'}, 'cloudflare', 'saves the destination provider');
		is($saved->{'dns_cloud_id'}, 'existing-zone', 'saves the existing zone ID');
		is_deeply($destination, $before, 'preserves all records and proxy settings');
		# Require reads before deletion and forbid setup or writes.
		is_deeply(\@calls, ['lookup', 'read-destination', 'delete-source', 'clear-cache'],
			'reads before deletion without writing destination records');
		ok($keep_dkim, 'does not schedule DKIM writes against the adopted zone');
		}
	};

subtest 'disabled takeover refuses a clash without changing either side' => sub {
	my $d = fixture();
	# A stale per-domain setting must not bypass the current template.
	$template->{'dns_cloud_import'} = 0;
	$d->{'dns_cloud_import'} = 1;
	my $before = dclone($d);
	like(modify_dns_cloud($d, 'cloudflare'), qr/setup_dnscloudclash/, 'reports existing zone');
	is_deeply($d, $before, 'leaves domain settings unchanged despite a stale saved default');
	is_deeply(\@calls, ['lookup'], 'does not delete or write either zone');
	ok(!$saved, 'does not save changed DNS hosting');
	};

subtest 'an explicit import option overrides the template' => sub {
	my $d = fixture();
	$template->{'dns_cloud_import'} = 0;
	is(modify_dns_cloud($d, 'cloudflare', undef, 1), undef, 'explicit import permits adoption');
	is($saved->{'dns_cloud_id'}, 'existing-zone', 'attaches the existing zone');
	# Explicit refusal must also override a template that allows adoption.
	$d = fixture();
	like(modify_dns_cloud($d, 'cloudflare', undef, 0), qr/setup_dnscloudclash/,
		'explicit refusal takes precedence over an enabled template');
	is_deeply(\@calls, ['lookup'], 'refusal leaves both zones unchanged');
	};

subtest 'API failures abort before removing local DNS' => sub {
	for my $failure ('lookup', 'records') {
		my $d = fixture();
		my $before = dclone($d);
		# Fail lookup and record access separately to test both exits.
		$lookup_error = 'Cloudflare lookup failed' if $failure eq 'lookup';
		$read_error = 'Cloudflare record read failed' if $failure eq 'records';
		like(modify_dns_cloud($d, 'cloudflare'), qr/Cloudflare .*failed/, 'returns API error');
		ok(!grep($_ eq 'delete-source', @calls), 'keeps the source zone');
		is_deeply($d, $before, 'does not change domain settings');
		ok(!$saved, 'does not save a broken provider association');
		}
	};

subtest 'new zones receive source records with either import setting' => sub {
	for my $import (0, 1) {
		my $d = fixture();
		$template->{'dns_cloud_import'} = $import;
		# Either import setting must allow creation of a missing zone.
		$zone = undef;
		is(modify_dns_cloud($d, 'cloudflare'), undef, 'migration succeeds');
		is_deeply($destination, $source, 'copies the original records');
		is($saved->{'dns_cloud_id'}, 'created-zone', 'saves the created zone');
		ok(grep($_ eq 'write-destination', @calls), 'uploads records to the new zone');
		ok(!$keep_dkim, 'new zones retain normal DKIM setup');
		}
	};

subtest 'source removal skips deferred DKIM writes only during adoption' => sub {
	# Exercise real delete_dns while replacing its external operations.
	my @actions;
	# require_bind(): No BIND module is needed for this cloud-only fixture.
	local *main::require_bind = sub { };
	# dnscloud_cloudflare_delete_domain(&domain, &info): Simulate success.
	local *main::dnscloud_cloudflare_delete_domain = sub { return (1); };
	# delete_parent_ns_records(&domain): There is no parent zone to modify.
	local *main::delete_parent_ns_records = sub { };
	# register_post_action(&function, [args...]): Capture deferred work.
	local *main::register_post_action = sub { push(@actions, [ @_ ]); };
	# first_print(message), second_print(message): Suppress progress output.
	local $main::first_print = sub { };
	local $main::second_print = sub { };
	for my $options ([0, 0], [0, 1], [1, 0]) {
		my ($adopting, $preserve) = @$options;
		@actions = ();
		my $d = { id => 123, dom => 'example.com', dns_cloud => 'cloudflare',
			dns_cloud_id => 'source-zone' };
		# Only adoption should suppress the later DKIM record update.
		$d->{'dns_keep_dkim'} = 1 if $adopting;
		# Domain deletion passes its preserve-files option as the second
		# argument. That option must not suppress ordinary DKIM cleanup.
		ok($delete_dns->($d, $preserve), 'removes the source zone');
		ok(!exists($d->{'dns_keep_dkim'}), 'consumes the temporary takeover flag');
		is(scalar(grep { $_->[0] eq \&main::sync_dkim_domain } @actions),
			$adopting ? 0 : 1, 'only ordinary deletion schedules DKIM updates');
		is(scalar(grep { $_->[0] eq \&main::restart_bind } @actions), 1,
			'keeps the scheduled DNS restart');
		}
	};

done_testing();
