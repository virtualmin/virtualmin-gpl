#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;

{
	no warnings 'once';
	$main::module_root_directory = "$FindBin::Bin/..";
}
do "$FindBin::Bin/../virtual-server-lib-funcs.pl"
	or die "Failed to load virtual-server-lib-funcs.pl: $@ $!";

# Run an atomic config update against an independently changed on-disk config
sub run_config_update
{
my ($local, $disk, $update) = @_;
my (@events, @saved);
my $result;

{
	no warnings qw(once redefine);
	local %main::config = %$local;
	local $main::module_config_file = '/tmp/virtualmin-config-test';
	local *main::lock_file = sub {
		push(@events, 'lock');
		return 1;
		};
	local *main::read_file = sub {
		push(@events, 'read');
		%{$_[1]} = %$disk;
		return 1;
		};
	local *main::save_module_config = sub {
		push(@events, 'save');
		push(@saved, { %{$_[0]} });
		};
	local *main::unlock_file = sub { push(@events, 'unlock'); };
	$result = $update->();
	%$local = %main::config;
	}

return ($result, \@events, \@saved);
}

subtest 'selected-key update preserves newer settings' => sub {
	my $local = {
		'wizard_run' => 0,
		'spam' => 1,
		'last_renewal' => 10,
		};
	my $disk = {
		'wizard_run' => 1,
		'spam' => 0,
		'last_renewal' => 10,
		};
	my ($result, $events, $saved) = run_config_update(
		$local, $disk,
		sub { &main::save_module_config_keys(
			{ 'last_renewal' => 20 }) });

	is_deeply($events, [ qw(lock read save unlock) ],
		'config is read and saved while locked');
	is_deeply($saved->[0], {
		'wizard_run' => 1,
		'spam' => 0,
		'last_renewal' => 20,
		}, 'only the requested key is merged into the latest config');
	is($local->{'last_renewal'}, 20,
		'updated key is reflected in the process-local config');
	is($local->{'wizard_run'}, 0,
		'unrelated process-local values are not silently changed');
	is($result, undef, 'keyed config update has a void return value');
	};

subtest 'unchanged update avoids an unnecessary write' => sub {
	my $local = { 'last_renewal' => 20 };
	my $disk = { 'last_renewal' => 20, 'wizard_run' => 1 };
	my ($result, $events, $saved) = run_config_update(
		$local, $disk,
		sub { &main::save_module_config_keys(
			{ 'last_renewal' => 20 }) });

	is_deeply($events, [ qw(lock read unlock) ],
		'no write is made when the selected value is current');
	is(scalar(@$saved), 0, 'module config was not saved');
	is($result, undef, 'unchanged keyed update has a void return value');
	};

subtest 'snapshot update merges only changes made by a long process' => sub {
	my $original = {
		'wizard_run' => 0,
		'spam' => 1,
		'checked' => 'old',
		'removed' => 1,
		};
	my $local = {
		'wizard_run' => 0,
		'spam' => 1,
		'checked' => 'new',
		'added' => 1,
		};
	my $disk = {
		'wizard_run' => 1,
		'spam' => 0,
		'checked' => 'old',
		'removed' => 1,
		'concurrent' => 1,
		};
	my ($result, $events, $saved) = run_config_update(
		$local, $disk,
		sub { &main::save_module_config_diff($original) });

	is_deeply($saved->[0], {
		'wizard_run' => 1,
		'spam' => 0,
		'checked' => 'new',
		'added' => 1,
		'concurrent' => 1,
		}, 'newer values survive while intended additions, changes and deletions apply');
	is_deeply($events, [ qw(lock read save unlock) ],
		'snapshot changes use the same locked merge');
	is($result, undef, 'snapshot config update has a void return value');
	};

subtest 'an existing process lock is retained' => sub {
	no warnings qw(once redefine);
	local %main::config = ( 'checked' => 'old' );
	local $main::module_config_file = '/tmp/virtualmin-config-test';
	my $saved;
	my $unlocks = 0;
	local *main::lock_file = sub { return 0; };
	local *main::test_lock = sub { return $$; };
	local *main::read_file = sub {
		%{$_[1]} = ( 'checked' => 'old', 'concurrent' => 1 );
		return 1;
		};
	local *main::save_module_config = sub { $saved = { %{$_[0]} }; };
	local *main::unlock_file = sub { $unlocks++ };

	my $result = &main::save_module_config_keys({ 'checked' => 'new' });
	is_deeply($saved, { 'checked' => 'new', 'concurrent' => 1 },
		'update succeeds while the caller owns the lock');
	is($unlocks, 0, 'helper does not release its caller lock');
	is($result, undef, 'caller-owned lock keeps the void return contract');
	};

subtest 'update stops when the lock was not acquired' => sub {
	no warnings qw(once redefine);
	local %main::config = ( 'checked' => 'old' );
	local $main::module_config_file = '/tmp/virtualmin-config-test';
	my $read = 0;
	local *main::lock_file = sub { return 0; };
	local *main::test_lock = sub { return $$ + 1; };
	local *main::read_file = sub { $read++; return 1; };

	my $result = &main::save_module_config_keys({ 'checked' => 'new' });
	ok(!defined($result), 'failed lock returns no config');
	is($read, 0, 'config is not accessed without a lock');
	is($main::config{'checked'}, 'old', 'process-local config is unchanged');
	};

# Execute the real provider save CGI body and capture its targeted write.
sub run_provider_save_cgi
{
my ($file, $kind, $list_name) = @_;
my @saved;
{
	no warnings qw(once redefine);
	no strict 'refs';
	local %main::in = (
		'name' => 'preprod',
		'useby_reseller' => 'resellers',
		'useby_owner' => 'owners',
		);
	local %main::config = ( 'sentinel' => 'keep' );
	local $INC{'./virtual-server-lib.pl'} = 1;
	local *main::ReadParse = sub { };
	local *main::licence_status = sub { };
	local *main::error_setup = sub { };
	local *main::can_cloud_providers = sub { return 1; };
	local *{"main::$list_name"} = sub {
		return ({ 'name' => 'preprod' });
		};
	local *{"main::${kind}_preprod_parse_inputs"} = sub {
		my ($request) = @_;
		is($request, \%main::in, "$kind CGI passes its request hash");
		is_deeply([ @main::config{"${kind}_preprod_owner",
					   "${kind}_preprod_reseller"} ],
			[ 'owners', 'resellers' ],
			"$kind parser sees the submitted access controls");
		return undef;
		};
	local *main::save_module_config_keys = sub {
		push(@saved, { %{$_[0]} });
		return undef;
		};
	local *main::webmin_log = sub { };
	local *main::redirect = sub { };
	local *main::error = sub { die $_[0]; };
	do "$main::module_root_directory/$file";
	die $@ if ($@);
	}
is_deeply(\@saved, [ {
	"${kind}_preprod_reseller" => 'resellers',
	"${kind}_preprod_owner" => 'owners',
	} ], "$kind CGI explicitly saves both access-control settings");
}

subtest 'cloud provider CGI saves access controls after validation' => sub {
	&run_provider_save_cgi('save_cloud.cgi', 'cloud',
		'list_cloud_providers');
	};

subtest 'DNS provider CGI saves access controls after validation' => sub {
	&run_provider_save_cgi('save_dnscloud.cgi', 'dnscloud',
		'list_dns_clouds');
	};

do "$main::module_root_directory/cloud-lib.pl"
	or die "Failed to load cloud-lib.pl: $@ $!";
do "$main::module_root_directory/dnscloud-lib.pl"
	or die "Failed to load dnscloud-lib.pl: $@ $!";

subtest 'cloud parsers use their passed request hashes' => sub {
	no warnings qw(once redefine);
	local *main::save_module_config_diff = sub { return undef; };
	local *main::error = sub { die $_[0]; };

	{
	local %main::config;
	local %main::in = ( 'rs_endpoint' => 'global', 'rs_snet' => 0 );
	my %request = (
		'rs_user_def' => 1,
		'rs_endpoint' => 'passed',
		'rs_snet' => 1,
		'rs_chunk_def' => 1,
		);
	&main::cloud_rs_parse_inputs(\%request);
	is($main::config{'rs_endpoint'}, 'passed',
		'Rackspace endpoint comes from the passed hash');
	is($main::config{'rs_snet'}, 1,
		'Rackspace network flag comes from the passed hash');
	}

	{
	local %main::config = ( 'dropbox_token' => 'existing-token' );
	local %main::in = ( 'dropbox_set_oauth' => 0 );
	my %request = (
		'dropbox_set_oauth' => 1,
		'dropbox_oauth' => 'passed-code',
		);
	&main::cloud_dropbox_parse_inputs(\%request);
	is($main::config{'dropbox_oauth'}, 'passed-code',
		'Dropbox mode comes from the passed hash');
	}

	{
	local %main::config;
	local %main::in = ( 'bb_keyid' => 'global', 'bb_key' => 'global' );
	local *main::run_bb_command = sub { return ('ok', undef); };
	my %request = ( 'bb_keyid' => 'passed/id', 'bb_key' => 'passed_key' );
	&main::cloud_bb_parse_inputs(\%request);
	is($main::config{'bb_keyid'}, 'passed/id',
		'Backblaze key ID comes from the passed hash');
	is($main::config{'bb_key'}, 'passed_key',
		'Backblaze key comes from the passed hash');
	}

	{
	local %main::config;
	local %main::in = ( 'azure_account' => 'global-invalid' );
	local *main::call_az_cmd = sub {
		my ($group, $args) = @_;
		return [ { 'user' => { 'name' => 'passed@example.com' } } ]
			if ($group eq 'account');
		return [ { 'name' => 'automatic',
			'id' => '/subscriptions/automatic-id/resource' } ]
			if ($args->[0] eq 'account');
		return [ ];
		};
	my %request = (
		'azure_account' => 'passed@example.com',
		'azure_name_def' => 0,
		'azure_name' => 'passedname',
		'azure_id_def' => 0,
		'azure_id' => 'passed-id',
		);
	&main::cloud_azure_parse_inputs(\%request);
	is($main::config{'azure_account'}, 'passed@example.com',
		'Azure account comes from the passed hash');
	is($main::config{'azure_name'}, 'passedname',
		'Azure storage name comes from the passed hash');
	is($main::config{'azure_id'}, 'passed-id',
		'Azure subscription ID comes from the passed hash');
	}

	{
	local %main::config = ( 'route53_dset' => 'old-set' );
	local %main::in = ( 'dset_def' => 0, 'dset' => 'global-set' );
	local %main::can_use_aws_cmd_cache;
	local *main::can_use_aws_route53_creds = sub { return 1; };
	local *main::can_use_aws_route53_cmd = sub { return (1, undef); };
	my %request = (
		'route53_location' => 'us-east-1',
		'route53_akey' => '',
		'route53_skey' => '',
		'dset_def' => 1,
		);
	&main::dnscloud_route53_parse_inputs(\%request);
	ok(!exists($main::config{'route53_dset'}),
		'Route 53 delegation choice comes from the passed hash');
	is($main::config{'route53_location'}, 'us-east-1',
		'Route 53 location comes from the passed hash');
	}
	};

done_testing();
