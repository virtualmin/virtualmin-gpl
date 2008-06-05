# uninstall.pl
# Called when this module is un-installed to delete the backup cron job

require 'virtual-server-lib.pl';

sub module_uninstall
{
&foreign_require("cron", "cron-lib.pl");
local @jobs = &cron::list_cron_jobs();
foreach my $cmd (@all_cron_commands) {
	local $job = &find_virtualmin_cron_job($cmd, \@jobs);
	if ($job) {
		&cron::delete_cron_job($job);
		}
	}

# Turn off lookup-domain action
&foreign_require("init", "init-lib.pl");
&foreign_require("proc", "proc-lib.pl");
if (&check_pid_file($pidfile)) {
	&init::stop_action("lookup-domain");
	}
&init::disable_at_boot("lookup-domain");
}

1;

