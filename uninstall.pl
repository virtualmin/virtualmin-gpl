# uninstall.pl
# Called when this module is un-installed to delete the backup cron job

require 'virtual-server-lib.pl';

sub module_uninstall
{
&foreign_require("cron", "cron-lib.pl");
local @jobs = &cron::list_cron_jobs();
foreach my $cmd (@all_cron_commands) {
	local ($job) = grep { $_->{'user'} eq 'root' &&
			      $_->{'command'} eq $cmd } @jobs;
	if ($job) {
		&cron::delete_cron_job($job);
		}
	}
}

1;

