# Functions for advertising Pro features to GPL users

# should_show_pro_tip(tipid)
# If the current user should see Pro tip for the given page
sub should_show_pro_tip
{
my ($tipid) = @_;
my %protips;
my $protip_file = "$newfeatures_seen_dir/$remote_user-pro-tips";
&read_file_cached($protip_file, \%protips);
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

# list_scripts_pro_tip(\gpl-scripts)
# Displays an alert for Install Scripts page
# and its Available Scripts tab if not previously
# dismissed (seen) by a user
sub list_scripts_pro_tip
{
my ($scripts) = @_;
if ($virtualmin_pro || $in{'search'} ||
    $config{'no_pro_tips'} || !should_show_pro_tip('list_scripts')) {
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

# Returns an alert with given Pro tip description and dismiss button
sub alert_pro_tip
{
my ($tipid) = @_;
my $form = &ui_form_start("@{[&get_webprefix_safe()]}/$module_name/set_seen_pro_tip.cgi", "post").
			$text{"scripts_gpl_pro_tip_$tipid"}. " " .
			&text('scripts_gpl_pro_tip_enroll',
			      'https://www.virtualmin.com/product-category/virtualmin/') . "<p>\n".
			&ui_hidden("tipid", $tipid) .
			&ui_form_end([ [ undef, ($text{"scripts_gpl_pro_tip_${tipid}_hide"} ||
			                         $text{"scripts_gpl_pro_tip_hide"}), undef, undef, undef, 'fa fa-fw fa-times-circle-o' ] ], undef, 1);

return &ui_alert_box($form, 'success', undef, undef, $text{'scripts_gpl_pro_tip'}, " fa2 fa2-smile");
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

