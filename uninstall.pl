# uninstall.pl
# Called when this module is un-installed to delete the backup cron job

require 'virtual-server-lib.pl';

sub module_uninstall
{
&foreign_require("cron", "cron-lib.pl");
local @jobs = &cron::list_cron_jobs();
local ($job) = grep { $_->{'user'} eq 'root' &&
		      $_->{'command'} eq $backup_cron_cmd } @jobs;
if ($job) {
	&cron::delete_cron_job($job);
	}
}

1;

