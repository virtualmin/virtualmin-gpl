#!/usr/bin/perl

use strict;
use warnings;
no warnings qw(once redefine);
use Test::More;
use FindBin;
use Storable qw(dclone);

# Load the handler without reading Webmin configuration or changing accounts.
open(my $fh, '<', "$FindBin::Bin/../feature-webmin.pl") or die $!;
my $source = do { local $/; <$fh> };
close($fh);
my ($function) = $source =~ /(^sub clone_webmin\n\{.*?^\})/ms;
die 'Missing clone_webmin' unless $function;
eval "no strict; no warnings; $function";
die $@ if $@;

# Include inherited preferences and an explicitly disabled theme.
foreach my $case (qw(custom inherited unthemed missing_source missing_target)) {
	subtest "Webmin clone with $case preferences" => sub {
		my $old = { user => 'source' };
		my $new = { user => 'target' };
		my %users = (
			source => { name => 'source', lang => 'fr', theme => 'source-theme',
				real => 'Source owner', modules => [ 'source-module' ] },
			target => { name => 'target', lang => 'en', theme => 'target-theme',
				real => 'Target owner', modules => [ 'target-module' ] });
		if ($case eq 'inherited') {
			delete(@{$users{'source'}}{qw(lang theme)});
			}
		elsif ($case eq 'unthemed') {
			$users{'source'}->{'theme'} = '';
			}
		delete($users{'source'}) if $case eq 'missing_source';
		delete($users{'target'}) if $case eq 'missing_target';
		my $before = dclone(\%users);
		my (@locks, @unlocks, @modified, @actions);
		local *main::require_acl = sub { };
		local *main::obtain_lock_webmin = sub { push(@locks, $_[0]); };
		local *main::release_lock_webmin = sub { push(@unlocks, $_[0]); };
		local *main::register_post_action = sub { push(@actions, $_[0]); };
		local *acl::list_users = sub { values %{dclone(\%users)} };
		local *acl::modify_user = sub {
			push(@modified, $_[0]);
			$users{$_[0]} = dclone($_[1]);
			};

		# The clone dispatcher passes the destination before the source.
		is(clone_webmin($new, $old), 1, 'cloning succeeds');
		is_deeply($users{'source'}, $before->{'source'}, 'does not modify the source user');
		my $expected = dclone($before);
		if ($case !~ /^missing_/) {
			@{$expected->{'target'}}{qw(lang theme)} = @{$before->{'source'}}{qw(lang theme)};
			is_deeply(\@modified, [ 'target' ], 'writes only the destination user');
			}
		else {
			is_deeply(\@modified, [], 'does not modify users if either account is missing');
			}
		is_deeply(\%users, $expected, 'copies preferences and preserves other account settings');
		is_deeply(\@locks, [ $new ], 'locks for the destination');
		is_deeply(\@unlocks, [ $new ], 'releases the destination lock');
		is_deeply(\@actions, [ \&restart_webmin ], 'queues the Webmin reload');
		};
	}
done_testing();
