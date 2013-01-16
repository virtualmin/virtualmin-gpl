# Functions for webmincron and classic cron jobs

# run_cron_script(path, [args])
# Given a script like spamclear.pl that would normally be run by
# cron via a wrapper, run it within the same process
sub run_cron_script
{
local ($script, $args) = @_;
local @args = split(/\s+/, $args);
local $fh = "CRONOUT";
local $temp = &transname();
open($fh, ">$temp");
my $pid = &execute_webmin_script("$module_root_directory/$script", $module_name,
			         \@args, $fh);
close($fh);
waitpid($pid, 0);
my $ex = $?;
print &read_file_contents($temp);
&unlink_file($temp);
}

# setup_cron_script(&cron-spec)
# Creates a Webmin Cron entry for some cron job, converting any
# existing matching regular Cron job if it exists. If the Webmin Cron
# entry already exists for the command, do nothing
sub setup_cron_script
{
local ($job) = @_;
&foreign_require("cron");
&foreign_require("webmincron");
local $cronjob = &find_virtualmin_cron_job($job->{'command'});
if ($job->{'command'} =~ /\Q$module_config_directory\E\/([^ \|\&><;]+)/) {
	# Run from this module
	local $script = $1;
	&cron::create_wrapper($job->{'command'}, $module_name,
			      $script);

	# Find existing classic cron job, and remove it
	if ($cronjob) {
		# Delete for conversion to Webmin Cron
		&lock_file(&cron::cron_file($cronjob));
		&cron::delete_cron_job($cronjob);
		&unlock_file(&cron::cron_file($cronjob));
		}

	# Check if a WebminCron job exists already
	my $args;
	if ($job->{'command'} =~ /\Q$script\E\s+([^\|\&><;]+)/) {
		# Has command-line args 
		$args = $1;
		}
	local @wcrons = &webmincron::list_webmin_crons();
	local ($wjob) = grep { $_->{'func'} eq "run_cron_script" &&
			       $_->{'args'}->[0] eq $script &&
			       $_->{'args'}->[1] eq $args } @wcrons;

	# Clear fields that are only used by classic cron
	delete($job->{'command'});
	delete($job->{'file'});

	if (!$wjob) {
		# Need to create
		$job->{'func'} = "run_cron_script";
		$job->{'module'} = $module_name;
		$job->{'args'} = [ $script ];
		push(@{$job->{'args'}}, $args) if ($args);
		&webmincron::save_webmin_cron($job);
		}
	else {
		# Bring times into sync
		&copy_cron_sched_keys($job, $wjob);
		&webmincron::save_webmin_cron($wjob);
		}
	}
else {
	# Some other random job .. just use normal cron
	if (!$cronjob) {
		if ($job->{'command'} =~
		    /\Q$config_directory\E\/([^\/]+)\/([^ \|\&><;]+)/) {
			local ($m, $s) = ($1, $2);
			&cron::create_wrapper($job->{'command'}, $m, $s);
			}
		&lock_file(&cron::cron_file($job));
		&cron::create_cron_job($job);
		&unlock_file(&cron::cron_file($job));
		}
	}
}

# delete_cron_script(script|&job)
# Deletes the classic or WebminCron job that runs some script
sub delete_cron_script
{
local ($script_or_job) = @_;
if (ref($script_or_job)) {
	# Delete a specific classic or webmincron job
	local $job = $script_or_job;
	if ($job->{'module'}) {
		&foreign_require("webmincron");
		&webmincron::delete_webmin_cron($job);
		}
	else {
		&foreign_require("cron");
		&lock_file(&cron::cron_file($job));
		&cron::delete_cron_job($job);
		&unlock_file(&cron::cron_file($job));
		}
	}
else {
	# Delete all matching the script
	local $script = $script_or_job;
	local $shortscript = $script;
	$shortscript =~ s/^.*\///;

	# Classic cron
	&foreign_require("cron");
	local @jobs = &cron::list_cron_jobs();
	foreach my $job (&find_virtualmin_cron_job($script, \@jobs)) {
		&lock_file(&cron::cron_file($job));
		&cron::delete_cron_job($job);
		&unlock_file(&cron::cron_file($job));
		}

	# Webmin cron
	&foreign_require("webmincron");
	local @wcrons = &webmincron::list_webmin_crons();
	foreach my $wjob (grep { $_->{'func'} eq "run_cron_script" &&
				 $_->{'args'}->[0] eq $shortscript } @wcrons) {
		&webmincron::delete_webmin_cron($wjob);
		}
	}
}

# convert_cron_script(script)
# If a classic cron job exists that runs some script, convert to webmin cron
sub convert_cron_script
{
local ($script) = @_;
local $shortscript = $script;
$shortscript =~ s/^.*\///;

&foreign_require("cron");
&foreign_require("webmincron");
local @jobs = &cron::list_cron_jobs();
local @wcrons = &webmincron::list_webmin_crons();
foreach my $job (&find_virtualmin_cron_job($script, \@jobs)) {
	&lock_file(&cron::cron_file($job));
	&cron::delete_cron_job($job);
	&unlock_file(&cron::cron_file($job));

	my $args;
	if ($job->{'command'} =~ /\Q$script\E\s+([^ \|\&><;]+)/) {
		# Has command-line args 
		$args = $1;
		}
	local ($wjob) = grep { $_->{'func'} eq "run_cron_script" &&
			       $_->{'args'}->[0] eq $shortscript &&
			       $_->{'args'}->[1] eq $args } @wcrons;
	if (!$wjob) {
		$job->{'func'} = "run_cron_script";
		$job->{'module'} = $module_name;
		$job->{'args'} = [ $shortscript ];
		push(@{$job->{'args'}}, $args) if ($args);
		delete($job->{'command'});
		delete($job->{'file'});
		&webmincron::save_webmin_cron($job);
		}
	}
}

# find_cron_script(script)
# Finds the classic or Webmin cron job that runs some script
sub find_cron_script
{
local ($fullscript) = @_;
local ($script, @wantargs) = split(/\s+/, $fullscript);
local $shortscript = $script;
$shortscript =~ s/^.*\///;

# Classic cron
local @rv;
push(@rv, &find_virtualmin_cron_job($fullscript));

# Webmin cron
&foreign_require("webmincron");
foreach my $wjob (grep { $_->{'func'} eq "run_cron_script" &&
		         $_->{'args'}->[0] eq $shortscript }
		       &webmincron::list_webmin_crons()) {
	# Check rest of the args
	local @a = @{$wjob->{'args'}};
	shift(@a);
	if (join(" ", @a) ne join(" ", @wantargs)) {
		next;
		}

	# Fake up command
	$wjob->{'command'} = $script;
	if (@a) {
		$wjob->{'command'} .= " ".join(" ", @a);
		}
	push(@rv, $wjob);
	}

return wantarray ? @rv : $rv[0];
}

# copy_cron_sched_keys(&src-job, &dst-job)
# Copy all time-related keys from one cron job to another
sub copy_cron_sched_keys
{
local ($src, $dst) = @_;
foreach my $k ('mins', 'hours', 'days', 'months', 'weekdays',
	       'special', 'interval') {
	$dst->{$k} = $src->{$k};
	}
}

1;
