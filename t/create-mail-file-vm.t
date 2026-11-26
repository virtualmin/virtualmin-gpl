#!/usr/bin/perl
use strict;
use warnings;
use File::Temp qw(tempdir tempfile);
use Test::More;

plan skip_all =>
	'Set VIRTUALMIN_CREATE_MAIL_FILE_VM_TEST=1 on a disposable Maildir VM'
	unless $ENV{'VIRTUALMIN_CREATE_MAIL_FILE_VM_TEST'} &&
	       $^O eq 'linux' && !$>;

sub cli
{
my ($command, @args) = @_;
open(my $fh, '-|', 'timeout', '120', 'virtualmin', $command, @args) or die $!;
local $/;
my $out = <$fh>;
close($fh) or die "$command failed ($?)";
return $out;
}

my $tmp = tempdir(CLEANUP => 1);
my ($pass, $passfile) = tempfile(DIR => $tmp);
open(my $random, '<', '/dev/urandom') or die $!;
read($random, my $bytes, 24) == 24 or die 'Cannot generate fixture password';
print $pass unpack('H*', $bytes), "\n" or die $!;
close($pass) or die $!;
my $owner = sprintf('mc%x%04x', $$, int(rand(65536)));
my $domain = "$owner.invalid";
my @domain = ('--domain', $domain);
die 'Fixture already exists' if getpwnam($owner) ||
	grep { $_ eq $domain } split(/\n/, cli('list-domains', '--name-only'));

my $ok = eval {
	cli('create-domain', @domain, '--user', $owner, '--passfile', $passfile,
	    '--unix', '--dir', '--mail', '--no-email');
	cli('create-user', @domain, '--user', 'sales', '--passfile', $passfile);
	my $login = cli('list-users', @domain, '--user', 'sales',
			'--name-only');
	chomp($login);
	my @user = getpwnam($login) or die 'Missing fixture account';
	my $sent = "$user[7]/Maildir/.Sent";
	is_deeply([ (stat("$user[7]/Maildir/new"))[4, 5] ], [ @user[2, 3] ],
		  'a new mailbox owns its delivery folder');

	# The mailbox user can replace a folder with a link to a root-only file.
	my ($fh, $secret) = tempfile(DIR => $tmp);
	close($fh);
	system('rm', '-rf', $sent) == 0 && symlink($secret, $sent) or die $!;
	cli('modify-user', @domain, '--user', 'sales', '--real', 'Sales');
	is((stat($secret))[4], 0,
	   'a mailbox edit keeps the linked file root-owned');

	# A home owned by the domain owner still gets a Maildir for its mailbox.
	my $shared = (getpwnam($owner))[7]."/shared";
	mkdir($shared) && chown((getpwnam($owner))[2, 3], $shared) or die $!;
	cli('create-user', @domain, '--user', 'team', '--passfile', $passfile,
	    '--home', 'shared');
	chomp($login = cli('list-users', @domain, '--user', 'team',
			   '--name-only'));
	is_deeply([ (stat("$shared/Maildir/new"))[4, 5] ],
		  [ (getpwnam($login))[2, 3] ],
		  'a home owned by the domain owner gets a Maildir');
	1;
	};
my $err = $@;
if (grep { $_ eq $domain } split(/\n/, cli('list-domains', '--name-only'))) {
	cli('delete-domain', @domain);
	}
ok($ok, 'mail file checks completed') or diag($err);
done_testing();
