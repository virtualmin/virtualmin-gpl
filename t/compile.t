#!/usr/bin/perl
# Verify every .pl and .cgi in the tree parses with perl -c.
#
# This catches syntax and `use` breakage from mechanical refactors without
# loading every page in a browser.
#
# Skipped:
#   - $file.pl when a sibling $file exists without the .pl suffix. .pl is also
#     the Polish translation suffix, so module.info.pl, config.info.pl, and
#     similar files are data files, not Perl.
#   - Files that fail only because of a missing CPAN module. The file itself
#     parses, but `use Foo::Bar` cannot resolve at compile time. These are
#     treated as skips so missing optional deps do not gate the local suite.
#     Set VIRTUALMIN_COMPILE_T_STRICT=1 to turn these into failures.
#
# Narrow with VIRTUALMIN_COMPILE_T_FILTER=<regex> when iterating on a specific
# area.

use strict;
use warnings;
use Test::More;
use File::Find;
use File::Basename qw(dirname);
use File::Spec;
use Cwd qw(abs_path);
use IPC::Open3;
use IO::Select;
use Symbol qw(gensym);

my $root = abs_path(File::Spec->catdir(dirname(__FILE__), '..'));
chdir($root) or die "chdir($root): $!";

my $filter = $ENV{'VIRTUALMIN_COMPILE_T_FILTER'};
my $strict = $ENV{'VIRTUALMIN_COMPILE_T_STRICT'};

my @files;
find({
	no_chdir => 1,
	wanted => sub {
		my $name = $File::Find::name;
		if (-d) {
			if ($name =~ m{^\./\.(git|hg|svn)\z}) {
				$File::Find::prune = 1;
				}
			return;
			}
		return if $name !~ /\.(pl|cgi)\z/;

		# Skip Polish translations that share the .pl suffix.
		if ($name =~ m{(.+)\.pl\z}) {
			my $base = $1;
			return if -f $base;
			}

		push(@files, $name);
		},
	}, '.');

@files = sort @files;
@files or BAIL_OUT("found no .pl/.cgi scripts under $root");

if ($filter) {
	@files = grep { /$filter/ } @files;
	if (!@files) {
		diag("filter '$filter' matched zero files");
		plan skip_all => "no files match filter";
		}
	}

diag("compile-checking ".scalar(@files)." files");

for my $file (@files) {
	my $rel = $file;
	$rel =~ s{^\./}{};
	my ($status, $out) = &run_compile_check($rel);

	if (!$status && $out =~ /\bsyntax OK\b/) {
		pass("$rel compiles");
		}
	elsif (!$strict && $out =~ /Can't locate (\S+\.pm) in \@INC/) {
		SKIP: { skip("$rel: missing optional CPAN module $1", 1); }
		}
	else {
		fail("$rel compiles");
		diag($out);
		}
	}

done_testing();

sub run_compile_check
{
my ($file) = @_;
my $err = gensym();
my $pid = open3(my $in, my $out, $err, $^X, '-I.', '-c', '--', $file);
close($in);

my $combined = '';
my $select = IO::Select->new($out, $err);
while (my @ready = $select->can_read()) {
	foreach my $fh (@ready) {
		my $buf;
		my $bytes = sysread($fh, $buf, 8192);
		if ($bytes) {
			$combined .= $buf;
			}
		else {
			$select->remove($fh);
			close($fh);
			}
		}
	}

waitpid($pid, 0);
return ($?, $combined);
}
