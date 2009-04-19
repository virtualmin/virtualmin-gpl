# Functions for the post-install wizard

# If the wizard should be invoked, returns a URL for it. For calling by themes
sub wizard_redirect
{
if (!$config{'wizard_run'} && $config{'first_version'} >= 3.69) {
	return "/$module_name/wizard.cgi";
	}
return undef;
}

sub get_wizard_steps
{
return ( "intro",
	 $config{'virus'} ? ( "virus" ) : ( ),
	 $config{'spam'} ? ( "spam" ): ( ),
	 $config{'mysql'} ? ( "mysql" ) : ( ) );
}

sub wizard_show_intro
{
print &ui_table_row(undef,
	$text{'wizard_intro'}, 2);
}

sub wizard_show_virus
{
print &ui_table_row(undef,
	$text{'wizard_virus'}, 2);
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

sub wizard_parse_virus
{
local ($in) = @_;
if (defined($in->{'clamd'})) {
	local $cs = &check_clamd_status();
	if ($in->{'clamd'} && !$cs) {
		# Enable if needed
		# XXX
		}
	elsif (!$in->{'clamd'} && $cs) {
		# Disable if needed
		# XXX
		}
	}
}

1;

