#!/usr/bin/perl
# Keep owner, reseller and API permissions intact when sharing their helpers.
use strict;
use warnings;
use Test::More;
use FindBin;
our (%access, %config, $base_remote_user, $api_access_domain);
# Load the real permission helpers from this checkout without starting Webmin.
{
	no warnings 'once';
	$main::module_root_directory = "$FindBin::Bin/..";
}
do "$FindBin::Bin/../virtual-server-lib-funcs.pl" or die $@ || $!;

# Match exact IDs; treat * as a wildcard only when the caller opts in.
ok(acl_list_contains('0 12', 0), 'zero is a valid template ID');
ok(!acl_list_contains('12', 1), 'IDs do not match prefixes');
ok(!acl_list_contains('* 12', 13), 'stars need explicit wildcard support');
ok(acl_list_contains('* 12', 13, 1), 'API lists allow a star beside other IDs');
ok(!acl_list_contains('*', undef, 1), 'wildcards cannot grant a missing ID');
ok(!acl_list_contains('*', '', 1), 'wildcards cannot grant an empty ID');

# Real permission functions use these resources without reading system state.
my %domains = (
	1 => { id => 1, user => 'owner', reseller => 'reseller', plan => 10 },
	2 => { id => 2, parent => 1, plan => 99 },
	3 => { id => 3, user => 'other', api_owner => 'creator', plan => 20 },
	4 => { id => 4, user => 'outside', reseller => 'someone-else', plan => 99 },
	5 => { id => 5, parent => 3 },
);
# Distinguish owned, unrestricted, explicitly granted and literal-* plans.
my @plans = (
	{ id => 10, owner => 'reseller', resellers => 'someone-else', featurelimits => 'web' },
	{ id => 20, owner => 'root', resellers => '', featurelimits => '' },
	{ id => 30, owner => 'root', resellers => 'reseller', featurelimits => 'web unix' },
	{ id => 40, owner => 'root', resellers => '*' },
);
{
	no warnings qw(redefine once);
	# get_domain(id): resolve parents from the fixture catalog.
	local *get_domain = sub { return $domains{$_[0]}; };
	# get_domain_by(field, value, [field, value])
	# Return the owner's domain for template permission checks.
	# Recognize only the value 'owner'; other searches return no domain.
	local *get_domain_by = sub { return $domains{1} if $_[1] eq 'owner'; return; };
	# get_plan(id): leave unknown IDs unresolved to test missing plans.
	local *get_plan = sub { my ($id) = @_; return (grep { $_->{id} eq $id } @plans)[0]; };
	# list_plans(): preserve catalog order for availability and default checks.
	local *list_plans = sub { return @plans; };

	# Owner domain lists allow all only when the whole field is *.
	%access = (noconfig => 1, domains => '1');
	$base_remote_user = 'owner';
	ok(can_edit_domain($domains{1}), 'owner retains selected domain access');
	ok(!can_edit_domain($domains{2}), 'ordinary selection does not gain API ancestry rules');
	$access{domains} = '* 1';
	ok(can_edit_domain($domains{1}), 'mixed legacy list retains explicit IDs');
	ok(!can_edit_domain($domains{4}), 'mixed legacy list does not become unrestricted');
	$access{domains} = '*';
	ok(can_edit_domain($domains{4}), 'legacy all-domain access remains available');

	# Reseller ownership still covers descendants without granting outside servers.
	%access = (noconfig => 1, reseller => 1);
	$base_remote_user = 'reseller';
	ok(can_edit_domain($domains{1}), 'reseller can edit its customer');
	ok(can_edit_domain($domains{2}), 'reseller can edit a customer child');
	ok(!can_edit_domain($domains{4}), 'reseller cannot edit another reseller customer');
	is_deeply([map { $_->{id} } list_available_plans()], [10, 20, 30],
		'reseller sees owned, unrestricted and explicitly granted plans');
	ok(!can_use_plan($plans[3]), 'legacy plan reseller star remains literal');

	# Template owner and reseller restrictions remain independent of API lists.
	my $template = { id => 0, resellers => 'reseller', owners => 'owner' };
	ok(can_use_template($template), 'reseller can use its granted template');
	$base_remote_user = 'someone-else';
	ok(!can_use_template($template), 'unlisted reseller cannot use the template');
	%access = (noconfig => 1);
	$base_remote_user = 'owner';
	ok(can_use_template($template), 'owner satisfies owner and reseller restrictions');
	ok(!can_use_template({ %$template, owners => '* someone-else' }),
		'mixed owner list does not acquire wildcard access');
	is_deeply([list_available_plans()], [], 'ordinary owner gains no plan permissions');

	# API accounts can access selected servers and servers they created,
	# including children of either. Owner and reseller lists do not apply.
	%access = (api_id => 'creator', api_domains => '1', api_created => 1,
		api_plans => '20', api_plan => 20, api_templates => '0');
	ok(can_edit_domain($domains{2}), 'API selection still covers descendants');
	ok(can_edit_domain($domains{3}), 'API creator still manages its server');
	ok(can_edit_domain($domains{5}), 'API creator still manages child servers');
	ok(!can_edit_domain($domains{4}), 'API scope still denies outside servers');
	# A new account ID must not inherit access based on the old creator ID.
	$access{api_id} = 'replacement';
	ok(!can_edit_domain($domains{3}), 'replacement credential inherits no creations');
	# Disabling the account must also block explicitly selected servers.
	$access{api_disabled} = 1;
	ok(!can_edit_domain($domains{2}), 'disabled API account loses explicit access too');
	delete $access{api_disabled};
	# Allowed plans and templates do not depend on domain grants or roles.
	is_deeply([map { $_->{id} } list_available_plans()], [20], 'API plan list stays restricted');
	is(get_default_plan()->{id}, 20, 'allowed API default is retained');
	$access{api_plan} = 10;
	ok(!get_default_plan(), 'revoked API default does not fall back to another plan');
	ok(can_use_template($template), 'API template grant remains independent of owner rules');
	ok(!can_use_template({ %$template, id => 1 }), 'API template selection remains exact');

	# API feature checks must also enforce the customer's plan limits.
	%config = (web => 0, unix => 3);
	$access{feature_web} = 1;
	$api_access_domain = $domains{2};
	ok(can_use_feature('web'), 'API child uses the parent plan');
	ok(!can_use_feature('unix'), 'forced feature cannot bypass the API customer plan');
	$api_access_domain = $domains{4};
	ok(!can_use_feature('web'), 'missing customer plan denies the API feature');
	# Without plan limits, access still depends on feature permissions.
	$api_access_domain = $domains{3};
	ok(can_use_feature('web'), 'empty plan feature list preserves granted capability');
	$access{feature_web} = 0;
	ok(!can_use_feature('web'), 'API feature still needs its capability');
	$api_access_domain = undef;
	ok(can_use_feature('unix'), 'API creation context retains forced Unix feature');

	# Ordinary owner, reseller and master feature behavior stays unchanged.
	%access = (noconfig => 1, feature_web => 1, feature_unix => 1);
	ok(can_use_feature('web'), 'owner retains granted features');
	ok(!can_use_feature('unix'), 'owner cannot change Unix even when forced or granted');
	$access{reseller} = 1;
	ok(can_use_feature('unix'), 'reseller retains forced Unix feature');
	%access = (noconfig => 0);
	ok(can_use_feature('unconfigured'), 'master retains unrestricted feature access');
	is_deeply([map { $_->{id} } list_available_plans()], [10, 20, 30, 40],
		'master retains every plan');
}
done_testing();
