#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Basename qw(dirname);
use File::Spec;
use Cwd qw(abs_path);

my $root = abs_path(File::Spec->catdir(dirname(__FILE__), '..'));
my $lib = File::Spec->catfile($root, 'scripts-lib.pl');
my $loaded = do $lib;
die $@ if ($@);
die "Failed to load $lib: $!" if (!defined($loaded));

is_deeply(
	[ &php_versioned_module_packages('mysqlnd', '8.4', 'yum') ],
	[ 'php8.4-mysqlnd', 'php84-mysqlnd' ],
	'RPM package candidates include the dotted RHEL 10 PHP stream name');

is_deeply(
	[ &php_versioned_module_packages('mysql', '8.4', 'apt') ],
	[ 'php8.4-mysql' ],
	'Debian package candidates retain the dotted PHP version');

is_deeply(
	[ &php_versioned_module_packages('mysqlnd', '8.4', 'other') ],
	[ 'php84-mysqlnd' ],
	'other package managers retain the legacy dotless form');

{
	no warnings qw(once redefine);
	local *main::get_balancer_usage = sub {
		my ($domain, $script_usage, $plugin_usage) = @_;
		$plugin_usage->{'/'} = {
			'plugin' => 'virtualmin-podman',
			'path' => '/',
			};
		$plugin_usage->{'/blog/'} = {
			'plugin' => 'virtualmin-podman',
			'path' => '/blog/',
			};
		};
	local *main::list_proxy_balancers = sub {
		return (
			{ 'path' => '/proxied/', 'urls' => [ 'http://127.0.0.1:8000' ] },
			{ 'path' => '/available/', 'none' => 1 },
			);
		};
	my $usage = &script_path_used_by_proxy({ 'id' => 42 }, '/');
	is($usage->{'plugin'}, 'virtualmin-podman',
		'plugin-owned root application path is detected');
	is(&script_path_used_by_proxy({ 'id' => 42 }, '/blog')->{'path'},
		'/blog/', 'equivalent trailing slash paths are detected');
	is(&script_path_used_by_proxy({ 'id' => 42 }, '/proxied')->{'path'},
		'/proxied/', 'active proxy paths are detected from web configuration');
	ok(!&script_path_used_by_proxy({ 'id' => 42 }, '/available'),
		'non-proxy path overrides remain available');
	ok(!&script_path_used_by_proxy({ 'id' => 42 }, '/other'),
		'unowned application path remains available');
}

foreach my $installer (qw(script_install.cgi install-script.pl)) {
	my $path = File::Spec->catfile($root, $installer);
	open(my $fh, '<', $path) || die "Cannot read $path: $!";
	local $/ = undef;
	my $source = <$fh>;
	close($fh);
	like($source, qr/script_path_used_by_proxy\s*\(/,
		"$installer checks active and feature-plugin proxy paths");
	like($source,
		qr/if \(!\$sinfo && &script_path_used_by_proxy\s*\(/,
		"$installer checks proxy paths independently of script overlap");
	like($source,
		qr/text\('scripts_epluginclash',\s*(?:"<tt>)?\$opts->\{'path'\}/,
		"$installer reports the conflicting URL path");
	like($source, qr/\$text\{'scripts_epluginclashroot'\}/,
		"$installer reports root conflicts without a technical path");
	if ($installer eq 'script_install.cgi') {
		like($source,
			qr/has_proxy_balancer\s*\(\$d\).*can_edit_forward\s*\(\)/s,
			'GUI links to accessible proxy-path management');
		like($source, qr/scripts_epluginclashproxy/,
			'GUI appends proxy-path guidance to plugin conflicts');
		}
}

done_testing();
