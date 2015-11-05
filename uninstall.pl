# uninstall.pl
# Called when this module is un-installed to delete all cron jobs, init
# scripts and daemons

require 'virtual-server-lib.pl';

sub module_uninstall
{
foreach my $cmd (@all_cron_commands) {
	&delete_cron_script($cmd);
	}

# Turn off lookup-domain action
&foreign_require("init");
&foreign_require("proc");
if (&check_pid_file($pidfile)) {
	&init::stop_action("lookup-domain");
	}
&init::disable_at_boot("lookup-domain");

# Delete API helper
local $api_helper_command = &get_api_helper_command();
if (-r $api_helper_command && !-d $api_helper_command) {
	&unlink_file($api_helper_command);
	}
}

1;

