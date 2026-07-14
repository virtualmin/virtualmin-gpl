#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Basename qw(dirname);
use File::Spec;
use File::Temp qw(tempdir);
use Cwd qw(abs_path);
use IPC::Open3;
use Symbol qw(gensym);

my $root = abs_path(File::Spec->catdir(dirname(__FILE__), '..'));
my $script = File::Spec->catfile($root, 'lookup-domain.pl');
my $mib = 1024*1024;

my ($status, $stdout, $stderr) = &run_lookup(
	'spam' => 0,
	'quota' => 10*$mib,
	'usage' => 6*$mib,
	'repeats' => 2,
	'message' => 'x');
is($status, 0, 'mail below quota margin is accepted without spam');
is($stdout, '', 'spam-disabled domain stays disabled in the lookup cache');

($status, $stdout, $stderr) = &run_lookup(
	'spam' => 0,
	'quota' => 10*$mib,
	'usage' => 7*$mib,
	'message' => 'x');
is($status, 73, 'mail inside quota margin is rejected without spam');
is($stdout, "123\n", 'quota rejection returns the domain ID');
like($stderr, qr/Disk quota .* has been reached/, 'quota rejection is logged');

($status, $stdout, $stderr) = &run_lookup(
	'spam' => 0,
	'quota' => 0,
	'usage' => 0,
	'group_quotas' => 1,
	'domain_quota' => 10*$mib,
	'domain_usage' => 7*$mib,
	'message' => 'x');
is($status, 73, 'domain quota is enforced for an unlimited user');

($status, $stdout, $stderr) = &run_lookup(
	'spam' => 0,
	'hard_quotas' => 0,
	'quota' => 10*$mib,
	'usage' => 7*$mib,
	'message' => 'x');
is($status, 0, 'soft quotas do not reject delivery');
is($stdout, '', 'soft quota path preserves spam-disabled output');

($status, $stdout, $stderr) = &run_lookup(
	'spam' => 1,
	'quota' => 20*$mib,
	'usage' => 6*$mib,
	'message' => 'x');
is($status, 0, 'mail below quota margin is accepted with spam');
is($stdout, "123\n", 'spam-enabled domain returns its domain ID');

($status, $stdout, $stderr) = &run_lookup(
	'spam' => 1,
	'nospam' => 1,
	'quota' => 20*$mib,
	'usage' => 6*$mib,
	'repeats' => 2,
	'message' => 'x');
is($status, 0, 'mail for a user with spam disabled is accepted');
is($stdout, '', 'user-level spam opt-out stays disabled in the lookup cache');

($status, $stdout, $stderr) = &run_lookup(
	'spam' => 0,
	'no_user' => 1,
	'message' => 'x');
is($status, 0, 'missing second-stage user lookup does not fail delivery');
is($stdout, '', 'missing user does not enable spam for a disabled domain');

done_testing();

sub run_lookup
{
my (%opts) = @_;
my $temp = tempdir(CLEANUP => 1);
my $lib = File::Spec->catfile($temp, 'virtual-server-lib.pl');
open(my $fh, '>', $lib) || die "Failed to create $lib: $!";
print $fh <<'EOF';
$config{'hard_quotas'} = $ENV{'TEST_HARD_QUOTAS'};

sub get_user_domain
{
return { 'id' => 123,
	 'dom' => 'example.test',
	 'spam' => $ENV{'TEST_SPAM'},
	 'quota' => $ENV{'TEST_DOMAIN_QUOTA'} };
}

sub has_home_quotas { return 1; }
sub has_group_quotas { return $ENV{'TEST_GROUP_QUOTAS'}; }
sub get_domain_spam_client { return 'spamassassin'; }
sub replace_atsign { return $_[0]; }
sub quota_bsize { return 1; }
sub get_domain { return &get_user_domain(); }
sub get_domain_quota { return $ENV{'TEST_DOMAIN_USAGE'}; }

sub list_domain_users
{
return () if ($ENV{'TEST_NO_USER'});
return ({ 'user' => 'alice',
	  'quota' => $ENV{'TEST_QUOTA'},
	  'uquota' => $ENV{'TEST_USAGE'},
	  'nospam' => $ENV{'TEST_NOSPAM'} });
}

1;
EOF
close($fh) || die "Failed to close $lib: $!";

local %ENV = (%ENV,
	'WEBMIN_VAR' => $temp,
	'TEST_SPAM' => $opts{'spam'} || 0,
	'TEST_HARD_QUOTAS' => exists($opts{'hard_quotas'}) ?
		$opts{'hard_quotas'} : 1,
	'TEST_NO_USER' => $opts{'no_user'} || 0,
	'TEST_NOSPAM' => $opts{'nospam'} || 0,
	'TEST_QUOTA' => $opts{'quota'} || 0,
	'TEST_USAGE' => $opts{'usage'} || 0,
	'TEST_GROUP_QUOTAS' => $opts{'group_quotas'} || 0,
	'TEST_DOMAIN_QUOTA' => $opts{'domain_quota'} || 0,
	'TEST_DOMAIN_USAGE' => $opts{'domain_usage'} || 0);

my $runner = 'my ($dir, $script) = splice(@ARGV, 0, 2); ' .
	'chdir($dir) || die "chdir($dir): $!"; $0 = $script; ' .
	'my $rv = do $script; die $@ if ($@); die $! if (!defined($rv));';
my ($status, $stdout, $stderr);
for(my $i=0; $i<($opts{'repeats'} || 1); $i++) {
	my $err = gensym();
	my $pid = open3(my $in, my $out, $err, $^X, '-e', $runner,
		$temp, $script, '--port', 0, '--exitcode', 73, 'alice');
	print $in $opts{'message'};
	close($in);
	$stdout = do { local $/; <$out> };
	$stderr = do { local $/; <$err> };
	waitpid($pid, 0);
	$status = $? >> 8;
	}
return ($status, $stdout, $stderr);
}
