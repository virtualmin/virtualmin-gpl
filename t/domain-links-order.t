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

# Numeric priorities order top-level domain shortcuts around optional links.
my @links = (
	{ 'url' => '/edit', 'cat' => 'objects', 'order' => 100 },
	{ 'url' => '/server', 'cat' => 'server' },
	{ 'url' => '/scripts', 'cat' => 'objects', 'order' => 500 },
	{ 'url' => '/plugin-default', 'cat' => 'objects' },
	{ 'url' => '/containers', 'cat' => 'objects', 'order' => 400 },
	{ 'url' => '/web', 'cat' => 'web' },
	{ 'url' => '/files', 'cat' => 'objects', 'order' => 600 },
);
&order_domain_object_links(\@links);
is_deeply([ map { $_->{'url'} } @links ],
	[ qw(/edit /server /containers /scripts /files /web /plugin-default) ],
	'object shortcuts use priorities without displacing other categories');

# Equal, omitted and invalid priorities retain their original relative order.
my @stable = (
	{ 'url' => '/one', 'cat' => 'objects', 'order' => 10 },
	{ 'url' => '/two', 'cat' => 'objects', 'order' => 10 },
	{ 'url' => '/default-one', 'cat' => 'objects' },
	{ 'url' => '/invalid', 'cat' => 'objects', 'order' => -1 },
	{ 'url' => '/default-two', 'cat' => 'objects' },
);
&order_domain_object_links(\@stable);
is_deeply([ map { $_->{'url'} } @stable ],
	[ qw(/one /two /default-one /invalid /default-two) ],
	'equal and default domain-link priorities remain stable');

done_testing();
