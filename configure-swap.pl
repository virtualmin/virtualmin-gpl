#!/usr/local/bin/perl

=head1 configure-swap.pl

Configure swap space.

This command downloads the Virtualmin installer and runs only its swap setup.
It does not install packages or change repositories.

Use C<--size> to create, resize or reuse the installer-managed swapfile.
Bare numbers mean MiB; suffixes C<K>, C<M> and C<G>, with an optional C<B>,
use binary units and are case-insensitive. C<--size 0> removes that swapfile
and its boot configuration. Other swap files and partitions stay untouched.

Without C<--size>, automatic sizing accounts for RAM, active swap and free
disk space, leaving an existing managed swapfile unchanged. Btrfs is supported
through the installer's dedicated swap subvolume.

The command requires root on the command line or Virtualmin master-administrator
privileges through the remote API. Changes apply without prompting.
The installer writes C<virtualmin-swap.log> in the module's log directory;
failures return a non-zero exit status.

For example, C<virtualmin configure-swap --size 2G> sets up 2 GiB of swap.

=cut

package virtual_server;
use POSIX ();
if (!$module_name) {
	$< == 0 || die "configure-swap.pl must be run as root";
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*)\/[^\/]+$/) {
		chdir($pwd = $1);
		}
	else {
		chop($pwd = `pwd`);
		}
	$0 = "$pwd/configure-swap.pl";
	require './virtual-server-lib.pl';
	}
&set_all_text_print();
@OLDARGV = @ARGV;

# Accept only swap settings, never arbitrary installer options.
my $size;
while (@ARGV > 0) {
	my $a = shift(@ARGV);
	if ($a eq "--size") {
		defined($size) && &usage("Option --size can only be given once");
		$size = shift(@ARGV);
		defined($size) && $size =~ /\A[0-9]+(?:[KMG]B?)?\z/i ||
			&usage("Option --size requires a size in MiB or with a K, M or G suffix");
		}
	elsif ($a eq "--yes") {
		# Accept the installer's confirmation flag silently, as this
		# command never prompts.
		next;
		}
	elsif ($a eq "--help") {
		&usage();
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Swap affects the whole host, including when invoked through the remote API.
&master_admin() || &usage("Only the master administrator can configure swap");
&is_readonly_mode() && &usage("Swap cannot be configured in read-only mode");

# Set the log directory and request noninteractive output with download progress.
my $shcmd = &has_command('sh') || &usage("The sh command was not found");
local $ENV{'log_dir_path'} = $module_var_directory;
local $ENV{'INTERACTIVE_MODE'} = 'off';
# An inherited shell prompt must not enable installer interactivity.
local $ENV{'PS1'} = '';
local $ENV{'VIRTUALMIN_SETUP_PROGRESS'} = 1;
my @args = ( 'swap' );
push(@args, '--swap', $size) if (defined($size));
push(@args, '--yes');
my $status = &run_swap_setup($shcmd, @args);
&virtualmin_api_log(\@OLDARGV);
exit($status);

# run_swap_setup(shell, args, ...)
# Format noninteractive installer output using Virtualmin status messages.
sub run_swap_setup
{
my ($shcmd, @args) = @_;
local $| = 1;
&$first_print("Fetching latest installer ..");
my $pid = open(my $output, '-|');
if (!defined($pid)) {
	&$first_print(".. error : failed to start swap setup: $!");
	return 1;
	}
if (!$pid) {
	# Merge diagnostics into the same stream without invoking a shell command string.
	open(STDERR, '>&STDOUT') || POSIX::_exit(1);
	# Never consume caller input, including from an interactive terminal.
	open(STDIN, '<', '/dev/null') || POSIX::_exit(1);
	exec { $shcmd } $shcmd, "$module_root_directory/run-setup.sh", @args;
	print STDERR "[ERROR] Failed to start swap setup: $!\n";
	POSIX::_exit(1);
	}

my $downloaded = 0;
my $progress = 0;
my ($pending, $read_error) = ('', 0);
my @errors;
my $show_line = sub {
	my ($line) = @_;
	if (!$downloaded && $line eq "[SETUP] Download complete\n") {
		$downloaded = 1;
		&$first_print(".. done");
		&$first_print("Configuring swap space ..");
		&$indent_print();
		return;
		}
	$line =~ s/\e(?:\[[0-?]*[ -\/]*[\@-~]|[()][A-Za-z0-9])//g;
	my ($level, $message) = $line =~ /^\[(INFO|SUCCESS|WARNING|ERROR|DEBUG)\]\s*(.*)/;
	# These installer messages remain in its log but do not belong in CLI output.
	return if ($level && $level eq 'INFO' && $message =~ /^Swap setup log is written to /);
	return if ($level && $level eq 'ERROR' && $message =~ /^Re-run the installer with --no-swap(?: instead of --swap)? to skip swap setup\.$/);
	return if ($level && $message eq 'Started swap setup');
	return if ($level && $message eq 'Swap setup completed successfully.');
	# Omit sentence-ending periods in CLI messages, preserving ellipses.
	$message =~ s/(?<!\.)\.\s*$// if ($level);
	if ($level && $level eq 'ERROR') {
		push(@errors, $message);
		}
	else {
		$line =~ s/[\r\n]+$//;
		# Use Virtualmin's progress suffix without duplicating existing dots.
		$message .= " .." if ($level && $message !~ /\.\.\s*$/);
		&$first_print($level ? ($level eq 'WARNING' ? "Warning: $message" : $message) : $line)
			if ($line ne '');
		$progress = 1 if ($downloaded && $line ne '');
		}
	};

# Stream complete lines and retain diagnostics if reading fails.
while (1) {
	my $n = sysread($output, my $chunk, 4096);
	if (!defined($n)) {
		next if ($!{EINTR});
		push(@errors, "Failed to read swap setup output: $!");
		$read_error = 1;
		last;
		}
	last if (!$n);
	$pending .= $chunk;
	while ($pending =~ s/^(.*?\n)//s) {
		&$show_line($1);
		}
	}
&$show_line($pending) if ($pending ne '');
close($output);
my $st = $?;
my $status = $st == -1 ? 1 : $st & 127 ? 128 + ($st & 127) : $st >> 8;
$status ||= 1 if ($read_error);
&$first_print("Error: $_") for ($status ? () : @errors);
# Close the swap operation before reporting the overall command result.
my $error = @errors ? join('; ', @errors)
		    : "Swap setup failed (exit status $status)";
# Include the log hint only once configuring has started, and never repeat the
# path when the installer's own error already gives it.
my $log = "$module_var_directory/virtualmin-swap.log";
$error .= "; see $log for more details"
	if ($status && $downloaded && -s $log && index($error, $log) < 0);
# Fail the configuration stage directly if no inner operation was announced.
if ($status && $downloaded && !$progress) {
	&$outdent_print();
	&$first_print(".. failed : ".lcfirst($error));
	return $status;
	}
&$first_print($status ? ".. error : ".lcfirst($error) : ".. done");
if ($downloaded) {
	&$outdent_print();
	&$first_print($status ? ".. failed" : ".. done");
	}
return $status;
}

sub usage
{
print STDERR "$_[0]\n\n" if ($_[0]);
print "Configure swap space automatically or with a specified size.\n\n";
print "virtualmin configure-swap [--size <size>]\n\n";
print "  --size    Swap size in MiB, or with K/M/G suffix; 0 removes it\n";
exit($_[0] ? 1 : 0);
}
