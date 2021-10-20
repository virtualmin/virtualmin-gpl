# Functions for advertising Pro features to GPL users

############################################################
# Page related alert generators
############################################################

# list_scripts_pro_tip(\gpl-scripts)
# Displays an alert for Install Scripts page
# and its Available Scripts tab with install scripts
# available in Pro version only, if not previously
# dismissed by a user
sub list_scripts_pro_tip
{
my ($scripts) = @_;
if ($in{'search'} || !should_show_pro_tip('list_scripts')) {
	return;
	}
my $pro_scripts = &unserialise_variable(&read_file_contents("$scripts_directories[2]/scripts-pro.info"));
if ($pro_scripts && scalar(@{$pro_scripts}) > 0) {
	push(@{$scripts}, @{$pro_scripts});
	@{$scripts} = sort { lc($a->{'pro'}) cmp lc($b->{'pro'}) } @{$scripts};
	print &alert_pro_tip('list_scripts');
	return 1;
	}
}

# dnsclouds_pro_tip
# Displays an alert for Cloud DNS Providers page
# with providers available in Pro version only,
# and if not previously dismissed by a user
sub dnsclouds_pro_tip
{
return if (!should_show_pro_tip('dnsclouds'));
my @pro_dnsclouds_list = (
	"<em>Cloudflare DNS</em>",
	"<em>Google Cloud DNS</em>",
	);
my $pro_dnsclouds = join(', ', @pro_dnsclouds_list);
$pro_dnsclouds =~ s/(.+)(,)(.+)$/$1 $text{'scripts_gpl_pro_tip_and'}$3/;
$text{"scripts_gpl_pro_tip_dnsclouds"} = &text('scripts_gpl_pro_tip_clouds', $pro_dnsclouds);
print &alert_pro_tip('dnsclouds');
}

# list_clouds_pro_tip
# Displays an alert for Cloud Storage Providers page
# with providers available in Pro version only,
# and if not previously dismissed by a user
sub list_clouds_pro_tip
{
return if (!should_show_pro_tip('list_clouds'));
my @pro_list_clouds_list = (
	"<em>Google Cloud Storage</em>",
	"<em>Dropbox</em>",
	"<em>Backblaze</em>",
	);
my $pro_list_clouds = join(', ', @pro_list_clouds_list);
$pro_list_clouds =~ s/(.+)(,)(.+)$/$1 $text{'scripts_gpl_pro_tip_and'}$3/;
$text{"scripts_gpl_pro_tip_list_clouds"} = &text('scripts_gpl_pro_tip_clouds', $pro_list_clouds);
print &alert_pro_tip('list_clouds');
}

# demo_maillog_pro_tip()
sub demo_maillog_pro_tip
{
return if (!should_show_pro_tip('demo_maillog'));
$text{"scripts_gpl_pro_tip_demo_maillog"} = $text{'maillog_desc'};
print &alert_pro_tip('demo_maillog', 1);
}

############################################################
# API general subs
############################################################

# should_show_pro_tip(tipid)
# If the current user should see Pro tip for the given page
sub should_show_pro_tip
{
my ($tipid) = @_;
my %protips;
my $protip_file = "$newfeatures_seen_dir/$remote_user-pro-tips";
&read_file_cached($protip_file, \%protips);
return if ($virtualmin_pro);
return if ($config{'no_pro_tips'});
return !$protips{$tipid};
}

# set_seen_pro_tip(tipid)
# Flags that the current user has seen a Pro tip for some page
sub set_seen_pro_tip
{
my ($tipid) = @_;
my %protips;
my $protip_file = "$newfeatures_seen_dir/$remote_user-pro-tips";
&make_dir($newfeatures_seen_dir, 0700) if (!-d $newfeatures_seen_dir);
&read_file_cached($protip_file, \%protips);
$protips{$tipid} = 1;
&write_file($protip_file, \%protips);
}

# alert_pro_tip(tip-id)
# Returns an alert with given Pro tip description and dismiss button
sub alert_pro_tip
{
my ($tipid, $purge) = @_;
my $form = "&mdash;&nbsp;" . &ui_form_start("@{[&get_webprefix_safe()]}/$module_name/set_seen_pro_tip.cgi", "post").
			$text{"scripts_gpl_pro_tip_$tipid"} . " <br>" .
			&text('scripts_gpl_pro_tip_enroll',
			      'https://www.virtualmin.com/product-category/virtualmin/') . "<p>\n".
			&ui_hidden("tipid", $tipid) .
			($purge ? &ui_hidden("purge", $tipid) : "") .
			&ui_form_end([ [ undef, ($text{"scripts_gpl_pro_tip_${tipid}_hide"} ||
			                         $text{"scripts_gpl_pro_tip_hide"}), undef, undef, undef, 'fa2 fa-fw fa2-eye-off' ] ], undef, 1);

return &ui_alert_box($form, 'success', undef, undef, $text{'scripts_gpl_pro_tip'}, " fa2 fa2-virtualmin");
}

# menu_link_pro_tip
# Modifies default menu link to advertise GPL user Pro features if allowed
sub menu_link_pro_tip
{
my ($demo_feature, $link_hash) = @_;
return if (!-r "$virtual_server_root/$demo_feature.cgi");
if (should_show_pro_tip($demo_feature)) {
	$link_hash->{'page'} = "$demo_feature.cgi";
	$link_hash->{'title'} = $link_hash->{'title'} .
	  (
	    " <span>" .
	      "<span data-menu-link-demo>$text{'scripts_gpl_pro_tip_demo'}</span>" .
	      "<span data-menu-link-icon-demo title='$text{'scripts_gpl_pro_tip'}'></span>" .
	    "</span>"
	  );
	}
elsif (!$virtualmin_pro) {
	$link_hash->{'skip'} = 1;
	}
}

# build_pro_scripts_list_for_pro_tip()
# Builds a list of Virtualmin Pro scripts for inclusion to GPL package
sub build_pro_scripts_list_for_pro_tip
{
my @scripts_pro_list;
my @scripts = map { &get_script($_) } &list_scripts();
@scripts = grep { $_->{'avail'} } @scripts;
@scripts = sort { lc($a->{'desc'}) cmp lc($b->{'desc'}) } @scripts;
foreach my $script (@scripts) {
	my @vers = grep { &can_script_version($script, $_) }
		     @{$script->{'install_versions'}};
	next if (!@vers);
	next if ($script->{'dir'} !~ /$scripts_directories[3]/ &&
	        !$script->{'migrated'});
	push(@scripts_pro_list,
	    { 'version' => $vers[0],
	      'name' => $script->{'name'},
	      'desc' => $script->{'desc'},
	      'longdesc' => $script->{'longdesc'},
	      'categories' => $script->{'categories'},
	      'pro' => 1
	      },
	    );
	}
my $scripts_pro_file = "$scripts_directories[2]/scripts-pro.info";
my $fh = "SCRIPTS";
&open_tempfile($fh, ">$scripts_pro_file");
&print_tempfile($fh, &serialise_variable(\@scripts_pro_list));
&close_tempfile($fh);
}

