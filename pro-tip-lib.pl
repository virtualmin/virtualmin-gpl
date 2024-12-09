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
	"<em>Namecheap DNS</em>",
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
	"<em>Google Drive</em>",
	"<em>Google Cloud Storage</em>",
	"<em>Azure Blob Storage</em>",
	"<em>Dropbox</em>",
	"<em>Backblaze</em>",
	);
my $pro_list_clouds = join(', ', @pro_list_clouds_list);
$pro_list_clouds =~ s/(.+)(,)(.+)$/$1 $text{'scripts_gpl_pro_tip_and'}$3/;
$text{"scripts_gpl_pro_tip_list_clouds"} = &text('scripts_gpl_pro_tip_clouds', $pro_list_clouds);
print &alert_pro_tip('list_clouds');
}

# list_extra_user_pro_tip(type, return-url)
# Displays an alert for Create Database User and
# Create Webserver User page explaining the feature
sub list_extra_user_pro_tip
{
my ($etype, $return_url) = @_;
$etype = "extra_${etype}_users";
return if (!should_show_pro_tip($etype, 1));
print &alert_pro_tip($etype,
	{ return_url => $return_url,
	  button_text => $text{'scripts_gpl_pro_tip_extra_user_dismiss'}} );
}

############################################################
# API general subs
############################################################

# should_show_pro_tip(tipid, [ignore])
# If the current user should see Pro tip for the given page
sub should_show_pro_tip
{
my ($tipid, $ignore) = @_;
return if ($virtualmin_pro);
return if (!&master_admin());
return if (!$ignore &&
            $config{'hide_pro_tips'} == 1);
my %protips;
my $protip_file = "$newfeatures_seen_dir/$remote_user-pro-tips";
&read_file_cached($protip_file, \%protips);
return wantarray ? ($protips{$tipid}) : !$protips{$tipid};
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
$protips{$tipid} = time();
&write_file($protip_file, \%protips);
}

# alert_pro_tip(tip-id, optional-settings-hash-ref)
# Returns an alert with given Pro tip description and dismiss button
sub alert_pro_tip
{
my ($tipid, $opts) = @_;
my $alert_title = $text{'scripts_gpl_pro_tip'};
my $alert_body1 = $text{"scripts_gpl_pro_tip_$tipid"} . " ";
my $alert_body2 =
       &text(($text{"scripts_gpl_pro_tip_enroll_$tipid"} ?
                    "scripts_gpl_pro_tip_enroll_$tipid" :
                    'scripts_gpl_pro_tip_enroll'),
              $virtualmin_shop_link_cat);
my $hide_button_text = ($text{"scripts_gpl_pro_tip_${tipid}_hide"} ||
                        $text{"scripts_gpl_pro_tip_hide"});
my $hide_button_icon = 'fa2 fa-fw fa2-eye-off';
my $return_url;
if ($opts) {
	$alert_title = $opts->{'alert_title'}
		if ($opts->{'alert_title'});
	$alert_body1 = $opts->{'alert_body1'}
		if ($opts->{'alert_body1'});
	$alert_body2 = $opts->{'alert_body2'}
		if ($opts->{'alert_body2'});
	$hide_button_text = $opts->{'button_text'}
		if ($opts->{'button_text'});
	$hide_button_icon = $opts->{'button_icon'}
		if ($opts->{'button_icon'});
	$hide_button_text2 = $opts->{'button_text2'}
		if ($opts->{'button_text'});
	$hide_button_icon2 = $opts->{'button_icon2'}
		if ($opts->{'button_icon'});
	$hide_button_text3 = $opts->{'button_text3'}
		if ($opts->{'button_text'});
	$hide_button_icon3 = $opts->{'button_icon3'}
		if ($opts->{'button_icon'});
	$return_url = $opts->{'return_url'}
		if ($opts->{'return_url'});
	}
my %tinfo = &get_theme_info($current_theme);
my ($ptitle, $btncls, $alertcls);
if ($tinfo{'bootstrap'}) {
	$ptitle = "&mdash;&nbsp;";
	$btncls = "btn btn-tiny btn-success";
	$alertcls = " fa2 fa2-virtualmin";
	}
else {
	$alert_body1 = "<b>$alert_body1</b>";
	$alert_body2 = "<b>$alert_body2</b>";
	}
my $form = $ptitle .
    &ui_form_start("@{[&get_webprefix_safe()]}/$module_name/set_seen_pro_tip.cgi", "post") .
        $alert_body1 .
        $alert_body2 . "<p>\n" . 
        &ui_hidden("tipid", $tipid) .
        ($return_url ? &ui_hidden("return_url", $return_url) : "") .
        &ui_form_end([
            $hide_button_text2 ? [ undef, $hide_button_text2, undef, undef,
                "onclick=\"window.open('$virtualmin_shop_link_cat','_blank');event.preventDefault();event.stopPropagation();\"",
                $hide_button_icon2, $btncls ] : undef,
            $hide_button_text3 ? [ 'remind', $hide_button_text3, undef, undef, undef, $hide_button_icon3 ] : undef,
            $hide_button_text ? [ undef, $hide_button_text, undef, undef, undef, $hide_button_icon ] : undef ], undef, 1);
return &ui_alert_box($form, 'success', undef, undef, $alert_title, $alertcls);
}

# global_menu_link_pro_tip(global-links-hash-ref)
# Modifies global links and returns grayed out Pro
# links for GPL users for advertising purposes
sub global_menu_link_pro_tip
{
my ($global_links_hash) = @_;
foreach my $pro_demo_feature
(
	# Add demo Reseller Accounts link for GPL users 
	{ 'name' => 'newresels',
	  'title' => $text{'newresels_title'},
	  'cat' => 'setting',
	  'url' => "$virtualmin_docs_pro/#newresels",
	},

	# Add demo Cloud Mail Delivery Providers link for GPL users 
	{ 'name' => 'smtpclouds',
	  'title' => $text{'smtpclouds_title'},
	  'cat' => 'email',
	  'url' => "$virtualmin_docs_pro/#smtpclouds",
	},

	# Add demo Email Server Owners link for GPL users 
	{ 'name' => 'newnotify',
	  'title' => $text{'newnotify_title'},
	  'cat' => 'email',
	  'url' => "$virtualmin_docs_pro/#newnotify",
	},

	# Add demo Email Server Owners link for GPL users 
	{ 'name' => 'newretention',
	  'title' => $text{'newretention_title'},
	  'cat' => 'email',
	  'url' => "$virtualmin_docs_pro/#newretention",
	},

	# Add demo New Reseller Email link for GPL users 
	{ 'name' => 'newreseller',
	  'title' => $text{'newreseller_title'},
	  'cat' => 'email',
	  'url' => "$virtualmin_docs_pro/#newreseller",
	},

	# Add demo Custom Links link for GPL users 
	{ 'name' => 'newlinks',
	  'title' => $text{'newlinks_title'},
	  'cat' => 'custom',
	  'url' => "$virtualmin_docs_pro/#newlinks",
	},

	# Add demo Remote DNS
	{ 'name' => 'remotedns',
	  'title' => $text{'remotedns_title'},
	  'cat' => 'ip',
	  'url' => "$virtualmin_docs_pro/#remotedns",
	},

	# Add demo SSL Providers
	{ 'name' => 'newacmes',
	  'title' => $text{'newacmes_title'},
	  'cat' => 'ip',
	  'url' => "$virtualmin_docs_pro/#newacmes",
	},

	# Add demo Secondary Mail Servers link for GPL users 
	{ 'name' => 'newmxs',
	  'title' => $text{'newmxs_title'},
	  'cat' => 'email',
	  'url' => "$virtualmin_docs_pro/#newmxs",
	},

	# Add demo Disk Quota Monitoring link for GPL users 
	{ 'name' => 'newquotas',
	  'title' => $text{'newquotas_title'},
	  'cat' => 'check',
	  'url' => "$virtualmin_docs_pro/#newquotas",
	  'skip' => !&has_home_quotas()
	},

	# Add demo Batch Create Servers link for GPL users 
	{ 'name' => 'newcmass',
	  'title' => $text{'cmass_title'},
	  'cat' => 'add',
	  'url' => "$virtualmin_docs_pro/#newcmass",
	},

	# Add demo Backup Encryption Keys link for GPL users 
	{ 'name' => 'bkeys',
	  'title' => $text{'bkeys_title'},
	  'cat' => 'backup',
	  'url' => "$virtualmin_docs_pro/#bkeys",
	},

	# Add demo System Statistics link for GPL users 
	{ 'name' => 'history',
	  'icon' => 'graph',
	  'title' => $text{'edit_history'},
	  'url' => "$virtualmin_docs_pro/#demo_history",
	},
)
{
	&menu_link_pro_tip($pro_demo_feature->{'name'}, $pro_demo_feature);
	delete($pro_demo_feature->{'name'});
	push(@{$global_links_hash}, $pro_demo_feature)
		if (!$pro_demo_feature->{'skip'});
	}
}

# menu_link_pro_tips(links-hash-ref, dom-hash-ref)
# Modifies sub-menu links and returns grayed out
# Pro links for GPL users for advertising purposes
sub menu_link_pro_tips
{
my ($links_hash, $d) = @_;
foreach my $pro_demo_feature
(
	# Add demo Edit Resource Limits link for GPL users 
	{ 'name' => 'edit_res',
	  'title' => $text{'edit_res'},
	  'cat' => 'server',
	  'url' => "$virtualmin_docs_pro/#edit_res",
	  'skip' => !($d->{'unix'} && &can_edit_res($d))
	},

	# Add demo Search Mail Logs link for GPL users 
	{ 'name' => 'edit_maillog',
	  'title' => $text{'edit_maillog'},
	  'cat' => 'logs',
	  'url' => "$virtualmin_docs_pro/#edit_maillog",
	  'skip' => !($config{'mail'} &&
	              $mail_system <= 1 &&
	              $d->{'mail'}),
	},

	# Add demo Check Connectivity link for GPL users 
	{ 'name' => 'edit_connect',
	  'title' => $text{'edit_connect'},
	  'cat' => 'logs',
	  'url' => "$virtualmin_docs_pro/#edit_connect",
	},

	# Add demo Edit Web Pages link for GPL users 
	{ 'name' => 'edit_html',
	  'title' => $text{'edit_html'},
	  'cat' => 'web',
	  'url' => "$virtualmin_docs_pro/#edit_html",
	  'skip' => !(&domain_has_website($d) &&
	              $d->{'dir'} &&
	              !$d->{'alias'} &&
	              !$d->{'proxy_pass_mode'} &&
	              &can_edit_html()),
	},
)
{
	&menu_link_pro_tip($pro_demo_feature->{'name'}, $pro_demo_feature);
	delete($pro_demo_feature->{'name'});
	push(@{$links_hash}, $pro_demo_feature)
		if (!$pro_demo_feature->{'skip'});
	}
}

# menu_link_pro_tip(demo-feature-name, link-hash-ref)
# Modifies default menu link to advertise GPL user Pro features, if allowed
sub menu_link_pro_tip
{
my ($demo_feature, $link_hash) = @_;
if (should_show_pro_tip($demo_feature)) {
	delete($link_hash->{'page'});
	$link_hash->{'inactive'} = 1;
	$link_hash->{'urlpro'} = $link_hash->{'url'};
	$link_hash->{'title'} .=
	  (
	    " <span>" .
	      "<small data-menu-link-demo><sub>&#128274;&nbsp;&nbsp;Pro</sub></small>" .
	      "<span data-menu-link-icon-demo title='$text{'scripts_gpl_pro_tip'}'></span>" .
	    "</span>"
	  );
	}
elsif (!$virtualmin_pro) {
	$link_hash->{'skip'} = 1;
	}
}

# inline_html_pro_tip(html, name, always-show)
# Modifies passed HTML element to advertise GPL user Pro features, if allowed
sub inline_html_pro_tip
{
my ($h, $n, $a) = @_;
my $f = sub {
	my ($h) = @_;
	map { $h =~ /<input/ &&
	      $h =~ s/(<input[^>]*?)\s?(name|value|id|size)=["'][^"']*["'](.*?>)/$1$3/ }
	      	(0..3);
	      $h =~ s/(<input[^>]*?)>/$1 disabled>/g;
	return $h;
	};
my $d = sub {
	my ($h, $n) = @_;
	return "<span data-pro-disabled='$n'>$h</span>";
	};
if (!$virtualmin_pro) {
	if ($config{'hide_pro_tips'} != 1 || $a) {
		$h = &$d(&$f($h), "$n-elem");
		$h .= &$d("&nbsp;&nbsp;<small><a target='_blank' ".
		            "href='$virtualmin_docs_pro/#${n}' ".
			    "data-pro='$n'>&#128274;&nbsp;&nbsp;".
			    	"<span>Pro</span></a></small>", "$n-link");
		return $h;
		}
	return undef;
	}
return $h;
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
	    { 'version' => 'latest',
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

# proshow()
# Returns 1 or 0 depending on whether Pro features should be shown at all in GPL
sub proshow
{
return 1 if ($virtualmin_pro);
return ($config{'hide_pro_tips'} == 1 && !$virtualmin_pro) ? 0 : 1
}

# procell([col-size], [tds-ref])
# Returns a reference to an array of table cells attributes
sub procell {
	my ($colsize, @tds) = @_;
	$colsize ||= 1;
	@tds = (("") x $colsize) if (!@tds);
	@tds = map { "data-pro-disabled='cell' $_" } @tds;
	return $virtualmin_pro ? undef : \@tds;
};

1;