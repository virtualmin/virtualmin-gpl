# Functions for turning Virus filtering on or off on a per-domain basis

sub check_depends_virus
{
return !$_[0]->{'spam'} ? $text{'setup_edepvirus'} : undef;
}

sub init_virus
{
$clam_wrapper_cmd = "$module_config_directory/clam-wrapper.pl";
}

# setup_virus(&domain)
# Adds an entry to the procmail file for this domain to call clamscan too
sub setup_virus
{
&$first_print($text{'setup_virus'});
&require_spam();

local $spamrc = "$procmail_spam_dir/$_[0]->{'id'}";
&lock_file($spamrc);

# Find the clamscan recipe
local @recipes = &procmail::parse_procmail_file($spamrc);
local @clamrec = &find_clam_recipe(\@recipes);
if (@clamrec) {
	# Already there?
	&$second_print($text{'setup_virusalready'});
	}
else {
	# Copy the wrapper program
	&copy_source_dest("$module_root_directory/clam-wrapper.pl", $clam_wrapper_cmd);
	&set_ownership_permissions(undef, undef, 0755, $clam_wrapper_cmd);

	# Add the recipe
	local $recipe0 = { 'flags' => [ 'c', 'w' ],
			   'type' => '|',
			   'action' => $clam_wrapper_cmd." ".
				       &full_clamscan_path() };
	local $varon = { 'name' => 'VIRUSMODE', 'value' => 1 };
	local $recipe1 = { 'flags' => [ 'e' ],
			   'action' => $config{'clam_delivery'} };
	local $varoff = { 'name' => 'VIRUSMODE', 'value' => 0 };
	if (@recipes > 1) {
		&procmail::create_recipe_before($recipe0, $recipes[1], $spamrc);
		&procmail::create_recipe_before($varon, $recipes[1], $spamrc);
		&procmail::create_recipe_before($recipe1, $recipes[1], $spamrc);
		&procmail::create_recipe_before($varoff, $recipes[1], $spamrc);
		}
	else {
		&procmail::create_recipe($recipe0, $spamrc);
		&procmail::create_recipe($varon, $spamrc);
		&procmail::create_recipe($recipe1, $spamrc);
		&procmail::create_recipe($varoff, $spamrc);
		}
	&unlock_file($spamrc);
	&$second_print($text{'setup_done'});
	}
}

# modify_virus(&domain, &olddomain)
# Doesn't have to do anything
sub modify_virus
{
}

# delete_virus(&domain)
# Just remove the procmail entry that calls clamscan
sub delete_virus
{
&$first_print($text{'delete_virus'});
&require_spam();
local $spamrc = "$procmail_spam_dir/$_[0]->{'id'}";
&lock_file($spamrc);
local @recipes = &procmail::parse_procmail_file($spamrc);
local @clamrec = &find_clam_recipe(\@recipes);
if (@clamrec) {
	&procmail::delete_recipe($clamrec[1]);
	&procmail::delete_recipe($clamrec[0]);
	&$second_print($text{'setup_done'});
	}
else {
	&$second_print($text{'delete_virusnone'});
	}
&unlock_file($spamrc);
}

# validate_virus(&domain)
# Make sure the domain's procmail config file calls ClamAV
sub validate_virus
{
local ($d) = @_;
&require_spam();
local $spamrc = "$procmail_spam_dir/$d->{'id'}";
return &text('validate_espamprocmail', "<tt>$spamrc</tt>") if (!-r $spamrc);
local @recipes = &procmail::parse_procmail_file($spamrc);
local @clamrec = &find_clam_recipe(\@recipes);
return &text('validate_evirus', "<tt>$spamrc</tt>") if (!@clamrec);
return undef;
}

# check_virus_clash()
# No need to check for clashes ..
sub check_virus_clash
{
return 0;
}

# find_clam_recipe(&recipes)
# Returns the two recipes used for virus filtering
sub find_clam_recipe
{
local $i;
for($i=0; $i<@{$_[0]}; $i++) {
	if ($_[0]->[$i]->{'action'} =~ /clam(d?)scan/ ||
	    $_[0]->[$i]->{'action'} =~ /\Q$clam_wrapper_cmd\E/) {
		# Found clamscan .. but is the next one OK?
		if ($_[0]->[$i+1]->{'flags'}->[0] eq 'e') {
			return ( $_[0]->[$i], $_[0]->[$i+1] );
			}
		}
	}
return ( );
}

# sysinfo_virus()
# Returns the ClamAV version
sub sysinfo_virus
{
local $out = &backquote_command("$config{'clamscan_cmd'} -V", 1);
local $vers = $out =~ /ClamAV\s+([0-9\.]+)/i ? $1 : "Unknown";
return ( [ $text{'sysinfo_virus'}, $vers ] );
}

# Update the procmail scripts for all domains that call clamscan so that they
# call the wrapper instead
sub fix_clam_wrapper
{
&require_spam();
&copy_source_dest("$module_root_directory/clam-wrapper.pl", $clam_wrapper_cmd);
foreach my $d (grep { $_->{'virus'} } &list_domains()) {
	local $spamrc = "$procmail_spam_dir/$d->{'id'}";
	local @recipes = &procmail::parse_procmail_file($spamrc);
	local @clamrec = &find_clam_recipe(\@recipes);
	if ($clamrec[0]->{'action'} !~ /\Q$clam_wrapper_cmd\E/ &&
	    $clamrec[0]->{'action'} =~ /^(\S*clam(d?)scan)\s+\-$/) {
		$clamrec[0]->{'action'} = "$clam_wrapper_cmd $1";
		&procmail::modify_recipe($clamrec[0]);
		}
	}
}

# get_domain_virus_delivery(&domain)
# Returns the delivery mode and dest for some domain. The modes can be :
# 0 - Throw away , 1 - File under home , 2 - Forward to email , 3 - Other file,
# 4 - Normal ~/mail/virus file, 5 - Deliver normally , 6 - ~/Maildir/.virus/ ,
# -1 - Broken!
sub get_domain_virus_delivery
{
local ($d) = @_;
&require_spam();
local $spamrc = "$procmail_spam_dir/$d->{'id'}";
local @recipes = &procmail::parse_procmail_file($spamrc);
local @clamrec = &find_clam_recipe(\@recipes);
if (!@clamrec) {
	return (-1);
	}
elsif (!$clamrec[1]) {
	return (5);
	}
elsif ($clamrec[1]->{'action'} eq '/dev/null') {
	return (0);
	}
elsif ($clamrec[1]->{'action'} =~ /^\$HOME\/mail\/virus$/) {
	return (4);
	}
elsif ($clamrec[1]->{'action'} =~ /^\$HOME\/Maildir\/.virus\/$/) {
	return (6);
	}
elsif ($clamrec[1]->{'action'} =~ /^\$HOME\/(.*)$/) {
	return (1, $1);
	}
elsif ($clamrec[1]->{'action'} =~ /\@/) {
	return (2, $clamrec[1]->{'action'});
	}
else {
	return (3, $clamrec[1]->{'action'});
	}
}

# save_domain_virus_delivery(&domain, mode, dest)
# Updates the delivery method for viruses for some domain
sub save_domain_virus_delivery
{
local ($d, $mode, $dest) = @_;
&require_spam();
local $spamrc = "$procmail_spam_dir/$d->{'id'}";
local @recipes = &procmail::parse_procmail_file($spamrc);
local @clamrec = &find_clam_recipe(\@recipes);
return 0 if (!@clamrec);
&lock_file($spamrc);
local $r = $clamrec[1];
$r->{'action'} = $mode == 0 ? "/dev/null" :
		 $mode == 4 ? "\$HOME/mail/virus" :
		 $mode == 6 ? "\$HOME/Maildir/.virus/" :
		 $mode == 1 ? "\$HOME/$dest" :
			      $dest;
$r->{'type'} = $mode == 2 ? "!" : "";
&procmail::modify_recipe($r);
&unlock_file($spamrc);
return 1;
}

# full_clamscan_path()
# Returns the clamav scan command, using the full path plus any args
sub full_clamscan_path
{
local ($cmd, @args) = &split_quoted_string($config{'clamscan_cmd'});
local $fullcmd = &has_command($cmd);
return undef if (!$fullcmd);
local @rv = ( $fullcmd, @args );
return join(" ", map { /\s/ ? "\"$_\"" : $_ } @rv);
}

$done_feature_script{'virus'} = 1;

1;

