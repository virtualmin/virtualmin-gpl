#!/usr/bin/perl

use strict;
use warnings;
no warnings qw(once redefine);
use Test::More;
use File::Basename qw(dirname);
use File::Spec;
use File::Temp qw(tempdir);
use Cwd qw(abs_path);

our $module_root_directory = abs_path(
	File::Spec->catdir(dirname(__FILE__), '..'));
foreach my $file ('virtual-server-lib-funcs.pl', 'feature-mysql.pl',
		  'feature-postgres.pl') {
	my $path = File::Spec->catfile($module_root_directory, $file);
	my $loaded = do $path;
	die $@ if ($@);
	die "Failed to load $path: $!" if (!defined($loaded));
	}

# Use the real English labels so titles and row order can be checked.
open(my $lang, '<', File::Spec->catfile($module_root_directory, 'lang', 'en'))
	|| die "lang/en: $!";
while (my $line = <$lang>) {
	$main::text{$1} = $2 if ($line =~ /^([^=]+)=(.*)$/);
	}
close($lang);

# Describe each database type as enabled, installed or both.
my %enabled;
my %installed;
my @required;
our (%config, %isfeature, @template_features, @plugins, %in);
local @template_features = ( 'mysql', 'postgres' );
local %isfeature = ( 'mysql' => 1, 'postgres' => 1 );
local @plugins = ( );
local *main::check_module_mysql = sub { return $installed{'mysql'}; };
local *main::check_module_postgres = sub { return $installed{'postgres'}; };
local *main::require_mysql = sub { push(@required, 'mysql'); };
local *main::require_postgres = sub { push(@required, 'postgres'); };
local *main::get_dom_remote_mysql_version = sub { return '8.0.36'; };
local *main::list_mysql_character_sets = sub {
	return ( [ 'utf8mb4', 'UTF-8' ] );
	};
local *main::list_mysql_collation_orders = sub {
	return ( [ 'utf8mb4_bin' ] );
	};
local *main::list_postgres_encodings = sub { return ( 'UTF8' ); };
$mysql::config{'mysql_data'} = tempdir(CLEANUP => 1);

# Render rows as their labels, and separators as HR.
local *main::hlink = sub { return $_[0]; };
local *main::ui_table_row = sub { return "ROW $_[0]\n"; };
local *main::ui_table_hr = sub { return "HR\n"; };
local *main::ui_radio = sub { return ''; };
local *main::ui_select = sub { return ''; };
local *main::ui_textbox = sub { return ''; };
local *main::none_def_input = sub { return ''; };
local *main::parse_none_def = sub { return $in{$_[0]}; };
local *main::error = sub { die "error: $_[0]\n"; };

# set_databases(mysql-state, postgres-state)
# Each state is enabled, installed or both. Anything else turns it off.
sub set_databases
{
my %state = ( 'mysql' => $_[0], 'postgres' => $_[1] );
foreach my $type (keys %state) {
	$enabled{$type} = $state{$type} =~ /^(enabled|both)$/ ? 1 : 0;
	$installed{$type} = $state{$type} =~ /^(installed|both)$/ ? 1 : 0;
	$config{$type} = $enabled{$type};
	}
@required = ( );
}

# Return the template sections shown for the current databases.
sub sections
{
# The function collects sections in a package array, and CGI scripts call it
# once per process. Clear it so repeated calls here start empty.
@main::rv = ( );
return map { "$_->[0]: $_->[1]" } &list_template_editmodes({ 'id' => 0 });
}

# Return the printed form for a template, one row label or HR per line.
sub form_lines
{
my ($tmpl) = @_;
my $out = '';
open(my $fh, '>', \$out) || die $!;
my $old = select($fh);
&show_template_mysql($tmpl);
select($old);
close($fh);
return map { s/^ROW //r } split(/\n/, $out);
}

my $title = "mysql: $main::text{'tmpl_editmode_mysql'}";
my @shared = map { $main::text{$_} }
	qw(tmpl_mysql tmpl_mysql_suffix tmpl_mysql_mkdb tmpl_mysql_nouser
	   tmpl_mysql_nopass2);
my @mysql_only = map { $main::text{$_} }
	qw(tmpl_mysql_hosts tmpl_mysql_chgrp tmpl_mysql_charset
	   tmpl_mysql_collate tmpl_mysql_conns tmpl_mysql_uconns);
my @postgres_only = ( $main::text{'tmpl_postgres_encoding'} );

# One database section is shown when either database can be used.
is($main::text{'tmpl_editmode_mysql'}, 'Databases for domain',
	'section has a database title');
set_databases('both', 'both');
is_deeply([ sections() ], [ $title ], 'both databases share one section');
set_databases('none', 'both');
is_deeply([ sections() ], [ $title ],
	  'PostgreSQL-only systems get the section');
set_databases('both', 'none');
is_deeply([ sections() ], [ $title ], 'MySQL-only systems get the section');
set_databases('none', 'none');
is_deeply([ sections() ], [ ], 'no section without any database');
set_databases('enabled', 'installed');
is_deeply([ sections() ], [ ], 'a database must be enabled and installed');

# Shared rows come first, then each enabled database after a separator.
set_databases('both', 'both');
is_deeply([ form_lines({ }) ],
	  [ @shared, 'HR', @mysql_only, 'HR', @postgres_only ],
	  'both databases show shared, MySQL and PostgreSQL groups');
set_databases('none', 'both');
is_deeply([ form_lines({ }) ], [ @shared, 'HR', @postgres_only ],
	  'PostgreSQL-only form has no MySQL group or separator');
is_deeply(\@required, [ 'postgres' ], 'MySQL is not loaded when it is off');
set_databases('both', 'none');
is_deeply([ form_lines({ }) ], [ @shared, 'HR', @mysql_only ],
	  'MySQL-only form has no PostgreSQL group or separator');
is_deeply(\@required, [ 'mysql' ], 'PostgreSQL is not loaded when it is off');
is_deeply([ grep { $_ eq $main::text{'tmpl_mysql_nopass2'} }
		 form_lines({ 'hashpass' => 1 }) ], [ ],
	  'password row stays hidden for hashed passwords');

# Saving keeps settings for databases that were not shown.
my %saved = ( 'mysql_hosts' => '%.example.com', 'mysql_conns' => 5,
	      'mysql_charset' => 'latin1', 'postgres_encoding' => 'LATIN1' );
local %in = ( 'mysql_mode' => 1, 'mysql_suffix_mode' => 1,
	      'mysql_mkdb' => 0, 'mysql_nopass' => 2, 'mysql_nouser' => 1,
	      'mysql_hosts_mode' => 2, 'mysql_hosts' => 'db.example.com',
	      'mysql_conns_mode' => 1, 'mysql_uconns_mode' => 1,
	      'mysql_charset' => 'utf8mb4', 'mysql_collate' => 'utf8mb4_bin',
	      'postgres_encoding' => 'UTF8' );
set_databases('none', 'both');
my $tmpl = { %saved };
&parse_template_mysql($tmpl);
is($tmpl->{'mysql_nopass'}, 2, 'shared password option saved without MySQL');
is($tmpl->{'mysql_mkdb'}, 0, 'shared initial database option saved');
is($tmpl->{'postgres_encoding'}, 'UTF8', 'PostgreSQL encoding saved');
is_deeply([ @$tmpl{qw(mysql_hosts mysql_conns mysql_charset)} ],
	  [ @saved{qw(mysql_hosts mysql_conns mysql_charset)} ],
	  'hidden MySQL settings are kept');
set_databases('both', 'none');
$tmpl = { %saved };
&parse_template_mysql($tmpl);
is($tmpl->{'mysql_hosts'}, 'db.example.com', 'MySQL hosts saved');
is($tmpl->{'mysql_charset'}, 'utf8mb4', 'MySQL character set saved');
is($tmpl->{'postgres_encoding'}, 'LATIN1',
	'hidden PostgreSQL encoding is kept');

# A page opened before the upgrade has no encoding field, so saving it must
# keep the stored encoding. An empty choice still means the default.
set_databases('both', 'both');
my %stale = %in;
delete($stale{'postgres_encoding'});
{
	local %in = %stale;
	$tmpl = { %saved };
	&parse_template_mysql($tmpl);
	is($tmpl->{'postgres_encoding'}, 'LATIN1',
		'page without the encoding field keeps the encoding');
}
{
	local %in = ( %stale, 'postgres_encoding' => '' );
	$tmpl = { %saved };
	&parse_template_mysql($tmpl);
	is($tmpl->{'postgres_encoding'}, '',
		'empty encoding is saved to use the default');
}

done_testing();
