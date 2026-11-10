#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Basename qw(dirname);
use File::Spec;
use File::Temp qw(tempdir);
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

ok(&valid_script_install_path('/'), 'root install path is valid');
ok(&valid_script_install_path('/apps/my_app-1.2'),
	'plain nested install path is valid');
ok(&valid_script_install_path("/apps/\xC3\xA9"),
	'non-ASCII install path bytes are valid');
foreach my $path ('relative', '/two words', q{/quote'value}, '/$(id)',
		  "/line\nbreak", '/apps/../other') {
	ok(!&valid_script_install_path($path),
		"unsafe install path is rejected: $path");
	}

{
	no warnings qw(once redefine);
	my $dir = tempdir(CLEANUP => 1);
	my $scripts = File::Spec->catdir($dir, 'scripts');
	mkdir($scripts) || die "Cannot create $scripts: $!";
	my $marker = File::Spec->catfile($dir, 'loaded');
	my $escape = File::Spec->catfile($dir, 'escape.pl');
	open(my $fh, '>', $escape) || die "Cannot write $escape: $!";
	print {$fh} 'open(my $fh, \'>\', \''.$marker.
		    '\') || die $!; print {$fh} \'loaded\'; close($fh); 1;'."\n";
	close($fh);
	# Confirm the fixture can execute before testing the rejected lookup.
	ok(do($escape), 'traversal fixture is executable Perl');
	ok(-e $marker, 'traversal fixture creates its marker when loaded');
	unlink($marker) || die "Cannot remove $marker: $!";
	local @main::scripts_directories = ($scripts);
	local *main::list_script_plugins = sub { return (); };
	local *main::check_script_plugins_extensions = sub { return (); };
	ok(!&get_script('../escape'), 'script names cannot traverse directories');
	ok(!-e $marker, 'rejected script names are not loaded');
}

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
	like($source, qr/valid_script_install_path\s*\(\$opts->\{'path'\}\)/,
		"$installer validates the URL path it is given");
	if ($installer eq 'install-script.pl') {
		# Flags are validated when parsed, and --opt cannot replace them.
		# Upgrades reuse stored options and are not re-validated.
		like($source, qr/valid_script_install_path\s*\(\$forcedir\)/,
			"$installer validates the forced directory flag");
		like($source,
			qr/indexof\(\$oname,\s*"path",\s*"dir",\s*"db",\s*"newdb"\)/,
			"$installer stops --opt from replacing validated options");
		}
	else {
		like($source,
			qr/if \(!\$sinfo\) \{.*?valid_script_install_path\s*\(\$opts->\{'dir'\}\)/s,
			"$installer validates the directory for new installs only");
		}
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
