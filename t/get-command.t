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

# Exercise the real metadata parser without loading Webmin or running commands.
write_file("$tmp/example.pl", "=head1 example.pl\n\nFixture command.\n\n=cut\n");
write_file("$tmp/driver.pl", <<'PERL');
package virtual_server;
$module_name = 'virtual-server';
$module_root_directory = $config_directory = $ENV{'TEST_MODULE'};
@plugins = ();
sub parse_common_cli_flags { }
sub master_admin { 1 }
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

sub parse_help {
	my ($help) = @_;
	my $pid = fork();
	die "fork: $!" if !defined($pid);
	if (!$pid) {
		$ENV{'TEST_MODULE'} = $tmp;
		$ENV{'TEST_ENTRY'} = "$root/get-command.pl";
		$ENV{'TEST_HELP'} = "virtualmin example $help\n\n";
		open(STDOUT, '>', "$tmp/output") or die $!;
		open(STDERR, '>&STDOUT') or die $!;
		exec { $^X } $^X, "$tmp/driver.pl", '--command', 'example';
		die "exec: $!";
	}
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

done_testing();
