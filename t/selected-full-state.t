#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Copy ( );
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;

package virtual_server;

sub unlink_file
{
foreach my $file (@_) {
	unlink($file) if (defined($file) && -e $file);
	}
}

sub copy_source_dest
{
my ($source, $dest) = @_;
my $ok = File::Copy::copy($source, $dest);
return ($ok ? 1 : 0, $ok ? undef : "$!");
}

sub set_ownership_permissions
{
my (undef, undef, $mode, $file) = @_;
return chmod($mode, $file);
}

require "$FindBin::Bin/../backups-lib.pl";

package main;

my $domain1 = { 'id' => 101, 'dom' => 'one.example' };
my $domain2 = { 'id' => 102, 'dom' => 'two.example' };
my %dirdone = ( 101 => 1, 102 => 1 );
my %stateok;

# A failed upload for the first domain followed by a successful upload for the
# second must never mark the first domain's selected-full state as durable.
virtual_server::record_full_backup_destination_success(
	\%stateok, \%dirdone, $domain2);
is_deeply(\%stateok, { 102 => 1 },
	'only the domain whose archive reached the destination is marked');

my %nodirdone;
virtual_server::record_full_backup_destination_success(
	\%stateok, \%nodirdone, $domain1);
is_deeply(\%stateok, { 102 => 1 },
	'a backup without the directory feature does not promote stale state');

my $tempdir = tempdir(CLEANUP => 1);
my $staged = File::Spec->catfile($tempdir, 'selected.new');
my $selected = File::Spec->catfile($tempdir, 'selected');
my $default = File::Spec->catfile($tempdir, 'default');

# All public state is invalidated before the first domain is archived, so an
# interrupted multi-domain run cannot leave an old baseline for later domains.
my $oldselected = File::Spec->catfile($tempdir, 'old-selected');
my $staletemp = $oldselected.'.new.1234';
&write_test_file($oldselected, "old selected snapshot\n");
&write_test_file($staletemp, "stale staged snapshot\n");
my $invalidateerr =
	virtual_server::invalidate_selected_full_backup_state({
		'file' => $oldselected,
		});
is($invalidateerr, undef, 'selected-full state is invalidated up front');
ok(!-e $oldselected && !-e $staletemp,
	'public and abandoned staged state are both removed');

my $unremovable = File::Spec->catdir($tempdir, 'unremovable');
mkdir($unremovable) || die "Failed to create $unremovable: $!";
my $invalidatefail =
	virtual_server::invalidate_selected_full_backup_state({
		'file' => $unremovable,
		});
like($invalidatefail, qr/Failed to invalidate unusable snapshot/,
	'an invalidation failure aborts instead of leaving stale state silently');
rmdir($unremovable) || die "Failed to remove $unremovable: $!";

&write_test_file($staged, "new snapshot\n");
&write_test_file($selected, "old selected snapshot\n");
&write_test_file($default, "old default snapshot\n");

my $publisherr = virtual_server::publish_selected_full_backup_state({
	'temp' => $staged,
	'file' => $selected,
	'default' => $default,
	});
is($publisherr, undef, 'staged selected-full state is published');
ok(!-e $staged, 'staging file is consumed by atomic publication');
is(&read_test_file($selected), "new snapshot\n",
	'per-schedule snapshot contains the new state');
is(&read_test_file($default), "new snapshot\n",
	'default snapshot is promoted from the same state');

my $missingerr = virtual_server::publish_selected_full_backup_state({
	'temp' => File::Spec->catfile($tempdir, 'missing'),
	'file' => $selected,
	'default' => $default,
	});
like($missingerr, qr/Staged snapshot file is missing/,
	'a missing staged snapshot is reported instead of being promoted');

my $failedstaged = File::Spec->catfile($tempdir, 'failed.new');
my $failedselected = File::Spec->catfile($tempdir, 'failed');
&write_test_file($failedstaged, "failed new snapshot\n");
&write_test_file($failedselected, "previous selected snapshot\n");
my $discarderr = virtual_server::discard_selected_full_backup_state({
	'temp' => $failedstaged,
	'file' => $failedselected,
	});
is($discarderr, undef, 'failed selected-full state is discarded');
ok(!-e $failedstaged && !-e $failedselected,
	'neither staged nor public state survives a failed full backup');

my $unstagedselected = File::Spec->catfile($tempdir, 'unstaged');
&write_test_file($unstagedselected, "stale selected snapshot\n");
my $unstagederr = virtual_server::discard_selected_full_backup_state({
	'file' => $unstagedselected,
	});
is($unstagederr, undef,
	'an old public snapshot can be discarded without staged state');
ok(!-e $unstagedselected,
	'a selected full that fails before directory backup leaves no old state');

done_testing();

sub write_test_file
{
my ($file, $contents) = @_;
open(my $fh, '>', $file) || die "Failed to write $file: $!";
print $fh $contents;
close($fh) || die "Failed to close $file: $!";
}

sub read_test_file
{
my ($file) = @_;
open(my $fh, '<', $file) || die "Failed to read $file: $!";
local $/;
my $contents = <$fh>;
close($fh);
return $contents;
}
