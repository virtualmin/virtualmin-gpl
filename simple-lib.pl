# Functions for simple alias parsing

use Time::Local;

# get_simple_alias(&domain, &alias)
# If the current forwarding rules are simple (local delivery, autoreply
# and forwarding only), return a hash ref containing the settings. Otherwise,
# return undef.
sub get_simple_alias
{
local ($d, $a) = @_;
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
	elsif ($atype == 13 && $aval eq $d->{'id'}) {
		# To everyone in domain
		$simple->{'everyone'} = 1;
		}
	elsif ($atype == 5) {
		# Autoreply program
		return undef if ($simple->{'autoreply'});
		$simple->{'autoreply'} = $aval =~ /^\// ? $aval
							: "$d->{'home'}/$aval";
		$simple->{'auto'} = 1;
		local $l = &read_autoreply(&command_as_user($d->{'user'}, 0,
		    "cat ".quotemeta($simple->{'autoreply'}))." |", $simple);
		local @st = stat($simple->{'autoreply'});
		if ($st[7] && !$l) {
			# Fall back to reading directly, if allowed
			if ($st[4] == $d->{'uid'}) {
				&read_autoreply($simple->{'autoreply'},$simple);
				}
			}
		}
	else {
		# Some un-supported rule
		return undef;
		}
	}
#if (!$simple->{'autoreply'}) {
#	# Get autoreply message from default file
#	$simple->{'autoreply'} = "$d->{'home'}/autoreply-".
#			         ($a->{'user'} || $a->{'from'}).".txt";
#	&read_autoreply($simple->{'autoreply'}, $simple);
#	}
$simple->{'cmt'} = $a->{'cmt'};
return $simple;
}

# read_autoreply(file, &simple)
# Updates a simple alias object with setting from an autoreply file
sub read_autoreply
{
local ($file, $simple) = @_;
local @lines;
local $_;
local $lines;
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
	elsif (/^Autoreply-Start:\s*(\d+)/) {
		$simple->{'autoreply_start'} = $1;
		}
	elsif (/^Autoreply-End:\s*(\d+)/) {
		$simple->{'autoreply_end'} = $1;
		}
	elsif (/^From:\s*(.*)/) {
		$simple->{'from'} = $1;
		}
	elsif (/^Charset:\s*(.*)/) {
		$simple->{'charset'} = $1;
		}
	elsif (/^No-Forward-Reply:\s*(.*)/) {
		$simple->{'no_forward_reply'} = $1;
		}
	else {
		push(@lines, $_);
		if (/\S/) {
			# End of headers, so just read the rest of the lines
			# verbatim
			last;
			}
		}
	$lines++;
	}
while(<FILE>) {
	push(@lines, $_);
	$lines++;
	}
close(FILE);
$simple->{'autotext'} = join("", @lines);
return $lines;
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
	local $escuser = $simple->{'local'};
	if ($config{'mail_system'} == 0 && $escuser =~ /\@/) {
		$escuser = &replace_atsign($escuser);
		}
	else {
		$escuser = &escape_user($escuser);
		}
	push(@v, "\\".$escuser);
	}
if ($simple->{'tome'}) {
	local $escuser = $alias->{'user'};
	if ($config{'mail_system'} == 0 && $escuser =~ /\@/) {
		$escuser = &replace_atsign($escuser);
		}
	else {
		$escuser = &escape_user($escuser);
		}
	push(@v, "\\".($escuser || $alias->{'name'}));
	}
if ($simple->{'auto'}) {
	local $who = $alias->{'user'} || $alias->{'from'};
	$simple->{'autoreply'} ||= "$d->{'home'}/autoreply-$who.txt";
	local $link = &convert_autoreply_file($d, $simple->{'autoreply'});
	push(@v, "|$module_config_directory/autoreply.pl $simple->{'autoreply'} $who $link");
	}
if ($simple->{'everyone'}) {
	push(@v, ":include:$everyone_alias_dir/$d->{'id'}");
	&create_everyone_file($d);
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
        &open_tempfile_as_domain_user($d, AUTO, ">$simple->{'autoreply'}");
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
	if ($simple->{'autoreply_start'}) {
		&print_tempfile(AUTO,
			"Autoreply-Start: $simple->{'autoreply_start'}\n");
		}
	if ($simple->{'autoreply_end'}) {
		&print_tempfile(AUTO,
			"Autoreply-End: $simple->{'autoreply_end'}\n");
		}
        if ($simple->{'from'}) {
                &print_tempfile(AUTO, "From: $simple->{'from'}\n");
                }
        if ($simple->{'charset'}) {
                &print_tempfile(AUTO, "Charset: $simple->{'charset'}\n");
                }
        if ($simple->{'no_forward_reply'}) {
                &print_tempfile(AUTO, "No-Forward-Reply: $simple->{'no_forward_reply'}\n");
                }
        &print_tempfile(AUTO, $simple->{'autotext'});
        &close_tempfile_as_domain_user($d, AUTO);

	# Hard link to the autoreply directory, which is readable by the mail
	# server, unlike users' homes
	local $link = &convert_autoreply_file($d, $simple->{'autoreply'});
	if ($link) {
		&unlink_file_as_domain_user($d, $link);
		&link_file_as_domain_user($d, $simple->{'autoreply'}, $link) ||
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
		&unlink_file_as_domain_user($d, $simple->{'autoreply'});
		&unlink_file_as_domain_user($d, $link) if ($link);
		}
	}
}

# show_simple_form(&simple, [no-reply-from], [no-local], [no-bounce],
#		   [no-everyone], [&tds], suffix)
# Outputs ui_table_row entries for a simple mail forwarding form
sub show_simple_form
{
local ($simple, $nofrom, $nolocal, $nobounce, $noeveryone, $tds, $sfx) = @_;
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

# Forward to everyone in domain
if (!$noeveryone) {
	print &ui_table_row(&hlink($text{$sfx.'_everyone'}, $sfx."_everyone"),
		    &ui_checkbox("everyone", 1, $text{'alias_everyoneyes'},
				 $simple->{'everyone'}));
	}

# Autoreply active and text
print &ui_table_row(&hlink($text{$sfx.'_auto'}, $sfx."_auto"),
		    &ui_checkbox("auto", 1,$text{'alias_autoyes'},
				 $simple->{'auto'})."<br>\n".
		    &ui_textarea("autotext", $simple->{'autotext'},
				 5, 60),
		    undef, $tds);

# Hidden section for autoreply options
my $aopts = $simple->{'replies'} ||
	    $simple->{'charset'} ||
	    $simple->{'autoreply_start'} ||
	    $simple->{'autoreply_end'} ||
	    $simple->{'from'} && !$nofrom;
print &ui_hidden_table_row_start($text{'alias_aopts'}, "aopts", $aopts);

# Message character set
my $charset = $simple->{'autotext'} ? $simple->{'charset'}
				    : &get_charset();
print &ui_table_row(&hlink($text{'user_charset'}, "user_charset"),
	&ui_opt_textbox("charset", $charset, 10, $text{'user_charset_def'}));

# Autoreply period
$period = $simple->{'replies'} && $simple->{'period'} ?
		int($simple->{'period'}/60) :
	  $simple->{'replies'} ? 60 : undef;
print &ui_table_row(&hlink($text{$sfx.'_period'}, $sfx."_period"),
	    &ui_opt_textbox("period", $period, 3, $text{'alias_noperiod'})." ".
	    $text{'alias_mins'},
	    undef, $tds);

# Autoreply date range
foreach my $p ('start', 'end') {
	local @tm;
	if ($simple->{'autoreply_'.$p}) {
		@tm = localtime($simple->{'autoreply_'.$p});
		$tm[4]++; $tm[5] += 1900;
		}
	local $dis1 = &js_disable_inputs([ 'd'.$p, 'm'.$p, 'y'.$p ], [ ]);
	local $dis2 = &js_disable_inputs([ ], [ 'd'.$p, 'm'.$p, 'y'.$p ]);
	print &ui_table_row(&hlink($text{'alias_'.$p}, 'alias_'.$p),
		&ui_radio($p.'_def', $simple->{'autoreply_'.$p} ? 0 : 1,
			  [ [ 1, $text{'alias_pdef'}, "onClick='$dis1'" ],
			    [ 0, $text{'alias_psel'}, "onClick='$dis2'" ] ]).
		&ui_date_input($tm[3], $tm[4], $tm[5],
			       'd'.$p, 'm'.$p, 'y'.$p, !$tm[3])." ".
		&date_chooser_button('d'.$p, 'm'.$p, 'y'.$p));
	}

# Autoreply From: address
if (!$nofrom) {
	print &ui_table_row(&hlink($text{$sfx.'_from'}, $sfx."_from"),
		&ui_radio("from_def", $simple->{'from'} ? 0 : 1,
			  [ [ 1, $text{'alias_fromauto'} ],
			    [ 0, &ui_textbox("from", $simple->{'from'},
					     40) ] ]),
		undef, $tds);
	}

# End of hidden
print &ui_hidden_table_row_end("aopts");
}

# parse_simple_form(&simple, &in, &domain, [no-reply-from], [no-local],
#                   [no-bounce], [name])
# Updates a simple delivery object with settings from &in
sub parse_simple_form
{
local ($simple, $in, $d, $nofrom, $nolocal, $nobounce, $name) = @_;

if ($nolocal) {
	# Check to-me option
	$simple->{'tome'} = $in->{'tome'};
	}
else {
	# Check local delivery field
	if ($in->{'local'}) {
		$in->{'localto'} =~ /^\S+$/ ||
			&error(&text('alias_etype7', $in->{'local'}));
		$in->{'localto'} !~ /\@/ || 
		  defined(getpwnam($in->{'localto'})) ||
		  &error(&text('alias_elocaluser', $in->{'localto'}));
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
	foreach my $f (@{$simple->{'forward'}}) {
		$f =~ /^([^\|\:\"\' \t\/\\\%]\S*)$/ ||
			&error(&text('alias_etype1', $f));
		&can_forward_alias($f) || &error(&text('alias_etype1f', $f));
		}
	}
else {
	delete($simple->{'forward'});
	}
$simple->{'everyone'} = $in->{'everyone'};
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
		if (!$simple->{'replies'}) {
			# Setting up for the first time
			$simple->{'replies'} =
				&convert_autoreply_file($d, "replies-$name");
			}
		else {
			# Fix existing file
			local $adir = &get_autoreply_file_dir();
			if (!&is_under_directory($adir, $simple->{'replies'})) {
				local $c = &convert_autoreply_file(
						$d, "replies-$name");
				$simple->{'replies'} = $c if ($c);
				}
			}
		if (!$simple->{'replies'}) {
			# If we couldn't link the reply tracking file, use one
			# in the home dir. This can happen if each user has
			# a home on a different fs
			$simple->{'replies'} = "$d->{'home'}/replies-$name";
			}
		}

	# Save character set
	if ($in{'charset_def'}) {
		delete($simple->{'charset'});
		}
	else {
		$in{'charset'} =~ /^[a-z0-9\.\-\_]+$/i ||
                        error($text{'user_echarset'});
		$simple->{'charset'} = $in{'charset'};
		}

	# Save autoreply start and end
	foreach my $p ('start', 'end') {
		if ($in{'d'.$p}) {
			local ($s, $m, $h) = $p eq 'start' ? (0, 0, 0) :
						(59, 59, 23);
			local $tm = timelocal($s, $m, $h, $in{'d'.$p},
                                        $in{'m'.$p}-1, $in{'y'.$p}-1900);
			$tm || &error($text{'alias_e'.$p});
			$simple->{'autoreply_'.$p} = $tm;
			}
		else {
			delete($simple->{'autoreply_'.$p});
			}
		}

	# Save autoreply from address
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

# get_autoreply_file_dir()
# Returns the directory for autoreply file links
sub get_autoreply_file_dir
{
local $autoreply_file_dir = "/var/virtualmin-autoreply";
&require_useradmin();
local @hst = stat($home_base);
local @vst = stat("/var");
if ($hst[0] != $vst[0]) {
	# /var and /home are on different FS
	$autoreply_file_dir = "$home_base/virtualmin-autoreply";
	}
if (!-d $autoreply_file_dir) {
	&make_dir($autoreply_file_dir, 01777);
	&set_ownership_permissions(undef, undef, 01777, $autoreply_file_dir);
	}
return $autoreply_file_dir;
}

# convert_autoreply_file(&domain, file)
# Returns a file in the autoreply directory, for hard linking to
sub convert_autoreply_file
{
local ($d, $file) = @_;
local $dir = &get_autoreply_file_dir();
return undef if (!$dir);
local $origdir;
if ($file =~ /\/(autoreply-([^\/]+)\.txt)$/) {
	# Autoreply file in directory
	$linkpath = "$dir/$d->{'id'}-$1";
	$origdir = $file;
	$origdir =~ s/\/[^\/]+$//;
	}
elsif ($file !~ /\//) {
	# A relative path
	$linkpath = "$dir/$d->{'id'}-$file";
        $origdir = $dir;
	}
else {
	# An absolute path of some other type
	$origdir = $file;
	$origdir =~ s/\/[^\/]+$//;
	$file =~ s/\//_/g;
	$linkpath = "$dir/$d->{'id'}-$file";
	}
local @fst = stat($origdir);
local @lst = stat($dir);
if ($fst[0] == $lst[0]) {
	return $linkpath;
	}
else {
	# Still not on same filesystem, perhaps due to user's home being
	# a different mount. Don't link.
	return undef;
	}
}

# create_autoreply_alias_links(&domain)
# For all aliases and users in some domain that have simple aliases with
# autoreponders, create hard links and update the aliases to use them.
sub create_autoreply_alias_links
{
local ($d) = @_;
local $adir = &get_autoreply_file_dir();

# Fix up aliases
foreach my $virt (&list_domain_aliases($d)) {
	local $simple = &get_simple_alias($d, $virt);
	if ($simple && $simple->{'auto'}) {
		local $link = &convert_autoreply_file(
			$d, $simple->{'autoreply'});
		if ($link) {
			local @st = stat($link);
			if (!@st || $st[3] == 1) {
				# Need to create the link, and re-write alias
				local $oldvirt = { %$virt };
				unlink($link);
				link($simple->{'autoreply'}, $link);
				&save_simple_alias($d, $virt, $simple);
				&modify_virtuser($oldvirt, $virt);
				}
			if ($simple->{'replies'} &&
			    !&is_under_directory($adir, $simple->{'replies'})) {
				# Fix up reply tracking file
				$simple->{'replies'} = &convert_autoreply_file(
					$d, "replies-$virt->{'from'}");
				&write_simple_autoreply($d, $simple);
				}
			}
		}
	}

# Fix up users
foreach my $user (&list_domain_users($d)) {
	local $simple = &get_simple_alias($d, $user);
	if ($simple && $simple->{'auto'}) {
		local $link = &convert_autoreply_file(
			$d, $simple->{'autoreply'});
		if ($link) {
			local @st = stat($link);
			if (!@st || $st[3] == 1) {
				# Need to create the link, and re-write alias
				local $olduser = { %$user };
				unlink($link);
				link($simple->{'autoreply'}, $link);
				&save_simple_alias($d, $user, $simple);
				&modify_user($user, $olduser, $d, 0);
				}
			if ($simple->{'replies'} &&
			    !&is_under_directory($adir, $simple->{'replies'})) {
				# Fix up reply tracking file
				$simple->{'replies'} = &convert_autoreply_file(
					$d, "replies-$user->{'user'}");
				&write_simple_autoreply($d, $simple);
				}
			}
		}
	}
}

# break_autoreply_alias_links(&domain)
# Delete all autoreply hard links for a domain. This is needed in preparation
# for copying with tar, which tries to preserve hard links which isn't what
# we want.
sub break_autoreply_alias_links        
{                               
local ($d) = @_;                
local $adir = &get_autoreply_file_dir();
foreach my $virt (&list_domain_aliases($d), &list_domain_users($d)) {
	local $simple = &get_simple_alias($d, $virt);
	if ($simple && $simple->{'auto'}) {
		local $link = &convert_autoreply_file(
			$d, $simple->{'autoreply'});
		if ($link && -r $link && $link ne $simple->{'autoreply'}) {
			&unlink_file($link);
			}
		}
	}
}

1;

