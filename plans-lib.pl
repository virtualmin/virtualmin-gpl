# Functions for managing plans, which are sets of limits separate from templates

# list_plans([no-convert])
# Returns a list of all plans, each of which is a hash ref
sub list_plans
{
local ($noconvert) = @_;
if (!-d $plans_dir && !$noconvert) {
	# Somehow hasn't been run yet
	&convert_plans();
	}
if (!@list_plans_cache) {
	local @rv;
	opendir(DIR, $plans_dir);
	foreach my $id (readdir(DIR)) {
		if ($id ne "." && $id ne "..") {
			local $plan = &get_plan($id);
			push(@rv, $plan) if ($plan && !$plan->{'deleted'});
			}
		}
	closedir(DIR);
	@list_plans_cache = sort { lc($a->{'name'}) cmp lc($b->{'name'}) } @rv;
	}
return @list_plans_cache;
}

# list_editable_plans()
# Returns a list of plans the current user can edit
sub list_editable_plans
{
local $canmode = &can_edit_plans();
if ($canmode == 0) {
	return ( );
	}
elsif ($canmode == 1) {
	return grep { $_->{'owner'} eq $base_remote_user } &list_plans();
	}
else {
	return &list_plans();
	}
}

# list_available_plans()
# Returns a list of plans the current user can use
sub list_available_plans
{
local $canmode = &can_edit_plans();
local @plans = &list_plans();
if (&master_admin()) {
	# Master admin can use all
	return @plans;
	}
elsif (&reseller_admin()) {
	# Resellers can use their plans, and those granted to them by the 
	# master admin.
	return grep { $_->{'owner'} eq $base_remote_user ||
		      !$_->{'resellers'} ||
		      &indexof($base_remote_user,
			       split(/\s+/, $_->{'resellers'})) >= 0 } @plans;
	}
else {
	# Domain owners? Can't happen ..
	return ( );
	}
}

# can_use_plan(&plan)
# Returns 1 if the current user can use a plan
sub can_use_plan
{
local ($plan) = @_;
if (&master_admin()) {
	# Masters can use all plans
	return 1;
	}
elsif (&reseller_admin()) {
	# Resellers can use their plans, and granted
	return $plan->{'owner'} eq $base_remote_user ||
	       !$plan->{'resellers'} ||
	       &indexof($base_remote_user,
                        split(/\s+/, $plan->{'resellers'})) >= 0;
	}
else {
	# Domain owners can use none
	return 0;
	}
}

# get_default_plan([allow-undef])
# Returns the default plan for the current user - may be undef if none is set
sub get_default_plan
{
local ($allowundef) = @_;
local @plans = sort { $a->{'id'} <=> $b->{'id'} } &list_available_plans();
local $defplan;
if (&reseller_admin()) {
	($defplan) = grep { $_->{'id'} eq $access{'defplan'} } @plans;
	}
if (!$defplan) {
	($defplan) = grep { $_->{'id'} eq $config{'init_plan'} } @plans;
	}
if (!$defplan && !$allowundef) {
	$defplan = $plans[0];
	}
return $defplan;
}

# set_default_plan(&plan)
# Sets the default plan for the current user. If he is a reseller, then this
# sets a reseller-level option .. otherwise, the global default iset
sub set_default_plan
{
local ($plan) = @_;
if (&reseller_admin()) {
	$access{'defplan'} = $plan ? $plan->{'id'} : undef;
	&save_module_acl(\%access);
	}
else {
	$config{'init_plan'} = $plan ? $plan->{'id'} : undef;
	&save_module_config();
	}
}

# get_plan(id)
# Returns the hash ref for the plan with some ID
sub get_plan
{
local ($id) = @_;
local %plan;
&read_file_cached("$plans_dir/$id", \%plan) || return undef;
$plan{'id'} = $id;
$plan{'file'} = "$plans_dir/$id";
return \%plan;
}

# save_plan(&plan)
# Updates or creates a plan on disk
sub save_plan
{
local ($plan) = @_;
local $newplan;
if ($plan->{'id'} eq '') {
	$plan->{'id'} = &domain_id();
	$newplan = 1;
	}
$plan->{'file'} = "$plans_dir/$plan->{'id'}";
if (!-d $plans_dir) {
	&make_dir($plans_dir, 0700);
	}
&lock_file($plan->{'file'});
&write_file($plan->{'file'}, $plan);
&unlock_file($plan->{'file'});
if (@list_plans_cache && $newplan) {
	push(@list_plans_cache, $plan);
	}
}

# delete_plan(&plan)
# Deletes an existing plan.
sub delete_plan
{
local ($plan) = @_;
&lock_file($plan->{'file'});
local @users = &get_domain_by("plan", $plan->{'id'});
if (@users) {
	# Just flag as deleted
	$plan->{'deleted'} = 1;
	&save_plan($plan);
	}
else {
	&unlink_file($plan->{'file'});
	}
if (@list_plans_cache) {
	@list_plans_cache = grep { $_->{'id'} ne $plan->{'id'} }
				 @list_plans_cache;
	}
&unlock_file($plan->{'file'});
}

# convert_plans()
# Converts all templates that have owner limits into plans, and updates virtual
# servers to refer to the converted plan. Only designed to be called once at
# installation time, to handle upgrades.
sub convert_plans
{
local $main::no_auto_plan = 1;	# So plans don't get set by complete_domain

# For each template, create a plan
local %planmap;
foreach my $ltmpl (&list_templates()) {
	local $tmpl = &get_template($ltmpl->{'id'});
	local $got = &get_plan($tmpl->{'id'});
	next if ($got);				# Already converted
	next if ($tmpl->{'id'} eq '1');		# Sub-servers don't have plans!

	# Extract plan-related settings
	$plan = { 'id' => $tmpl->{'id'},
		  'name' => $tmpl->{'id'} eq '0' ? 'Default Plan'
						 : $tmpl->{'name'} };
	$plan->{'featurelimits'} = $tmpl->{'featurelimits'} eq 'none' ? '' :
				    $tmpl->{'featurelimits'};
	foreach my $l (@plan_maxes) {
		$plan->{$l.'limit'} = $tmpl->{$l.'limit'} eq 'none' ? '' :
					$tmpl->{$l.'limit'};
		}
	$plan->{'quota'} = $tmpl->{'quota'} eq 'none' ? '' : $tmpl->{'quota'};
	$plan->{'uquota'} = $tmpl->{'uquota'} eq 'none' ? '' :$tmpl->{'uquota'};
	$plan->{'capabilities'} = $tmpl->{'capabilities'} eq 'none' ? '' :
				   $tmpl->{'capabilities'};
	foreach my $n ('nodbname', 'norename', 'forceunder', 'safeunder',
		       'ipfollow', 'migrate') {
		$plan->{$n} = $tmpl->{$n};
		}
	&save_plan($plan);
	$planmap{$tmpl->{'id'}} = $plan;
	}

# For each top-level domain, map it's template to the created plan
foreach my $d (grep { !$_->{'parent'} } &list_domains()) {
	if ($d->{'plan'} eq '' || !&get_plan($d->{'plan'})) {
		local $plan = $planmap{$d->{'template'}};
		$d->{'plan'} = $plan ? $plan->{'id'} : '0';
		&save_domain($d);
		}
	# Filter down to sub-servers, even though they don't really use plans
	foreach my $sd (&get_domain_by("parent", $d->{'id'})) {
		$sd->{'plan'} = $d->{'plan'};
		&save_domain($sd);
		}
	}
}

# set_limits_from_plan(&domain, &plan)
# Set initial owner limits on a domain from the given plan
sub set_limits_from_plan
{
local ($d, $plan) = @_;
$d->{'quota'} = $plan->{'quota'};
$d->{'uquota'} = $plan->{'uquota'};
$d->{'bw_limit'} = $plan->{'bwlimit'};
$d->{'mailboxlimit'} = $plan->{'mailboxlimit'};
$d->{'aliaslimit'} = $plan->{'aliaslimit'};
$d->{'dbslimit'} = $plan->{'dbslimit'};
$d->{'domslimit'} = $plan->{'domslimit'} eq '' ? '*' :
		     $plan->{'domslimit'} eq '0' ? '' :
		     $plan->{'domslimit'};
$d->{'aliasdomslimit'} = $plan->{'aliasdomslimit'} eq '' ? '*' :
			  $plan->{'aliasdomslimit'};
$d->{'realdomslimit'} = $plan->{'realdomslimit'} eq '' ? '*' :
			 $plan->{'realdomslimit'};
$d->{'mongrelslimit'} = $plan->{'mongrelslimit'};
$d->{'nodbname'} = $plan->{'nodbname'};
$d->{'norename'} = $plan->{'norename'};
$d->{'forceunder'} = $plan->{'forceunder'};
$d->{'safeunder'} = $plan->{'safeunder'};
$d->{'ipfollow'} = $plan->{'ipfollow'};
$d->{'migrate'} = $plan->{'migrate'};
}

# set_reseller_limits_from_plan(&reseller, &plan)
# Set initial limits for a reseller based on relevant ones from a plan
sub set_reseller_limits_from_plan
{
local ($resel, $plan) = @_;
local %lmap = ( 'domslimit' => 'max_doms',
		'aliasdomslimit' => 'max_aliasdoms',
		'realdomslimit' => 'max_realdoms',
		'quota' => 'max_quota',
		'uquota' => 'max_quota',
		'mailboxlimit' => 'max_mailboxes',
		'aliaslimit' => 'max_aliases',
		'dbslimit' => 'max_dbs',
		'bwlimit' => 'max_bw' );
foreach my $m (keys %lmap) {
	if ($plan->{$m} eq '') {
		delete($resel->{'acl'}->{$lmap{$m}});
		}
	else {
		$resel->{'acl'}->{$lmap{$m}} = $plan->{$m};
		}
	}
}

# set_featurelimits_from_plan(&domain, &plan)
# Updates a virtual server's limit_ variables based on either the enabled
# features or limits defined in the plan.
sub set_featurelimits_from_plan
{
local ($d, $plan) = @_;
if ($plan->{'featurelimits'}) {
	# From template
	local %flimits = map { $_, 1 } split(/\s+/, $plan->{'featurelimits'});
	foreach my $f (@features, 'virt', &list_feature_plugins()) {
		$d->{'limit_'.$f} = int($flimits{$f});
		}
	}
else {
	# From domain
	foreach my $f (@features, 'virt', &list_feature_plugins()) {
		$d->{'limit_'.$f} = $f eq "webmin" ? 0 : int($d->{$f});
		}
	}
}

# set_reseller_featurelimits_from_plan(&reseller, &plan)
# Set limits on allowed features for a reseller from a plan
sub set_reseller_featurelimits_from_plan
{
local ($resel, $plan) = @_;
local %flimits = map { $_, 1 } split(/\s+/, $plan->{'featurelimits'});
foreach my $f (@features, &list_feature_plugins()) {
	$resel->{'acl'}->{'feature_'.$f} = int($flimits{$f});
	}
}

# set_capabilities_from_plan(&domain, &template)
# Set initial owner editing capabilities and allowed scripts on a domain from
# the given plan
sub set_capabilities_from_plan
{
local ($d, $plan) = @_;
if ($plan->{'capabilities'}) {
	local %caps = map { $_, 1 } split(/\s+/, $plan->{'capabilities'});
	foreach my $ed (@edit_limits) {
		$d->{'edit_'.$ed} = $caps{$ed} ? 1 : 0;
		}
	}
$d->{'allowedscripts'} = $plan->{'scripts'};
}

1;

