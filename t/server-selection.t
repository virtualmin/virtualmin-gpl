#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Basename qw(dirname);
use File::Spec;

my $root = File::Spec->catdir(dirname(__FILE__), '..');

# Exercise only selection parsing, before any services, files or mail are changed.
sub selection_code {
	my ($file, @bounds) = @_;
	my $path = File::Spec->catfile($root, $file);
	open(my $fh, '<', $path) or die "$path: $!";
	my $source = do { local $/; <$fh> };
	close($fh);
	my $code = '';
	while (@bounds) {
		my ($start, $end) = splice(@bounds, 0, 2);
		my $from = index($source, $start);
		my $to = index($source, $end, $from + length($start));
		die "Missing selection block in $file" if ($from < 0 || $to < 0);
		$code .= substr($source, $from, $to - $from)."\n";
		}
	return $code;
}

my @cases = (
	[ 'save_newips.cgi', 'servers', 'servers_def', 1, undef,
	  '# Work out which domains to update', 'if (!@doms)' ],
	[ 'notify.cgi', 'servers', 'servers_def', 1, undef,
	  "if (\$in{'servers_def'})", "\$in{'subject'}" ],
	[ 'validate.cgi', 'servers', 'servers_def', 1, undef,
	  '# Check and parse inputs', "if (\$in{'features_def'})" ],
	[ 'fixperms.cgi', 'servers', 'servers_def', 1, undef,
	  '# Check and parse inputs', '&ui_print_header' ],
	[ 'bwreset.cgi', 'domains', 'domains_def', 1, undef,
	  "if (\$in{'domains_def'})", '&ui_print_header' ],
	[ 'mass_scripts.cgi', 'servers', 'servers_def', 1, undef,
	  "if (\$in{'servers_def'})", '# Work out who has it' ],
	[ 'save_validate.cgi', 'servers', 'servers_def', 1, 'validate_servers',
	  "if (\$in{'servers_def'})", "if (\$in{'features_def'})" ],
	[ 'save_newretention.cgi', 'doms', 'mode', 0, 'retention_doms',
	  "\$config{'retention_mode'} =", "\$config{'retention_folders'} =" ],
	[ 'save_newbw.cgi', 'servers', 'serversmode', 0, 'bw_servers',
	  "if (\$in{'serversmode'})", '# Save configuration',
	  "\$config{'bw_servers'} =", "\$config{'bw_nomailout'} =" ],
	[ 'save_scriptwarn.cgi', 'servers', 'serversmode', 0, 'scriptwarn_servers',
	  "if (\$in{'serversmode'} == 0)", "\$config{'scriptwarn_email'} =" ],
	);

our (%in, %config, %text, %servers, @doms, @servers, $d, $id, $did);
my @available = map { { 'id' => $_, 'dir' => 1, 'emailto' => 'owner@example.test' } } 1..3;

{
	no warnings qw(once redefine);
	local *main::list_domains = sub { @available };
	local *main::list_visible_domains = sub { @available };
	local *main::get_domain = sub { my $id = shift; (grep { $_->{'id'} eq $id } @available)[0] };
	local *main::can_edit_domain = sub { 1 };
	local *main::can_edit_scripts = sub { 1 };
	local *main::unique = sub { my %seen; grep { !$seen{$_}++ } @_ };
	local *main::error = sub { die "selection rejected\n" };

	foreach my $case (@cases) {
		my ($file, $field, $mode, $all, $key, @bounds) = @$case;
		my $code = selection_code($file, @bounds);
		foreach my $input ("1\n3", "1\r\n3", "1\0".'3') {
			local %in = ( $field => $input, $mode => 1 - $all );
			local (%config, @doms, @servers);
			eval $code;
			is($@, '', "$file accepts the submitted selection");
			my $result = defined($key) ? $config{$key} :
				join(' ', map { $_->{'id'} } @doms);
			is($result, '1 3', "$file retains every selected ID");
			}

		# All mode and exclusion mode retain their existing meanings.
		{
			local %in = ( $field => '', $mode => $all );
			local (%config, @doms, @servers);
			$config{$key} = '1 3' if (defined($key));
			eval $code;
			is($@, '', "$file accepts all-server mode");
			if (defined($key)) {
				ok(!$config{$key}, "$file clears the selected domain list");
				}
			else {
				is_deeply([ map { $_->{'id'} } @doms ], [ 1, 2, 3 ],
					"$file selects all eligible domains");
				}
			}
		if (!$all) {
			local %in = ( $field => "1\n3", $mode => 2 );
			local (%config, @doms, @servers);
			eval $code;
			is($@, '', "$file accepts exclusion mode");
			is($config{$key}, $key eq 'retention_doms' ? '1 3' : '!1 3',
				"$file retains excluded IDs");
			is($config{'retention_mode'}, 2, 'mailbox cleanup retains exclusion mode')
				if ($key eq 'retention_doms');
			}
		elsif ($file ne 'save_newips.cgi') {
			local %in = ( $field => '', $mode => 0 );
			local (%config, @doms, @servers);
			eval $code;
			like($@, qr/selection rejected/, "$file rejects an empty selected list");
			}
		}

	# Parsing multiple IDs must not bypass per-domain access checks.
	local *main::can_edit_domain = sub { $_[0]->{'id'} != 3 };
	foreach my $case (grep { $_->[0] eq 'validate.cgi' || $_->[0] eq 'mass_scripts.cgi' } @cases) {
		local %in = ( 'servers_def' => 0, 'servers' => "1\n3" );
		local (@doms, @servers);
		eval selection_code($case->[0], @$case[5..$#$case]);
		like($@, qr/selection rejected/, "$case->[0] rejects an unauthorized domain");
		}
}

done_testing();
