# Functions for the post-install wizard

# If the wizard should be invoked, returns a URL for it. For calling by themes
sub wizard_redirect
{
if (&master_admin() &&
    ($config{'wizard_run'} eq '' && $config{'first_version'} >= 3.69 ||
     $config{'wizard_run'} eq '0')) {
	return "/$module_name/wizard.cgi";
	}
return undef;
}

sub get_wizard_steps
{
return ( "intro",
	 $config{'virus'} ? ( "virus" ) : ( ),
	 "db",
	 $config{'mysql'} ? ( "mysql" ) : ( ) );
}

sub wizard_show_intro
{
print &ui_table_row(undef,
	$text{'wizard_intro'}, 2);
}

# Show a form asking the user if he wants to run clamd
sub wizard_show_virus
{
print &ui_table_row(undef, $text{'wizard_virus'}, 2);
local $cs = &check_clamd_status();
if ($cs != -1) {
	print &ui_table_row($text{'wizard_clamd'},
		&ui_radio("clamd", $cs ? 1 : 0,
			  [ [ 1, $text{'wizard_clamd1'}."<br>" ],
			    [ 0, $text{'wizard_clamd0'} ] ]));
	}
else {
	print &ui_table_row($text{'wizard_clamdnone'});
	}
}

# Parse the clamd form, and enable or disable clamd
sub wizard_parse_virus
{
local ($in) = @_;
if (defined($in->{'clamd'})) {
	local $cs = &check_clamd_status();
	if ($in->{'clamd'} && !$cs) {
		# Enable if needed
		&push_all_print();
		&set_all_null_print();
		local $ok = &enable_clamd();
		&pop_all_print();
		if ($ok) {
			# Switch to clamdscan, after testing
			local $last_err;
			for(my $try=0; $try<10; $try++) {
				$last_err = &test_virus_scanner("clamdscan");
				last if (!$last_err);
				sleep($try);
				}
			return &text('wizard_eclamdtest', $last_err)
				if ($last_err);
			&save_global_virus_scanner("clamdscan");
			}
		else {
			return $text{'wizard_eclamdenable'};
			}
		}
	elsif (!$in->{'clamd'} && $cs) {
		# Disable if needed
		&push_all_print();
		&set_all_null_print();
		&disable_clamd();
		&pop_all_print();
		&save_global_virus_scanner("clamscan");
		}
	}
return undef;
}

# Ask the user if he wants to run MySQL and/or PostgreSQL
sub wizard_show_db
{
print &ui_table_row(undef, $text{'wizard_db'}, 2);
print &ui_table_row($text{'wizard_db_mysql'},
	&ui_radio("mysql", $config{'mysql'} ? 1 : 0,
		  [ [ 1, $text{'wizard_db_mysql1'}."<br>" ],
		    [ 0, $text{'wizard_db_mysql0'} ] ]));
print &ui_table_row($text{'wizard_db_postgres'},
	&ui_radio("postgres", $config{'postgres'} ? 1 : 0,
		  [ [ 1, $text{'wizard_db_postgres1'}."<br>" ],
		    [ 0, $text{'wizard_db_postgres0'} ] ]));
}

# Enable or disable MySQL and PostgreSQL, depending on user's selections
sub wizard_parse_mysql
{
# XXX shutdown mysql and not start at boot
# XXX check if actually installed!
}

1;

