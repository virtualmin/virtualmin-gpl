#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use FindBin;
use File::Temp qw(tempdir);
use Cwd qw(abs_path);

my $root = abs_path("$FindBin::Bin/..");
my $tmp = tempdir(DIR => '/tmp', CLEANUP => 1);

sub write_file {
	my ($path, $text) = @_;
	open(my $fh, '>', $path) or die "$path: $!";
	print $fh $text;
	close($fh) or die "$path: $!";
}

# Stub command help so the real metadata parser needs no Webmin installation.
write_file("$tmp/example.pl", "=head1 example.pl\n\nFixture command.\n\n=cut\n");
mkdir("$tmp/pro") or die $!;
write_file("$tmp/pro/pro-example.pl", "=head1 pro-example.pl\n\nFixture command.\n\n=cut\n");
write_file("$tmp/driver.pl", <<'PERL');
package virtual_server;
$module_name = 'virtual-server';
$module_root_directory = $config_directory = $ENV{'TEST_MODULE'};
@plugins = ();
sub parse_common_cli_flags { }
# master_admin(): use an ordinary master unless this is an API account case.
sub master_admin { !$ENV{'TEST_API'} }
# is_api_access_user(): select dedicated-account help when the case requests it.
sub is_api_access_user { $ENV{'TEST_API'} }
# is_api_account_command(name): fixture commands have no terminal-only rule.
sub is_api_account_command { 0 }
# is_remote_api_request(): mark dedicated-account cases as HTTP requests.
sub is_remote_api_request { $ENV{'TEST_API'} }
# can_remote_as_user(name): the Pro fixture command has an explicit grant.
sub can_remote_as_user { 1 }
# get_api_access_command(name): resolve the fixture stored only in the Pro folder.
sub get_api_access_command {
	return { path => "$module_root_directory/pro/pro-example.pl",
		provider => 'virtual-server/pro' };
}
# prepare_api_access_command(name, &args): retain the granted fixture provider.
sub prepare_api_access_command { return get_api_access_command($_[0]); }
# execute_webmin_script(path, provider, &args, output-fh): fork fixture help.
# args is an argv arrayref. The parent closes output-fh and returns the PID.
sub execute_webmin_script {
	my ($path, $provider, $args, $out) = @_;
	-r $path || die "Missing provider script";
	my $pid = fork();
	defined($pid) || die $!;
	if (!$pid) {
		# The child writes only fixture help and cannot run system commands.
		print $out $ENV{'TEST_HELP'};
		close($out);
		exit(0);
	}
	# Release the parent's writer so the real parser can read through EOF.
	close($out);
	return $pid;
}
sub require_remote_api_command { }
sub api_command_unavailable_message { return undef; }
sub clean_environment { }
sub reset_environment { }
sub read_file_contents {
	open(my $fh, '<', $_[0]) or die $!;
	local $/;
	return <$fh>;
}
sub backquote_command { return $ENV{'TEST_HELP'}; }
do $ENV{'TEST_ENTRY'};
die $@ if $@;
PERL

# parse_help(help, [api]): return the real parser's exit status and output.
# help supplies the usage flags. api defaults to false; true uses the Pro stub.
sub parse_help {
	my ($help, $api) = @_;
	my $pid = fork();
	die "fork: $!" if !defined($pid);
	if (!$pid) {
		# Isolate request globals and capture output in a child.
		$ENV{'TEST_MODULE'} = $tmp;
		$ENV{'TEST_ENTRY'} = "$root/get-command.pl";
		$ENV{'TEST_HELP'} = "virtualmin example $help\n\n";
		$ENV{'TEST_API'} = $api || '';
		# Select the ordinary or Pro-only command for this case.
		open(STDOUT, '>', "$tmp/output") or die $!;
		open(STDERR, '>&STDOUT') or die $!;
		exec { $^X } $^X, "$tmp/driver.pl", '--command', $api ? 'pro-example' : 'example';
		die "exec: $!";
	}
	# Wait before reading so partial output cannot produce a false match.
	waitpid($pid, 0);
	my $status = $? >> 8;
	open(my $fh, '<', "$tmp/output") or die $!;
	local $/;
	return ($status, <$fh>);
}

# Assert complete metadata so argument boundaries and value types are checked.
sub metadata {
	my (@flags) = @_;
	my $out = "Description: Fixture command.\n";
	for my $flag (@flags) {
		my ($name, $value, $optional, $repeat) = @$flag;
		$out .= "$name\n    Binary: ".(defined($value) ? 'No' : 'Yes')."\n";
		$out .= "    Value: $value\n" if defined($value);
		$out .= "    Optional: ".($optional ? 'Yes' : 'No')."\n";
		$out .= "    Repeats: ".($repeat || 'No')."\n";
	}
	return $out;
}

my @cases = (
	[ 'optional size and confirmation', '[--size <size>] [--yes]',
		[ 'size', 'size', 1 ], [ 'yes', undef, 1 ] ],
	[ 'branch choices stay one value', '[--branch <stable|prerelease|unstable>]',
		[ 'branch', 'stable|prerelease|unstable', 1 ] ],
	[ 'unwrapped required value', '--size <size> [--yes]',
		[ 'size', 'size', 0 ], [ 'yes', undef, 1 ] ],
	[ 'placeholder inside required group', '<--domain <name>> [--yes]',
		[ 'domain', 'name', 0 ], [ 'yes', undef, 1 ] ],
	[ 'multiple placeholders in required alternatives', '<--domain <name> | --id <number>>+',
		[ 'domain', 'name', 0, '1 or more times' ], [ 'id', 'number', 0, '1 or more times' ] ],
	[ 'optional alternatives and repetition', '[--file <path> | --stdin]*',
		[ 'file', 'path', 1, '0 or more times' ], [ 'stdin', undef, 1, '0 or more times' ] ],
	[ 'mixed quoted and bracketed values', '[--label "display name" --size <size>]',
		[ 'label', 'display name', 1 ], [ 'size', 'size', 1 ] ],
	[ 'required groups after bare flags are not values', '--yes <--domain name> <--verbose>',
		[ 'yes', undef, 0 ], [ 'domain', 'name', 0 ], [ 'verbose', undef, 0 ] ],
	[ 'separate required groups with placeholders', '<--domain <name>> <--user <name>>',
		[ 'domain', 'name', 0 ], [ 'user', 'name', 0 ] ],
	[ 'existing bare, quoted and optional values', '--domain name --owner "full name" [--disabled]',
		[ 'domain', 'name', 0 ], [ 'owner', 'full name', 0 ], [ 'disabled', undef, 1 ] ],
	[ 'existing required groups and repetition', '<--domain name>+ [--user "full name"]*',
		[ 'domain', 'name', 0, '1 or more times' ], [ 'user', 'full name', 1, '0 or more times' ] ],
	[ 'existing value choices and flag alternatives', '[--type mysql|postgres] [--enable | --disable]',
		[ 'type', 'mysql|postgres', 1 ], [ 'enable', undef, 1 ], [ 'disable', undef, 1 ] ],
	[ 'multiline help keeps argument boundaries', "[--size <size>]\n                  [--yes]",
		[ 'size', 'size', 1 ], [ 'yes', undef, 1 ] ],
);

for my $case (@cases) {
	my ($name, $help, @flags) = @$case;
	subtest $name => sub {
		my ($status, $out) = parse_help($help);
		is($status, 0, 'help can be parsed');
		is($out, metadata(@flags), 'metadata preserves values and argument properties');
	};
}

subtest 'malformed placeholders report errors' => sub {
	for my $help ('[--size <size]', '[--size <>]', '<--size <size>', '--size <size') {
		my ($status, $out) = parse_help($help);
		is($status, 1, "rejects $help");
		like($out, qr/Cannot parse (?:args|flag)/, 'reports a parse error');
	}
};

# Metadata must find a granted Pro command even without a core script copy.
subtest 'API metadata uses the granted Pro provider' => sub {
	my ($status, $out) = parse_help('--domain name', 1);
	is($status, 0, 'Pro-only command help is available to its API grantee');
	is($out, metadata(['domain', 'name', 0]), 'returns the authorized provider metadata');
};

done_testing();
