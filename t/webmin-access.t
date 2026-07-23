#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Basename qw(dirname);
use File::Spec;
use Cwd qw(abs_path);

my $root = abs_path(File::Spec->catdir(dirname(__FILE__), '..'));
no warnings 'once';
$main::module_root_directory = $root;
$main::module_name = 'virtual-server';
my $lib = File::Spec->catfile($root, 'virtual-server-lib-funcs.pl');
my $loaded = do $lib;
die $@ if ($@);
die "Failed to load $lib: $!" if (!defined($loaded));

my $list_domain_owner_modules = \&main::list_domain_owner_modules;
my $list_available_domain_owner_modules =
	\&main::list_available_domain_owner_modules;
{
no warnings 'redefine';
local *main::require_mysql = sub { $mysql::mysql_version = 'MariaDB 10'; };
local *main::load_plugin_libraries = sub { };
local *main::plugin_defined = sub { return $_[1] eq 'feature_modules'; };
local *main::plugin_call = sub {
	return ([ 'plugin', 'Plugin (managed scope)' ]);
	};
my @foreign_checks;
local *main::foreign_available = sub {
	push(@foreign_checks, $_[0]);
	return $_[0] ne 'custom' && $_[0] ne 'shell' && $_[0] ne 'mail';
	};
my @foreign_install_checks;
local *main::foreign_check = sub {
	push(@foreign_install_checks, $_[0]);
	return $_[0] ne 'custom' && $_[0] ne 'shell';
	};
local @main::plugins = ('sample-plugin');
my @modules = &$list_available_domain_owner_modules();
my ($plugin) = grep { $_->[0] eq 'plugin' } @modules;
is($plugin->[4], 1,
	'plugin-provided modules carry their legacy enabled default in the registry');
ok(!scalar(grep { $_->[0] eq 'custom' || $_->[0] eq 'shell' } @modules),
	'unavailable Webmin modules are omitted from the registry');
ok(scalar(grep { $_->[0] eq 'mail' } @modules),
	'internal capabilities are retained without a foreign module check');
ok(!scalar(grep { $_ eq 'mail' } @foreign_checks),
	'internal capabilities are not passed to foreign_available');
my ($dns) = grep { $_->[0] eq 'dns' } @modules;
ok($dns, 'feature aliases remain listed when their backing module is available');
is(scalar(@$dns), 2,
	'module aliases do not add implementation details to registry entries');
ok(scalar(grep { $_ eq 'bind8' } @foreign_checks),
	'DNS availability is checked against the actual BIND module');
ok(scalar(grep { $_ eq 'filemin' } @foreign_checks),
	'File Manager availability is checked against the filemin module');
ok(!scalar(grep { $_ eq 'file-manager' } @foreign_checks),
	'unused file-manager alias is never checked');
my @cli_modules = &$list_domain_owner_modules();
ok(scalar(grep { $_->[0] eq 'proc' } @cli_modules) &&
   !scalar(grep { $_->[0] eq 'shell' } @cli_modules),
	'CLI registry uses installed module checks without exposing absent modules');
ok(scalar(grep { $_ eq 'proc' } @foreign_install_checks),
	'CLI registry checks installed modules without Webmin user ACL state');
@foreign_checks = ();
@foreign_install_checks = ();
my @policy_modules = &$list_domain_owner_modules();
ok(!scalar(@foreign_checks) && scalar(@foreign_install_checks),
	'policy construction never depends on the calling user Webmin ACL');
is(scalar(@policy_modules), scalar(@cli_modules),
	'policy registry matches the installed module registry');
}

# The one-shot migration must never alter valid enumerated access levels, and
# must be stable when applied more than once. This is checked against the real
# registry, as the synthetic registry used below cannot catch a regression in
# the real module option lists.
{
no warnings 'redefine';
local *main::require_mysql = sub { $mysql::mysql_version = 'MariaDB 10'; };
local *main::load_plugin_libraries = sub { };
local *main::plugin_defined = sub { return $_[1] eq 'feature_modules'; };
local *main::plugin_call = sub {
	return ([ 'plugin', 'Plugin (managed scope)' ]);
	};
local *main::foreign_check = sub { return 1; };
local @main::plugins = ('sample-plugin');
my $stored = 'passwd=2 proc=2 updown=2 plugin=0';
my %normalized = &main::webmin_avail_map(
	&main::normalize_webmin_avail($stored));
is($normalized{'passwd'}.' '.$normalized{'proc'}.' '.$normalized{'updown'},
	'2 2 2',
	'enumerated access levels survive normalization with the real registry');
my $migrated = &main::legacy_webmin_avail($stored);
my %legacy = &main::webmin_avail_map($migrated);
is($legacy{'passwd'}.' '.$legacy{'proc'}.' '.$legacy{'updown'}, '2 2 2',
	'enumerated access levels survive migration with the real registry');
is($legacy{'plugin'}, 1,
	'plugin zeroes are reset to the legacy enabled access on migration');
is(&main::legacy_webmin_avail($migrated), $migrated,
	'migration is stable when applied to an already-migrated policy');
}

my %templates = (
	0 => { 'id' => 0, 'default' => 1,
	       'avail' => 'dns=0 proc=1 plugin=1' },
	10 => { 'avail' => 'dns=1 proc=2 plugin=virtualmin-nginx' },
);
my %domains;
my $can_edit_limits = 1;

{
no warnings 'redefine';
*main::get_template = sub { return $templates{$_[0]}; };
*main::get_domain = sub { return $domains{$_[0]}; };
*main::can_edit_limits = sub { return $can_edit_limits; };
*main::error = sub { die $_[0]."\n"; };
my $test_modules = sub {
	return (
		[ 'dns', 'DNS' ],
		[ 'proc', 'Processes', [ [ 2, 'Own' ], [ 1, 'All' ], [ 0, 'No' ] ] ],
		[ 'plugin', 'Plugin (managed scope)', undef, undef, 1 ],
		);
	};
*main::list_domain_owner_modules = $test_modules;
*main::list_available_domain_owner_modules = $test_modules;
*main::domain_owner_module_registry = sub {
	my @modules = (&$test_modules(), [ 'shell', 'Command Shell' ]);
	return (\@modules, { });
	};
}

{
local %main::config = (
	'avail_dns' => 0,
	'avail_proc' => 2,
	'avail_plugin' => 0,
	'avail_shell' => 1,
	);
my $default_template_saves = 0;
no warnings 'redefine';
local *main::get_template = sub {
	return { 'id' => 0,
		 'avail' => &main::get_default_webmin_avail() };
	};
local *main::save_template = sub {
	my ($tmpl) = @_;
	$main::config{'default_webmin_avail'} = $tmpl->{'avail'};
	$default_template_saves++;
	};
is(&main::get_default_webmin_avail(),
	'dns=0 proc=2 plugin=0 shell=1',
	'legacy owner defaults include unavailable module settings');
ok(&main::migrate_default_webmin_avail(),
	'default owner policy is migrated to its separate config key');
is($default_template_saves, 1,
	'default owner policy is saved through the template API');
is($main::config{'default_webmin_avail'},
	'dns=0 proc=2 plugin=1 shell=1',
	'default owner policy preserves legacy effective plugin access');
is($main::config{'avail_plugin'}, 0,
	'migration does not widen the plugin access used by Pro resellers');
ok(!&main::migrate_default_webmin_avail(),
	'default owner policy migration is idempotent');
is($default_template_saves, 1,
	'idempotent migration does not save the default template again');
}

my $legacy = { 'id' => 100, 'template' => 10 };
is(&main::get_domain_webmin_avail($legacy),
	'dns=1 proc=2 plugin=1',
	'legacy domain falls back to its normalized effective template value');

ok(&main::init_domain_webmin_avail($legacy),
	'initialization snapshots the template value');
is($legacy->{'webmin_avail'}, 'dns=1 proc=2 plugin=1',
	'legacy truthy plugin value is normalized without changing access');

$templates{10}->{'avail'} = 'dns=0 proc=0 plugin=0';
is(&main::get_domain_webmin_avail($legacy), 'dns=1 proc=2 plugin=1',
	'later template changes do not alter domain access');
ok(!&main::init_domain_webmin_avail($legacy),
	'existing per-domain access is never overwritten');

my $partly_migrated = {
	'id' => 106, 'template' => 10,
	'webmin_avail' => 'dns=1 proc=2 plugin=0',
	};
ok(&main::init_domain_webmin_avail($partly_migrated, 1),
	'migration corrects a plugin zero left by an interrupted earlier run');
is($partly_migrated->{'webmin_avail'}, 'dns=1 proc=2 plugin=1',
	'migration preserves the plugin access that the old runtime granted');
ok(!&main::init_domain_webmin_avail($partly_migrated, 1),
	'legacy plugin access migration is idempotent');

$domains{100} = $legacy;
my $child = { 'id' => 101, 'parent' => 100, 'template' => 10 };
is(&main::get_domain_webmin_avail($child), 'dns=1 proc=2 plugin=1',
	'sub-server uses its top-level owner policy');
ok(!&main::init_domain_webmin_avail($child),
	'sub-servers do not receive an independent owner policy');
my $orphan = { 'id' => 105, 'parent' => 999, 'template' => 10 };
is(&main::get_domain_webmin_avail($orphan), 'dns=0 proc=0 plugin=0',
	'a sub-server with a missing parent fails closed');

is(&main::get_template_webmin_avail({ 'id' => 11 }),
	'dns=0 proc=1 plugin=1',
	'custom template without a value inherits the default template');
is(&main::get_template_webmin_avail(
	{ 'id' => 12, 'avail' => 'dns=1 proc=2 plugin=0' }),
	'dns=1 proc=2 plugin=0',
	'custom template with a value uses its own initial access');

$templates{11} = { 'id' => 11 };
my $created = { 'id' => 102, 'template' => 11 };
ok(&main::init_domain_webmin_avail($created),
	'new domain snapshots its inherited template access');
is($created->{'webmin_avail'}, 'dns=0 proc=1 plugin=1',
	'new domain receives the effective template value');
$templates{0}->{'avail'} = 'dns=1 proc=0 plugin=0';
is(&main::get_domain_webmin_avail($created), 'dns=0 proc=1 plugin=1',
	'changing a template default does not alter the created domain');
is(&main::get_template_webmin_avail($templates{11}),
	'dns=1 proc=0 plugin=0',
	'template inheritance still applies to subsequently-created domains');
$templates{0}->{'avail'} = 'dns=0 proc=1 plugin=1';

my $custom_tmpl = { 'id' => 20, 'avail' => 'dns=0 proc=0 plugin=0' };
is(&main::set_template_webmin_avail($custom_tmpl,
	{ 'avail_def' => 0, 'avail_dns' => 1,
	  'avail_proc' => 2, 'avail_plugin' => 0 }), undef,
	'explicit template module access is accepted');
is($custom_tmpl->{'avail'}, 'dns=1 proc=2 plugin=0',
	'explicit template module access is stored in stable order');
{
no warnings 'redefine';
local *main::list_available_domain_owner_modules = sub {
	return ([ 'dns', 'DNS' ]);
	};
my $restricted_tmpl = {
	'id' => 22, 'avail' => 'dns=0 proc=2 plugin=0',
	};
is(&main::set_template_webmin_avail($restricted_tmpl,
	{ 'avail_def' => 0, 'avail_dns' => 1 }), undef,
	'caller-visible template settings can be saved');
is($restricted_tmpl->{'avail'}, 'dns=1 proc=2 plugin=0',
	'saving visible settings preserves modules hidden by the caller ACL');
}
is(&main::set_template_webmin_avail($custom_tmpl,
	{ 'avail_def' => 1 }), undef,
	'custom template can inherit default module access');
ok(!defined($custom_tmpl->{'avail'}),
	'inherited template module access is stored as undefined');

my $default_tmpl = { 'id' => 0, 'default' => 1 };
is(&main::set_template_webmin_avail($default_tmpl,
	{ 'avail_def' => 1, 'avail_dns' => 1,
	  'avail_proc' => 1, 'avail_plugin' => 0 }), undef,
	'default template always stores an explicit module selection');
is($default_tmpl->{'avail'}, 'dns=1 proc=1 plugin=0',
	'default template cannot inherit module access from itself');

my $invalid_tmpl = { 'id' => 21, 'avail' => 'unchanged' };
is(&main::set_template_webmin_avail($invalid_tmpl,
	{ 'avail_def' => 0, 'avail_dns' => 1,
	  'avail_proc' => 9, 'avail_plugin' => 0 }), 'proc',
	'invalid template module access is rejected');
is($invalid_tmpl->{'avail'}, 'unchanged',
	'invalid template module access does not change the template');

$main::text{'edit_egone'} = 'Server no longer exists';
$main::text{'edit_ecannot'} = 'Cannot edit server';
$main::text{'limits_etoplevel'} = 'Owner limits require a top-level server';
is(&main::get_editable_limits_domain(100), $legacy,
	'owner limits resolve an existing editable domain');
eval { &main::get_editable_limits_domain(999); };
like($@, qr/Server no longer exists/,
	'owner limits reject a stale domain before rendering or saving');
$domains{101} = $child;
eval { &main::get_editable_limits_domain(101); };
like($@, qr/Owner limits require a top-level server/,
	'owner limits reject sub-servers at the shared CGI boundary');
$can_edit_limits = 0;
eval { &main::get_editable_limits_domain(100); };
like($@, qr/Cannot edit server/,
	'owner limits reject a domain without edit permission');
$can_edit_limits = 1;

my ($serialized, $bad) = &main::make_webmin_avail(
	{ 'dns' => 0, 'proc' => 1, 'plugin' => 1 });
is($bad, undef, 'valid module access levels are accepted');
is($serialized, 'dns=0 proc=1 plugin=1', 'module settings serialize stably');
my %mapped = &main::webmin_avail_map($serialized);
ok(exists($mapped{'dns'}) && $mapped{'dns'} eq '0',
	'disabled module entries remain explicit for ACL enforcement');
ok(!&main::webmin_avail_enabled(\%mapped, 'dns', 1),
	'explicitly disabled plugin module access overrides the legacy default');
ok(&main::webmin_avail_enabled(\%mapped, 'unregistered-plugin', 1),
	'unregistered plugin modules retain the legacy allow-by-default behavior');

($serialized, $bad) = &main::make_webmin_avail(
	{ 'dns' => 2, 'proc' => 1, 'plugin' => 1 });
is($serialized, undef, 'invalid binary access level is rejected');
is($bad, 'dns', 'invalid module is identified');

($serialized, $bad) = &main::make_webmin_avail(
	{ 'dns' => 1, 'proc' => 3, 'plugin' => 1 });
is($serialized, undef, 'invalid enumerated access level is rejected');
is($bad, 'proc', 'invalid enumerated module is identified');

is(&main::normalize_webmin_avail(
	'dns=1 proc=invalid plugin=virtualmin-nginx'),
	'dns=1 proc=0 plugin=1',
	'legacy values normalize safely and preserve truthy binary access');

is(&main::normalize_webmin_avail(
	'dns=1 proc=2 plugin=0 unavailable-z=1 unavailable-a=custom=value'),
	'dns=1 proc=2 plugin=0 unavailable-a=custom=value unavailable-z=1',
	'normalization preserves unavailable module settings in stable order');

is(&main::normalize_webmin_avail('dns=1 proc=2'),
	'dns=1 proc=2 plugin=1',
	'a newly registered plugin module retains its legacy enabled default');
is(&main::normalize_webmin_avail('', 1),
	'dns=0 proc=0 plugin=0',
	'module defaults can be suppressed when no owner policy can be resolved');
is(&main::legacy_webmin_avail('dns=1 proc=2 plugin=0'),
	'dns=1 proc=2 plugin=1',
	'legacy migration ignores plugin zeroes that the old runtime never enforced');

my $incomplete = {
	'id' => 103, 'template' => 10,
	'webmin_avail' => 'dns=1 proc=invalid',
	};
is(&main::get_domain_webmin_avail($incomplete),
	'dns=1 proc=0 plugin=1',
	'invalid core access fails closed while new plugins remain compatible');

{
no warnings 'redefine';
*main::help_file = sub { return '/file/that/does/not/exist'; };
*main::ui_yesno_radio = sub { return "yesno($_[0]=$_[1])"; };
*main::ui_radio = sub { return "radio($_[0]=$_[1])"; };
*main::ui_table_row = sub { return "row($_[0]|$_[1])\n"; };
}
my $rows = &main::webmin_avail_rows('dns=1 proc=2 plugin=0');
like($rows, qr/row\(DNS\|yesno\(avail_dns=1\)\)/,
	'binary module access renders as a standard table row');
like($rows, qr/row\(Processes\|radio\(avail_proc=2\)\)/,
	'multi-level module access renders as a standard table row');
like($rows, qr/row\(Plugin \(managed scope\)\|yesno\(avail_plugin=0\)\)/,
	'plugin module access preserves its registry label');
unlike($rows, qr/Module and function|Available\?/,
	'module access does not render a nested legacy columns table');

my $feature_unix = File::Spec->catfile($root, 'feature-unix.pl');
open(my $feature_fh, '<', $feature_unix) ||
	die "Failed to open $feature_unix: $!";
my $feature_source = do { local $/; <$feature_fh> };
close($feature_fh);
like($feature_source,
	qr/\$text\{'tmpl_webmin_avail'\}\." "\.\s*&ui_help\(\$text\{'tmpl_webmin_avail_help'\}\)/,
	'template module access uses a plain heading with a standard help tooltip');
unlike($feature_source,
	qr/&hlink\(\$text\{'tmpl_webmin_avail'\}/,
	'template module access heading is not clickable');

my @saved_domains;
{
no warnings 'redefine';
local *main::make_dir = sub { };
local *main::lock_file = sub { };
local *main::unlock_file = sub { };
local *main::read_file = sub { return 0; };
local *main::write_file = sub { push(@saved_domains, { %{$_[1]} }); };
local *main::set_ownership_permissions = sub { };
local *main::build_domain_maps = sub { };
my $raw = {
	'id' => 107, 'dom' => 'raw.example', 'template' => 10,
	};
ok(&main::save_domain($raw, 1),
	'low-level creation persistence accepts a domain');
ok(!defined($saved_domains[-1]->{'webmin_avail'}),
	'low-level persistence does not derive a Webmin module policy');
my $imported = {
	'id' => 108, 'dom' => 'imported.example', 'template' => 10,
	};
ok(&main::init_domain_webmin_avail($imported),
	'direct import initializes its Webmin module policy explicitly');
ok(&main::save_domain($imported, 1),
	'directly imported domain can be persisted');
is($saved_domains[-1]->{'webmin_avail'}, 'dns=0 proc=0 plugin=0',
	'explicit direct-import initialization snapshots the effective template policy');
}

done_testing();
