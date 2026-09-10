#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Basename qw(dirname);
use File::Spec;
use Cwd qw(abs_path);

my $root = abs_path(File::Spec->catdir(dirname(__FILE__), '..'));
no warnings 'once';
$main::module_root_directory = $root;
$main::module_name = 'virtual-server';
my $lib = File::Spec->catfile($root, 'virtual-server-lib-funcs.pl');
my $loaded = do $lib;
die $@ if ($@);
die "Failed to load $lib: $!" if (!defined($loaded));

{
	no warnings 'redefine';
	local $main::mail_system = 0;
	local $main::first_print = sub { };
	local $main::second_print = sub { };
	local *main::require_mail = sub { };
	local *main::obtain_lock_mail = sub { };
	local *main::release_lock_mail = sub { };
	local *main::check_dkim = sub { return 'Not configured'; };
	local *main::check_postgrey = sub { return 'Not configured'; };
	local *main::can_install_postgrey = sub { return 0; };
	local *main::check_ratelimit = sub { return 'Not configured'; };
	local *main::can_install_ratelimit = sub { return 0; };
	local *main::read_file = sub { %{$_[1]} = (); };
	local *main::read_file_contents = sub { return "0\n"; };
	local *main::lock_file = sub { };
	local *main::unlock_file = sub { };
	local *main::unflush_file_lines = sub { };
	local %postfix::config = (
		'postfix_config_file' => '/fixture/main.cf',
		'postfix_master' => '/fixture/master.cf',
		);
	my (%settings, %backup);
	local *main::copy_source_dest = sub {
		%settings = %backup if ($_[0] eq '/backup/mailserver_maincf');
		};
	local *postfix::get_current_value = sub { return $settings{$_[0]}; };
	local *postfix::set_current_value = sub { $settings{$_[0]} = $_[1]; };

	# Exercise the complete mail restore helper with old backups that
	# omit the SASL path and backups from hosts using a different path.
	foreach my $case (
		[ '/etc/postfix/sasl', undef, '/etc/postfix/sasl',
		  'older backup cannot remove the destination SASL path' ],
		[ '/custom/sasl', '/source/sasl', '/custom/sasl',
		  'destination custom path takes precedence over the backup' ],
		[ '/etc/postfix/sasl', '', '/etc/postfix/sasl',
		  'an empty backup setting cannot clear the destination path' ],
		[ '$config_directory/sasl', undef, '$config_directory/sasl',
		  'Postfix variable references in the local path are preserved' ],
		[ undef, '/source/sasl', '/source/sasl',
		  'backup path is restored when no local path is configured' ],
		[ undef, undef, undef,
		  'no path is invented when both configurations omit it' ]) {
		my ($local, $saved, $expected, $description) = @$case;
		%settings = ( 'myhostname' => 'destination.example.invalid',
			     'alias_maps' => 'lmdb:/etc/aliases' );
		%backup = ( 'myhostname' => 'source.example.invalid',
			    'alias_maps' => 'hash:/etc/aliases' );
		$settings{'cyrus_sasl_config_path'} = $local if (defined($local));
		$backup{'cyrus_sasl_config_path'} = $saved if (defined($saved));
		ok(&virtualmin_restore_mailserver('/backup/mailserver', []),
			'mail settings restore succeeds');
		is($settings{'cyrus_sasl_config_path'}, $expected, $description);
		is($settings{'alias_maps'}, 'lmdb:/etc/aliases',
			'other destination-specific settings are still preserved');
		is($settings{'myhostname'}, 'source.example.invalid',
			'ordinary mail settings are restored from the backup');
		}
	}

done_testing();
