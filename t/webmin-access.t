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
my $lib = File::Spec->catfile($root, 'virtual-server-lib-funcs.pl');
my $loaded = do $lib;
die $@ if ($@);
die "Failed to load $lib: $!" if (!defined($loaded));

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
*main::list_domain_owner_modules = sub {
	return (
		[ 'dns', 'DNS' ],
		[ 'proc', 'Processes', [ [ 2, 'Own' ], [ 1, 'All' ], [ 0, 'No' ] ] ],
		[ 'plugin', 'Plugin (managed scope)' ],
		);
	};
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
	'dns=1 proc=2 plugin=0 unavailable-z=1 unavailable-a=custom'),
	'dns=1 proc=2 plugin=0 unavailable-a=custom unavailable-z=1',
	'normalization preserves unavailable module settings in stable order');

my $incomplete = {
	'id' => 103, 'template' => 10,
	'webmin_avail' => 'dns=1 proc=invalid',
	};
is(&main::get_domain_webmin_avail($incomplete),
	'dns=1 proc=0 plugin=0',
	'stored access fails closed for invalid and newly-added module entries');

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

my $saved_domain;
{
no warnings 'redefine';
local *main::make_dir = sub { };
local *main::lock_file = sub { };
local *main::unlock_file = sub { };
local *main::read_file = sub { return 0; };
local *main::write_file = sub { $saved_domain = { %{$_[1]} }; };
local *main::set_ownership_permissions = sub { };
local *main::build_domain_maps = sub { };
my $imported = {
	'id' => 104, 'dom' => 'imported.example', 'template' => 10,
	};
ok(&main::save_domain($imported, 1),
	'directly imported domain can be persisted');
is($saved_domain->{'webmin_avail'}, 'dns=0 proc=0 plugin=0',
	'direct creation persistence snapshots the effective template policy');
}

done_testing();
