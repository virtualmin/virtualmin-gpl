# Functions for the post-install wizard

@wizard_steps = ( "intro", "virus", "spam", "mysql" );

# If the wizard should be invoked, returns a URL for it. For calling by themes
sub wizard_redirect
{
if (!$config{'wizard_run'} && $config{'first_version'} >= 3.69) {
	return "/$module_name/wizard.cgi";
	}
return undef;
}

1;

