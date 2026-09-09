#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use FindBin;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use Cwd qw(abs_path);

my $root = abs_path("$FindBin::Bin/..");
my $tmp = tempdir(DIR => '/tmp', CLEANUP => 1);
mkdir("$tmp/logs") or die $!;

sub write_file {
	my ($path, $text) = @_;
	open(my $fh, '>', $path) or die "$path: $!";
	print $fh $text;
	close($fh) or die "$path: $!";
}

# Use real command sources and an isolated module context with no system writes.
for my $file (qw(configure-repos.pl configure-swap.pl)) {
	copy("$root/$file", "$tmp/$file") or die $!;
	chmod(0755, "$tmp/$file") or die $!;
}
ok(-l "$root/setup-repos.pl", 'old command is a compatibility symlink');
is(readlink("$root/setup-repos.pl"), 'configure-repos.pl', 'alias uses the canonical implementation');
ok(-x "$root/setup-repos.pl", 'alias remains executable for the CLI and remote API');
symlink(readlink("$root/setup-repos.pl"), "$tmp/setup-repos.pl") or die $!;
# Exercise the real repository runner without loading Webmin or its system setup.
open(my $lib, '<', "$root/virtual-server-lib-funcs.pl") or die $!;
my $source = do { local $/; <$lib> };
close($lib);
my ($runner) = $source =~ /(sub setup_virtualmin_repos\n.*?)(?=# require_licence\()/s;
die 'Repository runner not found' if (!$runner);
write_file("$tmp/repo-runner.pl", "package virtual_server; use POSIX ();\n".$runner."\n1;\n");
write_file("$tmp/driver.pl", <<'PERL');
package virtual_server;
$module_name = 'virtual-server';
$module_root_directory = $root_directory = $ENV{'TEST_MODULE'};
$module_var_directory = "$ENV{'TEST_MODULE'}/logs";
@plugins = ();
%access = (edit_remote_api => 1);
do "$ENV{'TEST_SOURCE'}/commands-lib.pl";
die $@ if $@;
sub master_admin { !$ENV{'TEST_NONMASTER'} }
sub reseller_admin { 0 }
sub indexof {
	my ($item, @list) = @_;
	for (my $i=0; $i<@list; $i++) { return $i if $list[$i] eq $item; }
	return -1;
}
sub read_file_contents {
	open(my $fh, '<', $_[0]) or return undef;
	local $/;
	return <$fh>;
}
sub set_all_text_print {
	$first_print = sub {
		print "@_\n";
		if ($ENV{'TEST_REAL_REPO'} && $_[0] eq 'Configure repositories') {
			open(my $fh, '>', "$ENV{'TEST_MODULE'}/stage-started") or die $!;
			close($fh);
			}
		};
}
sub has_command { '/bin/sh' }
sub is_readonly_mode { $ENV{'TEST_READONLY'} }
sub trim { my $s = shift; $s =~ s/^\s+|\s+$//g; return $s; }
sub detect_virtualmin_repo_branch { 'stable' }
sub read_env_file { %{$_[1]} = (SerialNumber => 'GPL', LicenseKey => 'GPL'); }
sub setup_virtualmin_repos {
	&{$_[1]}() if ($_[1] && !$ENV{'TEST_REPO_FAIL'});
	print "branch=$_[0]\n";
	return $ENV{'TEST_REPO_FAIL'} ? (256, 'Download failed', '') : (0, '', '');
}
sub setup_repos_error { return $_[0]; }
if ($ENV{'TEST_REAL_REPO'}) {
	do "$ENV{'TEST_MODULE'}/repo-runner.pl";
	die $@ if $@;
	}
sub change_licence {
	print "licence=@_\n";
	if ($ENV{'TEST_LICENCE_FAIL'}) {
		print "License validation failed\n";
		return (1, undef);
		}
	return (0, '');
}
sub virtualmin_api_log { print "audit=".join('|', @{$_[0]})."\n"; }
sub clean_environment { }
sub reset_environment { }
sub backquote_command { return $ENV{'TEST_HELP_OUTPUT'}; }
$text{'licence_updating_repo_stable_gpl'} = 'Configure repositories';
$text{'remote_ecannotcmd'} = 'Access denied';
chdir($ENV{'TEST_MODULE'}) or die $!;
my $entry = shift(@ARGV);
if ($entry eq 'check-access') {
	print join("\n", map { $_.'='.(can_remote($_) ? 1 : 0) } @ARGV), "\n";
}
else {
	do $entry;
	die $@ if $@;
}
PERL

sub run_command {
	my ($nonmaster, $entry, @args) = @_;
	my $pid = fork();
	die "fork: $!" if !defined($pid);
	if (!$pid) {
		$ENV{'TEST_MODULE'} = $tmp;
		$ENV{'TEST_SOURCE'} = $root;
		$ENV{'TEST_NONMASTER'} = $nonmaster;
		open(STDOUT, '>', "$tmp/output") or die $!;
		open(STDERR, '>&STDOUT') or die $!;
		exec { $^X } $^X, "$tmp/driver.pl", $entry, @args;
		die "exec: $!";
	}
	waitpid($pid, 0);
	my $status = $? >> 8;
	open(my $fh, '<', "$tmp/output") or die $!;
	local $/;
	return ($status, <$fh>);
}

subtest 'only canonical names appear in command listings' => sub {
	for my $args ([], ['--name-only'], ['--multiline']) {
		my ($st, $out) = run_command(0, "$root/list-commands.pl", @$args);
		is($st, 0, 'command listing succeeds');
		like($out, qr/^configure-repos(?:\s|$)/m, 'repository command is listed');
		like($out, qr/^configure-swap(?:\s|$)/m, 'swap command is listed');
		unlike($out, qr/^setup-(?:repos|swap)(?:\s|$)/m, 'old names are hidden');
		like($out, qr/^    Category: Repository$/m, 'repository category is preserved')
			if (@$args && $args->[0] eq '--multiline');
	}
};

subtest 'repository alias preserves arguments, help and exit status' => sub {
	for my $args ([], ['--branch', 'prerelease'],
		['--branch', 'unstable', '--serial', '123', '--key', 'example-key', '--no-check'],
		['--branch', 'invalid'], ['--help']) {
		my @new = run_command(0, "$tmp/configure-repos.pl", @$args);
		my @old = run_command(0, "$tmp/setup-repos.pl", @$args);
		is_deeply(\@old, \@new, "alias matches canonical command: @$args");
		if (!@$args || $args->[0] eq '--branch' && $args->[1] ne 'invalid') {
			is($new[0], 0, 'configuration succeeds');
			my $branch = @$args ? $args->[1] : 'stable';
			like($new[1], qr/^branch=\Q$branch\E$/m, 'requested branch reaches setup');
			my $audit = join('|', @$args);
			like($new[1], qr/^audit=\Q$audit\E$/m, 'original arguments are preserved');
		}
		else {
			is($new[0], 1, 'existing help or usage exit status is preserved');
			like($new[1], qr/virtualmin configure-repos/, 'help uses the preferred name');
		}
	}
};

subtest 'remote API access remains restricted to master administrators' => sub {
	my @names = qw(configure-repos configure-swap setup-repos);
	for my $nonmaster (0, 1) {
		my ($st, $out) = run_command($nonmaster, 'check-access', @names);
		is($st, 0, 'access check succeeds');
		my $allowed = $nonmaster ? 0 : 1;
		is($out, join('', map { "$_=$allowed\n" } @names), 'both names have the same access restrictions');
	}
};

subtest 'repository failures reach both command names' => sub {
	local $ENV{'TEST_REPO_FAIL'} = 1;
	for my $name (qw(configure-repos setup-repos)) {
		my ($st, $out) = run_command(0, "$tmp/$name.pl");
		is($st, 1, "$name reports failure to its caller");
		like($out, qr/\.\. error : download failed/, 'failure is explained');
		unlike($out, qr/\.\. done/, 'failure is not reported as success');
	}
};

subtest 'failed license validation stops repository configuration' => sub {
	local $ENV{'TEST_LICENCE_FAIL'} = 1;
	for my $name (qw(configure-repos setup-repos)) {
		my ($st, $out) = run_command(0, "$tmp/$name.pl",
			'--serial', '123', '--key', 'invalid-key');
		is($st, 1, "$name preserves a validation failure with no returned message");
		like($out, qr/License validation failed/, 'retains the validation diagnostic');
		unlike($out, qr/Fetching|Configure repositories|branch=|\.\. done/,
			'repository setup never starts after license validation fails');
		}
};

subtest 'repository download progress is live and errors belong to the right stage' => sub {
	write_file("$tmp/run-setup.sh", <<'SH');
#!/bin/sh
printf '%s\n' "$@" >"$TEST_MODULE/repo-args"
if [ "$TEST_FETCH_FAIL" = 1 ]; then
	printf '[ERROR] Failed to download the Virtualmin setup script.\n'
	exit 22
fi
[ "$VIRTUALMIN_SETUP_PROGRESS" = 1 ] || exit 78
printf '[SETUP] Download complete\n'
# Execution waits for the parent's callback, proving progress is not buffered.
i=0
while [ ! -e "$TEST_MODULE/stage-started" ] && [ "$i" -lt 40 ]; do
	/bin/sleep 0.05
	i=$((i+1))
done
[ -e "$TEST_MODULE/stage-started" ] || exit 79
printf 'Repository setup details\n' >"$log_dir_path/$setup_log_file_name.log"
printf '[INFO] Repository setup started\n'
if [ "$TEST_CONFIG_FAIL" = 1 ]; then
	printf '[ERROR] Something went wrong. Exiting.\n'
	exit 7
fi
SH
	local $ENV{'TEST_REAL_REPO'} = 1;
	for my $failure ('', 'TEST_FETCH_FAIL', 'TEST_CONFIG_FAIL', 'TEST_READONLY') {
		local $ENV{'TEST_FETCH_FAIL'} = $failure eq 'TEST_FETCH_FAIL' ? 1 : '';
		local $ENV{'TEST_CONFIG_FAIL'} = $failure eq 'TEST_CONFIG_FAIL' ? 1 : '';
		local $ENV{'TEST_READONLY'} = $failure eq 'TEST_READONLY' ? 1 : '';
		unlink("$tmp/stage-started", "$tmp/repo-args");
		my ($st, $out) = run_command(0, "$tmp/configure-repos.pl");
		is($st, $failure ? 1 : 0, "exit status for '$failure'");
		like($out, qr/^Fetching latest repository setup script \.\.\n/, 'fetching is announced first');
		unlike($out, qr/\[SETUP\]|\[INFO\]|\[ERROR\]/, 'internal messages stay hidden');
		if (!$failure || $failure eq 'TEST_CONFIG_FAIL') {
			like($out, qr/Fetching .*\n\.\. done\nConfigure repositories\n/, 'fetching completes before configuration');
			ok(-e "$tmp/stage-started", 'callback ran while the helper was still executing');
			like($out, qr/Configure repositories\n\.\. done\n/, 'configuration reports success') if (!$failure);
			like($out, qr/Configure repositories\n\.\. error : something went wrong, exiting;/, 'configuration failure follows successful fetching') if ($failure);
			if ($failure) {
				like($out, qr/^\.\. error : something went wrong, exiting; see \Q$tmp\/logs\/configure-repos.log\E for more details$/m,
					'configuration errors point to the setup log on the same line');
				}
			else {
				unlike($out, qr/see .* for more details/i, 'successful setup has no log reminder');
				}
			}
		else {
			unlike($out, qr/\.\. done|Configure repositories/, 'failed fetching never starts configuration');
			like($out, qr/\.\. error : /, 'failure is shown under fetching');
			unlike($out, qr/see .* for more details/i, 'failed fetching does not point to the previous setup log');
			ok(!-e "$tmp/repo-args", 'read-only mode never launches the helper') if ($failure eq 'TEST_READONLY');
			}
		}
};

subtest 'command metadata can parse the advertised options' => sub {
	for my $name (qw(configure-repos setup-repos configure-swap)) {
		my ($help_st, $help) = run_command(0, "$tmp/$name.pl", '--help');
		local $ENV{'TEST_HELP_OUTPUT'} = $help;
		my ($st, $out) = run_command(0, "$root/get-command.pl", '--command', $name);
		is($st, 0, "$name metadata is readable");
		if ($name eq 'configure-swap') {
			like($out, qr/^size\n    Binary: No\n    Value: size\n    Optional: Yes$/m,
				'swap size is an optional value');
			unlike($out, qr/^yes$/m, 'confirmation flag is not advertised');
			}
		else {
			like($out, qr/^branch\n    Binary: No\n    Value: stable\|prerelease\|unstable$/m,
				'repository branch choices are readable');
			like($out, qr/^serial\n    Binary: No$/m, 'license serial is a value');
			like($out, qr/^key\n    Binary: No$/m, 'license key is a value');
			like($out, qr/^no-check\n    Binary: Yes$/m, 'license check option is a flag');
			}
		}
};

# The documentation exporter uses this skip list even for symlink aliases.
do "$root/commands-lib.pl";
die $@ if $@;
ok(scalar(grep { $_ eq 'setup-repos.pl' } list_api_skip_scripts()),
	'old repository name is excluded from generated API documentation');
done_testing();
