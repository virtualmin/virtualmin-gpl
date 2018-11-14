# Functions for getting and showing new Virtualmin or Cloudmin features

# list_new_features(mod, version)
# Returns a list of new features in a given Virtualmin or plugin version. Each
# is a hash ref containing the keys :
#  id - A unique name
#  desc - A short description
#  html - A longer HTML description
#  master,reseller,extra,domain - Set to 1 if usable by this type of user
#  link - An optional link to the feature. May include substitutions like $ID
# The list is returned newest first, assuming that features have numeric prefix
sub list_new_features
{
my ($mod, $ver) = @_;
$ver =~ s/\.([a-z]+)$//;	# Remove .gpl / etc
my (@rv, @dirs);
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
		my %nf;
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
my @rv;
foreach my $mod ($module_name, @plugins, 'security-updates') {
	next if (!&foreign_check($mod));
	my %minfo = $mod eq $module_name ? %module_info : &get_module_info($mod);
	push(@rv, \%minfo);
	}
return @rv;
}

# should_show_new_features([show-all])
# If the current user should see new features, returns a list of modules and
# version numbers to show for. The list is in descending version order.
sub should_show_new_features
{
my ($showall) = @_;
my @nf;
my %seen;
&read_file_cached("$newfeatures_seen_dir/$remote_user", \%seen);
foreach my $minfo (&list_new_features_modules()) {
	my $ver = $minfo->{'version'};
	my $mod = $minfo->{'dir'};
	my %mc = &foreign_config($mod);
	while($ver > 0 &&
	      ($showall ||
	       (!$seen{$mod} || $seen{$mod} < $ver) &&
	       (!$mc{'first_version'} || $mc{'first_version'} <= $ver))) {
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
my ($mod, $ver, $seen) = @_;
my %seen;
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
my ($ver, $mod) = @_;
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
my $ver = $module_info{'version'};
return sprintf("%.2f", int($ver*100) / 100.0);
}

# get_new_features_html(&domain|&server, show-all)
# Returns HTML listing new features in this (and older) versions of Virtualmin.
# If there are none, returns undef.
sub get_new_features_html
{
my ($d, $showall) = @_;
&load_theme_library();

# Find out what's new
my @nf = &should_show_new_features($showall);
return undef if (!@nf);
my (@rv, @modvers, %modvers);
my $me;
if (defined(&master_admin)) {
	# In Virtualmin
	$me = &master_admin() ? 'master' :
	      &reseller_admin() ? 'reseller' :
	      &extra_admin() ? 'extra' : 'domain';
	}
else {
	# In Cloudmin
	$me = $access{'owner'} ? 'owner' : 'master';
	}
my %shownf = map { $_, 1 } split(/,/, $config{'show_nf'});
return undef if ($me && !$shownf{$me} && !$showall);
my %donemod;
my $wver = &get_webmin_version();
foreach my $nf (@nf) {
	# Get new features in some version. If there were none, stop looking
	# for this module.
	next if ($donemod{$nf->[0]});
	my @mrv = &list_new_features($nf->[0], $nf->[1]);
	if (!@mrv && !$showall) {
		$donemod{$nf->[0]} = 1;
		}
	if ($me) {
		@mrv = grep { $_->{$me} } @mrv;
		}
	@mrv = grep { $wver >= $_->{'webmin'} } @mrv;	# Filter for Webmin vers
	push(@rv, @mrv);
	if (@mrv && !$modvers{$mf->[0]}++) {
		# Create a description for this new version
		my ($mdesc, $timestr);
		if ($nf->[0] eq $module_name) {
			$mdesc = $text{'nf_vm'};
			}
		elsif (&indexof($nf->[0], @plugins) >= 0) {
			$mdesc = &plugin_call($nf->[0], "feature_name");
			}
		if (!$mdesc) {
			my %minfo = &get_module_info($nf->[0]);
			$mdesc = $minfo{'desc'};
			}
		if ($nf->[0] eq $module_name) {
			# When was Virtualmin installed?
			my %itimes;
			&read_file_cached($install_times_file, \%itimes);
			my $basever = &get_base_module_version();
			if ($itimes{$basever}) {
				$timestr = " ".&text('nf_date',
					&make_date($itimes{$basever}, 1));
				}
			}
		push(@modvers, "$mdesc $nf->[1]$timestr");
		}
	}
return undef if (!@rv);
#@rv = reverse(@rv);

# If not given, pick a domain or server
my @servers;
if (defined(&list_available_managed_servers_sorted)) {
	@servers = &list_available_managed_servers_sorted();
	}
if (!$d && defined(&list_domains)) {
	# First Virtualmin domain we can edit
	foreach my $cd (&list_domains()) {
		if (&can_edit_domain($cd)) {
			$d = $cd;
			last;
			}
		}
	}
elsif (!$d && @servers) {
	# First Cloudmin server
	$d = $servers[0];
	}

# Select template function for Virtualmin or Cloudmin
my $subs = defined(&substitute_domain_template) ?
	\&substitute_domain_template :
	\&substitute_virtualmin_template;

# Make the HTML
my $rv;
if (!$showall) {
	my $modvers = @modvers <= 1 ? join(", ", @modvers) :
			&text('nf_and', join(", ", @modvers[0..$#modvers-1]),
					$modvers[$#modvers]);
	$rv .= &text('nf_header', $modvers)."<br>\n";
	}
$rv .= "<dl>\n";
foreach my $nf (@rv) {
	my $link;
	if ($nf->{'link'}) {
		# Create link, with domain substitution
		if ($d || $nf->{'link'} !~ /\$\{/) {
			# If this is Cloudmin and the new feature is only for
			# some type, limit to them
			if ($module_name =~ /^server-manager/ &&
			    $nf->{'managers'}) {
				my @mans = grep { &match_server_manager($_,
					        $nf->{'managers'}) } @servers;
				@mans = sort { &sort_server_manager($a, $b) }
					     @mans;
				$d = $mans[0];
				}

			# Convert the link template into a real link
			$link = $d ? &$subs($nf->{'link'}, $d)
				   : $nf->{'link'};
			if ($link !~ /^\// && $link !~ /^(http|https):/) {
				# Assume in this module if relative
				if ($link =~ /^([^\?]+)/ &&
				    !-r "$module_root_directory/$1") {
					# Script doesn't exist!
					$link = undef;
					}
				else {
					# Convert to absolute path
					$link = "$gconfig{'webprefix'}/$module_name/$link";
					}
				}
			}
		}
	$rv .= "<dt><b>".$nf->{'desc'}.
	       ($showall ? " ".&text('nf_ver', $nf->{'ver'}) : "").
	       "</b>\n";
	if ($link) {
		$rv .= " | <a href='$link'>$text{'nf_try'}</a>\n";
		}
	$rv .= "<dd>$nf->{'html'}<p>\n";
	}
$rv .= "</dl>\n";

# Button to hide new features
if (!$showall) {
	$rv .= &ui_form_start(
		"$gconfig{'webprefix'}/$module_name/seen_newfeatures.cgi");
	$rv .= &ui_form_end([ [ undef, $text{'nf_seen'} ] ]);
	}

return $rv;
}

sub match_server_manager
{
my ($server, $managers) = @_;
return 1 if (!$managers);
foreach my $m (split(/\s+/, $managers)) {
	return 1 if ($server->{'manager'} eq $m);
	}
return 0;
}

# Sort Cloudmin systems so that those which are up come first
sub sort_server_manager
{
my ($a, $b) = @_;
my $ao = &order_server_manager_status($a->{'status'});
my $bo = &order_server_manager_status($b->{'status'});
return $ao - $bo;
}

sub order_server_manager_status
{
my ($s) = @_;
return $s eq 'nohost' ? 0 :
       $s eq 'down' ? 10 :
       $s eq 'paused' ? 15 :
       $s eq 'nossh' ? 20 :
       $s eq 'alive' ? 25 :
       $s eq 'nosshlogin' ? 30 :
       $s eq 'nowebminlogin' ? 40 :
       $s eq 'nowebmin' ? 50 :
       $s eq 'downwebmin' ? 60 :
       $s eq 'novirt' ? 70 :
       $s eq 'virt' ? 80 : undef;
}

1;

