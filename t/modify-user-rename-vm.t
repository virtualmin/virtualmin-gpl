#!/usr/bin/perl
use strict;
use warnings;
use File::Temp qw(tempdir tempfile);
use IPC::Open2;
use Test::More;

plan skip_all => 'Set VIRTUALMIN_MODIFY_USER_RENAME_VM_TEST=1 on a disposable VM'
	unless ($ENV{'VIRTUALMIN_MODIFY_USER_RENAME_VM_TEST'} || '') eq '1';
plan skip_all => 'Requires root on a Linux VM with local mail users'
	unless $^O eq 'linux' && $> == 0;

# Run the installed CLI and capture its output without logging fixture data.
sub cli
{
my ($command, @args) = @_;
open(my $fh, '-|', 'timeout', '120', 'virtualmin', $command, @args) or die $!;
local $/;
my $output = <$fh>;
close($fh) or die ($command eq 'modify-user' ? $output : "$command failed ($?)\n");
return $output;
}

open(my $conf, '<', '/etc/webmin/miniserv.conf') or die $!;
my ($root) = map { /^root=(.*)/ ? $1 : () } <$conf>;
close($conf);
chdir("$root/virtual-server") or die $!;

# Submit a mailbox edit to the installed CGI as Webmin's root user.
sub form
{
my ($id, $old, $new, @fields) = @_;
my $post = join('&', "dom=$id", "old=$old", "oldpop3=$old", "mailuser=$new",
		'mailpass_def=1', 'quota_def=1', 'home_def=1', 'mailbox=1', @fields);
local @ENV{qw(WEBMIN_CONFIG WEBMIN_VAR REMOTE_USER SCRIPT_NAME REQUEST_METHOD
	      CONTENT_TYPE CONTENT_LENGTH SERVER_ROOT)} =
	('/etc/webmin', '/var/webmin', 'root', '/virtual-server/save_user.cgi',
	 'POST', 'application/x-www-form-urlencoded', length($post), $root);
my $pid = open2(my $out, my $in, 'timeout', '120', $^X, './save_user.cgi');
print $in $post or die $!;
close($in) or die $!;
local $/;
my $html = <$out>;
close($out);
waitpid($pid, 0);
return $html;
}

my $tmp = tempdir(CLEANUP => 1);
my $owner = sprintf('rn%x%04x', $$, int(rand(65536)));
my $domain = "$owner.invalid";
my @domain = ('--domain', $domain);
die 'Fixture already exists' if getpwnam($owner) ||
	grep { $_ eq $domain } split(/\n/, cli('list-domains', '--name-only'));
my ($pass, $passfile) = tempfile(DIR => $tmp);
open(my $random, '<', '/dev/urandom') or die $!;
read($random, my $bytes, 24) == 24 or die 'Cannot generate fixture password';
print $pass unpack('H*', $bytes), "\n" or die $!;
close($pass) or die $!;
close($random);

my $completed = eval {
	cli('create-domain', @domain, '--user', $owner, '--passfile', $passfile,
	    '--unix', '--dir', '--mail', '--no-email');
	my $id = cli('list-domains', @domain, '--id-only');
	chomp($id);
	foreach my $case (qw(cli key shell)) {
		my $old = "sales$case";
		my $new = "orders$case";
		cli('create-user', @domain, '--user', $old, '--passfile', $passfile,
		    '--quota', 'UNLIMITED');
		my $login = cli('list-users', @domain, '--user', $old, '--name-only');
		chomp($login);
		my $home = (getpwnam($login))[7] or die 'Missing fixture account';
		my $info = cli('list-users', @domain, '--user', $old, '--multiline');
		my ($mail) = $info =~ /^\s*Mail location: (.+)$/m;
		die 'Missing fixture mailbox' unless $mail && -e $mail;
		my ($marker, $path) = tempfile(DIR => $home);
		close($marker) or die $!;
		my ($name) = $path =~ m{/([^/]+)$};

		# Check the error itself so an unrelated failure cannot pass the test.
		if ($case eq 'cli') {
			cli('modify-user', @domain, '--user', $old, '--autoreply', 'Original reply');
			eval { cli('modify-user', @domain, '--user', $old, '--newuser', $new,
				   '--ssh-pubkey', 'invalid-key', '--autoreply', 'Changed reply') };
			like($@, qr/SSH public key is invalid/i, 'CLI rejects the invalid key');
			$info = cli('list-users', @domain, '--user', $old,
				       '--multiline', '--simple-aliases');
			ok($info =~ /Autoreply message: Original reply/, 'rejected edit keeps the active reply');
			}
		else {
			my $html = $case eq 'key'
				? form($id, $old, $new, 'sshkey_mode=2', 'sshkey=invalid-key')
				: form($id, $old, $new, 'shell=/unavailable-fixture-shell');
			my $error = $case eq 'key' ? qr/SSH public key is invalid/i
						   : qr/Selected shell is not available/i;
			ok($html =~ $error, "form rejects the invalid $case");
			}
		is((getpwnam($login))[7], $home, "$case rejection keeps the account's home path");
		ok(-f $path, "$case rejection keeps files in the original home");
		ok(-e $mail, "$case rejection keeps mail at its original location");

		if ($case eq 'cli') {
			cli('modify-user', @domain, '--user', $old, '--newuser', $new);
			}
		else {
			my $html = form($id, $old, $new);
			ok($html =~ /^Location: .*list_users\.cgi\?dom=\Q$id\E\s*$/mi,
			   "$case retry returns to the mailbox list");
			}
		my $renamed = cli('list-users', @domain, '--user', $new, '--name-only');
		chomp($renamed);
		my $newhome = (getpwnam($renamed))[7];
		ok(!-d $home && $newhome && -f "$newhome/$name",
		   "$case retry moves the account and its files");
		}
	1;
	};
my $error = $@;
if (grep { $_ eq $domain } split(/\n/, cli('list-domains', '--name-only'))) {
	cli('delete-domain', @domain);
	}
ok($completed, 'mailbox rename checks completed') or diag($error);
done_testing();
