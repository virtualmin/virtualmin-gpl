#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use FindBin;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Copy qw(copy);
use Cwd qw(abs_path);
use Time::HiRes qw(time);

my $root = "$FindBin::Bin/..";
my $tmp = abs_path(tempdir(DIR => '/tmp', CLEANUP => 1));
my $module = "$tmp/module with spaces";
make_path($module, "$tmp/logs", "$tmp/work", "$tmp/bin");

sub write_file {
	my ($path, $text) = @_;
	open(my $fh, '>', $path) or die "$path: $!";
	print $fh $text;
	close($fh) or die "$path: $!";
}
sub read_file {
	my ($path) = @_;
	return '' if (!-f $path);
	open(my $fh, '<', $path) or die "$path: $!";
	local $/;
	return <$fh>;
}

# Run real entry points in a child, with all system work replaced by fixtures.
sub run_command {
	my ($env, $input, @cmd) = @_;
	unlink("$tmp/called", "$tmp/fetched", "$tmp/audit", "$tmp/probes", "$tmp/fetched-library");
	write_file("$tmp/input", $input);
	my $pid = fork();
	die "fork: $!" if (!defined($pid));
	if (!$pid) {
		@ENV{keys %$env} = values %$env;
		open(STDIN, '<', "$tmp/input") or die $!;
		open(STDOUT, '>', "$tmp/stdout") or die $!;
		open(STDERR, '>', "$tmp/stderr") or die $!;
		chdir($tmp) or die $!;
		exec { $cmd[0] } @cmd;
		die "exec: $!";
	}
	waitpid($pid, 0);
	return ($? >> 8, read_file("$tmp/stdout").read_file("$tmp/stderr"));
}

# The already-loaded-module path is also how Webmin invokes API commands.
write_file("$tmp/driver.pl", <<'PERL');
package virtual_server;
$module_name = 'virtual-server';
$module_root_directory = $ENV{'TEST_MODULE'};
$module_var_directory = "$ENV{'TEST_ROOT'}/logs";
$main::virtualmin_remote_api = $ENV{'TEST_REMOTE'};
sub set_all_text_print {
	$first_print = sub { print $indent_text, "@_\n"; };
	$indent_print = sub { $indent_text .= '    '; };
	$outdent_print = sub { $indent_text = substr($indent_text, 4); };
}
sub master_admin { !$ENV{'TEST_DENY'} }
sub is_readonly_mode { $ENV{'TEST_READONLY'} }
sub has_command { '/bin/sh' }
sub virtualmin_api_log {
	open(my $fh, '>', "$ENV{'TEST_ROOT'}/audit") or die $!;
	print $fh join("\n", @{$_[0]});
}
do $ENV{'TEST_ENTRY'};
die "Could not run entry point: $@ $!";
PERL
write_file("$module/run-setup.sh", <<'SH');
printf '%s\n' "$@" >"$TEST_ROOT/called"
confirmed=0
for arg do [ "$arg" != --yes ] || confirmed=1; done
[ "$confirmed" = 1 ] || { echo "Missing --yes"; exit 90; }
if [ "$TEST_DOWNLOAD_FAIL" = 1 ]; then
	printf '[ERROR] Failed to download the Virtualmin setup script.\n' >&2
	exit 1
fi
printf '[SETUP] Download complete\n'
if [ "$TEST_MESSAGES" = 1 ]; then
	printf 'Swap setup details\n' >"$log_dir_path/virtualmin-swap.log"
	printf '\033[36m[INFO]\033(B\033[m Swap setup log is written to %s/virtualmin-swap.log\n' "$log_dir_path"
	printf '[INFO] Started swap setup\n'
	if [ "$TEST_EARLY_FAIL" != 1 ]; then
		printf '[INFO] The swap space will be created with a size of \033[33m1 GiB\033[m.\n'
	fi
	if [ "$TEST_STATUS" != 0 ]; then
		printf '[ERROR] Insufficient free disk space.\n' >&2
		printf '[ERROR] Re-run the installer with --no-swap instead of --swap to skip swap setup.\n' >&2
		printf '[ERROR] Re-run the installer with --no-swap to skip swap setup.\n' >&2
		exit "$TEST_STATUS"
	fi
	printf '[SUCCESS] Swap setup completed successfully.\n'
	exit 0
fi
printf 'log=%s\ninteractive=%s\n' "$log_dir_path" "$INTERACTIVE_MODE"
printf 'prompt-env=%s\n' "$PS1"
if [ "$TEST_READ_INPUT" = 1 ]; then
	read -r reply
	printf 'reply=%s\n' "$reply"
fi
if [ "$TEST_SIGNAL" = 1 ]; then kill -TERM $$; fi
exit "${TEST_STATUS:-0}"
SH
my %cli_env = (
	TEST_ROOT => $tmp, TEST_MODULE => $module,
	TEST_ENTRY => "$root/configure-swap.pl",
	TEST_REMOTE => '', TEST_DENY => '', TEST_READONLY => '',
	TEST_SIGNAL => '', TEST_READ_INPUT => '', TEST_STATUS => 0,
	TEST_MESSAGES => '', TEST_DOWNLOAD_FAIL => '', TEST_EARLY_FAIL => '',
);
sub run_cli {
	my ($overrides, $input, @args) = @_;
	return run_command({ %cli_env, %$overrides }, $input,
		$^X, "$tmp/driver.pl", @args);
}

subtest 'CLI forwards sizes without shell interpolation' => sub {
	foreach my $size ('2G', '976M', '1000', '2gb', '010M', '1K', '0') {
		my ($st, $out) = run_cli({}, '', '--size', $size);
		is($st, 0, "$size succeeds");
		is(read_file("$tmp/called"), "swap\n--swap\n$size\n--yes\n",
			'only the swap mode and selected options are forwarded');
		is(read_file("$tmp/audit"), "--size\n$size", 'request is audited');
	}
	my ($st, $out) = run_cli({ TEST_READ_INPUT => 1, PS1 => 'inherited prompt' }, "y\n");
	is($st, 0, 'automatic mode succeeds');
	is(read_file("$tmp/called"), "swap\n--yes\n", 'automatic mode skips confirmation');
	like($out, qr/^    reply=$/m, 'installer cannot consume caller input');
	unlike($out, qr/Confirm|\(y\/n\)/, 'no confirmation prompt');
	like($out, qr/\Qlog=$tmp\/logs\E/, 'log directory survives temp cleanup');
	like($out, qr/interactive=off/, 'captured output has no forced terminal colors');
	like($out, qr/prompt-env=\n/, 'inherited shell prompts do not force interactive output');
};

subtest 'CLI rejects invalid requests before starting setup' => sub {
	foreach my $args (['--size'], ['--size', '--yes'], ['--size', '-1'],
		['--size', '1.5G'], ['--size', "2G\n"], ['--size', '2G; touch nope'],
		['--size', '0', '--size', '2G'], ['--setup'], ['--uninstall'],
		['--size', '2G', '--branch', 'stable']) {
		my ($st, $out) = run_cli({}, '', @$args);
		is($st, 1, "rejects @{$args}");
		like($out, qr/^(?:Option --size|Unknown parameter) /m, 'explains the argument error');
		unlike($out, qr/\[ERROR\]/, 'usage errors have no logger prefix');
		ok(!-e "$tmp/called", 'setup was not started');
	}
	my ($st, $out) = run_cli({}, '', '--help');
	is($st, 0, 'help succeeds');
	like($out, qr/virtualmin configure-swap/, 'help names the new command');
	unlike($out, qr/--yes/, 'help has no confirmation option');
	ok(!-e "$tmp/called", 'help does not start setup');
};

subtest 'host-wide changes require administrator access' => sub {
	foreach my $env ({ TEST_DENY => 1 }, { TEST_READONLY => 1 }) {
		my ($st, $out) = run_cli($env, '');
		is($st, 1, 'unsafe invocation rejected');
		ok(!-e "$tmp/called", 'no setup started');
	}
	my ($st) = run_cli({ TEST_REMOTE => 1 }, '');
	is($st, 0, 'master API request needs no confirmation flag');
	is(read_file("$tmp/called"), "swap\n--yes\n", 'API setup skips confirmation');
	($st) = run_cli({}, '', '--yes');
	is($st, 0, 'former confirmation flag remains accepted');
	is(read_file("$tmp/called"), "swap\n--yes\n", 'compatibility flag is not duplicated');
};

subtest 'CLI propagates failures and signals' => sub {
	my ($st) = run_cli({ TEST_STATUS => 7 }, '', '--yes');
	is($st, 7, 'installer failure remains a failure');
	($st) = run_cli({ TEST_SIGNAL => 1 }, '', '--yes');
	is($st, 143, 'signal termination remains a failure');
};

subtest 'setup messages use Virtualmin output' => sub {
	my ($st, $out) = run_cli({ TEST_MESSAGES => 1 }, '');
	is($st, 0, 'successful setup retains its status');
	is($out, "Fetching latest installer ..\n.. done\nConfiguring swap space ..\n".
		"    The swap space will be created with a size of 1 GiB ..\n".
		"    .. done\n".
		".. done\n", 'reports operation and overall success at their respective indentation levels');
	($st, $out) = run_cli({ TEST_MESSAGES => 1, TEST_STATUS => 7 }, '', '--yes');
	is($st, 7, 'failed setup retains its status');
	is($out, "Fetching latest installer ..\n.. done\nConfiguring swap space ..\n".
		"    The swap space will be created with a size of 1 GiB ..\n".
		"    .. error : insufficient free disk space; see $tmp/logs/virtualmin-swap.log for more details\n".
		".. failed\n", 'reports an indented error followed by overall failure');
	unlike($out, qr/\[INFO\]|\[ERROR\]|\e/, 'no installer prefixes or colors');
	unlike($out, qr/Log file:|Swap setup log|Re-run the installer|--no-swap/, 'omits log announcement and installer-only advice');
	($st, $out) = run_cli({ TEST_MESSAGES => 1, TEST_EARLY_FAIL => 1, TEST_STATUS => 7 }, '', '--size', '311g');
	is($st, 7, 'early failure retains its status');
	is($out, "Fetching latest installer ..\n.. done\nConfiguring swap space ..\n".
		".. failed : insufficient free disk space; see $tmp/logs/virtualmin-swap.log for more details\n",
		'early failure closes the configuration stage without an indented error');
	($st, $out) = run_cli({ TEST_DOWNLOAD_FAIL => 1 }, '');
	is($st, 1, 'download failure remains a failure');
	is($out, "Fetching latest installer ..\n".
		".. error : failed to download the Virtualmin setup script\n",
		'failed fetching does not announce configuration or success');
};

# An isolated PATH tests each downloader without ever accessing the network.
foreach my $cmd (qw(sh mkdir rm mktemp)) {
	my ($path) = grep { -x $_ } map { "$_/$cmd" } split(/:/, $ENV{'PATH'});
	$path || die "Missing test utility $cmd";
	symlink($path, "$tmp/bin/$cmd") or die $!;
}
copy("$root/run-setup.sh", "$module/run-setup.sh") or die $!;
write_file("$tmp/installer.sh", <<'SH');
#!/bin/sh
printf '%s\n' "$@" >"$TEST_ROOT/called"
printf 'mode=%s\nlog=%s\n' "$VIRTUALMIN_SETUP_ONLY" "$log_dir_path"
printf 'pwd=%s\ntmp=%s\n' "$PWD" "$VIRTUALMIN_INSTALL_TEMPDIR"
installer_pwd=$PWD
cd "$VIRTUALMIN_INSTALL_TEMPDIR" || exit 98
. "$installer_pwd/slib.sh"
printf 'library=%s\n' "$downloaded_library"
exit "${TEST_STATUS:-0}"
SH
write_file("$tmp/slib.sh", "exit 99\n");
write_file("$tmp/downloaded-slib.sh", "downloaded_library=yes\n");
my %shell_env = (
	PATH => "$tmp/bin", TMPDIR => "$tmp/work", TEST_ROOT => $tmp,
	TEST_STATUS => 0, FETCH_STATUS => 0, FETCH_EMPTY => '',
	LIBRARY_STATUS => 0, LIBRARY_EMPTY => '',
	download_virtualmin_host => '', download_virtualmin_host_dev => '', download_virtualmin_host_rc => '',
	log_dir_path => "$tmp/logs", VIRTUALMIN_SETUP_ONLY => 1,
	VIRTUALMIN_INSTALL_TEMPDIR => "$tmp/do-not-use",
	VIRTUALMIN_SETUP_PROGRESS => 1,
);

subtest 'curl preflight prefers IPv4 and falls back without restricting the download' => sub {
	write_file("$tmp/bin/curl", <<'SH');
#!/bin/sh
case " $* " in
	*" -fsIL "*)
		printf '%s\n' "$*" >>"$TEST_ROOT/probes"
		[ "$1" = "$TEST_FAMILY" ]
		exit $?
		;;
esac
for address do :; done
case "$address" in
	*/slib.sh)
		printf '%s\n' "$@" >"$TEST_ROOT/fetched-library"
		if [ "$LIBRARY_EMPTY" != 1 ]; then /bin/cat "$TEST_ROOT/downloaded-slib.sh"; fi
		exit "${LIBRARY_STATUS:-0}"
		;;
esac
printf '%s\n' "$@" >"$TEST_ROOT/fetched"
/bin/cat "$TEST_ROOT/installer.sh"
SH
	chmod(0755, "$tmp/bin/curl") or die $!;
	for my $family ('-4', '-6', '') {
		for my $mode ('swap', 'repos') {
			my ($st, $out) = run_command({ %shell_env, TEST_FAMILY => $family }, '',
				'/bin/sh', "$module/run-setup.sh", $mode);
			is($st, 0, "$mode succeeds with family '$family'");
			my $url = $mode eq 'swap' ? 'https://download.virtualmin.com/virtualmin-install.sh' :
				'https://download.virtualmin.com/repository';
			is(read_file("$tmp/fetched"), ($family ? "$family\n" : '')."-fsSL\n$url\n",
				'only a successful preflight restricts the actual download');
			is(read_file("$tmp/fetched-library"), ($family ? "$family\n" : '')."-fsSL\nhttps://download.virtualmin.com/slib.sh\n",
				'library download reuses the same address selection');
			my @families = $family eq '-4' ? ('-4') : ('-4', '-6');
			is(read_file("$tmp/probes"), join('', map {
				"$_ -fsIL --max-time 0.5 -o /dev/null $url\n"
				} @families), 'probes use the endpoint in order with a one-second total timeout budget');
			unlike($out, qr/-fsIL|--max-time/, 'preflight is silent');
		}
	}
	unlink("$tmp/bin/curl") or die $!;
};

subtest 'wget preflight has a deadline and preserves normal fallback' => sub {
	my ($timeout) = grep { -x $_ } map { "$_/timeout" } split(/:/, $ENV{'PATH'});
	plan skip_all => 'timeout is unavailable' if (!$timeout);
	symlink($timeout, "$tmp/bin/timeout") or die $!;
	write_file("$tmp/bin/wget", <<'SH');
#!/bin/sh
case " $* " in
	*" --spider "*)
		printf '%s\n' "$*" >>"$TEST_ROOT/probes"
		if [ "$TEST_SLOW" = 1 ]; then exec /bin/sleep 10; fi
		[ "$1" = "$TEST_FAMILY" ]
		exit $?
		;;
esac
for address do :; done
case "$address" in
	*/slib.sh)
		printf '%s\n' "$@" >"$TEST_ROOT/fetched-library"
		if [ "$LIBRARY_EMPTY" != 1 ]; then /bin/cat "$TEST_ROOT/downloaded-slib.sh"; fi
		exit "${LIBRARY_STATUS:-0}"
		;;
esac
printf '%s\n' "$@" >"$TEST_ROOT/fetched"
/bin/cat "$TEST_ROOT/installer.sh"
SH
	chmod(0755, "$tmp/bin/wget") or die $!;
	for my $family ('-4', '-6', '') {
		for my $mode ('swap', 'repos') {
			my ($st, $out) = run_command({ %shell_env, TEST_FAMILY => $family, TEST_SLOW => '' }, '',
				'/bin/sh', "$module/run-setup.sh", $mode);
			is($st, 0, "$mode succeeds with family '$family'");
			my $url = $mode eq 'swap' ? 'https://download.virtualmin.com/virtualmin-install.sh' :
				'https://download.virtualmin.com/repository';
			is(read_file("$tmp/fetched"), ($family ? "$family\n" : '')."-qO-\n$url\n",
				'only a successful preflight restricts the download');
			is(read_file("$tmp/fetched-library"), ($family ? "$family\n" : '')."-qO-\nhttps://download.virtualmin.com/slib.sh\n",
				'library download reuses the same address selection');
			my @families = $family eq '-4' ? ('-4') : ('-4', '-6');
			is(read_file("$tmp/probes"), join('', map {
				"$_ -q --spider --tries=1 $url\n"
				} @families), 'probes IPv4 first with no retries');
			unlike($out, qr/--spider|Killed/, 'preflight is silent');
		}
	}

	# Real timeout processes must stop stalled probes without stopping the download.
	my $start = time();
	my ($st, $out) = run_command({ %shell_env, TEST_SLOW => 1 }, '',
		'/bin/sh', "$module/run-setup.sh", 'swap');
	my $elapsed = time() - $start;
	is($st, 0, 'stalled probes fall back to a normal download');
	cmp_ok($elapsed, '<', 3, 'two ten-second stalls finish within the budget plus scheduling allowance');
	like(read_file("$tmp/fetched"), qr/^-qO-\n/, 'timeout does not force either family');
	unlike($out, qr/Killed|--spider/, 'timeout diagnostics stay hidden');

	unlink("$tmp/bin/timeout") or die $!;
	($st, $out) = run_command({ %shell_env, TEST_FAMILY => '-4' }, '',
		'/bin/sh', "$module/run-setup.sh", 'swap');
	is($st, 0, 'download still works without timeout');
	ok(!-e "$tmp/probes", 'no unbounded preflight when timeout is absent');
	like(read_file("$tmp/fetched"), qr/^-qO-\n/, 'normal address selection without timeout');

	# An incompatible timeout implementation must not prevent a normal download.
	write_file("$tmp/bin/timeout", "#!/bin/sh\nexit 125\n");
	chmod(0755, "$tmp/bin/timeout") or die $!;
	($st, $out) = run_command(\%shell_env, '', '/bin/sh', "$module/run-setup.sh", 'swap');
	is($st, 0, 'unsupported timeout options fall back normally');
	ok(!-e "$tmp/probes", 'failed timeout never launches a probe');
	like(read_file("$tmp/fetched"), qr/^-qO-\n/, 'failed timeout leaves the download unrestricted');
	unlink("$tmp/bin/wget", "$tmp/bin/timeout") == 2 or die $!;
};

subtest 'shared downloader preserves modes and cleans up' => sub {
	foreach my $client (qw(curl wget fetch)) {
		write_file("$tmp/bin/$client", <<'SH');
#!/bin/sh
for address do :; done
case "$address" in
	*/slib.sh)
		printf '%s\n' "$@" >"$TEST_ROOT/fetched-library"
		if [ "$LIBRARY_EMPTY" != 1 ]; then /bin/cat "$TEST_ROOT/downloaded-slib.sh"; fi
		exit "${LIBRARY_STATUS:-0}"
		;;
esac
printf '%s\n' "$@" >"$TEST_ROOT/fetched"
if [ "$FETCH_EMPTY" != 1 ]; then /bin/cat "$TEST_ROOT/installer.sh"; fi
exit "$FETCH_STATUS"
SH
		chmod(0755, "$tmp/bin/$client") or die $!;
		my ($st, $out) = run_command(\%shell_env, '', '/bin/sh',
			"$module/run-setup.sh", 'swap', '--swap', '2G', '--yes');
		is($st, 0, "$client can download swap setup");
		like(read_file("$tmp/fetched"), qr{https://download.virtualmin.com/virtualmin-install.sh\n\z},
			'uses the installer endpoint');
		like($out, qr/^\[SETUP\] Download complete\nmode=0\n/m, 'download stage completes before installer execution');
		is(read_file("$tmp/called"), "--swap-only\n--swap\n2G\n--yes\n",
			'forces swap-only mode');
		like($out, qr/mode=0\n/, 'clears inherited repository-only environment');
		like($out, qr/\Qlog=$tmp\/logs\E/, 'preserves requested log path');
		like($out, qr/^library=yes$/m, 'loads the downloaded sibling library, not the caller directory library');
		my ($cwd) = $out =~ /^pwd=(.*)$/m;
		ok($cwd && !-e $cwd, 'download and working files cleaned up');

		($st, $out) = run_command({ %shell_env, log_dir_path => '' }, '',
			'/bin/sh', "$module/run-setup.sh", 'repos', '--setup', '--branch', 'stable');
		is($st, 0, "$client still supports repository setup");
		like(read_file("$tmp/fetched"), qr{https://download.virtualmin.com/repository\n\z},
			'preserves repository endpoint');
		is(read_file("$tmp/called"), "--setup\n--branch\nstable\n",
			'preserves repository arguments');
		like($out, qr/mode=1\n/, 'forces repository-only mode');
		like($out, qr/\Qlog=$tmp\E\n/, 'default log path is the original directory');

		for my $branch ('stable', 'prerelease', 'unstable', 'rc', 'devel') {
			($st, $out) = run_command(\%shell_env, '', '/bin/sh',
				"$module/run-setup.sh", 'repos', '--setup', '--branch', $branch);
			is($st, 0, "$client fetches the $branch library");
			my $host = $branch eq 'stable' ? 'download.virtualmin.com' :
				$branch eq 'prerelease' || $branch eq 'rc' ? 'rc.download.virtualmin.dev' :
				'download.virtualmin.dev';
			like(read_file("$tmp/fetched-library"), qr{https://\Q$host\E/slib\.sh\n\z},
				'library URL matches the installer branch');
			like($out, qr/^library=yes$/m, 'installer can source its sibling after changing directory');
			is(read_file("$tmp/called"), "--setup\n--branch\n$branch\n", 'branch arguments stay intact');
		}

		foreach my $overrides ({ FETCH_STATUS => 22 }, { FETCH_EMPTY => 1 },
			{ TEST_STATUS => 9 }, { LIBRARY_STATUS => 22 }, { LIBRARY_EMPTY => 1 }) {
			($st, $out) = run_command({ %shell_env, %$overrides }, '',
				'/bin/sh', "$module/run-setup.sh", 'swap');
			is($st, $overrides->{'TEST_STATUS'} || 1, 'failure is propagated');
			unlike($out, qr/\[SETUP\] Download complete/, 'failed fetching never reports completion')
				if (!$overrides->{'TEST_STATUS'});
			ok(!-e "$tmp/called", 'setup never runs with a failed or empty download')
				if (!$overrides->{'TEST_STATUS'});
			opendir(my $dh, "$tmp/work") or die $!;
			my @left = grep { !/^\.\.?\z/ } readdir($dh);
			closedir($dh);
			is_deeply(\@left, [], 'temporary files removed after failure');
		}
		unlink("$tmp/bin/$client") or die $!;
	}
	my ($st, $out) = run_command(\%shell_env, '', '/bin/sh',
		"$module/run-setup.sh", 'swap');
	is($st, 1, 'fails without a downloader');
	like($out, qr/Neither curl, wget, nor fetch/, 'explains missing dependency');
	($st, $out) = run_command(\%shell_env, '', '/bin/sh',
		"$module/run-setup.sh", 'install');
	is($st, 1, 'full installation is not a supported mode');
	ok(!-e "$tmp/called", 'invalid mode never executes the installer');
};

done_testing();
