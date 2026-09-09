#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Basename qw(dirname);
use File::Spec;
use Cwd qw(abs_path);

our $module_root_directory = abs_path(
	File::Spec->catdir(dirname(__FILE__), '..'));
my $lib = File::Spec->catfile(
	$module_root_directory, 'virtual-server-lib-funcs.pl');
my $loaded = do $lib;
die $@ if ($@);
die "Failed to load $lib: $!" if (!defined($loaded));

# Include a disabled sub-server, a child with an unrelated domain name,
# and a selected domain outside the offered list.
my %domains = (
	1 => { 'dom' => 'example.test' },
	2 => { 'dom' => 'child.example.test', 'parent' => 1, 'disabled' => 1 },
	3 => { 'dom' => 'unrelated.test', 'parent' => 1 },
	4 => { 'dom' => 'outside.test' },
	);
foreach my $id (keys %domains) {
	$domains{$id} = { 'id' => $id, 'parent' => '', 'alias' => '',
			 'created' => 0, %{$domains{$id}} };
	}
my @offered = @domains{3, 2, 1};
my @selected = (2, 4, 99);
my $listopts = {
	'height' => '200px',
	'modes' => { 'name' => 'all', 'value' => 0,
		     'options' => [ [ 1, 'All' ], [ 0, 'Selected' ] ],
		     'hide' => [ 1 ] },
	'children' => { 'name' => 'parent', 'checked' => 1,
			'label' => 'Include sub-servers' },
	};

{
	no warnings qw(once redefine);
	local %main::config = ( 'domains_sort' => 'sub' );
	local %main::text = ( 'servers_disabled' => 'Disabled',
			     'enable_tooltip' => 'Server disabled' );
	local *main::get_domain = sub { return $domains{$_[0]}; };
	local *main::show_domain_name = sub { return $_[0]->{'dom'}; };
	local *main::html_unescape = sub {
		my $value = shift;
		$value =~ s/&#(\d+);/chr($1)/ge;
		return $value;
		};
	local *main::ui_select = sub { return [ 'native', @_ ]; };
	local *main::ui_multi_select = sub { return [ 'legacy', @_ ]; };
	local *main::ui_multi_select_list = sub { return [ 'list', @_ ]; };

	# Dual-list callers retain their styling, selections and disabled state.
	my $legacy = &servers_input('doms', \@selected, \@offered, 1, 1);
	is($legacy->[0], 'legacy', 'omitting list options retains the dual-list widget');
	is_deeply([ @$legacy[4..6] ], [ 5, 1, 1 ],
		'legacy size, add-if-missing and disabled arguments are preserved');
	is($legacy->[3]->[1]->[1], '&nbsp;&nbsp;child.example.test',
		'legacy sub-server labels keep their indentation');
	like($legacy->[3]->[1]->[2], qr/font-style:italic/,
		'legacy disabled servers keep their option styling');

	# List options explicitly opt into the new widget and its domain metadata.
	my $list = &servers_input('doms', \@selected, \@offered, 0, 1, $listopts);
	is($list->[0], 'list', 'list options select the checkbox list');
	is($list->[1], 'doms', 'the submitted field name stays the same');
	is_deeply([ map { [ @$_[0, 1] ] } @{$list->[2]} ],
		[ [ 2, 'child.example.test' ], [ 4, 'outside.test' ], [ 99, 99 ] ],
		'selected IDs retain names, including missing options and unknown IDs');
	is_deeply($list->[2], $legacy->[2],
		'both widgets receive the same selected values');
	is_deeply([ map { $_->{'value'} } @{$list->[3]} ], [ 1, 2, 3 ],
		'domain sorting still puts sub-servers after their parent');
	is_deeply($list->[3]->[1], {
		'value' => 2, 'label' => 'child', 'suffix' => '.example.test',
		'level' => 1, 'tag' => 'Disabled' },
		'sub-server metadata preserves the suffix, indentation and disabled tag');
	is($list->[3]->[2]->{'label'}, 'unrelated.test',
		'a child with a different domain keeps its full name');
	ok(!defined($list->[3]->[2]->{'suffix'}),
		'a non-matching parent suffix is not removed');
	is_deeply($list->[4], { %$listopts, 'disabled' => 0 },
		'optional mode, children and display settings reach the widget');
	ok(!exists($listopts->{'disabled'}), 'caller options are not modified');

	# Folding requires each offered parent to precede its children.
	{
		local $main::config{'domains_sort'} = 'dom';
		my $sorted = &servers_input('doms', [], \@offered, 0, 1, $listopts);
		is_deeply([ map { $_->{'value'} } @{$sorted->[3]} ], [ 1, 2, 3 ],
			'alphabetical sorting keeps children beside their parent');
		}
	my $orphans = &servers_input('doms', [], [ @domains{2, 3, 4} ],
		0, 1, $listopts);
	is_deeply([ map { $_->{'level'} } @{$orphans->[3]} ], [ 0, 0, 0 ],
		'children without an offered parent remain visible when folded');
	is_deeply([ sort map { $_->{'label'} } @{$orphans->[3]} ],
		[ 'child.example.test', 'outside.test', 'unrelated.test' ],
		'children without an offered parent keep their full names');

	# Convert pre-escaped IDN display names only for the plain-label API.
	{
		local *main::show_domain_name = sub {
			return $_[0]->{'id'} == 1 ? '&#1044;.test' :
			       $_[0]->{'id'} == 2 ? 'child.&#1044;.test' : $_[0]->{'dom'};
			};
		my $idn = &servers_input('doms', [ 1 ], [ @domains{1, 2} ], 0, 1, {});
		is($idn->[3]->[0]->{'label'}, "\xD0\x94.test", 'IDN parent label is decoded');
		is($idn->[3]->[1]->{'suffix'}, ".\xD0\x94.test", 'IDN suffix is decoded');
		is($idn->[2]->[0]->[1], "\xD0\x94.test", 'selected IDN labels are decoded');
		my $old = &servers_input('doms', [ 1 ], [ @domains{1, 2} ], 0, 1);
		is($old->[2]->[0]->[1], '&#1044;.test', 'legacy labels keep their entities');
		}

	# Both picker variants support the positional disabled flag.
	my $disabled = &servers_input('doms', \@selected, \@offered, 1, 1, {});
	is_deeply($disabled->[4], { 'disabled' => 1 },
		'the positional disabled flag disables the new widget');

	# Native-select callers keep their output.
	my $native = &servers_input('doms', \@selected, \@offered, 0);
	is($native->[0], 'native', 'omitting multi-select retains the native select');
	is_deeply($native->[3], $legacy->[3], 'native selects keep legacy option formatting');
	is_deeply([ @$native[4..7] ], [ 5, 1, 0, 0 ],
		'native select size, multiple, missing and disabled arguments stay the same');
	}

# Saving the admin picker must retain every selected ID on one config line.
{
	no warnings 'once';
	my $path = File::Spec->catfile($module_root_directory, 'save_admin.cgi');
	open(my $fh, '<', $path) or die "$path: $!";
	my $source = do { local $/; <$fh> };
	close($fh);
	my ($block) = $source =~ /(\t# Save allowed domains\n.*?)(?=\n\t# Save or create the admin)/s;
	die 'Missing admin domain save block' if (!$block);

	our (%in, %text);
	local %text = ( 'admin_edoms' => 'Select at least one server' );
	local *main::error = sub { die $_[0]."\n"; };
	foreach my $case (
		[ "1\n2\n3", '1 2 3', 'checkbox selections' ],
		[ "1\r\n2", '1 2', 'CRLF form submission' ],
		[ "1\0".'2', '1 2', 'repeated form fields' ],
		[ '1', '1', 'single selection' ]) {
		local %in = ( 'doms_def' => 0, 'doms' => $case->[0] );
		my $admin = {};
		eval $block;
		is($@, '', "$case->[2] save successfully");
		is($admin->{'doms'}, $case->[1], "$case->[2] retain all IDs");
		}

	# All-server access clears restrictions; selected mode requires a selection.
	local %in = ( 'doms_def' => 1, 'doms' => '' );
	my $admin = { 'doms' => '1 2' };
	eval $block;
	is($@, '', 'all-server mode saves without an explicit selection');
	ok(!exists($admin->{'doms'}), 'all-server mode clears domain restrictions');
	$in{'doms_def'} = 0;
	eval $block;
	like($@, qr/Select at least one server/, 'empty selected mode is rejected');
}

done_testing();
