
do 'virtual-server-lib.pl';

# backup_config_files()
# Returns files and directories that can be backed up
sub backup_config_files
{
local @rv;

# Add all domain files
foreach my $d (&list_domains()) {
	push(@rv, $d->{'file'});
	}

# Add all bandwidth files
foreach my $d (&list_domains()) {
	push(@rv, "$bandwidth_dir/$d->{'id'}")
		if (-r "$bandwidth_dir/$d->{'id'}");
	}

# Add all templates
foreach my $t (&list_templates()) {
	if ($t->{'id'} > 0) {
		push(@rv, "$templates_dir/$t->{'id'}");
		}
	}

# Add records of installed scripts
foreach my $d (&list_domains()) {
	push(@rv, "$script_log_directory/$d->{'id'}")
		if (-r "$script_log_directory/$d->{'id'}");
	}

# Add mail templates
foreach my $tf (@all_template_files) {
	push(@rv, "$module_config_directory/$tf");
	}

# Add other files
push(@rv, $custom_fields_file);
push(@rv, $scripts_unavail_file);

# Add spam and procmail config files
foreach my $d (&list_domains()) {
	push(@rv, "$procmail_spam_dir/$d->{'id'}")
		if (-r "$procmail_spam_dir/$d->{'id'}");
	push(@rv, "$spam_config_dir/$d->{'id'}")
		if (-r "$spam_config_dir/$d->{'id'}");
	}

# Add initial users
foreach my $d (&list_domains()) {
	push(@rv, "$initial_users_dir/$d->{'id'}")
		if (-r "$initial_users_dir/$d->{'id'}");
	}

return @rv;
}

# pre_backup(&files)
# Called before the files are actually read
sub pre_backup
{
return undef;
}

# post_backup(&files)
# Called after the files are actually read
sub post_backup
{
return undef;
}

# pre_restore(&files)
# Called before the files are restored from a backup
sub pre_restore
{
# Delete other domains
foreach my $d (&list_domains()) {
	&delete_domain($d);
	}

return undef;
}

# post_restore(&files)
# Called after the files are restored from a backup
sub post_restore
{
return undef;
}

1;

