# Functions for managing a domain's home directory

# setup_dir(&domain)
# Creates the home directory
sub setup_dir
{
local $tmpl = &get_template($_[0]->{'template'});
&require_useradmin();
local $qh = quotemeta($_[0]->{'home'});

# Get Unix user, either for this domain or its parent
local $uinfo;
if ($_[0]->{'unix'} || $_[0]->{'parent'}) {
	local @users = &list_all_users();
	($uinfo) = grep { $_->{'user'} eq $_[0]->{'user'} } @users;
	}
if ($_[0]->{'unix'} && !$uinfo) {
	# If we are going to have a Unix user but none has been created
	# yet, fake his details here for use in chowning and skel copying
	$uinfo ||= { 'uid' => $_[0]->{'uid'},
		     'gid' => $_[0]->{'ugid'},
		     'shell' => '/bin/sh',
		     'group' => $_[0]->{'group'} || $_[0]->{'ugroup'} };
	}

# Create and populate home directory
&$first_print($text{'setup_home'});
&system_logged("mkdir $qh") if (!-d $_[0]->{'home'});
&system_logged("chmod '$uconfig{'homedir_perms'}' $qh");
if ($uinfo) {
	&system_logged("chown $uinfo->{'uid'}:$uinfo->{'gid'} $qh");
	}
if ($tmpl->{'skel'} ne "none" && !$d->{'nocopyskel'}) {
	&copy_skel_files(&substitute_domain_template($tmpl->{'skel'}, $_[0]),
			 $uinfo, $_[0]->{'home'},
			 $_[0]->{'group'} || $_[0]->{'ugroup'}, $_[0]);
	}

# Setup sub-directories
local $d;
foreach $d (&virtual_server_directories($_[0])) {
        &system_logged("mkdir -p $qh/$d->[0] 2>/dev/null");
        &system_logged("chmod $d->[1] $qh/$d->[0]");
	if ($uinfo) {
		&system_logged("chown $uinfo->{'uid'}:$uinfo->{'gid'} $qh/$d->[0]");
		}
        }
&$second_print($text{'setup_done'});

return 1;
}

# modify_dir(&domain, &olddomain)
# Rename home directory if needed
sub modify_dir
{
if ($_[0]->{'home'} ne $_[1]->{'home'}) {
	# Move the home directory if changed, and if not already moved as
	# part of parent
	if (-d $_[1]->{'home'}) {
		&$first_print($text{'save_dirhome'});
		local $out = &backquote_logged("mv ".quotemeta($_[1]->{'home'}).
			       " ".quotemeta($_[0]->{'home'})." 2>&1");
		if ($?) {
			&$second_print(&text('save_dirhomefailed', "<tt>$out</tt>"));
			}
		else {
			&$second_print($text{'setup_done'});
			}
		}
	}
if ($_[0]->{'unix'} && !$_[1]->{'unix'} ||
    $_[0]->{'uid'} ne $_[1]->{'uid'}) {
	# Unix user now exists or has changed! Set ownership of home dir
	&$first_print($text{'save_dirchown'});
	&set_home_ownership($_[0]);
	&$second_print($text{'setup_done'});
	}
}

# delete_dir(&domain)
# Delete the home directory
sub delete_dir
{
# Delete homedir
if (-d $_[0]->{'home'} && $_[0]->{'home'} ne "/") {
	&$first_print($text{'delete_home'});
	&system_logged("rm -rf ".quotemeta($_[0]->{'home'}));
	&$second_print($text{'setup_done'});
	}
}

# validate_dir(&domain)
# Returns an error message if the directory is missing, or has the wrong
# ownership
sub validate_dir
{
local ($d) = @_;
if (!-d $d->{'home'}) {
	return &text('validate_edir', "<tt>$d->{'home'}</tt>");
	}
local @st = stat($d->{'home'});
if ($d->{'uid'} && $st[4] != $d->{'uid'}) {
	local $owner = getpwuid($st[4]);
	return &text('validate_ediruser', "<tt>$d->{'home'}</tt>",
		     $owner, $d->{'user'})
	}
if ($d->{'gid'} && $st[5] != $d->{'gid'} && $st[5] != $d->{'ugid'}) {
	local $owner = getgrgid($st[5]);
	return &text('validate_edirgroup', "<tt>$d->{'home'}</tt>",
		     $owner, $d->{'group'})
	}
foreach my $sd (&virtual_server_directories($d)) {
	if (!-d "$d->{'home'}/$sd->[0]") {
		return &text('validate_esubdir', "<tt>$sd->[0]</tt>")
		}
	local @st = stat("$d->{'home'}/$sd->[0]");
	if ($d->{'uid'} && $st[4] != $d->{'uid'}) {
		local $owner = getpwuid($st[4]);
		return &text('validate_esubdiruser', "<tt>$sd->[0]</tt>",
			     $owner, $d->{'user'})
		}
	if ($d->{'gid'} && $st[5] != $d->{'gid'} && $st[5] != $d->{'ugid'}) {
		local $owner = getgrgid($st[5]);
		return &text('validate_esubdirgroup', "<tt>$sd->[0]</tt>",
			     $owner, $d->{'group'})
		}
	}
return undef;
}

# check_dir_clash(&domain, [field])
sub check_dir_clash
{
# Does nothing ..?
return 0;
}

# backup_dir(&domain, file, &options, home-format)
# Backs up the server's home directory in tar format to the given file
sub backup_dir
{
&$first_print($text{'backup_dirtar'});
local $out;
local $cmd;
local $gzip = $_[3] && &has_command("gzip");

# Create exclude file
$xtemp = &transname();
&open_tempfile(XTEMP, ">$xtemp");
&print_tempfile(XTEMP, "domains\n");
&print_tempfile(XTEMP, "./domains\n");
if ($_[2]->{'dirnologs'}) {
	&print_tempfile(XTEMP, "logs\n");
	&print_tempfile(XTEMP, "./logs\n");
	}
&print_tempfile(XTEMP, "virtualmin-backup\n");
&print_tempfile(XTEMP, "./virtualmin-backup\n");
foreach my $e (&get_backup_excludes($_[0])) {
	&print_tempfile(XTEMP, "$e\n");
	&print_tempfile(XTEMP, "./$e\n");
	}

# Exclude all .zfs files, for Solaris
if ($gconfig{'os_type'} eq 'solaris') {
	open(FIND, "find ".quotemeta($_[0]->{'home'})." -name .zfs |");
	while(<FIND>) {
		s/\r|\n//g;
		s/^\Q$_[0]->{'home'}\E\///;
		&print_tempfile(XTEMP, "$_\n");
		&print_tempfile(XTEMP, "./$_\n");
		}
	close(FIND);
	}
&close_tempfile(XTEMP);

# Do the backup
if ($_[3] && $config{'compression'} == 0) {
	# With gzip
	$cmd = "tar cfX - $xtemp . | gzip -c >".quotemeta($_[1]);
	}
elsif ($_[3] && $config{'compression'} == 1) {
	# With bzip
	$cmd = "tar cfX - $xtemp . | bzip2 -c >".quotemeta($_[1]);
	}
else {
	# Plain tar
	$cmd = "tar cfX ".quotemeta($_[1])." $xtemp .";
	}
&execute_command("cd ".quotemeta($_[0]->{'home'})." && $cmd",
		 undef, \$out, \$out);
if ($?) {
	&$second_print(&text('backup_dirtarfailed', "<pre>$out</pre>"));
	return 0;
	}
else {
	&$second_print($text{'setup_done'});
	return 1;
	}
}

# show_backup_dir(&options)
# Returns HTML for the backup logs option
sub show_backup_dir
{
return sprintf
	"(<input type=checkbox name=dir_logs value=1 %s> %s)",
	!$opts{'dirnologs'} ? "checked" : "", $text{'backup_dirlogs'};
}

# parse_backup_dir(&in)
# Parses the inputs for directory backup options
sub parse_backup_dir
{
local %in = %{$_[0]};
return { 'dirnologs' => !$in{'dir_logs'} };
}

# restore_dir(&domain, file, &options, homeformat?)
# Extracts the given tar file into server's home directory
sub restore_dir
{
&$first_print($text{'restore_dirtar'});
local $out;
local $cf = &compression_format($_[1]);
local $comp = $cf == 1 ? "gunzip -c" :
	      $cf == 2 ? "uncompress -c" :
	      $cf == 3 ? "bunzip2 -c" : "cat";
local $q = quotemeta($_[1]);
local $qh = quotemeta($_[0]->{'home'});
&execute_command("cd $qh && $comp $q | tar xf -", undef, \$out, \$out);
if ($?) {
	&$second_print(&text('backup_dirtarfailed', "<pre>$out</pre>"));
	return 0;
	}
else {
	&$second_print($text{'setup_done'});
	if ($_[0]->{'unix'}) {
		# Set ownership on extracted home directory, apart from
		# content of ~/homes
		&$first_print($text{'restore_dirchowning'});
		&set_home_ownership($_[0]);
		&$second_print($text{'setup_done'});
		}

	return 1;
	}
}

# set_home_ownership(&domain)
# Update the ownership of all files in a server's home directory, EXCEPT
# the homes directory which is used by mail users
sub set_home_ownership
{
local $hd = $config{'homes_dir'};
$hd =~ s/^\.\///;
local $gid = $_[0]->{'gid'} || $_[0]->{'ugid'};
&system_logged("find ".quotemeta($_[0]->{'home'})." | grep -v '$_[0]->{'home'}/$hd/' | sed -e 's/^/\"/' | sed -e 's/\$/\"/' | xargs chown $_[0]->{'uid'}:$gid");
&system_logged("chown $_[0]->{'uid'}:$gid ".quotemeta($_[0]->{'home'})."/".$config{'homes_dir'});
}

# virtual_server_directories(&dom)
# Returns a list of sub-directories that need to be created for virtual servers
sub virtual_server_directories
{
local $tmpl = &get_template($_[0]->{'template'});
local $perms = $tmpl->{'web_html_perms'};
return ( $d->{'subdom'} || $d->{'alias'} ? ( ) : ( [ &public_html_dir($_[0], 1), $perms ] ),
         $d->{'subdom'} || $d->{'alias'} ? ( ) : ( [ 'cgi-bin', $perms ] ),
         [ 'logs', '750' ],
         [ $config{'homes_dir'}, '755' ] );
}

# create_server_tmp(&domain)
# Creates the temporary files directory for a domain, and returns the path
sub create_server_tmp
{
local ($d) = @_;
if ($d->{'dir'}) {
	local $tmp = "$d->{'home'}/tmp";
	if (!-d $tmp) {
		&make_dir($tmp, 0750, 1);
		&set_ownership_permissions($d->{'uid'}, $d->{'ugid'},
					   0750, $tmp);
		}
	return $tmp;
	}
else {
	# For domains without a home
	return "/tmp";
	}
}

# show_template_dir(&tmpl)
# Outputs HTML for editing directory-related template options
sub show_template_dir
{
local ($tmpl) = @_;

# The skeleton files directory
print &ui_table_row(&hlink($text{'tmpl_skel'}, "template_skel"),
	&none_def_input("skel", $tmpl->{'skel'}, $text{'tmpl_skeldir'}, 0,
			$tmpl->{'standard'} ? 1 : 0, undef,
			[ "skel", "skel_subs" ])."\n".
	&ui_textbox("skel", $tmpl->{'skel'} eq "none" ? undef
						      : $tmpl->{'skel'}, 40));

# Perform substitions on skel file contents
print &ui_table_row(&hlink($text{'tmpl_skel_subs'}, "template_skel_subs"),
	&ui_yesno_radio("skel_subs", int($tmpl->{'skel_subs'})));
}

# parse_template_dir(&tmpl)
# Updates directory-related template options from %in
sub parse_template_dir
{
local ($tmpl) = @_;

# Save skeleton directory
$tmpl->{'skel'} = &parse_none_def("skel");
if ($in{"skel_mode"} == 2) {
	-d $in{'skel'} || &error($text{'tmpl_eskel'});
	$tmpl->{'skel_subs'} = $in{'skel_subs'};
	}
}

$done_feature_script{'dir'} = 1;

1;

