# Functions for getting and showing new Virtualmin or VM2 features

# list_new_features(mod, version)
# Returns a list of new features in a given Virtualmin or plugin version. Each
# is a hash ref containing the keys :
#  id - A unique name
#  desc - A short description
#  html - A longer HTML description
#  master,reseller,domain - Set to 1 if usable by this type of user
#  link - An optional link to the feature. May include substitutions like $ID
# The list is returned newest first, assuming that features have numeric prefix
sub list_new_features
{
local ($mod, $ver) = @_;
local (@rv, @dirs);
if ($mod eq $module_name) {
	# Core virtualmin features
	@dirs = map { "$_/$ver" } @newfeatures_dirs;
	}
else {
	# Features from some plugin
	@dirs = ( &module_root_directory($mod)."/newfeatures/".$ver );
	}
foreach my $dir (@dirs) {
	opendir(NF, $dir);
	foreach my $f (grep { !/^\./ } readdir(NF)) {
		local %nf;
		&read_file_cached("$dir/$f", \%nf);
		$nf{'id'} = $f;
		$nf{'mod'} = $mod;
		$nf{'ver'} = $ver;
		push(@rv, \%nf);
		}
	closedir(NF);
	}
return sort { $b->{'id'} <=> $a->{'id'} } @rv;
}

# list_new_features_modules()
# Returns a list of module info structures for modules that we are interested in
sub list_new_features_modules
{
local @rv;
foreach my $mod ($module_name, @plugins, 'security-updates') {
	next if (!&foreign_check($mod));
	local %minfo = $mod eq $module_name ? %module_info : &get_module_info($mod);
	push(@rv, \%minfo);
	}
return @rv;
}

# should_show_new_features()
# If the current user should see new features, returns a list of modules and
# version numbers to show for. The list is in descending version order.
sub should_show_new_features
{
local @nf;
local %seen;
&read_file_cached("$newfeatures_seen_dir/$remote_user", \%seen);
foreach my $minfo (&list_new_features_modules()) {
	local $ver = $minfo->{'version'};
	local $mod = $minfo->{'dir'};
	local %mc = &foreign_config($mod);
	while($ver > 0 &&
	      (!$seen{$mod} || $seen{$mod} < $ver) &&
	      (!$mc{'first_version'} || $mc{'first_version'} <= $ver)) {
		push(@nf, [ $mod, $ver ]);
		$ver = &down_one_version($ver, $mod);
		}
	}
return @nf;
}

# set_seen_new_features(module, version, seen)
# Flags that the current user has seen (or not) new features for some version
sub set_seen_new_features
{
local ($mod, $ver, $seen) = @_;
local %seen;
if (!-d $newfeatures_seen_dir) {
	&make_dir($newfeatures_seen_dir, 0700);
	}
&read_file_cached("$newfeatures_seen_dir/$remote_user", \%seen);
if ($seen) {
	$seen{$mod} = $ver;
	}
else {
	$seen{$mod} = &down_one_version($seen{$mod}, $mod);
	}
&write_file("$newfeatures_seen_dir/$remote_user", \%seen);
}

sub down_one_version
{
local ($ver, $mod) = @_;
if ($mod eq $module_name && $mod !~ /^server-manager/) {
	return (int($ver*100) - 1)  / 100.0;
	}
else {
	return (int($ver*10) - 1)  / 10.0;
	}
}

# get_base_module_version()
# Returns the Virtualmin version, rounded to 2 decimals
sub get_base_module_version
{
local $ver = $module_info{'version'};
return sprintf("%.2f", int($ver*100) / 100.0);
}

# get_new_features_html(&domain)
# Returns HTML listing new features in this (and older) versions of Virtualmin.
# If there are none, returns undef.
sub get_new_features_html
{
local ($d) = @_;
&load_theme_library();

# Find out what's new
local @nf = &should_show_new_features();
return undef if (!@nf);
local (@rv, @modvers, %modvers);
local $me = !defined(&master_admin) ? undef :	# For VM2
	    &master_admin() ? 'master' :
	    &reseller_admin() ? 'reseller' : 'domain';
local %shownf = map { $_, 1 } split(/,/, $config{'show_nf'});
return undef if ($me && !$shownf{$me});
local %donemod;
foreach my $nf (@nf) {
	# Get new features in some version. If there were none, stop looking
	# for this module.
	next if ($donemod{$nf->[0]});
	local @mrv = &list_new_features($nf->[0], $nf->[1]);
	if (!@mrv) {
		$donemod{$nf->[0]} = 1;
		}
	if ($me) {
		@mrv = grep { $_->{$me} } @mrv;
		}
	push(@rv, @mrv);
	if (@mrv && !$modvers{$mf->[0]}++) {
		# Create a description for this new version
		local ($mdesc, $timestr);
		if ($nf->[0] eq $module_name) {
			$mdesc = $text{'nf_vm'};
			}
		elsif (&indexof($nf->[0], @plugins) >= 0) {
			$mdesc = &plugin_call($nf->[0], "feature_name");
			}
		if (!$mdesc) {
			local %minfo = &get_module_info($nf->[0]);
			$mdesc = $minfo{'desc'};
			}
		if ($nf->[0] eq $module_name) {
			# When was Virtualmin installed?
			local %itimes;
			&read_file_cached($install_times_file, \%itimes);
			local $basever = &get_base_module_version();
			if ($itimes{$basever}) {
				$timestr = " ".&text('nf_date',
					&make_date($itimes{$basever}, 1));
				}
			}
		push(@modvers, "$mdesc $nf->[1]$timestr");
		}
	}
return undef if (!@rv);
@rv = reverse(@rv);

# If not given, pick a domain or server
if (!$d && defined(&list_domains)) {
	foreach my $cd (&list_domains()) {
		if (&can_edit_domain($cd)) {
			$d = $cd;
			last;
			}
		}
	}
elsif (!$d && defined(&list_managed_servers)) {
	($d) = &list_managed_servers();
	}

# Select template function for Virtualmin or VM2
local $subs = defined(&substitute_domain_template) ?
	\&substitute_domain_template :
	\&substitute_template;

# Make the HTML
local $rv;
local $modvers = @modvers <= 1 ? join(", ", @modvers) :
		 	&text('nf_and', join(", ", @modvers[0..$#modvers-1]),
					$modvers[$#modvers]);
$rv .= &text('nf_header', $modvers)."<br>\n";
#$rv .= &ui_columns_start([ $text{'nf_desc'}, $text{'nf_html'} ]);
$rv .= "<dl>\n";
foreach my $nf (@rv) {
	local $link;
	if ($nf->{'link'}) {
		# Create link, with domain substitution
		if ($d || $nf->{'link'} !~ /\$\{/) {
			$link = $d ? &$subs($nf->{'link'}, $d)
				   : $nf->{'link'};
			if ($link !~ /^\// && $link !~ /^(http|https):/) {
				# Assume in this module
				$link = "$gconfig{'webprefix'}/$module_name/$link";
				}
			}
		}
	#$rv .= &ui_columns_row([ $link ? "<a href='$link'>$nf->{'desc'}</a>"
	#			       : $nf->{'desc'}, $nf->{'html'} ]);
	$rv .= "<dt><b>$nf->{'desc'}</b>\n";
	if ($link) {
		$rv .= " | <a href='$link'>$text{'nf_try'}</a>\n";
		}
	$rv .= "<dd>$nf->{'html'}<p>\n";
	}
$rv .= "</dl>\n";
#$rv .= &ui_table_end();
$rv .= &ui_form_start("$gconfig{'webprefix'}/$module_name/seen_newfeatures.cgi");
$rv .= &ui_form_end([ [ undef, $text{'nf_seen'} ] ]);

return $rv;
}

1;

