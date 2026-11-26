#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use FindBin;

require "$FindBin::Bin/../virtual-server-lib-funcs.pl";

no warnings qw(once redefine);
my $top = { home => tempdir(CLEANUP => 1) };

# Enabling database access must still check the mailbox home.
my $db = { type => 'mysql', name => 'sales' };
local *main::check_any_database_user_clash = sub { undef };
my @home_check;
local *main::is_under_directory = sub { @home_check = @_; return 1 };
my $u = { dbs => [ $db ], plainpass => 'fixture', home => "$top->{home}/sales" };
main::validate_user($top, $u);
is_deeply(\@home_check, [ $top->{home}, $u->{home} ],
	  'checks the mailbox home when database access is first enabled');

done_testing();
