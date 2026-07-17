#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Basename qw(dirname);
use File::Spec;
use Cwd qw(abs_path);

my $root = abs_path(File::Spec->catdir(dirname(__FILE__), '..'));
my $lib = File::Spec->catfile($root, 'scripts-lib.pl');
my $loaded = do $lib;
die $@ if ($@);
die "Failed to load $lib: $!" if (!defined($loaded));

is_deeply(
	[ &php_versioned_module_packages('mysqlnd', '8.4', 'yum') ],
	[ 'php8.4-mysqlnd', 'php84-mysqlnd' ],
	'RPM package candidates include the dotted RHEL 10 PHP stream name');

is_deeply(
	[ &php_versioned_module_packages('mysql', '8.4', 'apt') ],
	[ 'php8.4-mysql' ],
	'Debian package candidates retain the dotted PHP version');

is_deeply(
	[ &php_versioned_module_packages('mysqlnd', '8.4', 'other') ],
	[ 'php84-mysqlnd' ],
	'other package managers retain the legacy dotless form');

done_testing();
