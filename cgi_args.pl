
do 'virtual-server-lib.pl';

sub cgi_args
{
my ($cgi) = @_;

# Global options, which need no params (if usable)
if ($cgi =~ /^edit_new/ || $cgi eq 'check.cgi') {
	# Global config of some kind
	return &can_edit_templates() ? '' : 'none';
	}
elsif ($cgi eq 'history.cgi') {
	return &can_show_history() ? '' : 'none';
	}
elsif ($cgi eq 'mass_create_form.cgi') {
	return (&can_create_master_servers() || &can_create_sub_servers()) &&
		&can_create_batch() ? '' : 'none';
	}
elsif ($cgi eq 'import_form.cgi') {
	return &can_import_servers() ? '' : 'none';
	}
elsif ($cgi eq 'migrate_form.cgi') {
	return &can_migrate_servers() ? '' : 'none';
	}
elsif ($cgi eq 'list_sched.cgi') {
	return &can_backup_sched() && &can_backup_domain() ? '' : 'none';
	}
elsif ($cgi eq 'backup_form.cgi') {
	return &can_backup_domain() ? '' : 'none';
	}
elsif ($cgi eq 'backuplog.cgi') {
	return &can_backup_log() ? '' : 'none';
	}
elsif ($cgi eq 'restore_form.cgi') {
	return &can_restore_domain() ? '' : 'none';
	}

# Other global settings
if ($cgi eq 'edit_tmpl.cgi') {
	return &can_edit_templates() ? 'id=0' : 'none';
	}
elsif ($cgi eq 'edit_plan.cgi') {
	my @plans = &list_editable_plans();
	return !&can_edit_plans() ? 'none' :
	       @plans ? 'id='.$plans[0]->{'id'} : 'new=1';
	}
elsif ($cgi eq 'edit_resel.cgi') {
	my @resels = &list_resellers();
	return !&can_edit_templates() ? 'none' :
	       @resels ? 'name='.&urlize($resels[0]->{'name'}) : 'new=1';
	}

# Assume a domain is needed, for some editing page
return undef if ($cgi =~ /^(save|delete|modify|mass)_/);
my @alldoms = grep { &can_edit_domain($_) } &list_domains();
my $d;
if ($in{'dom'}) {
	# From CGI parameter
	$d = &get_domain($in{'dom'});
	}
if (!$d) {
	# First top-level
	($d) = grep { !$_->{'parent'} } @alldoms;
	}
if (!$d) {
	# First of any kind
	$d = $alldoms[0];
	}
if ($d) {
	if ($cgi eq 'edit_user.cgi') {
		# Create user
		return 'dom='.$d->{'id'}.'&new=1';
		}
	elsif ($cgi eq 'edit_alias.cgi') {
		# Create alias
		return 'dom='.$d->{'id'}.'&new=1';
		}
	else {
		# Assume some other CGI that takes a domain parameter
		return 'dom='.$d->{'id'};
		}
	}

return undef;
}
