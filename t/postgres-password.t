#!/usr/bin/perl

use strict;
use warnings;
no warnings qw(once redefine);
use Test::More;
use File::Basename qw(dirname);
use File::Spec;
use Cwd qw(abs_path);

my $root = abs_path(File::Spec->catdir(dirname(__FILE__), '..'));
my $feature = File::Spec->catfile($root, 'feature-postgres.pl');
my $loaded = do $feature;
die $@ if ($@);
die "Failed to load $feature: $!" if (!defined($loaded));

# Look up parents and the server version without loading Webmin.
my %doms = (
	1 => { 'id' => 1, 'pass' => "parent'pass" },
	2 => { 'id' => 2, 'pass' => 'domain-pass',
	       'postgres_pass' => "db'pass" },
	);
local *main::get_domain = sub { return $doms{$_[0]}; };
local *main::require_postgres = sub { };
local *main::get_dom_remote_postgres_version = sub { return '16.4'; };

# Top-level domains quote their own password for SQL unless asked not to.
my $top = $doms{1};
is(main::postgres_pass($top), "'parent''pass'",
	'top-level password is quoted for SQL');
is(main::postgres_pass($top, 1), "parent'pass",
	'top-level password can be returned unquoted');
is(main::postgres_pass($doms{2}, 1), "db'pass",
	'separate PostgreSQL password is preferred');

# Sub-servers use the parent's login, with the same quoting choice.
my $sub = { 'id' => 3, 'parent' => 1, 'pass' => 'ignored' };
is(main::postgres_pass($sub), "'parent''pass'",
	'sub-server password is quoted for SQL');
is(main::postgres_pass($sub, 1), "parent'pass",
	'sub-server password can be returned unquoted');
is(main::postgres_pass({ 'id' => 4, 'parent' => 2 }, 1), "db'pass",
	"sub-server uses the parent's separate PostgreSQL password");

done_testing();
