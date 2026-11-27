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
push(@fields, 'home_def=1') unless grep { /^home=/ } @fields;
my $post = join('&', "dom=$id", "old=$old", "oldpop3=$old", "mailuser=$new",
		'mailpass_def=1', 'quota_def=1', 'mailbox=1', @fields);
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
		if ($case eq 'cli') {
			rename($newhome, "$newhome.saved") or die $!;
			my $ok = eval { cli('modify-user', @domain, '--user', $new,
					    '--newuser', 'recovered'); 1 };
			chomp(my $login = cli('list-users', @domain, '--user', 'recovered',
					      '--name-only'));
			my $recovered = $login && (getpwnam($login))[7];
			ok($ok && $recovered && $recovered ne $newhome && -d $recovered,
			   'CLI creates the new home when the old home is missing');
			ok($recovered && -d $recovered &&
			   (stat($recovered))[4] == (getpwnam($login))[2],
			   'the recovered home belongs to the mailbox user');
			}
		elsif ($case eq 'key') {
			my $custom = (getpwnam($owner))[7].'/custom';
			my $html = form($id, $new, $new, 'home=custom');
			like($html, qr/^Location: .*list_users\.cgi/mi, 'form accepts a custom home');
			is((getpwnam($renamed))[7], $custom, 'account uses the custom home');
			ok(!-d $newhome && -f "$custom/$name", 'mailbox files moved with the account');

			# An existing default home must survive an attempted move back.
			mkdir($newhome, 0700) or die $!;
			my $inode = (stat($newhome))[1];
			$html = form($id, $new, $new);
			like($html, qr/Home directory \Q$newhome\E already exists/i,
			     'form refuses an occupied default home');
			is((getpwnam($renamed))[7], $custom, 'refused move keeps the custom home');
			ok(-f "$custom/$name" && -d $newhome && (stat($newhome))[1] == $inode,
			   'refused move preserves the mailbox files and the existing directory');

			rmdir($newhome) or die $!;
			$html = form($id, $new, $new);
			like($html, qr/^Location: .*list_users\.cgi/mi, 'form accepts the default home');
			is((getpwnam($renamed))[7], $newhome, 'account uses the default home again');
			ok(!-d $custom && -f "$newhome/$name", 'files return to the default home');

			# A new destination inside a root-only parent reaches the move itself.
			mkdir($custom, 0700) or die $!;
			$html = form($id, $new, $new, 'home=custom/blocked');
			like($html, qr/Home directory \Q$newhome\E could not be renamed/i,
			     'form refuses a move into a root-only parent');
			ok((getpwnam($renamed))[7] eq $newhome && -f "$newhome/$name" &&
			   !-e "$custom/blocked", 'failed move keeps the account and files together');
			}
		}

	# Keep only the public halves of the two disposable test keys.
	require URI::Escape;
	my @keys;
	foreach my $name (qw(managed manual)) {
		my $file = "$tmp/$name";
		system('ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-C', $name,
		       '-f', $file) == 0 or die 'Cannot generate fixture key';
		unlink($file) or die $!;
		open(my $fh, '<', "$file.pub") or die $!;
		chomp(my $key = <$fh>);
		push(@keys, $key);
		close($fh);
		}
	my ($managed, $manual) = @keys;

	# A form rename can supply a first key or resubmit the current one.
	foreach my $case (qw(first existing)) {
		my $old = "keys$case";
		my $new = "renamed$case";
		cli('create-user', @domain, '--user', $old, '--passfile', $passfile,
		    '--quota', 'UNLIMITED', $case eq 'existing' ? ('--ssh-pubkey', $managed) : ());
		if ($case eq 'existing') {
			chomp(my $login = cli('list-users', @domain, '--user', $old, '--name-only'));
			my $home = (getpwnam($login))[7] or die 'Missing fixture account';
			open(my $fh, '>>', "$home/.ssh/authorized_keys") or die $!;
			print $fh "\n$manual\n" or die $!;
			close($fh) or die $!;
			}
		my $html = form($id, $old, $new, 'sshkey_mode=2',
				'sshkey='.URI::Escape::uri_escape($managed));
		ok($html =~ /^Location: .*list_users\.cgi\?dom=\Q$id\E\s*$/mi,
		   "form saves rename with $case key");
		chomp(my $login = cli('list-users', @domain, '--user', $new, '--name-only'));
		my $home = (getpwnam($login))[7];
		my @lines;
		if ($home && open(my $fh, '<', "$home/.ssh/authorized_keys")) {
			chomp(@lines = <$fh>);
			}
		is_deeply([ grep { length } @lines ],
			  [ "$managed [$id:$new]", $case eq 'existing' ? ($manual) : () ],
			  "renamed account has the expected keys ($case)");
		}
	1;
	};
my $error = $@;
if (grep { $_ eq $domain } split(/\n/, cli('list-domains', '--name-only'))) {
	cli('delete-domain', @domain);
	}
ok($completed, 'mailbox rename checks completed') or diag($error);
done_testing();
