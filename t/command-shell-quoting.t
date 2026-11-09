#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Basename qw(dirname);
use File::Spec;
use File::Temp qw(tempdir);
use Cwd qw(abs_path);
use Storable qw(retrieve);

my $root = abs_path(File::Spec->catdir(dirname(__FILE__), '..'));
my $lib = File::Spec->catfile($root, 'virtual-server-lib-funcs.pl');
my $loaded = do $lib;
die $@ if ($@);
die "Failed to load $lib: $!" if (!defined($loaded));

my $dir = tempdir(CLEANUP => 1);
my $helper = File::Spec->catfile($dir, 'capture.pl');
my $capture = File::Spec->catfile($dir, 'arguments');
my $marker = File::Spec->catfile($dir, 'injected');
open(my $fh, '>', $helper) || die "Cannot write $helper: $!";
print {$fh} <<'PERL';
use strict;
use warnings;
use Storable qw(nstore);
my $capture = shift(@ARGV);
nstore(\@ARGV, $capture);
PERL
close($fh);

# Use a real child process to check the wrappers' final argument boundaries.
my $wrapper = File::Spec->catfile($dir, 'virtualmin');
open($fh, '>', $wrapper) || die "Cannot write $wrapper: $!";
print {$fh} '#!'.$^X."\n", <<'PERL';
use Storable qw(nstore);
nstore(\@ARGV, $ENV{'QUOTING_CAPTURE'});
print "captured\n";
PERL
close($fh);
chmod(0700, $wrapper) || die "Cannot chmod $wrapper: $!";
local $ENV{'PATH'} = $dir.':'.$ENV{'PATH'};
local $ENV{'QUOTING_CAPTURE'} = $capture;

my @args = (
	'plain',
	'two words',
	"line\nbreak",
	"quote'value",
	'',
	'*',
	'; touch ignored',
	'`touch '.$marker.'`',
	'$(touch '.$marker.')',
	);
my $cmd = &shell_quote_command_args($^X, $helper, $capture, @args);
is(system($cmd), 0, 'quoted arguments execute successfully');
is_deeply(retrieve($capture), \@args,
	'quoted arguments reach the child without interpolation or data loss');
ok(!-e $marker, 'shell syntax inside arguments is not executed');

my $value = "O'Brien \$(touch $marker) `touch $marker`\n--domain foreign.test";
my ($status, $output) = run_script('run-api-command.pl', 'modify-user',
	'--real', $value);
is($status, 0, 'batch wrapper executes its child');
diag($output) if ($status);
is_deeply(retrieve($capture),
	[ 'modify-user', '--domain', 'owned.test', '--real', $value ],
	'batch wrapper preserves literal values without injecting options');
ok(!-e $marker, 'batch wrapper does not execute input');

done_testing();

# run_script(file, arguments...)
# Run a real command with fixture domain lookups and capture its output.
sub run_script
{
my ($file, @args) = @_;
pipe(my $reader, my $writer) || die $!;
my $pid = fork();
defined($pid) || die $!;
if (!$pid) {
	# Keep each command's package globals and exit calls in its own process.
	close($reader);
	open(STDOUT, '>&', $writer) || die $!;
	open(STDERR, '>&', $writer) || die $!;
	close($writer);
	chdir($dir) || die $!;
	@ARGV = @args;
	my $loaded = do "$root/$file";
	die $@ if ($@);
	die $! if (!defined($loaded));
	CORE::exit(0);
	}
# Drain command output before waiting so the child cannot fill its pipe.
close($writer);
local $/;
my $output = <$reader>;
close($reader);
waitpid($pid, 0);
return ($?, $output);
}

{
package virtual_server;
our $module_name;
BEGIN { $module_name = 'virtual-server'; }
our ($first_print, $indent_print, $outdent_print);
# Fixture lookups leave command parsing and shell execution in the real scripts.
sub licence_status { }
sub require_mail { }
sub is_api_access_user { return 0; }
sub list_plans { return (); }
sub list_domains { return { dom => 'owned.test' }; }
sub get_domains_by_names_users { return list_domains(); }
sub list_domain_users { return { user => 'one' }; }
sub remove_userdom { return $_[0]; }
sub parse_common_cli_flags { }
sub trim { my $v = $_[0]; $v =~ s/^\s+|\s+$//g; return $v; }
sub shell_quote_command_args { return main::shell_quote_command_args(@_); }
# open_execute_command(handle, command, capture): run the wrapper's real shell.
sub open_execute_command
{
no strict 'refs';
open(*{'virtual_server::'.$_[0]}, '-|', '/bin/sh', '-c', $_[1]) || die $!;
}
# execute_command(command, input, &output, [&errors]): use a real POSIX shell.
sub execute_command
{
my ($command, $input, $out, $err) = @_;
open(my $pipe, '-|', '/bin/sh', '-c', $command.' 2>&1') || die $!;
local $/;
$$out = <$pipe>;
close($pipe);
return $?;
}
# set_all_text_print(): supply the command's plain-text output callbacks.
sub set_all_text_print
{
$first_print = sub { print @_, "\n"; };
$indent_print = $outdent_print = sub { };
}
}
