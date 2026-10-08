#!/usr/bin/perl

use strict;
use warnings;
no warnings qw(once redefine);
use Test::More;
use FindBin;

# Exercise provider selection without writing zones or contacting providers.
$main::module_root_directory = "$FindBin::Bin/..";
do "$FindBin::Bin/../virtual-server-lib-funcs.pl" or die $@ || $!;
do "$FindBin::Bin/../feature-dns.pl" or die $@ || $!;
my $template = { dns_cloud => 'cloudflare', dns_sub => 'no' };
local *main::get_template = sub { return $template; };
local *main::list_provision_features = sub { return ('dns'); };
local *main::indexof = sub {
	my ($value, @values) = @_;
	for (0 .. $#values) { return $_ if $values[$_] eq $value; }
	return -1;
	};
local *main::require_bind = sub { return { id => 0 }; };
local *main::substitute_domain_template = sub { return ''; };
local *main::transname = sub { return 'unused-zone-file'; };
local *main::create_standard_records = sub { return undef; };
local *main::obtain_lock_dns = sub { };
local *main::records_to_text = sub { return (); };
local *main::list_dns_clouds = sub {
	return ({ name => 'cloudflare', desc => 'Cloudflare' });
	};
local *main::text = sub { return $_[0]; };
local %main::text = (setup_bind => 'local', setup_bind_provision => 'services');
local %main::config;
# Stop at the selected provider's progress message, before any system changes.
local $main::first_print = sub { die "selected:$_[0]\n"; };

# selected_provider(&domain): Run DNS setup up to its provider-specific branch.
sub selected_provider
{
my ($d) = @_;
eval { setup_dns($d); };
return $@;
}

# Creation resolves the CLI override and template before calling setup_dns.
for my $provider ('local', 'services', 'cloudflare', undef) {
	my $d = { dom => 'example.com', template => 0, dns => 1,
		creating => 1, dns_cloud => $provider };
	set_provision_features($d);
	my $expected = !$provider || $provider eq 'cloudflare' ?
		'setup_bind_cloud' : $provider;
	is(selected_provider($d), "selected:$expected\n",
		'creation honors '.($provider || 'the template default'));
	}

# Enabling DNS later must still apply the current template.
my $later = { dom => 'example.com', template => 0, provision_dns => 0 };
is(selected_provider($later), "selected:setup_bind_cloud\n",
	'enabling DNS later still uses the template');

# Creation callers that have not resolved a provider still need defaults.
my $unselected = { dom => 'example.com', template => 0, creating => 1 };
is(selected_provider($unselected), "selected:setup_bind_cloud\n",
	'unresolved creation still uses the template');

# An explicit migration destination must continue to bypass the template.
my $migration = { dom => 'example.com', template => 0, dns_keep_provider => 1 };
is(selected_provider($migration), "selected:local\n", 'migration keeps local DNS');
ok(!exists($migration->{'dns_keep_provider'}), 'migration flag is consumed');

done_testing();
