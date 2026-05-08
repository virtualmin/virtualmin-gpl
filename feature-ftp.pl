# Legacy loader for the retired ProFTPd virtual FTP feature.
#
# The actual Virtualmin feature was removed, but this file remains so any
# external code that still loads feature-ftp.pl gets the non-virtual ProFTPd
# helpers and the backup/restore compatibility shims.

do "$module_root_directory/proftpd-lib.pl" if (!defined(&has_proftpd_support));

$done_feature_script{'ftp'} = 1;

1;
