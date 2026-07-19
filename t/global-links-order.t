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

# Numeric priorities sort links while ties and omitted values remain stable.
my @links = (
	{ 'url' => '/default-one' },
	{ 'url' => '/third', 'order' => 3 },
	{ 'url' => '/first', 'order' => 1 },
	{ 'url' => '/second', 'order' => 2 },
	{ 'url' => '/default-two' },
);
&order_plugin_global_links(\@links);
is_deeply([ map { $_->{'url'} } @links ],
	[ qw(/first /second /third /default-one /default-two) ],
	'numeric priorities sort before stable default links');

# Categorized links remain untouched while top-level links use their slots.
my @categories = (
	{ 'url' => '/a-default', 'cat' => 'a' },
	{ 'url' => '/top-default' },
	{ 'url' => '/a-first', 'cat' => 'a', 'order' => 1 },
	{ 'url' => '/top-first', 'order' => 1 },
);
&order_plugin_global_links(\@categories);
is_deeply([ map { $_->{'url'} } @categories ],
	[ qw(/a-default /top-first /a-first /top-default) ],
	'categorized links remain in their original positions');

# A top-level before hint cannot target or displace a categorized link.
my @cross_category = (
	{ 'url' => '/categorized', 'cat' => 'a' },
	{ 'url' => '/top-one' },
	{ 'url' => '/top-two', 'before' => '/categorized' },
);
&order_plugin_global_links(\@cross_category);
is_deeply([ map { $_->{'url'} } @cross_category ],
	[ qw(/categorized /top-one /top-two) ],
	'before hint ignores categorized targets');

# A relative hint overrides numeric order for an exact target.
my @relative = (
	{ 'url' => '/first', 'order' => 1 },
	{ 'url' => '/target', 'order' => 2 },
	{ 'url' => '/before', 'order' => 3, 'before' => '/target' },
);
&order_plugin_global_links(\@relative);
is_deeply([ map { $_->{'url'} } @relative ],
	[ qw(/first /before /target) ],
	'before hint takes precedence over numeric order');

# Missing targets leave the existing plugin order unchanged.
my @missing = (
	{ 'url' => '/one' },
	{ 'url' => '/two', 'before' => '/not-installed' },
);
&order_plugin_global_links(\@missing);
is_deeply([ map { $_->{'url'} } @missing ], [ qw(/one /two) ],
	'missing target preserves existing global link order');

# Multiple links targeting the same URL retain their original order.
my @peers = (
	{ 'url' => '/target' },
	{ 'url' => '/one', 'before' => '/target' },
	{ 'url' => '/two', 'before' => '/target' },
);
&order_plugin_global_links(\@peers);
is_deeply([ map { $_->{'url'} } @peers ],
	[ qw(/one /two /target) ],
	'peer ordering hints remain stable');

done_testing();
