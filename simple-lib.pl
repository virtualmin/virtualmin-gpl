# Functions for simple alias parsing

# get_simple_alias(&domain, &alias)
# If the current forwarding rules are simple (local delivery, autoreply
# and forwarding only), return a hash ref containing the settings. Otherwise,
# return undef.
sub get_simple_alias
{
local ($d, $a) = @_;
return undef if (!$virtualmin_pro);
local $simple;
foreach my $v (@{$a->{'to'}}) {
	local ($atype, $aval) = &alias_type($v, $a->{'user'} || $a->{'name'});
	if ($atype == 1) {
		# Forward to an address
		push(@{$simple->{'forward'}}, $aval);
		}
	elsif ($atype == 9) {
		# Bounce mail
		$simple->{'bounce'} = 1;
		}
	elsif ($atype == 7) {
		# Local delivery
		$simple->{'local'} = $aval;
		}
	elsif ($atype == 10) {
		# To this user
		$simple->{'tome'} = 1;
		}
	elsif ($atype == 5) {
		# Autoreply program
		return undef if ($simple->{'autoreply'});
		$simple->{'autoreply'} = $aval =~ /^\// ? $aval
							: "$d->{'home'}/$aval";
		$simple->{'auto'} = 1;
		&read_autoreply($simple->{'autoreply'}, $simple);
		}
	else {
		# Some un-supported rule
		return undef;
		}
	}
if (!$simple->{'autoreply'}) {
	# Get autoreply message from default file
	$simple->{'autoreply'} = "$d->{'home'}/autoreply-".
			         ($a->{'user'} || $a->{'from'}).".txt";
	&read_autoreply($simple->{'autoreply'}, $simple);
	}
$simple->{'cmt'} = $a->{'cmt'};
return $simple;
}

# read_autoreply(file, &simple)
# Updates a simple alias object with setting from an autoreply file
sub read_autoreply
{
local ($file, $simple) = @_;
local @lines;
open(FILE, $file);
while(<FILE>) {
	if (/^Reply-Tracking:\s*(.*)/) {
		$simple->{'replies'} = $1;
		}
	elsif (/^Reply-Period:\s*(.*)/) {
		$simple->{'period'} = $1;
		}
	elsif (/^No-Autoreply:\s*(.*)/) {
		$simple->{'no_autoreply'} = $1;
		}
	elsif (/^No-Autoreply-Regexp:\s*(.*)/) {
		push(@{$simple->{'no_autoreply_regexp'}}, $1);
		}
	elsif (/^Autoreply-File:\s*(.*)/) {
		push(@{$simple->{'autoreply_file'}}, $1);
		}
	elsif (/^From:\s*(.*)/) {
		$simple->{'from'} = $1;
		}
	else {
		push(@lines, $_);
		}
	}
close(FILE);
$simple->{'autotext'} = join("", @lines);
}

# save_simple_alias(&domain, &alias|&user, &simple)
# Updates an alias object with simple settings, and writes out any autoreply
# file needed
sub save_simple_alias
{
local ($d, $alias, $simple) = @_;
local @v;
push(@v, @{$simple->{'forward'}});
if ($simple->{'bounce'}) {
	push(@v, "BOUNCE");
	}
if ($simple->{'local'}) {
	push(@v, "\\".$simple->{'local'});
	}
if ($simple->{'tome'}) {
	local $escuser = $alias->{'user'};
	if ($config{'mail_system'} == 0 && $escuser =~ /\@/) {
		$escuser = &replace_atsign($escuser);
		}
	push(@v, "\\".($escuser || $alias->{'name'}));
	}
if ($simple->{'auto'}) {
	local $who = $alias->{'user'} || $alias->{'from'};
	$simple->{'autoreply'} ||= "$d->{'home'}/autoreply-$who.txt";
	local $link = &convert_autoreply_file($d, $simple->{'autoreply'});
	push(@v, "|$module_config_directory/autoreply.pl $simple->{'autoreply'} $who $link");
	}
$alias->{'to'} = \@v;
$alias->{'cmt'} = $simple->{'cmt'};
}

# write_simple_autoreply(&domain, &simple)
# Save the autoreply file for a simple alias defintion
sub write_simple_autoreply
{
local ($d, $simple) = @_;
if ($simple->{'autotext'}) {
        # Save autoreply text
        &open_tempfile(AUTO, ">$simple->{'autoreply'}");
        if ($simple->{'replies'}) {
                &print_tempfile(AUTO,
                        "Reply-Tracking: $simple->{'replies'}\n");
                }
        if ($simple->{'period'}) {
                &print_tempfile(AUTO,
                        "Reply-Period: $simple->{'period'}\n");
                }
        if ($simple->{'no_autoreply'}) {
                &print_tempfile(AUTO,
                        "No-Autoreply: $simple->{'no_autoreply'}\n");
                }
        foreach my $r (@{$simple->{'no_autoreply_regexp'}}) {
                &print_tempfile(AUTO, "No-Autoreply-Regexp: $r\n");
                }
        foreach my $f (@{$simple->{'autoreply_file'}}) {
                &print_tempfile(AUTO, "Autoreply-File: $f\n");
                }
        if ($simple->{'from'}) {
                &print_tempfile(AUTO, "From: $simple->{'from'}\n");
                }
        &print_tempfile(AUTO, $simple->{'autotext'});
        &close_tempfile(AUTO);

	# Hard link to the autoreply directory, which is readable by the mail
	# server, unlike users' homes
	local $link = &convert_autoreply_file($d, $simple->{'autoreply'});
	if ($link) {
		unlink($link);
		link($simple->{'autoreply'}, $link) ||
			&error("Failed to link $simple->{'autoreply'} to ",
			       "$link : $!");
		}
        }
}

# delete_simple_autoreply(&domain, &simple)
# Remove the autoreply file for a domain (when the alias is deleted, or 
# being re-saved)
sub delete_simple_autoreply
{
local ($d, $simple) = @_;
if ($simple->{'auto'} &&
    $simple->{'autoreply'} &&
    $simple->{'autoreply'} =~ /\/autoreply-(\S+)\.txt$/) {
	local @st = stat($simple->{'autoreply'});
	if ($st[4] == $d->{'uid'}) {
		local $link = &convert_autoreply_file(
			$d, $simple->{'autoreply'});
		unlink($simple->{'autoreply'});
		unlink($link) if ($link);
		}
	}
}

# show_simple_form(&simple, [no-reply-from], [no-local], [no-bounce], [&tds])
# Outputs ui_table_row entries for a simple mail forwarding form
sub show_simple_form
{
local ($simple, $nofrom, $nolocal, $nobounce, $tds, $sfx) = @_;
$sfx ||= "alias";

if ($nolocal) {
	# Show checkbox for delivery to me
	print &ui_table_row(&hlink($text{$sfx.'_tome'}, $sfx."_tome"),
			    &ui_checkbox("tome", 1, $text{'alias_tomeyes'},
					 $simple->{'tome'}), undef, \@tds);
	}
else {
	# Deliver to any local user
	print &ui_table_row(&hlink($text{$sfx.'_local'}, $sfx."_local"),
			    &ui_checkbox("local", 1, $text{'alias_localyes'},
					 $simple->{'local'})." ".
			    &ui_textbox("localto", $simple->{'local'}, 40),
			    undef, $tds);
	}

if (!$nobounce) {
	# Bounce back
	print &ui_table_row(&hlink($text{$sfx.'_bounce'}, $sfx."_bounce"),
			    &ui_checkbox("bounce", 1, $text{'alias_bounceyes'},
					 $simple->{'bounce'}),
			    undef, $tds);
	}

# Forward to some address
@fwd = @{$simple->{'forward'}};
print &ui_table_row(&hlink($text{$sfx.'_forward'}, $sfx."_forward"),
		    &ui_checkbox("forward", 1,$text{'alias_forwardyes'},
				 scalar(@fwd))."<br>\n".
		    &ui_textarea("forwardto", join("\n", @fwd), 3, 40),
		    undef, $tds);

# Autoreply active and text
print &ui_table_row(&hlink($text{$sfx.'_auto'}, $sfx."_auto"),
		    &ui_checkbox("auto", 1,$text{'alias_autoyes'},
				 $simple->{'auto'})."<br>\n".
		    &ui_textarea("autotext", $simple->{'autotext'},
				 5, 70),
		    undef, $tds);

$period = $simple->{'replies'} && $simple->{'period'} ?
		int($simple->{'period'}/60) :
	  $simple->{'replies'} ? 60 : undef;
print &ui_table_row(&hlink($text{$sfx.'_period'}, $sfx."_period"),
	    &ui_opt_textbox("period", $period, 3, $text{'alias_noperiod'})." ".
	    $text{'alias_mins'},
	    undef, $tds);

if (!$nofrom) {
	print &ui_table_row(&hlink($text{$sfx.'_from'}, $sfx."_from"),
		&ui_radio("from_def", $simple->{'from'} ? 0 : 1,
			  [ [ 1, $text{'alias_fromauto'} ],
			    [ 0, &ui_textbox("from", $simple->{'from'},
					     40) ] ]),
		undef, $tds);
	}
}

# parse_simple_form(&simple, &in, &domain, [no-reply-from], [no-local],
#                   [no-bounce])
# Updates a simple delivery object with settings from &in
sub parse_simple_form
{
local ($simple, $in, $d, $nofrom, $nolocal, $nobounce) = @_;

if ($nolocal) {
	# Check to-me option
	$simple->{'tome'} = $in->{'tome'};
	}
else {
	# Check local delivery field
	if ($in->{'local'}) {
		$in->{'localto'} =~ /^\S+$/ ||
			&error(&text('alias_etype7', $in->{'local'}));
		$simple->{'local'} = $in->{'localto'};
		}
	else {
		delete($simple->{'local'});
		}
	}
if (!$nobounce) {
	$simple->{'bounce'} = $in->{'bounce'};
	}
if ($in->{'forward'}) {
	$in->{'forwardto'} || &error($text{'alias_eforward'});
	$simple->{'forward'} = [ split(/\s+/, $in->{'forwardto'}) ];
	}
else {
	delete($simple->{'forward'});
	}
$in->{'autotext'} =~ s/\r//g;
if ($in->{'autotext'}) {
	$simple->{'autotext'} = $in->{'autotext'};
	if ($in->{'period_def'}) {
		delete($simple->{'replies'});
		delete($simple->{'period'});
		}
	else {
		# Autoreply period set .. need to choose a file, and
		# make sure it can be created
		$in->{'period'} =~ /^\d+$/ ||
			&error($text{'alias_eperiod'});
		$simple->{'period'} = $in->{'period'}*60;
		local $rdir = "$d->{'home'}/replies";
		$simple->{'replies'} ||= "$rdir/replies-$name";
		if (!-e $rdir) {
			&make_dir($rdir, 0777);
			&set_ownership_permissions(
			    $d->{'uid'}, $d->{'ugid'}, 0777, $rdir);
			}
		}
	if (!$nofrom) {
		if ($in->{'from_def'}) {
			delete($simple->{'from'});
			}
		else {
			$in->{'from'} =~ /\S/ || &error($text{'alias_efrom'});
			$simple->{'from'} = $in->{'from'};
			}
		}
	&set_alias_programs();
	}
if ($in->{'auto'}) {
	$in->{'autotext'} =~ /\S/ || &error($text{'alias_eautotext'});
	}
$simple->{'auto'} = $in->{'auto'};
}

# convert_autoreply_file(&domain, file)
# Returns a file in the autoreply directory, for linking to
sub convert_autoreply_file
{
local ($d, $file) = @_;
return undef if (!-d $autoreply_file_dir);
if ($file =~ /\/(autoreply-(\S+)\.txt)$/) {
	return "$autoreply_file_dir/$d->{'id'}-$1";
	}
$file =~ s/\//_/g;
return "$autoreply_file_dir/$d->{'id'}-$file";
}

# create_autoreply_alias_links(&domain)
# For all aliases and users in some domain that have simple aliases with
# autoreponders, create hard links and update the aliases to use them.
sub create_autoreply_alias_links
{
local ($d) = @_;

# Fix up aliases
foreach my $virt (&list_domain_aliases($d)) {
	local $simple = &get_simple_alias($d, $virt);
	if ($simple && $simple->{'auto'}) {
		local $link = &convert_autoreply_file(
			$d, $simple->{'autoreply'});
		local @st = stat($link);
		if (!@st || $st[3] == 1) {
			# Need to create the link, and re-write the alias
			local $oldvirt = { %$virt };
			unlink($link);
			link($simple->{'autoreply'}, $link);
			&save_simple_alias($d, $virt, $simple);
			&modify_virtuser($oldvirt, $virt);
			}
		}
	}

# Fix up users
foreach my $user (&list_domain_users($d)) {
	local $simple = &get_simple_alias($d, $user);
	if ($simple && $simple->{'auto'}) {
		local $link = &convert_autoreply_file(
			$d, $simple->{'autoreply'});
		local @st = stat($link);
		if (!@st || $st[3] == 1) {
			# Need to create the link, and re-write the alias
			local $olduser = { %$user };
			unlink($link);
			link($simple->{'autoreply'}, $link);
			&save_simple_alias($d, $user, $simple);
			&modify_user($user, $olduser, $d, 0);
			}
		}
	}
}

1;

