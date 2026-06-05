#!/usr/bin/perl
# Verify every .pl and .cgi in the tree parses (perl -c).
#
# Catches syntax and `use` breakage from bulk refactors without having
# to load every page in a browser. The test is the first line of defence
# for the "we changed thousands of files mechanically, did anything
# break" question.
#
# Skipped:
#   - $file.pl when a sibling $file (no .pl) exists. .pl is also the
#     Polish translation suffix, so module.info.pl, config.info.pl, etc.
#     are data files, not Perl.
#   - Files that fail only because of a missing CPAN module. The file
#     itself parses, but `use Foo::Bar` can't resolve at compile time.
#     Treated as a skip so missing optional deps don't gate the suite.
#     Set VIRTUALMIN_COMPILE_T_STRICT=1 to turn these into failures.
#
# Narrow with VIRTUALMIN_COMPILE_T_FILTER=<regex> when iterating on a
# specific area.

use strict;
use warnings;
use Test::More;
use File::Find;
use File::Basename qw(dirname);
use File::Spec;
use Cwd qw(abs_path);

my $root = abs_path(File::Spec->catdir(dirname(__FILE__), '..'));
chdir($root) or die "chdir($root): $!";

my $filter = $ENV{VIRTUALMIN_COMPILE_T_FILTER};
my $strict = $ENV{VIRTUALMIN_COMPILE_T_STRICT};

my @files;
find({
	no_chdir => 1,
	wanted => sub {
		return if -d;
		my $name = $File::Find::name;
		return unless $name =~ /\.(pl|cgi)\z/;
		# Skip the Polish translations that share the .pl suffix.
		if ($name =~ m{(.+)\.pl\z}) {
			my $base = $1;
			return if -f "$base";
			}
		push(@files, $name);
		},
	}, '.');

@files = sort @files;
@files or BAIL_OUT("found no .pl/.cgi scripts under $root");

if ($filter) {
	@files = grep { /$filter/ } @files;
	@files or do { diag("filter '$filter' matched zero files"); plan skip_all => "no files match filter"; };
	}

diag("compile-checking " . scalar(@files) . " files");

for my $f (@files) {
	my $rel = $f;
	$rel =~ s{^\./}{};
	my $out = qx{perl -I. -c -- "$rel" 2>&1};
	if ($out =~ /\bsyntax OK\b/) {
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
