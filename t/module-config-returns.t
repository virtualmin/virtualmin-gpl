#!/usr/bin/perl
# The public config writers are mutation-only helpers with a void return.
# Reject call sites that rely on their return value so this contract stays
# independent from the private merge implementation.

use strict;
use warnings;
use Test::More;
use File::Find;
use File::Basename qw(dirname);
use File::Spec;
use Cwd qw(abs_path);

my $root = abs_path(File::Spec->catdir(dirname(__FILE__), '..'));
my @flagged;

sub scan_file
{
my ($file) = @_;
open(my $fh, '<', $file) || die "Failed to read $file: $!";
my @lines = <$fh>;
close($fh);
for (my $i = 0; $i < @lines; $i++) {
	my $line = $lines[$i];
	if ($line =~ /\breturn\s+&?save_module_config_(?:keys|diff)/ ||
	    $line =~ /=\s*&?save_module_config_(?:keys|diff)/ ||
	    $line =~ /\b(?:if|unless|while)\s*\(\s*&?save_module_config_(?:keys|diff)/) {
		push(@flagged, $file =~ s/^\Q$root\E\///r.":".($i + 1));
		}
	}
}

find({
	no_chdir => 1,
	wanted => sub {
		my $name = $File::Find::name;
		if (-d $name) {
			$File::Find::prune = 1
				if ($name =~ m{/(?:\.git|t)$});
			return;
			}
		return if ($name !~ /\.(?:pl|cgi)$/);
		&scan_file($name);
		},
	}, $root);

is_deeply(\@flagged, [ ],
	'no caller relies on a public config writer return value');

done_testing();
