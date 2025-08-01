#### Version 7.40.0
* Replaced IDNA::Punycode with the actively maintained Net::LibIDN2 for full IDNA2008 support
* Fix jailkit support for sub-servers [#1082](https://github.com/virtualmin/virtualmin-gpl/issues/1082)

#### Version 7.30.8
* Add an ad for WP Workbench to the dashboard
* Fix Backblaze backups to work with new API

#### Version 7.30.7
* Add missing string for WP Workbench

#### Version 7.30.6
* Fix to improve file saving operations for greater reliability
* Fix to optimize PHP session cleanup for directories with large numbers of files
* Add the `virtual-server` package provide `virtualmin`

#### Version 7.30.5
* Fix to exclude the default domain from license count
* Add AWS-CLI and WP Workbench as recommended packages

#### Version 7.30.4
* Fix conditional logic for license re-check

#### Version 7.30.3
* Fix missing button text when restarting a script’s service (Node.js, etc.)
* Fix advertised installable web apps always show the version as “latest”
* Fix system ID check to address incorrect license identification
* Fix to ensure files inside backups have the correct extensions
* Fix to clean up the code that adjusts FPM versions during the config check
* Fix to remove Webalizer as an option unless it is already installed
* Fix file locking to prevent disruption of configuration files in rare cases
* Add a new ClassicPress web app installer 

#### Version 7.30.2
* Fix to ensure the mail log is not read when the mail feature is disabled globally

#### Version 7.30.1
* Fix the bug to properly check for disabling in-use features and prevent breaking the system

#### Version 7.30.0
* Add support for multiple ACME-compatible SSL providers in the Pro version, like ZeroSSL, Sectigo and many other
* Add comprehensive page for license management in Virtualmin Pro
* Add numerous improvements to the DirectAdmin migration process
* Add a new `--json` flag to the Virtualmin CLI command to enable output in JSON format
* Add ability to bring supported web apps under Virtualmin control during migration
* Add an option in the wizard to configure the system default email address
* Add an option to enable or disable SSL certificate renewal email notifications
* Add status monitors for Usermin and Postgrey to the dashboard
* Add template option to create an alias domain with its own DNS zone
* Add ability for CAA DNS records to be manually edited and created
* Add ability to edit RUA and RUF DMARC DNS fields
* Fix numerous DNS-related bugs
* Fix support for `zstd` compression in backups
* Fix an issue with MySQL user creation in certain edge cases
* Fix config file to set the correct port/socket for Postgrey in EL derivatives

#### Version 7.20.2
* Fix external DNS filter to consider CNAME and IPv6 records
* Fix not to trigger DNS filter for existing Let’s Encrypt renewals
* Fix false positive message to move SSL certificate to default location
* Fix old documentation links

#### Version 7.20.1
* Add support for changing username format to match the local system when restoring a backup
* Fix a bug that can corrupt the Dovecot config when creation of the default domain fails
* Fix a bug that can cause CGI scripts to be disabled by default

#### Version 7.20.0
* Add support to record most recent user logins for virtual servers
* Add ability to disable domains on given schedule
* Add support for proxying WebSocket with Apache and Nginx proxy paths
* Add an API to manage scheduled backups
* Add the ability to enable DKIM even if the mail feature is disabled
* Add ability to check the resolvability of alternative names before issuing a Let's Encrypt certificate
* Add an API to move SSL certificates to a new location if it differs from the active template
* Add an option to the Website Options page to redirect www to non-www and vice versa (currently for Apache systems only)
* Add support for host-based redirects (currently for Apache systems only)
* Fix to change the default settings so that records are not proxied by default when using Cloudflare
* Fix a bug where CGI execution mode was disabled on initial install
* Fix PHP modes availability depending on the CGI execution mode
* Fix a bug with default shell selection when a user is created using the CLI
* Fix the issue where the last login time is not being updated
* Fix false-positive warnings about missing IPv6 addresses
* Fix domain locking bugs
* Drop support for obsolete or not fully supported mail servers like VPopMail, and Exim

#### Version 7.10.0
* Add S3 account management integration
* Add reworked **Edit Users** page with ability to add separate database and webserver users
* Add support for adding and updating SSH public key for virtual server users
* Add support for selecting CGI mode for virtual server using Website Options page and CLI
* Add Google Drive sub-folder support for backups and purging
* Add support for purging Backblaze date-based buckets
* Add support for name-based virtual FTP servers
* Add charset and collation retention for MySQL/MariaDB databases restored from backups
* Add support for restoring backups from relative paths using Virtualmin CLI
* Add option to clear spam and trash mail sub-folders
* Add sanity check for the DNS master IP address
* Add link from DNS Records page to reset DNS records
* Fix bugs in syncing of DNS TTL records
* Fix to re-parent DNS records upon owner change
* Fix to correctly split long DNS TXT records
* Fix to include webmail DNS records for Nginx configurations too
* Fix to further improve auto-discover config feature work correctly in Microsoft Outlook
* Fix to test if generated password matches the pattern required for installed scripts
* Fix to switch to System Logs Viewer module for viewing logs
* Fix wizard to handle MySQL/MariaDB socket authentication
* Fix to allow Let's Encrypt certificates be requested even without a website
* Updated terminology now refers to incremental backups as differential backups

#### Version 7.9.0
* Add reworked navigation menu for better usability and accessibility
* Add support for different PHP-FPM process manager modes (_dynamic_, _static_, _ondemand_)
* Add Google Drive support as cloud storage provider for Virtualmin Pro users
* Add enhanced Jailkit domain features for Virtualmin Pro user, including abilities to copy extra commands and sections, and to reset previously configured jail environment
* Add ability to preserve `php_value`, `php_admin_value`, `env` and `pm.` settings when changing PHP-FPM version
* Add Cloudflare API token support for more secure and precise authentication, replacing the need for using global API keys
* Add API for restarting system or virtual server services using `virtualmin restart-server` command
* Add support for showing dynamic placeholder for path/file field in **Backup and Restore ⇾ Scheduled Backups** page [#647/issuecomment-1732368172](https://github.com/virtualmin/virtualmin-gpl/issues/647#issuecomment-1732368172)
* Add ability to use the database character set when performing back up and restore
* Add improvements to validate domain output page
* Add various improvements for migrations from cPanel and Plesk
* Add template substitutions to support variables for the MySQL/MariaDB host and port [#666](https://github.com/virtualmin/virtualmin-gpl/issues/666)
* Add ability to show domain type when listing domains in UI [#676](https://github.com/virtualmin/virtualmin-gpl/pull/676)
* Add support for using Webmin RPC to perform virtual servers transfer to remote systems
* Add an option to re-allocate usernames when restoring backups
* Change SPF to default to `~all` instead of `?all` [#696](https://github.com/virtualmin/virtualmin-gpl/issues/696)
* Extend the GPL version with the capability to edit proxy paths, previously exclusive to Pro users
* Fix Backblaze clearing old backups [#640](https://github.com/virtualmin/virtualmin-gpl/issues/640)
* Fix issues when performing DNS-based Let's Encrypt renewals, including in wildcard mode
* Fix auto-discover config feature work correctly in Microsoft Outlook
* Fix to correctly revoke access to previously allowed MySQL/MariaDB databases
* Fix renewal errors for Let's Encrypt certificates caused by using incorrect certificate types
* Fix caching system external IP address for faster API calls
* Fix issues with base website redirects causing redirect loops in the past
* Fix to improve virtual servers restore experience
* Fix DKIM signature issue on Debian and Ubuntu systems
* Fix auto-reply form not being saved correctly
* Fix to correctly print _years_ in bandwidth usage reports [#689](https://github.com/virtualmin/virtualmin-gpl/issues/689)
* Fix detecting network interface names on Amazon Linux systems
* Fix enforcing correct permissions for PHP-FPM socket file
* Fix to preserve the PHP-FPM socket file when changing versions
* Fix to make sure all PHP-FPM versions are enabled at boot [#644](https://github.com/virtualmin/virtualmin-gpl/issues/644)
* Fix various issues with file locking

#### Version 7.8.2
* Update host and domain default page [#629](https://github.com/virtualmin/virtualmin-gpl/issues/629)
* Add API to setup Virtualmin default hostname SSL
* Add mass password update API in Virtualmin CLI
* Add mass modify users API in Virtualmin CLI
* Add various improvements and fixes to Cloudflare DNS
* Add a flag to show more details when purging backups
* Add support for fetching mail logs from `journalctl` if there are no regular log files available
* Changed password hashing to be enabled by default on all new installs
* Fix to allow domain name check to be skipped in domain creation time
* Fix backups when DNS zone is hosted on Cloudmin services
* Fix various bugs for S3 backups
* Fix syncing of SSL cert to MySQL/MariaDB [#571](https://github.com/virtualmin/virtualmin-gpl/issues/571)
* Fix to break possible linkage to `snakeoil` cert and key
* Fix to show progress when checking `php.ini` files in config check
* Fix to convert SSL private key to `PKCS1` for MySQL/MariaDB
* Fix various issues when cloning virtual servers
* Fix to make extra sure that old FPM pool is deleted
* Fix to ue `127.0.0.1` instead of `localhost` for DKIM milters
* Fix placeholder when toggled for create initial web page option
* Fix to make sure the PHP log file exists for logrotate not fail [#596](https://github.com/virtualmin/virtualmin-gpl/issues/596)
* Fix to make sure that parallel backups don't fail
* Fix to preserve PHP log when changing PHP version
* Fix to re-enable connectivity check by default for all new installs
* Fix to drop creating host default domain in Virtualmin wizard and instead use a new setting in Virtualmin Configuration page, under SSL Settings

#### Version 7.7
* Add cloud credentials to be automatically used if available when backing up to S3 or GCS
* Fix support for enabling and disabling the HTTP2 protocol
* Fix several bugs in the creation of AAAA and MX records
* Fix bugs in the management of secondary mail servers
* Fix to test `can_use_gcloud_storage_creds` as available in Pro only
* Fix backups with sub-servers (sub-domains)
* Fix to show backup URL without passwords

#### Version 7.6
* Add support for DNS zones to be hosted on remote Webmin servers
* Add support for remote databases for PostgreSQL in the same way as MySQL/MariaDB
* Added an option to share the same DNS zone file with different owners
* EC SSL certificates can now be created or uploaded

#### Version 7.5
* Add support for backups to Azure Blob Storage
* Add support for enabling an SSL website automatically 
* Add buttons to start and stop the `saslauthd` server
* Fix the way PHP extensions are enabled when installing scripts
* Fix cPanel migration for parked domains
* Fix for setting the limit on the number of processes in PHP FPM mode


#### Version 7.2
* Added a template option for default website aliases and redirects

#### Version 7.0
* Added flags to the modify-domain API command to re-generate Unix quotas for the domain owner or mailboxes if they are lost due to a filesystem move.
* Apache mod_php is no longer recommended for running PHP, and can be entirely disabled using a button on the System Information page.

#### Version 6.17
* ZIP format backups now use ZIP for archive files inside the backup as well.
* The location of SSL certificate and key files can now be configured at the template level, and a safer default location can be set in the post-install wizard.
* When backing up, you can now choose to download the resulting file in the browser via a link so that the progress of the backup is properly displayed.
* Reseller access to rename domains, manage extra admins, configure proxies, create, delete and edit virtual servers can now be restricted.
* Added support for outgoing SMTP providers like Amazon SES, so that systems with dynamic IPs can reliably send email.
* If using a supported Apache version or Nginx, HTTP2 can be enabled for individual websites or on the server templates page.
* Added a configuration option and flag to create-domain to allow SSL linkage across domain owners.
* Added the reset-feature API command and a tab on the Validate Virtual Servers page to reset the settings for selected features of a virtual server back to their defaults.
* Removed the mostly useless configuration check for 127.0.0.1 in /etc/resolv.conf.
* On systems without suEXEC, fcgiwrap will be used to execute CGI scripts instead for new virtual servers.

#### Version 6.16
* Added a field for entering an SSH private key file for use in backups, instead of a password.
* Massively simplified the SSL Certificate page for services certificates.
* Added the create-login-link API command to login as a domain owner without a password.
* Two-factor authentication for Usermin is setup for domain owners at the same time as Virtualmin.
* If needed, Virtualmin will configure the exact PHP version required to run scripts when installed.
* Added a field to the virtual server creation page to use an existing SSH key for logins, or generate a new key.

#### Version 6.15
* PHP-FPM using socket files instead of TCP ports is now fully supported, using the modify-web API command.

#### Version 6.14
* Added the Cloud DNS Providers page, for configuring Virtualmin to use Route53 to host DNS rather than doing it locally.
* SSL certicates can now be generated and managed for virtual servers even when they don't have the SSL feature enabled.
* Consolidated all PHP options into a single page, and moved website options to it's own page in the UI.

#### Version 6.12
* Improved locking for domain database files to prevent overwriting.
* Fixed bugs caused by removing domain features in the wrong order.
* Fixes for IPv6 addresses in SPF and default DNS records.
* Improved and preserved indentation for Apache configs.
* Massively improved support for MySQL / MariaDB user and password management.
* Better handle PHP FPM package upgrades done after domains are created.
* Improved the template page for website options when Nginx is in use.
* Fixes to creation and update of per-domain Dovecot SSL certs.
* Added a cron job to clean up old PHP session files.
* Added support for backing up to BackBlaze.

#### Version 6.09
* Updated the SSL Certificate page to allow more control over per-domain certs for Webmin, Usermin, Postfix and Dovecot.
* Per-domain SSL certifcates can now be setup in Postfix, if running version 3.4 or later.
* Scheduled backups can have a descriptive comment for recording their purpose, which is also displayed in backup logs.
* The compression format can now be selected on a per-backup basis.
* Added the set-dkim API command to enable and disable DKIM.

#### Version 6.06
* Virtual servers to backup can now be selected by reseller.

#### Version 6.05
* Existing GPG keys owned by the root user can now be imported as backup encrytion keys.
* Added support for MySQL 8 systems that use a different password hashing method.
* Remote backups can now be made using Webmin's RPC protocol, along with SSH. This allows backups to systems that only allow sudo logins.
* If multiple versions of the PHP-FPM packages are installed, a different version can be selected for each domain in Virtualmin.

#### Version 6.04
* The domain name used in links to a server's website can now be customized to use one of it's aliases instead.
* When used with Webmin 1.900 or above, Let's Encrypt SSL certificates can be requested for wildcard domains.
* Scheduled backups create by root can now be designated as allowing restore by virtual server owners, so that they don't have to maintain their own backups.

#### Version 6.03
* Redirects for / created using the UI are automatically adjusted to exclude Let's Encrypt validation paths.
* Dovecot and Postfix per-IP SSL certificate setup can now be configured on a per-template basis.
* Before a DNS zone is updated, BIND will be told to freeze it and thaw afterwards. This ensures that dynamic updates are preserved.
* Removed support for PHP 4.

#### Version 6.02
* Backups from cPanel, Plesk and other control panels can now be migrated even when Nginx is used as a webserver.
* When adding an alias to a domain with a Let's Encrypt SSL certificate, the cert is automatically updated to include the alias domain.

#### Version 6.01
* Any virtual servers can now share a DNS zone file, unlike in previous Virtualmin releases where only a top-level server could be a DNS domain parent. This removes the need to create additional NS records in the parent domain in most cases.
* The Wordpress script installer use wp-cli if available for installation and upgrades.
* PHP scripts run in FPM mode are now compatible with .htaccess files.

#### Version 6.00
* Installable scripts can now be in multiple categories, and the UI has been updated to reflect this.
* Support for rating scripts and viewing existing ratings has been removed, as this was a confusing and rarely-used feature.
* Multiple remote MySQL servers can now be defined, and selected on a per-domain basis at virtual server creation time. This allows some or all domains to easily use different MySQL hosts.

#### Version 5.99
* Added support for using clamdscan for remote virus scanning, so that clamd-stream-client doesn't need to be installed.
* Unexpected server processes running as domain users are now detected and included in the validation report, and can optionally be automatically terminated.
* Removed support for Qmail+LDAP as a mail server.

#### Version 5.07
* SSL certificates that are expired or close to it are displayed on the System Information page.
* SSL certificates can now be copied to Dovecot even for virtual servers that don't have their own private IP address.
* Chroot jails for virtual server domain owners can now be setup at domain creation time or afterwards. This limits the files visible to SSH sessions and PHP apps run via FPM to the jail directory.
* The SSL certificate for all virtual servers will now be configured for use in the Virtualmin UI on port 10000, so that URLs like https://admin.domain.com:10000/ work without cert errors.
* Updates the Node.JS installer to version 7.7.4, DokuWiki to 2017-02-19b, Roundcube to 1.2.4, Mantis to 2.2.0, Moodle to 3.2.2 and 2.7.19, Rainloop to 1.11.0.203, Mantis to 2.2.1 and 1.3.7, Drupal to 8.2.7, phpBB to 3.2, and Wordpress to 4.7.3.

#### Version 5.06
* Updated the FosWiki script installer to version 2.1.3, WHMCS to 6.3.2 and 7.1.1, Node.js to 7.6.0, Magento to 2.1.5, Ghost to 0.11.7, DokuWiki to 2017-02-19a, NextCloud to 11.0.2 and 10.0.4, Piwik to 3.0.2, and Coppermine to 1.5.46.

#### Version 5.05
* Virtualmin will now also generate SSHFP DNS records (for SSH host keys) when it creates TLSA records.
* Added the start-stop-script API command to manage the servers behind Ruby and Node.JS scripts.
* Added a button to the Manage SSL Certifcate page and a flag to the modify-web API command to break shared certificate linkage.
* Resellers and domain owners can be granted the ability to migrate backups from other control panels, like cPanel and Plesk.
* Added support for FPM as a PHP execution mode, on systems that have a system package which runs an FPM pool server.
* Updated the phpMyAdmin script installer to versions 4.6.5.2, 4.4.15.9 and 4.0.10.18, Roundcube to 1.2.3, MediaWiki to 1.28.0, Mantis to 1.3.6 and 2.1.0, Typo3 to 6.2.30, Wordpress to 4.7.2, Drupal to 8.2.6 and 7.54, NextCloud to 10.0.3 and 11.0.1, IONcube to 6.0.9, Joomla to 3.6.5, Node.js to 7.5.0, Piwik to 3.0.1, TikiWiki to 16.2 and 12.11, Dolibarr to 3.9.4, Moodle to 3.2, Magento to 2.1.4, SMF to 2.0.13, Ghost to 0.11.4, phpMyAdmin to 4.0.10.19 and 4.6.6, ZenPhoto to 1.4.14, Revive Adserver to 4.0.1, Instiki to 0.20.1, and ownCloud to 9.1.4.

#### Version 5.04
* Added configuration options to allow domain owners to see overall system statistics, and run validation on their domains.
* When a Let's Encrypt certificate is automatically renewed, the new cert will be copied to servers like Postfix, Dovecot and Webmin that were using the old version.
* Virtualmin can now generate TLSA DNS records for DANE SSL certificate verification, which (when combined with DNSSEC) provide additional assurance to clients that they are connecting to the correct webserver.
* The number of top-level virtual servers a reseller is allowed to create can now be limited.
* When using DNSSEC, the DS records that need to be created at your registrar are now displayed on the DNS Options page. If the parent domain is hosted by Virtualmin, the DS records will be added automatically.
* Added a script installer for Nextcloud 10.0.1, a fork of ownCloud.
* Updated the Moodle script installer to version 2.9.8 and 3.1.3, Piwik to 2.17.1, Drupal to 8.2.3 and 7.52, osTicket to 1.9.15, Rainloop to 1.10.5.192, phpMyAdmin to 4.6.4, 4.0.10.17 and 4.4.15.8, Wordpress to 4.6.1, Joomla to 3.6.4, MediaWiki to 1.27.1, ZenPhoto to 1.4.13, eGroupware to 16.1.20161006, Mantis to 1.3.3, Magento to 2.1.2, Node.JS to 7.1.0, Typo3 to 6.2.28, IONcube to 6.0.6, FengOffice to 3.4.4.1, ownCloud to 9.1.1, SMF to 2.0.12, Roundcube to 1.2.2, MoinMoin to 1.9.9, Revive Adserver to 4.0.0, Ghost to 0.11.3, and Pydio to 6.4.2.

#### Version 5.03
* Backups can now be deleted either from the Backup Logs page, or using the delete-backup API command.
* Added a config option to redirect HTTP requests to HTTPS for new domains (if they have an SSL website enabled).
* In the post-installation wizard, if Virtualmin does not know the current MySQL pasword the admin will be prompted to enter it.
* SSL versions 2 and 3 and TLS versions 1.0 and 1.0 are disabled by default in the Apache configuration for new domains.
* Updated the Django script installer to version 1.9.6, FengOffice to 3.4.3, Roundcube to 1.2.1, phpMyAdmin to 4.6.3, 4.4.15.7 and 4.0.10.16, MediaWiki to 1.27.0, Rainloop to 1.10.2.145, Drupal to 8.1.7 and 7.50, Dolibarr to 3.9.3, TikiWiki to 15.2 and 12.9, Coppermine to 1.5.42, Wordpress to 4.5.3, Moodle to 3.1.1 and 2.9.6, DokuWiki to 2016-06-26, FosWiki to 2.1.2, ownCloud to 9.1.0, extPlorer to 2.1.9, SugarCRM to 6.5.24, and Typo3 to 6.2.26.

#### Version 5.02
* Updated the Dolibarr script installer to version 3.9.1, and Wordpress to version 4.5.1.

#### Version 5.03
* Improved support for Ubuntu 16 and MySQL 5.7.
* Added a Virtualmin Configuration setting to request a Let's Encrypt certificate at virtual server creation time.
* Fixed support for mail server settings autodiscovery for Outlook clients.
* Added the generate-letsencrypt-cert API command, to request and install a cert from Let's Encrypt.
* Updated the Django script installer to version 1.9.6, FengOffice to 3.4.2.2, Roundcube to 1.2.0, phpMyAdmin to 4.6.3, 4.4.15.7 and 4.0.10.16, MediaWiki to 1.26.3, Rainloop to 1.10.1.127, Drupal to 8.1.3 and 7.44, Dolibarr to 3.9.2, TikiWiki to 15.1 and 12.8, Coppermine to 1.5.42, Wordpress to 4.5.3, Moodle to 3.1, DokuWiki to .4.415.

#### Version 5.02
* Updated the Dolibarr script installer to version 3.9.1, and Wordpress to version 4.5.1.

#### Version 5.03
* Improved support for Ubuntu 16 and MySQL 5.7.
* Added a Virtualmin Configuration setting to request a Let's Encrypt certificate at virtual server creation time.
* Fixed support for mail server settings autodiscovery for Outlook clients.
* Added the generate-letsencrypt-cert API command, to request and install a cert from Let's Encrypt.
* Updated the Django script installer to version 1.9.6, FengOffice to 3.4.2.2, Roundcube to 1.2.0, phpMyAdmin to 4.6.3, 4.4.15.7 and 4.0.10.16, MediaWiki to 1.26.3, Rainloop to 1.10.1.127, Drupal to 8.1.3 and 7.44, Dolibarr to 3.9.2, TikiWiki to 15.1 and 12.8, Coppermine to 1.5.42, Wordpress to 4.5.3, Moodle to 3.1, DokuWiki to .4.415.

#### Version 5.02
* Updated the Dolibarr script installer to version 3.9.1, and Wordpress to version 4.5.1.

#### Version 5.01
* Improved support for Ubuntu 16 and MySQL 5.7.
* Added a Virtualmin Configuration setting to request a Let's Encrypt certificate at virtual server creation time.
* Fixed support for mail server settings autodiscovery for Outlook clients.
* Added the generate-letsencrypt-cert API command, to request and install a cert from Let's Encrypt.
* Added a new script installer for Rainloop version 1.9.4.415.
* Updated the Rails script installer to version 4.2.5.2, Drupal to 8.1.0, Django to 1.9.5, Revive AdServer to 3.2.4, FengOffice to 3.4.1, Dolibarr to 3.9.0, Moodle to 3.0.3 and 2.9.5, ZenPhoto to 1.4.12, ownCloud to 7.0.13 and 9.0.1, phpMyAdmin to 4.6.0, Joomla to 3.5.1, Pydio to 6.4.1, Piwik to 2.16.1, phpMyFAQ to 2.8.27, Wordpress to 4.5, WHMCS to 6.3.1, Roundcube to 1.1.5, and Node.JS to 5.10.1.

#### Version 5.00
* Added support for multiple hostnames and automatic renewal of Let's Encrypt certificates.
* Updated the WordPress script installer to version 4.4.1, Moodle to 3.0.2 and 2.9.4, Drupal to 8.0.4, 7.43 and 6.38, eGroupware to 14.3.20160113, TikiWiki to 14.2, 12.6 and 6.15, IONcube to 5.0.23, Pydio to 6.2.2, Node.JS to 5.7.0, Magento to 1.9.2.4, Rails to 4.2.5.1, phpMyAdmin to 4.5.5.1, 4.4.15.5 and 4.0.10.15, ownCloud to 8.2.2, 7.0.12 and 6.0.9, Wordpress to 4.4.2, Dolibarr to 3.5.8, Piwik to 2.16.0, FengOffice to 3.4.0.17, LimeSurvey to 2.50, FosWiki to 2.1.0, IONcube to 5.1.1, phpMyFAQ to 2.8.26, PHPcalendar to 2.0.9, Django to 1.9.2, Joomla to 3.4.8, and Typo3 to 6.2.19.

#### Version 4.19
* Added a tab to the Manage SSL Certificate page to request a certificate from the free Let's Encrypt service.
* The paths to additional PHP versions can now be entered on the Virtualmin Configuration page, under PHP Options. This also makes it possible to run PHP version 7.
* The Excluded Directories page can now also be used to enter MySQL and PostgreSQL databases and tables to exclude from backups.
* Backup logs are now associated with the scheduled backup that created them, and are linked in the UI.
* Removed support for Apache versions older than 2.0.

#### Version 4.18
* Added the rename-domain API command, to allow changing the domain name, username or home directory of a virtual server from the command line.
* MX records for a domain can be pointed to a cloud mail filtering provider on the Email Options page, or using the modify-mail API command.
* Updated the Piwik script installer to version 2.14.3, Wordpress to 4.3, phpMyFAQ to 2.8.24, FengOffice to 3.3, Dolibarr to 3.7.2 and 3.6.4, MediaWiki to 1.25.2, Coppermine to 1.5.38, Magento to 1.9.2.1, Dokuwiki to 2015-08-10a, SugarCRM to 6.5.22, ownCloud to 8.1.1, Drupal to 7.39 and 6.37, Django to 1.4.22, Trac to 1.0.8 and 0.12.7, FosWiki to 2.0.1, CMS Made Simple to 1.12.1, Typo3 to 6.2.15, Ghost to 0.7.0, Joomla to 3.4.4, and phpMyAdmin to 4.4.14.1.

#### Version 4.17
* Under Webmin versions 1.780 and above, use /var/webmin for logs and data files instead of /etc/webmin.
* Added an option for scheduled backups to terminate an existing backup to the same destination, rather than being blocked by it.
* Updated the Dolibarr script installer to version 3.7.1, Wordpress to 4.2.2, SMF to 2.0.10, Revive Adserver to 3.2.0, Piwik to 2.13.1, Ghost to 0.6.2, Pydio to 6.0.8, Drupal to 7.38 and 6.36, ownCloud to 8.0.4, Coppermine to 1.5.36, Node.JS to 0.12.7, ZenPhoto to 1.4.9, Ghost to 0.6.4, X2CRM to 5.0.7, TikiWiki to 12.4 and 14.0, OpenCart to 2.0.3.1, MediaWiki to 1.25.1, Revive Adserver to 3.2.1, Roundcube to 1.1.2, Moodle to 2.9.1, phpMyFAQ 2.8.23, SugarCRM to 6.5.21, FengOffice to 3.2, Joomla to 3.4.3, Typo3 to 6.2.14, PiWik to 2.14.0, Django to 1.4.21, and phpMyAdmin to 4.4.11 and 4.0.10.10.

#### Version 4.16
* Improved support for replicating and deleting domains that use a shared home directory and MySQL database to synchronise state across two or more Virtualmin systems.
* Updated the Trac script installer to version 1.0.5, ownCloud to 8.0.2, MediaWiki to 1.24.2 and 1.19.24, Node.JS to 0.12.2, phpMyFAQ to 2.8.22, OpenCart to 2.0.2.0, Drupal to 7.36, Pydio to 6.0.6, vTigerCRM to 6.2.0, CMS Made Simple to 1.12, X2Engine to 5.0.6, Ghost to 0.6.0, and phpMyAdmin to 4.4.2.

#### Version 4.15
* If the aws command is installed, Virtualmin will call it to perform S3 operations rather than using it's own code. Because this command is developed by Amazon, it can be expected to be reliable in the face of S3 API changes.
* Updated the phpMyAdmin script installer to version 4.3.12 and 4.0.10.9, Piwik to 2.12.1, Moodle to 2.8.5, Django to 1.7.5, Roundcube to 1.1.1, Drupal to 7.35 and 6.35, Django to 1.7.7 and 1.4.20, DokuWiki to 2014-09-29d, Joomla to 3.4.1, TextPattern to 4.5.7, Node.JS to 0.12.1, X2CRM to 5.0.5, Ghost to 0.5.10, and Pydio to 6.0.5.

#### Version 4.14
* Switch from the old dkim-milter package to OpenDKIM on CentOS 7 systems.
* Added support for backing up to and restoring from Dropbox, similar to Virtualmin's existing Google Cloud Storage backup feature.
* The password recovery email address can now be edited for mailbox users via the Edit User page and the modify-user API command. The password reset process can also be triggered from within Virtualmin, as well as using the password recovery plugin.
* Added the Running Backups page for viewing scheduled and manually started backups that are currently executing.
* Updated the Moodle script installer to version 2.8.3, phpMyAdmin to 4.3.10, Node.js to 0.12.0, phpMyFAQ to 2.8.21, Trac to 1.0.4, ZenPhoto to 1.4.7, Roundcube to 1.1.0, Pydio to 6.0.3, X2CRM to 5.0.4, Z-Push to 2.2.0, extPlorer to 2.1.7, Wordpress to 4.1.1, Piwik to 2.11.1, CMS Made Simple to 1.11.13, Django to 1.7.5, Dokuwiki to 2014-09-29c, Joomla to 3.4.0, ownCloud to 8.0.0, Ghost to 0.5.9, and FengOffice to 3.0.7.

#### Version 4.13
* Added support for creating and editing DMARC DNS records for virtual servers, which specify a policy for other mail servers to be applied to email that does not pass SPF or DKIM validation.
* SNI (multiple SSL certs on the same IP) is now always assumed to be usable by clients, as long as the web server supports it.
* Updated the phpMyAdmin script installer to version 4.3.8 and 4.0.10.8, Django to 1.7.4 and 1.4.19, FengOffice to 3.0.3, Ghost to 0.5.8, Moodle to 2.8.2, X2CRM to 5.0.2, CMS Made Simple to 1.11.12, Trac to 1.0.3, phpMyFAQ to 2.8.19, OpenCart to 2.0.1.1, Roundcube to 1.0.5, Mantis to 1.2.19, Node.JS to 0.10.36, and PiWik to 2.10.0.

#### Version 4.12
* Added APIs that allow Virtualmin to define the preferred left and right frame contents for a theme, rather than requiring theme authors to write code for this.
* Added the Disassociate Features page for adding and removing features from a virtual server without actually changing the underlying configuration files.
* All operations performed by Virtualmin on files in a domain's home directory are now done with the user's permissions, to prevent attacks involving a malicious symbolic or hard link.
* Added a Virtualmin Configuration page option to control whether a * or an IP is used in Apache VirtualHost blocks.
* The hash format (SHA1 or SHA2) for new certificates can now be selected at creation time, and the default set on the Virtualmin Configuration page.
* For new installs, a single logrotate configuration block will now be shared by all virtual servers. For existing systems, whether to use a shared or separate blocks can be set on the Server Templates page.
* Added a Change Language link the on left menu for easily switching the UI language.
* A default shell can now be selected for reseller Unix accounts, independent of the domain owner default shell.
* Updated to Coppermine script installer to version 1.5.34, Drupal to 7.34 and 6.34, Piwik to 2.9.1, TikiWiki to 13.1 and 12.3, Moodle to 2.8.1, ownCloud to 6.0.6 and 7.0.4, phpMyFAQ to 2.8.18, Ghost to 0.5.7, WordPress to 4.1, phpMyAdmin to 4.3.4, 4.2.13.1, 4.1.14.8 and 4.0.10.7, Magento to 1.9.1.0, MediaWiki to 1.24.1 and 1.19.23, Trac to 1.0.2 and 0.12.6, DokuWiki to 2014-09-29b, Mantis to 1.2.18, Joomla to 2.5.28, Pydio to 6.0.2, Revive Adserver to 3.1.0, Node.JS to 0.10.35, Roundcube to 1.0.4, Dolibarr to 3.6.2, SugarCRM to 6.5.20, Django to 1.7.2 and 1.14.17, FengOffice to 3.0.1, and MoinMoin to 1.9.8.

#### Version 4.11
* Added support for backups to Google Cloud Storage, once an account is added on the new Cloud Storage Providers page.
* Moved all S3 and Rackspace Cloud Files settings from the Virtualmin Configuration page to the new Cloud Storage Providers page.
* On systems running Apache 2.4 and above, VirtualHost blocks are now created with an IP address instead of *.
* Updated the Piwik script installer to version 2.8.3, Joomla to 3.3.6 and 2.5.27, Ghost to 0.5.3, Roundcube to 1.0.3, phpMyFAQ to 2.8.15, Zikula to 1.3.9, phpMyAdmin to 4.2.11, 4.1.14.6 and 4.0.10.5, DokuWiki to 2014-09-29a, Dolibarr to 3.6.1, SMF to 2.0.9, TWiki to 6.0.1, SugarCRM to 6.5.18, Coppermine to 1.5.32, X2CRM to 4.3, TikiWiki to 13.0, Drupal to 7.32, PHPList to 3.0.10, OpenCart to 2.0.0.0, eXtplorer to 5.2.5, Django to 1.7.1 and 1.4.16, FengOffice to 2.7.1.6, Node.JS to 0.10.33, and MediaWiki to 1.23.6 and 1.19.21.

#### Version 4.10
* If Postfix and Dovecot are setup to use SSL, they will be configured to use the certificate belonging to virtual servers with their own private IP address for connections to that IP.
* Automatic cleanup of messages in all mailboxes and folders can now be setup in Virtualmin, to enforce an email retention policy or save on disk space.
* IPv6 addresses in Virtualmin are now supported on all operation systems that Webmin supports them for, rather than just Linux.
* If Dovecot 2 or higher has SSL enabled, the certificate for domains with a private IP address will be used for connections to the Dovecot server.
* Updated the phpMyAdmin script installer to version 4.2.9, 4.1.14.4 and 4.0.10.3, Moodle to 2.7, Wordpress to 4.0, PiWik to 2.6.1, X2CRM to 4.2.1, FengOffice to 2.7.1.1, Node.JS to 0.10.32, PHPList to 3.0.8, and Django to 1.4.15 and 1.7.

#### Version 4.09
* Ensim migration now includes alias domains and sub-domains.
* Updated the Dolibarr script installer to version 3.6.0, Drupal to 7.31 and 6.33, phpMyAdmin to 4.2.7.1, 4.0.10.2 and 4.1.14.3, Roundcube to 1.0.2, FengOffice to 2.6.3, Joomla to 3.3.3 and 2.5.24, MediaWiki to 1.23.3 and 1.19.18, Node.JS to 0.10.31, phpMyFAQ to 2.8.12, ownCloud to 7.0.2, Wordpress to 3.9.2, CMS Made Simple to 1.11.11, phpList to 3.0.7, PiWik to 2.5.0, Ghost to 0.5.1, Django to 1.6.6 and 1.4.14, and X2Engine to 4.1.7.

#### Version 4.08
* Added a warning message on the password change forms if a domain's MySQL or PostgreSQL logins would also be effected.
* Added Virtualmin configuration options for commands to run before and after a reseller is created, modified or deleted.
* Renamed the X2CRM installer to X2Engine, and updated the version to 4.1.4.
* Updated the phpMyAdmin script installer to version 4.2.5, Revive Adserver to 3.0.5, Magento to 1.9.0.1, Instiki to 0.19.7, TikiWiki to 12.2, FengOffice to 2.6.1, PiWik to 2.4.1, MediaWiki to 1.23.1 and 1.19.17, Dolibarr to 3.5.3, phpMyFAQ to 2.8.11, ZenPhoto to 1.4.6, osCommerce to 2.3.4, Joomla to 3.3.1 and 2.5.22, NodeJS to 0.10.29, SMF to 2.0.8, OwnCloud to 6.0.4, SugarCRM to 6.5.17, Z-push to 2.1.3, DokuWiki to 2014-05-05a, osTicket to 1.9.2 and 1.8.4, Coppermine to 1.5.30, and Django to 1.6.5 and 1.4.13.

#### Version 4.07
* Fixed support for the Options directive in Apache 2.4.
* DKIM keys can now be set on a domain by domain basis, rather than all virtual servers using the same key.
* Reseller accounts can now be granted the ability to edit and create other resellers.
* Updated the Roundcube script installer to version 1.0.1 and 0.8.7, Revive AdServer to 3.0.4, phpMyAdmin to 4.2.0, Piwik to 2.2.2, OpenGoo to 2.5.1.4, Dolibarr to 3.5.2, phpList to 3.0.6, Drupal to 6.31 and 7.28, MediaWiki to 1.22.6, Django to 1.4.12 and 1.6.4, ownCloud to 6.0.3, phpMyFAQ to 2.8.9, Joomla to 3.3.0 and 2.5.20, TikiWiki to 12.1 and 6.14, Node.JS to 0.10.28, Moodle to 2.6.3, Z-push to 2.1.2, and WordPress to 3.9.1.

#### Version 4.06
* Reseller accounts can now have an associated Unix account for FTP/SSH access, which has permissions to access all managed domains' files.
* A single virtual server can now be owned by multiple resellers, each of whom has permissions to manage it. This can be useful if reseller accounts are used as an additional layer of administrative control in Virtualmin.
* Alias servers can now be re-pointed to a different target, using the Move Virtual Server page or the move-domain API command.
* The Change IP Addresses	page can now be used to update the external DNS address of multiple virtual servers, as well as the actual address.
* Aliases and redirects can now be separately enabled for the SSL and non-SSL websites of a virtual server.
* Added Norwegian translation updates, thanks to Stein-Aksel Basma.
* Updated the Node.js script installer to version 0.10.26, Pydio to 5.2.3, Zikula to 1.3.7, MediaWiki to 1.22.5 and 1.19.15, Feng Office to 2.5.1.3, Mantis to 1.2.17, PiWik to 2.1.0, ownCloud to 6.0.2, Dolibarr to 3.5.1, Joomla to 3.2.3 and 2.5.19, Moodle to 2.6.2, Revive AdServer to 3.0.3, eGroupWare to 1.8.006, phpMyFAQ to 2.8.8, Ghost to 0.4.2, Coppermine to 1.5.28, and phpMyAdmin to 4.1.12.

#### Version 4.05
* The port used in URLs can now be set independently of the actual port, so that URLs are correct when a reverse proxy is in use.
* Added an option to the restore process to delete files in an existing destination domain that were not included in the backup.
* Added a script installer for Node.js version 0.10.25, and Ghost version 0.4.1.
* Updated the CMS Made Simple script installer to version 1.11.10, phpMyFAQ to 2.8.7, Pydio to 5.2.1, Joomla to 3.2.2 and 2.5.18, phpMyAdmin to 4.1.8, Mantis to 1.2.16, Django to 1.6.2, and Dolibarr to 3.5.0.

#### Version 4.04
* Added the Transfer Virtual Server page and transfer-domain API command for copying or moving a domain to another system running Virtualmin.
* Added SRV record support to the DNS Records page.
* Updated the Z-push script installer to version 2.1.1-1788, phpMyAdmin to 4.1.6, MediaWiki to 1.22.2 and 1.19.11, LimeSurvey to 2.05, Magento to 1.8.1.0, WordPress to 3.8.1, FengOffice to 2.5.0.1, Revive Adserver to 3.0.2, Django to 1.6.1, Joomla to 3.2.1 and 2.5.17, PiWik to 2.0.3, ZenPhoto to 1.4.5.9, phpMyFAQ to 2.8.5, eXtplorer to 2.1.5, Drupal to 7.26 and 6.30, ownCloud to 6.0.1, Dolibarr to 3.4.2, WHMCS to 5.2.15, Coppermine to 1.5.26, DokuWiki to 2013-12-08, Moodle to 2.6.1, Pydio to 5.2.0, SMF to 2.0.7, and TikiWiki to 12.0.
* Added the fix-domain-permissions API command, for resetting home directory ownership.

#### Version 4.03
* Errors that would prevent a virtual server from being restored (such as a missing reseller or parent) are now detected before the long restore process starts.
* Added support for migrating domains from DirectAdmin control panel backups.
* All incoming email to a domain can now be silently BCCd to another address, similar to the existing option for BCCing outgoing messages.
* Added the Mail Rate Limiting page for restricting the rate at which messages will be accepted by the system, either for local delivery or relaying. This can be useful to prevent spammers from using a hijacked account or website to rapidly send large amounts of email.
* Renamed the OpenX script to Revive Adserver, to reflect its open-source fork, and bumped the version to 3.0.0.
* Updated the Ajaxplorer script installer to 5.0.4 (and renamed to Pydio), TWiki to 6.0.0, Roundcube to 0.9.5, SMF to 2.0.6, SugarCRM to 6.5.16, WordPress to 3.7.1, Django to 1.4.10 and 1.6, MoinMoin to 1.9.7, ZenPhoto to 1.4.5.7, TikiWiki to 11.1 and 6.13, phpMyAdmin to 4.0.9, OwnCloud to 5.0.13, Joomla to 3.2.0, Moodle to 2.6, Zikula to 1.3.6, MediaWiki to 1.19.9 and 1.21.3, phpMyFAQ to 2.8.4, FosWiki to 1.1.19, Drupal to 6.29 and 7.24, Z-push to 2.1.0a-1776, FengOffice to 2.4, PHP-Nuke to 8.3.2, and Dolibarr to 3.4.1.
* Access to plugin modules is now granted to resellers.

#### Version 4.02
* The Dallas or Chicago datacenters can now be explictly selected when using Rackspace cloud files.
* When migrating a virtual server from cPanel, Plesk or some other control panel, you can now select if it will be assigned an IPv6 address by Virtualmin.
* Multiple virtual servers can now share a single IPv6 address, just as can be done for IPv4. Each domain can either not use IPv6 at all, use one of several shared addresses, or have its own private address.
* Backups from other control panels can now be migrated from their un-compressed or extract directories.
* Mail client auto-configuration now supports Outlook as well as Thunderbird.
* Updated the SMF script installer to version 2.0.5, X2CRM to 3.5.2, Django to 1.5.4 and 1.4.8, Roundcube to 0.9.4, osCommerce to 2.3.3.4, SugarCRM to 6.5.15, Z-push to 2.1.0, AjaXplorer to 5.0.3, MediaWiki to 1.12.2 and 1.19.8, phpMyAdmin to 4.0.8, Moodle to 2.5.2, ZenPhoto to 1.4.5.5, CMS Made Simple to 1.11.9, Wordpress to 3.6.1, phpList to 3.0.5, FengOffice to 2.3.2.1, Radiant to 1.1.4, phpBB to 3.0.12, Magento to 1.8.0.0, TextPattern to 4.5.5, and ownCloud to 5.0.12.

#### Version 4.01
* The Change IP Address page can now be used to switch a domain with a private IP to another address.
* On Apache version 2.4 and above, Virtualmin no longer adds the NameVirtualHost directive as it is deprecated.
* Updated the Roundcube script installer to version 0.9.2, DokuWiki to 2013-05-10a, X2CRM to 3.2, WordPress to 3.6, Movable Type to 5.2.7, TikiWiki to 11.0 and 6.12, AjaXplorer to 5.0.2, phpMyFAQ to 2.8.2, SugarCRM to 6.5.14, ZenPhoto to 1.4.5.1, Gallery to 3.0.9, Moodle to 2.5.1, ownCloud to 5.0.9, FengOffice to 2.3.1.1, dotProject to 2.1.8, Joomla to 3.1.5 and 2.5.14, Dolibarr to 3.4.0, Drupal to 7.23, OpenX to 2.8.11, and phpMyAdmin to 4.0.5 and 3.5.8.2.

#### Version 4.00
* For domains whose DNS is not hosted by the Virtualmin system, a sensible default set of records is shown on the Suggested DNS Records page.
* When changing the IP address of multiple domains, an option to update the master IP of slave DNS zones is now available.
* Added an option when restoring virtual servers to have them deleted and re-created before restoring files.
* Added the Amazon S3 Buckets page, for setting bucket ACLs, scheduled deletion and Glacier move rules.
* The default external IP address (for use in DNS records) can now be specified on a per-reseller basis.
* German translation updates, thanks to Raymond Vetter.
* Added script installers for ownCloud 5.0.7 and X2CRM 3.0.2.
* Updated the ZenPhoto script installer to version 1.4.4.8, Joomla to 3.1.1 and 2.5.11, MediaWiki to 1.21.1 and 1.19.7, phpMyAdmin to 4.0.3, eGroupWare to 1.8.004, DokuWiki to 2013-05-10, Moodle to 2.4.4, SugarCRM to 6.5.13, Roundcube to 0.9.1, FengOffice to 2.3, Dolibarr to 3.3.2, Coppermine to 1.5.24, CMS Made Simple to 1.11.7, PiWik to 1.12, Movable Type to 5.2.6, phpMyFAQ to 2.8.0, AjaXplorer to 5.0.0, Gallery to 3.0.8, and PHPList to 2.11.10.

#### Version 3.99
* Added buttons to the Scheduled Backups page to enable or disable backups, and a button on the Edit Scheduled Backup page to clone a backup configuration.
* Added a field to the DKIM page for entering domains to exclude from signing and DNS record creation.
* If Webmin's BIND module is configured to use the SPF type for Sender Permitted From records, Virtualmin will create both SPF and TXT records for domains.
* Updated the Django script installer to version 1.5.1, SugarCRM to 6.5.12, Mediawiki to 1.20.4 and 1.19.5, PiWik to 1.11.1, Drupal to 7.22, phpScheduleIt to 2.4.1, Moodle to 2.4.3, Typo3 to 4.6.18, phpScheduleIt to 2.4.1, FengOffice to 2.2.4.1, Dolibarr to 3.3.1, Gallery to 3.0.7, TikiWiki to 10.2, CMS Made Simple to 1.11.6, RoundCube to 0.9.0, Nucleus to 3.65, phpMyAdmin to 3.5.8.1, Mantis to 1.2.15, phpPgAdmin to 5.1, FosWiki to 1.1.8, Joomla to 3.1.0, and ZenPhoto to version 1.4.4.4.

#### Version 3.98
* Added an option to the Spam and Virus Scanning page to control what happens when email is sent to a mailbox that is over quota (bouncing or queueing for later).
* Changed the default email folder names to Junk, Trash, Drafts, Sent and Virus.
* When DNS records are modified in a virtual server, all records are synchronized into any alias domains.
* When the contact email address for a domain is changed, default mail aliases like postmaster will be updated to the new address.
* Plugin modules available to domain owners can now be configured at the template level, in the Administrator's Webmin modules section.
* The key size is now configurable when setting up DKIM or generating a new key.
* Added a template section to configure the mail client auto-configuration XML, for example if some domains use custom mail servers.
* If PHP 5.3 or higher is installed via a separate package, Virtualmin will now detect it and allow it to be selected on a per-domain or per-directory basis. This is useful for systems whose default PHP package is version 5.2 or older.
* Added the ability to enable or disable server-side includes for a specific file extension for virtual servers with a website.
* Updated the OpenCart script installer to version 1.5.5.1, Squirrelmail to 1.4.22, WordPress to 3.5.1, Movable Type to 5.2.3, PHP-Calendar to 1.1, Gallery to 3.0.4, Advanced Poll to 2.0.9, PHP-Wiki to 1.4.0rc1, Simple Invoices to 2011.1, phpScheduleIt to 2.3.6, Advanced Guestbook to 2.4.4, Zikula to 1.3.5, Roundcube to 0.8.5, phpMyAdmin to 3.5.7, Mantis to 1.12.14, SMF to 2.0.4, Trac to 1.0.1, SugarCRM to 6.5.10, Joomla to 3.0.3 and 2.5.9, ZenPhoto to 1.4.4.1b, Instiki to 0.19.6, TikiWiki to 10.1 and 6.10, Z-push to to 2.0.7, Django to 1.4.5, FengOffice to 2.2.3.1, Drupal to 7.20, Twiki to 5.1.4, WebCalendar to 1.2.7, Gallery to 3.0.5, Dolibarr to 3.3.0, and Radiant to 1.1.3. Marked several scripts that no longer appear to be updated or available as unsupported.

#### Version 3.97
* Moved all background cron jobs (except existing backups) to Webmin's built-in scheduler, to save memory and reduce the CPU load of launching cron jobs.
* Added the Mail Client Configuration page, for setting up a Thunderbird-style client autoconfiguration URL for all virtual servers.
* When disabling a top-level virtual server, an option is now available to also disable all sub-servers at the same time.
* Updated the Z-push script installer to version 2.0.6, Dolibarr to 3.2.3, Django to 1.4.3, WordPress to 3.5.0, TWiki to 5.1.3, SMF to 2.0.3, CMS Made Simple to 1.11.4, Drupal to 7.19 and 6.28, phpMyAdmin to 3.5.5, eXtplorer to 2.1.2, TikiWiki to 10.0 and 6.9, SugarCRM to 6.5.9, Moodle to 2.4.1, FengOffice to 2.2.2, WebCalendar to 1.2.6, Instiki to 0.9.15, Coppermine to 1.5.22, ZenPhoto to 1.4.4, PiWik to 1.10.1, Trac to 0.12.5, and Movable Type to 5.2.2. Added script installers for FileCharger and AjaXplorer.

#### Version 3.96
* Backups can now be prevented from updating the differential state, so that ad-hoc backups can be run without interfering with scheduled differential backups.
* Virtualmin will now prompt the root user after logging in if any virtual servers with unsafe symlink or mod_php settings are found. Previous versions applied fixes for these security issues automatically, which broke some domains.
* If running Virtualmin in SSL mode with a certificate of less than 2048 bits, a warning is now displayed on the system information page prompting the admin to generate or request a new cert.
* Updated the MediaWiki script installer to versions 1.20.2 and 1.19.3, bbPress to 1.2, TextPattern to 4.5.4, and ZenPhoto to 1.4.3.5.

#### Version 3.95
* All existing virtual servers using the FollowSymLinks option will be converted to SymLinksifOwnerMatch, to protect against malicious links into other domain's directories.
* For virtual servers using CGI or fcgid mode for executing PHP, mod_php mode is now forcibly disabled to prevent potential security issues. This is also done for all domains at installation time.
* Account plans can now be changed for multiple virtual servers at once, on the Update Virtual Servers page.
* The spamtrap and hamtrap email aliases now only accept mail from authenticated senders or the local system, to prevent poisoning of the spamassassin rules engine by attackers.
* Server templates can now be restricted to a subset of server owners, rather than being granted to all or nothing.
* Added an option to delete old mail in users' trash folder to the Spam and Virus Delivery page, similar to the existing option for deleting spam.
* Updated the Typo3 script installer to version 4.6.15, CMS made simple to 1.11.3, Drupal to 7.17, PiWik to 1.9.2, FengOffice to 2.2.1, TikiWiki to 9.2, SugarCRM to 6.5.8, ZenPhoto to 1.4.3.4, Joomla to 3.0.2 and 2.5.8, phpMyFAQ to 2.7.9, RoundCube to 0.8.4, MediaWiki to 1.20.0, Z-push to 2.0.5, phpMyAdmin to 3.5.4, Mantis to 1.2.12, dotProject to 2.1.7, Moodle to 2.3.3, and Django to 1.4.2.

#### Version 3.94
* Added the fix-domain-quota API command, to bring Unix quotas into sync with what Virtualmin expects.
* When running a scheduled backup from within the Virtualmin UI, pre and post backup commands are now run, and old backups purged if configured.
* Updated the osCommerce script installer to version 2.3.3, phpBB to 3.0.11, Dolibarr to 3.2.2, SugarCRM to 6.5.5, Radiant to 1.1.0, ZenPhoto to 1.4.3.3, MediaWiki to 1.19.2, WordPress to 3.4.2, Moodle to 2.3.2, DokuWiki to 2012-10-13, OpenX to 2.8.10, Joomla to 2.5.7, Trac to 0.12.4 and 1.0, PiWik to 1.9, CMS Made Simple to 1.11.2, Z-push to 2.0.4, TikiWiki to 6.7 and 9.1, Redmine to 2.1.2, ZenCart to 1.5.1, LimeSurvey to 2.00, Movable Type to 5.2, Roundcube to 0.8.2, phpMyAdmin to 3.5.3, TWiki to 5.1.2, FengOffice to 2.2.0, and TextPattern to 4.5.2. Disabled the Mambo installer, as it appears to be no longer supported or updated. Added a script installer for OpenCart 1.5.4.1.

#### Version 3.93
* Virtual servers can now be backed up to the Rackspace Cloud Files service, in a similar way to Virtualmin's S3 backup support.
* If the system's primary IP address has changed, display a warning message and prompt to update all virtual servers on the old IP.
* The outgoing IP address for email sent from a domain can now be configured to match the domain's IP, when using Postfix 2.7 or above.
* When installing Ruby scripts, dependencies like gcc and libfcgi-devel are now installed automatically if possible.
* Alias virtual servers that have their own mailboxes and aliases can now be created, rather than always forwarding mail to the destination domain.
* Updated the SugarCRM script installer to version 6.5.2, WHCMS to 5.1.2, Django to 1.4.1, phpMyAdmin to 3.5.2.2, ZenPhoto to 1.4.3.1, PHPList to 2.10.19, Drupal to 7.15, RoundCube to 0.8.1, Typo3 to 4.6.12, dotProject to 2.1.6, Piwik to 1.8.3, Z-push to 2.0.2-1437, phpMyFAQ to 2.7.8, and CMS made simple to 1.11.1.

#### Version 3.92
* When the SSL certificate for a domain is changed, any domains which shared the old cert but cannot use the new one will be switched to a copy of the old cert file.
* The default shell for new virtual servers on Linux systems is now bash, if installed.
* Added an option to the restore form and a flag to restore-domain to ignore virtual servers that have failed.
* Virtual server owners can now be granted permission to create domains on a single IP address.
* The disable-feature and enable-feature API commands now have flags to disassocaite and re-associate features with a domain, without actually updating the underlying configuration files or databases.
* Backups to Amazon S3 can now be to a sub-directory under a bucket, rather than being at the top level.
* The DKIM feature in Virtualmin now supports OpenDKIM, as seen in Ubuntu 12.04.
* The contact email address for a domain can now contain multiple addresses with real names.
* Backups of more than 2GB to Amazon's S3 service now use the mulitpart protocol, which is needed to support large backups.
* Added new API commands list list-s3-buckets and upload-s3-file for manipulating files on Amazon's S3 service.
* Updated the phpMyAdmin script installer to version 3.5.2, Drupal to 7.14 and 6.26, SugarCRM to 6.5, FengOffice to 2.1.0, Zikula to 1.2.9, OpenX to 2.8.9, ZenPhoto to 1.4.3, phpMyFAQ to 2.7.7, Movable Type to 5.14, Typo3 to 4.6.10, Flyspray to 0.9.9.7, PiWik to 1.8.2, WordPress to 3.4.1, Mantis to 1.2.11, Coppermime to 1.5.20, Joomla to 2.5.6, Magento to 1.7.0.2, Instiki to 0.19.4, Moodle to 2.3.1, Dolibarr to 3.2.0, Z-Push to 2.0-1346, DokuWiki to 2012-01-25b, and MediaWiki to 1.19.1.

#### Version 3.91
* Added a button to the Edit User page to re-send the signup email.
* Virtualmin backups can now be signed and encrypted, using GPG keys created within Virtualmin or imported from an existing file. This protects backups from snooping or modification when stored on an untrusted remote system.
* Updated the Mantis script installer to version 1.2.10, ZenPhoto to 1.4.2.3, phpMyAdmin to 3.5.0, Gallery to 2.3.2, phpMyFAQ to 2.7.5, SugarCRM to 6.4.3, WordPress to 3.3.2, DokuWiki to 2012-01-25a, vTigerCRM to 5.4.0, Typo3 to 4.6.8, MediaWiki to 1.18.3, Magento to 1.7.0.0, and Joomla to 2.5.4.

#### Version 3.90
* When calling the remote API with the json, perl or xml format flags, multiline mode is automatically enabled so that the output from commands can be correctly parsed. API errors are also returned using the selected format.
* Extra administrators can now be granted permissions to edit DNS records and options.
* When cloning a virtual server with a private IP, a new address for the clone can be entered instead of relying on automatic IP allocation.
* Added a Virtualmin Configuration option to use an alternate S3-compatible backup service instead of Amazon's.
* Updated the Drupal script installer to versions 6.25 and 7.12, ZenPhoto to 1.4.2.2, Autoload to 4.7.8, Horde to 3.3.13, IMP to 4.3.11, Horde Webmail to 1.2.11, SugarCRM to 6.4.2, phpMyAdmin to 3.4.10.2, PiWik to 1.7.1, Movable Type to 5.13, phpMyFAQ to 2.7.4, Radiant to 1.0.0, Dolibarr to 3.1.1, WebCalendar to 1.2.5, Mantis to 1.2.9, LimeSurvey to 1.92, Radiant to 1.0.1, RoundCube to 0.7.2, Moodle to 2.2.2, PHPList to 2.10.18, ZenCart to 1.5.0, MediaWiki to 1.18.2, phpPgAdmin to 5.0.4, Django to 1.4, Coppermine to 1.5.18, and Joomla to 2.5.3, 1.5.26 and 1.7.5.
* System statistics graphs now include the number of email messages received, bounced and greylisted. Statistic are also categorized by type, and when multiple stats are plotted at once the same axis is used for stats of the same type.

#### Version 3.89
* Scheduled backups now have a separate deletion policy for each destination, instead of the same policy being applied to all destinations. For example, you could delete local backups after 5 days and remote backups after 10.
* A new option on the Virtualmin Configuration page allows domain owners to restore backups made by root for their own domains. Because root backups are considered secure, the domain owner can restore all settings, including the Apache and DNS configuration.
* Backups now create a .dom file in the same directory as the tar.gz file, which contains information about the domains included and is used to speed up the restore process.
* The warning when multiple SSL sites share the same IP can now be disabled if your webserver supports SNI, via a new option on the Virtualmin Configuration page.
* Added the modify-proxy API command, to update an existing proxy balancer.
* The script installer update process can now detect new installer releases that don't change the application version.
* Added a script installer for Autoload 4.4.7.
* Updated the phpMyAdmin script installer to version 3.4.9, Drupal to 7.10, Moodle to 2.2.1, WordPress to 3.3.1, RoundCube to 0.7.1, SugarCRM to 6.3.1, SMF to 2.0.2, FosWiki to 1.1.4, WHMCS to 5.0.3, Dolibarr to 3.1.0, phpBB to 3.0.10, Bugzilla to 3.6.7, phpMyFAQ to 2.7.3, MediaWiki to 1.18.1, CMS Made Simple to 1.10.3, Magento to 1.6.2.0, TWiki to 5.1.1, ZenPhoto to 1.4.2, Joomla to 1.7.4, DokuWiki to 2012-01-25, and MoinMoin to 1.8.9.

#### Version 3.88
* The post-installation wizard now prompts for you to select a MySQL configuration size appropriate for the available memory on your system, and applies it to /etc/my.cnf.
* Backups now include the Dovecot control files of users when they are stored outside the home directory, so that message UIDs are preserved when the domain is restored on another system.
* Expanded the Virtualmin plugin API to allow a plugin to replace the core Apache website feature, for example with Nginx.
* When the email feature is disabled for a domain, all mail aliases are now removed and saved by Virtualmin. If email is later re-enabled, aliases will be restored.
* MySQL connection limits for domain owners and mailboxes can now be set at the template level, and will be applied to new virtual servers and mail users with database access.
* Added the --skip-warnings flag to the modify-domain API command, to ignore warnings related to new features from a plan change.
* The list of sub-servers under a top-level server has been moved from the Edit Virtual Server page to the List Sub-Servers link on the left menu.
* When creating or restoring a virtual server with a database that already exists, you now have the option to simply associate that database with the server rather than causing the server creation to fail.
* Updated the phpMyAdmin script installer to version 3.4.7.1, SMF to 2.0.1, bbPress to 1.1, SugarCRM to 6.3.0, Joomla to 1.7.3 and 1.5.25, phpMyFAQ to 2.7.1, phpPgAdmin to 5.0.3, ZenPhoto to 1.4.1.6, Moodle to 2.1.3, PiWik to 1.6, Magento to 1.6.1.0, CMS Made Simple to 1.10.2, Drupal to 7.9, OpenX to 2.8.8, eGroupWare to 1.8.002.20111111, vTigerCRM to 5.3.0, and PHPList to 2.10.17.

#### Version 3.87
* Storage of plaintext passwords for virtual servers and mailboxes can now be disabled on a per-template basis. Virtualmin will instead store only hashed passwords in multiple formats, which prevents passwords from being compromised if the system is hacked. Thanks to Dirk Ertner for supporting this feature.
* Added a tab to the Validate Virtual Servers page for fixing file ownership and permissions problems.
* Checking for new script updates is now enabled by default on new installs and upgrades, unless explicitly disabled by root.
* An IPv6 address that is already active can now be used when creating a virtual server.
* When a virtual server is disabled, any cron jobs run by its owner or mailbox users are also disabled.
* Updated the PiWik script installer to version 1.5.1, phpBB to 3.0.9, WordPress to 3.2.1, Joomla to 1.6.6 and 1.7.0, SugarCRM to 6.2.2, phpMyAdmin to 3.4.4, Mantis to 1.2.8, Drupal to 7.8, Horde Webmail to 1.2.10, Horde to 3.3.12, ZenPhoto to 1.4.1.3, Moodle to 2.1.1, LimeSurvey to 1.91, RoundCube to 0.6-rc, PHPList to 2.10.15, WebCalendar to 1.2.4, eGroupWare to 1.8.002.20110811, PHP-Nuke to 8.2.4, Magento to 1.6.0.0, TWiki to 5.1.0, Mantis to 1.2.7, CMS Made Simple to 1.9.4.3, Instiki to 0.19.3, i-Dreams to 6.0, Zikula to 1.2.8, Django to 1.3.1, and Dolibarr to 3.0.1.

#### Version 3.86
* Secondary mail servers running Sendmail and Postfix will now receive the list of allowed addresses for all domains from the master Virtualmin system, to prevent backscatter spam.
* Updated the modify-php-ini API command to set variables in the Apache configuration as well.
* The virtualmin configuration check now ensures that the system has at least 256 MB of real (non-burstable) memory, and displays a warning if total memory is too low.
* Added the --plan-features flag to the modify-domain command, to enable features based those selected for the plan.
* Added the list-backup-logs API command to report on previous backups run from the web UI, API or on schedule.
* When an alias domain with a website is disabled, it is now removed from the parent domain's Apache virtualhost.
* The last IMAP, POP3 and SMTP logins for mailbox users are now tracked by Virtualmin, and can be viewed on the Edit Mailbox page and in the output from the list-users API command.
* Added the new API command set-global-feature to turn features and plugins on and off from the command line.
* Updated the Roundcube script installer to version 0.5.3, PHPprojekt to 6.0.6, phpMyAdmin to 3.4.3.1, phpMyFAQ to 2.6.17, Movable Type to 5.11, Instiki to 0.19.2, FengOffice to 1.7.5, DokuWiki to 2011-05-25a, TextPattern to 4.4.1, WHMCS to 4.5.2, Piwik to 1.5, MediaWiki to 1.17.0, Simple Machines Forum to 2.0, Joomla to 1.6.4, WordPress to 3.2, Drupal to 7.4, Moodle to 2.1, ZenPhoto to 1.4.1.1, and SugarCRM to 6.2.0.

#### Version 3.85
* The default DNS TTL for one or more domains can now be changed via the --ttl flag to the modify-dns API command.
* Added a field for pasting in the text of a domain's CA certificate.
* Updated the Moodle script installer to version 2.0.3, Zikula to 1.2.7, phpMyAdmin to 3.4.1, PHPList to 2.10.14, WordPress to 3.1.3, Drupal to 7.2 and 6.22, DokuWiki to 2011-05-25, CMS Made Simple to 1.9.4.2, Movable Type to 5.12, WHMCS to 4.5.1, phpMyFAQ to 2.6.16, ZenPhoto to 1.4.1, and SugarCRM to 6.2.0RC3.

#### Version 3.84
* Reverse (PTR) records can now be created on the DNS Records page.
* As part of the post-install wizard process, the primary DNS server hostname is now prompted for and validated. This ensures that DNS zones created by Virtualmin have usable NS records.
* The HTTP and HTTPS ports for a virtual server can now be changed using the --port and --ssh-port flags to the modify-web API command.
* Unix UIDs and GIDs for domain owners and mailboxes are now tracked when deleted to prevent re-use.
* Added a checkbox to the Custom Fields page to control if each field appears on the List Virtual Servers page.
* Records can now be manually edited by the master admin on the DNS Records page, in BIND record format.
* Added support for spam and virus filtering offloading to the Cloudmin Services page.
* Comments are now shown and can be edited on the DNS Records page.
* Added a script installer for WHMCS 4.4.2. This is a commerical product, so you will need to purchase a licence for it before using the installer though.
* Updated the bbPress script installer to version 1.0.3, ZenPhoto to 1.4.0.4, Joomla to 1.6.3, Zikula to 1.2.6, SugarCRM to 6.1.3, FengOffice to 1.7.4, CMS Made Simple to 1.9.4.1, Nucleus to 3.64, SugarCRM to 6.2.0beta, phpMyAdmin to 3.3.10, Piwik to 1.4, Django to 1.3, TextPattern to 4.4.0, Dolibarr to 3.0.0, Joomla to 1.5.23, WordPress to 3.1.2, Mantis to 1.2.5, Rails to 3.0.6, Z-push to 1.5.2, MediaWiki to 1.16.5, Roundcube to 0.5.2, FosWiki to 1.1.3, Magento to 1.5.1.0, TWiki to 5.0.2, and Redmine to 1.1.3.

#### Version 3.83
* Added the Clone Virtual Server page to duplicate an existing domain, and the clone-domain API command.
* Added $WEBMIN_PORT, $WEBMIN_PROTO, $USERMIN_PORT and $USERMIN_PROTO template variables.
* Removed the restriction on database names that start with a number, for MySQL.
* Added the get-command API operation to fetch the parameters of another API command, for use by authors of higher-level APIs. Also updated the list-commands operation to make its output more parsable.
* Added the scheduled validation tab to the Validate Virtual Servers page, for setting up automatic email notification when Virtualmin detects problems with the configuration of any server, or the global configuration.
* Removed the 'Domain *' directive from the DKIM configuration, which was breaking signing for domains other than those hosted by Virtualmin (such as email from cron).
* The create-domain API command now lets you set a custom group name for a new virtual server with the C<--group> flag. If a custom username is set, the group name defaults to matching it.
* When adding an IPv6 address to a virtual server, an reverse DNS entry for the IP is also created if the IPv6 reverse zone is hosted on the Virtualmin system.
* Email to users that are with 100 kB of their quota is now bounced back to the sender, to prevent the mailbox from completely filling up and breaking Dovecot's avility to delete messages.
* Email to users that are with 100 kB of their quota is now bounced back to the sender, to prevent the mailbox from completely filling up and breaking Dovecot's avility to delete messages
* Updated the Redmine script installer to version 1.1.1, Z-push to 1.5.1, DokuWiki to 2010-11-07a, ZenPhoto to 1.4.0.2, Zikula to 1.2.5, Bugzilla to 3.6.4, phpMyFAQ to 2.6.15, Trac to 0.12.2, MediaWiki to 1.16.2, PHPList to 2.11.6, Joomla to 1.6.0, CMS Made Simple to 1.9.3, Wordpress to 3.1, Drupal to 7.0, phpMyAdmin to 2.11.11.3 and 3.3.9.2, Django to 1.2.5, Roundcube to 0.5.1, PHPList to 2.10.13, Magento to 1.5.0.1, SMF to 1.1.13, eGroupware to 1.8.001.20110216, Moodle to 2.0.2, Nucleus to 3.63, Piwik to 1.2, and SugarCRM to 6.1.2.

#### Version 3.82
* MySQL logins and databases and DNS zones can now be created on a central Cloudmin provisioning server, instead of on the Virtualmin system. This allows Virtualmin to be run on a system with less RAM, disk and CPU, while still providing the same functionality.
* Added a field to the DKIM form for entering additional domains to sign email for, even if they are not hosted on the system.
* German translation updates, thanks to Thomas Suess.
* When a virtual server's plan is changed on the Edit Virtual Server page, quotas are also updated to match those from the plan.
* Improved support for backing up to and restoring from IPv6 SSH and FTP servers.
* Added a link to the Mail Aliases page to also show normally hidden internal aliases, such as those for Mailman and spam traps.
* When creating a virtual server with the create-domain API command, custom fields can be set with the --field-name flag.
* Updated the Bugzilla script installer to version 3.6.3, Joomla to 1.5.22, TextPattern to 4.3.0, Dokuwiki to 2010-11-07, CMS Made Simple to 1.9.2, Z-push to 1.4.3, Dotproject to 2.1.4, phpBB to 3.0.8, Wordpress MU to 3.0.4, Horde Webmail to 1.2.9, Horde to 3.3.11, Moodle to 2.0.1, Foswiki to 1.1.2, Redmine to 1.0.5, phpMyAdmin to 3.3.9 and 2.11.11.1, phpPgAdmin to 5.0.2, Wordpress to 3.0.4, PHProjekt to 6.0.5, FengOffice to 1.7.3.1, Movable Type to 5.04, DaDaBiK to 4.3, Mantis to 1.2.4, Drupal to 6.20, Magento to 1.4.2.0, Nucleus to 3.62, Roundcube to 0.5-rc, Django to 1.2.4, SugarCRM to 6.1.0, vTigerCRM to 5.2.1, Piwik to 1.1.1, ZenPhoto to 1.4, dotProject to 2.5.1, MediaWiki to 1.16.1, and phpMyFAQ to 2.6.13.

#### Version 3.81
* Added byte quota sizes to the list-domains, list-users and list-resellers API calls, which are easier for code to parse.
* Fixed DKIM support to handle large numbers of domains.
* When Webalizer is enabled for a domain, allowed users for the /stats URL path can now be edited on the Protected Web Directories page.
* The maximum message size to check for spam can now be set even when regular spamassassin is used, as well as when using spamc.
* Virtual server backups can now be to multiple destinations, both local and remote. The time-consuming process of compressing each domain is done only once, and the resulting file then transferred to each destination.
* Updated the Trac script installer to version 0.12.1, Instiki to 0.19.1, Rails to 3.0.1, phpMyAdmin to 3.3.8, Moodle to 1.9.10, Horde Webmail to 1.2.8, Horde to 3.3.10, IMP to 4.3.8, ZenCart to 1.3.9h, SugarCRM to 6.0.3, Redmine to 1.0.3, SMF to 1.1.12, osCommerce to 2.3, and TWiki to 5.0.1.
* Added a template option to specify file types to not perform variable substitution on when copying from the /etc/skel directory.

#### Version 3.80
* Added an Italian translation, thanks to Andrea Di Mario.
* New virtual servers with an SSL website and status monitoring enabled will now also have the expiry date of their SSL certificate checked, to give advance warning when a cert is about to expire.
* DKIM signing of outgoing email can now be enabled on the new DomainKeys Identified Mail page. This also configures verification of signatures on incoming email.
* Added links to the Manage SSL Certificate page to download the key in PEM or PKCS12 format.
* When Virtualmin sends a backup to an SSH or FTP destination, it now also creates a .info file that contains meta-infomation about each backup. When restoring only this file needs to be downloaded to list the contents of a backup, which avoids the need to download the complete backup twice.
* The database username and password for a domain can now be changed using the new API commands modify-database-user and modify-database-pass.
* Added a server template option to not change the MySQL username when a domain's administration username is changed, and fixed bugs with a similar option for the MySQL password.
* Moved all IP-address related options from the Edit Virtual Server page to the Change IP Address page, where they fit in better and are easier to understand.
* Parallel bzip2 can now be used for backups if the pbzip2 command is installed, via a new option on the Virtualmin Configuration page.
* Updated the Horde Webmail installer to version 1.2.7, Horde to 3.3.9, and all its components to their latest versions.
* Renamed the OpenGoo script installer to Feng Office, and updated to version 1.7.2.
* Updated the Drupal script installer to versions 5.23 and 6.19, phpMyAdmin to 2.11.11 and 3.3.7, CMS Made Simple to 1.8.2, Z-push to 1.4.2, Webcalendar to 1.2.3, ZenCart to 1.3.9f, SugarCRM to 6.0.2, Zikula to 1.2.4, Redmine to 1.0.2, Piwik to 1.0, Zenphoto to 1.3.1.2, phpMyFAQ to 2.6.9, OpenX to 2.8.7, FOSwiki to 1.0.10, Django to 1.2.3, Movable Type to 5.031, Mantis to 1.2.3, eGroupware to 1.8.001.20100929, Roundcube to 0.4.2, Instiki to 0.19, Dolibarr to 2.9.0, Joomla to 1.5.21, and PHProjekt to 6.0.4.

#### Version 3.79
* The interval between bandwidth monitoring cron job runs can now be configured.
* Internationalized domain names are no longer converted to UTF-8 for output from API commands, to avoid the perl "wide character in print" warning.
* S3 backups can now be use the new reduced redundancy storage option, which is cheaper but less reliable.
* Alias domain DNS records are now copied from the target domain at creation time, rather than being created from the selected template.
* Updated the ZenCart script installer to version 1.3.9e, Coppermine to 1.5.8, MoinMoin to 1.8.8, Moodle to 1.9.9, Magento to 1.4.1.1, Trac to 0.12, Z-Push to 1.4, WordPress to 3.0.1, SugarCRM to 6.0.0, Piwik to 0.9, Simple Invoices to 2010.2-update1, Bugzilla to 3.6.2, Radiant to 0.9.1, phpMyFAQ to 2.6.7, phpMyAdmin 3.3.5, Redmine to 1.0.0, CMS Made Simple to 1.8.1, PHPList to 2.11.5, Joomla to 1.5.20, Instiki to 0.18.1, Squirrelmail to 1.4.21, Typo to 5.5, MediaWiki to 1.16.0, Mantis to 1.2.2, RoundCube to 0.4, phpBB to 3.0.7-PL1, ZenPhoto to 1.3.1, and TikiWiki to 4.3.

#### Version 3.78
* The website documents directory for a virtual server can be changed from public_html on the Website Options page, and using the modify-web API command.
* Added an option to the Magento script installer to setup sample data.
* Added options to the Module Config page for defining a link to additional documentation on the System Information page.
* Added a script installer for Foswiki, a TWiki fork.
* Updated the phpMyAdmin script installer to version 3.3.3, Zikula to 1.2.3, ZenCart to 1.3.9b, Zpush to 1.3, Mantis to 1.2.1, PHPlist to 2.10.12, Joomla to 1.5.18, Radiant to 0.8.2, Horde to 3.3.7, Horde Webmail to 1.2.6, CMS Made Simple to 1.7.1, Redmine to 0.9.4, Piwik to 0.6.2, Dolibarr to 2.8.1, SugarCRM to 5.5.2, Movable Type to 5.02, Django to 1.2.1, ZenCart to 1.3.9c, PHProjekt to 6.0.2, Coppermine to 1.4.27, Rails to 2.3.8, MediaWiki to 1.15.4, ZenPhoto to 1.3, TWiki to 5.0.0, Drupal to 6.17, and BugZilla to 3.6. Also updated all Horde applications to their latest versions.

#### Version 3.77
* The modify-dns API command can now add and remove slave DNS servers for virtual servers.
* Added the New Feature Log page, for showing all major changes in previous Virtualmin versions.
* Quotas are now disabled before importing a migrated database and re-enabled afterwards, to prevent quota issues from breaking the import process.
* Added user%domain as an option Unix username format.
* Domain owners can now be prevented from using the Website Redirects page via a new edit capability restriction.
* Added the get-ssl API command to output information about a virtual server's SSL certificate.
* Added fields to the Website Options page for changing the Apache log file locations, and added flags to the modify-web API command to do the same thing.
* Resellers now have access to the DNS records and Apache logs for virtual servers they own.
* Backups can now be restored from uploaded file, using a new source option on the restore form.
* Added the --simple-multiline flag to the list-domains API command, for outputting most of the information about virtual servers significantly faster.
* Added a plan and domain-owner level restriction to prevent creation of virtual servers under other user's domains.
* Updated the osTicket script installer to version 1.6.0, MoinMoin to 1.8.7, Magento to 1.4.0.1, Zikula to 1.2.2, Redmine to 0.9.3, phpScheduleIt to 1.2.12, ZenPhoto to 1.2.9, phpBB to 3.0.7, Typo3 to 4.3.3, Mantis to 1.2.0, CMS Made Simple to 1.6.7, TikiWiki to 4.2, OpenX to 2.8.5, Drupal to 6.16 and 5.22, phpMyAdmin to 3.3.1, Bugzilla to 3.4.6, MediaWiki to 1.15.3, SquirrelMail to 1.4.20, eGroupWare to 1.6.003, SugarCRM to 5.5.1, Trac to 0.11.7, PiWik to 0.5.5, PHProjekt to 6.0.1, CMS Made Simple to 1.7, Moodle to 1.9.8, Dolibarr to 2.8.0, phpPgAdmin to 4.2.3, PHPList to 2.11.3, WebCalendar to 1.2.1, Z-Push to 1.2.3, and WordPress and WordPress MU to 2.9.2.
* FTP backup transfers are now re-tried up to 3 times, configurable on the Module Config page.

#### Version 3.76
* Separated the creation of a CSR from a self-signed certificate on the Manage SSL Certificate page.
* Added a field to the backup form as the backup-domain API command to exclude some files from each domain's backup.
* When lowering a virtual server's disk quota below the current usage a warning is displayed asking the user if they really wants to do that.
* Added a 'status' section to the 'info' API command, to get the collected status of servers like Apache and BIND.
* Added the Website Redirects page, for easily creating aliases from URL paths to directories, and redirects from URL paths to other websites.
* The MySQL default collation order for new databases can now be set on the database creation form, and in the MySQL section of a server template.
* Added buttons to enable or disable multiple resellers at once.
* Added a Module Config option under Defaults for new domains to set the characters which random passwords are made up of.
* Added --autoreply-start, --autoreply-end and --autoreply-period flags to the modify-user API command, for changing other autoresponder settings.
* Changed statistics graphs to show load average in the regular scale, instead of converted to a percentage.
* Fixed the backup and restore for alias websites, which were previously not always restored correctly.
* Updated the Plans script installer to version 8.2, Dolibarr to 2.7.1, LimeSurvey to 1.87, DokuWiki to 2009-12-25c, OpenX to 2.8.4, phpMyFAQ to 2.5.7, WordPress and WordPress MU to 2.9.1.1, SimpleInvoices to 2010.1, Movable Type to 5.01, phpMyAdmin to 3.2.5, Typo3 to 4.3.1, TikiWiki to 3.4, Zikula to 1.2.1, Redmine to 0.9.1, Bugzilla to 3.4.5, Coppermine to 1.4.26, and ZenPhoto to 1.2.8.

#### Version 3.75
* Backups and restores to and from S3 sub-directories are now supported.
* When a mailbox user is created, make their spam, virus and trash directories under Maildir so that they show up in the IMAP folder list by default.
* If Apache supports SNI, make the warning about clashing certs less dramatic.
* Added Module Config options to limit the number of concurrent backups, which defaults to 3. This prevents system owners from overloading the machine with their scheduled backups.
* Backups and restores made by domain owners are now included in their bandwidth usage.
* When moving a virtual server, update the paths in the script logs DB to match the new location.
* Disk quota monitoring now has an option to send email to mailboxes who are over quota.
* Added a DNS template option to control if an NS record is added for the Virtualmin system.
* Added the --passfile flag to all domain, user, reseller and extra admin creation and modification commands, for reading the password from a file so it doesn't show up in ps output.
* Added a script installer for the Dolibarr ERP/CRM package, thanks to Regis Houssin.
* Also updated all Horde scripts to their latest versions.
* Updated the Plans script installer to version 8.1.6, Wordpress to 2.9, Wordpress MU to 2.8.6, redmine to 0.8.7, Bugzilla to 3.4.4, Moodle to 1.9.7, Rails to 2.3.5, Trac to 0.11.6, SMF to 1.1.11, ZenPhoto to 1.2.7, phpMyAdmin to 3.2.4 and 2.11.10, SugarCRM to 5.5.0, Typo3 to 4.3.0, dotProject to 2.1.3, Plans to 8.1.8, MoinMoin to 1.8.6, OpenGoo to 1.6, PiWik to 0.5.4, Drupal to 6.15 and 5.21, Gallery to 2.3.1, phpBB to 3.0.6, and Nucleus to 3.51.

#### Version 3.74
* Added a Module Config option to always show output from pre and post virtual server creation commands.
* Concurrent backups to the same destination are now no longer allowed, due to the potential for corruption and odd partial failures.
* Script version upgrades that are completely un-supported (like Jooma 1.0 to 1.5) are now no longer displayed in Virtualmin.
* The Manage SSL Certificate page can now be used to copy a domain's cert and key to Dovecot or Postfix.
* Added the import-database API command, for associating an existing un-owned database with a domain.
* When restoring a virtual server with a php.ini file whose extension directory is incorrect, fix it to match this system if possible.
* Added a logrotate template-level option for additional files to rotate for new domains.
* Added the list-php-ini API command for fetching PHP settings from one or more domains.
* Added a Module Config setting to make collection of all available packages optional.
* When a mailbox user is delete, their Dovecot index and control files are removed too in order to avoid clashes with future users with the same name.
* When a virtual server is disabled, all extra admin logins are disabled too.
* When a sub-server is converted to a top-level server, files from /etc/skel are copied into its home directory.
* Added a domain owner level capability restriction to prevent editing of external IP addresses.
* Updated the phpMyAdmin script installer to versions 3.2.3 and 2.11.9.6, OpenX to 2.8.2, PiWik to 0.4.5, Moodle to 1.9.6, WordPress to 2.8.5, Typo3 to 4.2.10, SugarCRM to 5.2.0k, TikiWiki to 3.3, WordPress MU to 2.8.5.2, Redmine to 0.8.6, Joomla to 1.5.15, Zikula to 1.2.0, Bugzilla to 3.4.3, and Plans to 8.1.6.

#### Version 3.73
* Removed the 'Bring up virtual interfaces?' module configuration option, as use of an existing interface can now be done on a per-domain basis.
* Added a button on the Edit Reseller page to clone their settings for a new reseller.
* Fixed a bug that prevented paths in php.ini from being updated when a domain is renamed or moved.
* Added a DNS template option to control which A records are added to new domains.
* Extra administrators can now change their own passwords, via a new link on the left menu.
* Resellers can be denied access to plans using the Edit Reseller page, or via the modify-reseller API call.
* Added validation to prevent SSL from being enabled on a virtual server with an invalid certificate or key.
* Added the modify-php-ini API command to update PHP variables in one or more virtual servers at once.
* Updated the French translation, thanks to Houssin Regis.
* The contents of mailboxes from Windows Plesk backups are now properly migrated.
* Added options to the Module Config page for selecting which columns appear on the List Virtual Servers page, including new ones like the reseller, email address and extra admins.
* Added a warning to the configuration check for systems behind a NAT gateway with an incorrectly configured DNS IP address.
* Additional allowed MySQL client hosts are now included in backups.
* If Postfix relay domains are stored in a hash, update it instead of adding to relay_domains in /etc/postfix/main.cf.
* Added a script installer for the eXtplorer AJAX file manager, version 2.0.1.
* Updated Horde to version 3.3.4, and all sub-applications to their latest versions.
* Updated the Horde Passwd script installer to h3-3.1.1, PHPCoin to 1.6.5, OpenGoo to 1.5.3, LimeSurvey to 1.85plus-build7561-20090902, TextPattern to 4.2.0, CMS Made Simple to 1.6.6, phpMyFAQ to 2.0.17, TWiki to 4.3.2, Rails to 2.3.4, Radiant to 0.8.1, MoinMoin to 1.8.5, SugarCRM to 5.2.0j, Bugzilla to 3.4.2, phpMyAdmin to 3.2.2, Roundcube to 0.3-stable, Redmine to 0.8.5, Drupal to 6.14 and 5.20, Nucleus to 3.50, Magento to 1.3.2.4, Typo3 to 4.2.9, Movable Type to 4.32, TikiWiki to 3.2, Simple Invoices to 2009.1, Django to 1.1.1, and Plans to 8.1.4.

#### Version 3.72
* Put back support for installing Joomla 1.0 series versions.
* Added a domain-owner leven restriction to prevent changing of a virtual server's password.
* Script installer versions more recent that those included with the current release of Virtualmin can now be downloaded using the Installer Updates section on the Script Installers page. The new versions will typically be released within hours or days of new script releases.
* On Sendmail systems with outgoing address mapping enabled, the generic domains file is now correctly updated.
* Updated the Plans script installer to 8.0.4, and Movable Type to 4.31.

#### Version 3.71
* Added a bandwidth monitoring option to include relayed email, thanks to Collin from Bisnet.
* When editing default scripts in a template, an option to always install the latest version is now available.
* If a single database backup for a virtual server fails, others will still be backed up.
* Added validation for incorrect suEXEC Apache directives.
* Deprecated the feature to write logs via a program, as logging to /var/log/virtualmin is now the default.
* Added support for JSON, XML and Perl output to the remote API, enabled with the json=1, xml=1 or perl=1 URL parameters.
* Removed support for Joomla 1.0 series versions.
* Added security patches for the 1.3.8 version to the Zencart installer.
* Updated the bbPress script installer to 1.0.2, SugarCRM to 5.2.0h, Bugzilla to 3.4.1, Roundcube to 0.3-RC1, Joomla to 1.5.14, Wordpress to 2.8.4, Wordpress MU to 2.8.4a, Django to 1.1, OpenGoo to 1.5.1, CMS Made Simple to 1.6.3, ZenCart to 1.3.8a, phpMyAdmin to 3.2.1, LimeSurvey to 1.85plus-build7435-20090810, PiWik to 0.4.3, ZenPhoto to 1.2.6, phpMyFAQ to 2.0.16, SugarCRM to 5.2.0i, and PHPCoin to 1.6.3.

#### Version 3.70
* Added the license-info API command for getting the serial number and domain counts for the current Virtualmin install.
* When a virtual server is restored from a backup, the pre and post-change commands are called with $VIRTUALSERVER_ACTION set to RESTORE_DOMAIN.
* Corrected a mis-feature that prevented alias virtual servers with no home directory from being backed up in the new format.
* Added an option to the backup form for selecting virtual servers by plan. Also added the --plan flag to the backup-domains command.
* Updated the Zpush script installer to 1.2.2, Bugzilla to 3.2.4, Wordpress to 2.8.2, Wordpress MU to 2.8.2, Typo3 to 4.2.8, Trac to 0.11.5, MediaWiki to 1.15.1, SMF to 1.1.10, Zikula to 1.1.2, Rails to 2.3.3, Joomla to 1.5.13, Piwik to 0.4.2, Magento to 1.3.2.3, eGroupware to 1.6.002, CMS Made Simple to 1.6.1, MT to 4.3, eGroupware to 1.8.005, and bbPress to 1.0.1.

#### Version 3.69
* Updated all code that reads or writes to files in a virtual server's home directory to operate with the user's permissions, which prevents use of malicious links to access root-owned files.
* Changed the Squirrelmail script installer to use the new set_user_data plugin via Ian Goldstein, which allows login by email address and sets the from address correctly by default.
* LXadmin backups can now be migrated into Virtualmin servers, preserving web content, databases, mailboxes and mail aliases.
* Added a template option to disable addition of also-notify and allow-transfer blocks to new DNS domains.
* Added support for migrating cPanel addon domains properly.
* When a virtual server is disabled for exceeding its bandwidth limits, all sub-servers will be too. Similarly, they will be re-enabled if the server falls below its limit.
* Email to domain owners on virtual server creation can now include variables like $PLAN_NAME, $RESELLER_NAME and $PARENT_DOM.
* Moved the settings for which Webmin modules are available to virtual server owners from the Module Config page to a new section in server templates, so that it can be adjusted on a per-template basis.
* Extra administrators can now be limited to a subset of the parent servers domains, either from the Edit Extra Administator page or using the command-line API.
* Historic statistics graphs can now be plotted on a log scale, and both axis are used if multiple values are plotted.
* Added the Convert Alias Server page to change an existing alias virtual server into a sub-server.
* The email to mailboxes who are approaching or over quota can now be customized on the Disk Quota Monitoring page.
* Partially completed backups (where only some domains failed) are now shown in the backup logs.
* Bandwidth usage by date or month can now be graphed for sub-servers.
* Added a script installer for eGroupWare 1.6.001.
* Updated the Piwik script installer to 0.4.1, Redmine to 0.8.4, SMF to 1.1.9, OpenGoo to 1.4.2, Squirrelmail to 1.4.19, Coppermine to 1.4.25, Magento to 1.3.2.1, phpMyFAQ to 2.0.15, DokuWiki to 2009-02-14b, OpenX to 2.8.1, phpBB to 3.0.5, TikiWiki to 3.1, Joomla to 1.5.12, Zenphoto to 1.2.5, bbPress to 1.0, phpCOIN to 1.6.2, Mantis to 1.1.8, WordPress to 2.8, MediaWiki to 1.15.0, Movable Type to 4.261, SugarCRM to 5.2.0f, MoinMoin to 1.8.4, Instiki to 0.17, Radiant to 0.8.0, CMS Made Simple to 1.6, osTicket to 1.6rc5, Magento to 1.3.2.2, Drupal to 5.19 and 6.13, Trac to 0.11.5rc1, and phpMyAdmin to 3.2.0.1.

#### Version 3.68
* Moved the option for a secondary group for domain owners to the template level.
* Added a field to the script upgrade notification to limit warnings to only some virtual servers, or to exclude servers.
* All backups made manually, on schedule or from the command line are now logged, and can be viewed using the new Backup Logs page.
* Netmasks can now be optionally specified for IP allocation ranges, rather than being always inherited from the primary interface's netmask.
* ClamAV's server scanner clamd can now be enabled on FreeBSD from within Virtualmin.
* After Virtualmin is installed and the master administrator logs in for the first time, a wizard allowing basic configuration of memory and speed tradeoffs will be displayed. This allows the system to be tuned for web, mail or database hosting, depending on how the admin intends it to be used.
* SpamAssassin's server filter spamd can now be activated from within Virtualmin, using a new button on the Spam and Virus Scanning page. You can also turn it on with the --enable-spamd flag to the set-spam API script.
* Added CPU and hard drive temperatures to the System Statistics page.
* Added buttons to the Manage SSL Certificate page to copy a domain's cert and key to Webmin or Usermin.
* Added a script installer for Redmine 0.8.3, thanks to Nick Orr.
* Updated the Nag script installer to version 2.3.2, phpMyFAQ to 2.0.13, Wordpress MU to 2.7.1, SugarCRM to 5.2.0e, phpMyAdmin to 3.1.4, MoinMoin to 1.8.3, TWiki to 4.3.1, Coppermine to 1.4.22, Drupal to 6.11/5.17, Flyspray to 0.9.9.6, Horde to 3.3.4, Horde Webmail to 1.2.3, phpList to 2.10.10, phpCOIN to 1.6.1, SquirrelMail to 1.4.18, Instiki to 0.16.6, Piwik to 0.2.35, Moodle to 1.9.5, and Mantis to 1.1.7.

#### Version 3.67
* Added the --purge and --strftime flags to backup-domain.pl, to allow automatic deletion of old backups and date-based backup destinations.
* Virtual servers can now have IPv6 addresses in addition to v4, on Debian, Ubuntu, Redhat, CentOS and Fedora systems. Virtualmin will configure BIND to add IPv6 address records, and Apache to accept connections to the IPv6 address. All pages that API commands that deal with addresses have new fields and options for an optional IPv6 address.
* Added --reseller, --no-reseller and --any-reseller flags to list-domains.pl.
* Parent virtual server details are now available in sub-server post-creation scripts in the $PARENT_VIRTUALSERVER_ environment variables.
* Added a field on the Website Options page for making a virtual server the default website for its IP address.
* When creating a sub-server that is a sub-domain of it's parent, DNS records for the new domain will be added to the parent's zone.
* Made the Website Options page available to domain owners, although only with limited fields available.
* Added the --no-alias flag to list-domains.pl, to show non-alias domains.
* Greylisting using Postgrey can now be setup using Virtualmin, via the new Email Greylisting page. In addition, whitelists for SMTP servers and email recipents can be managed.
* Added a Module Config option to control if default features come from plan or Features and Plugins page.
* Added a --plan flag to modify-reseller.pl, to allow setting of limits from a plan.
* Made the docutils Python module optional for MoinMoin installs, as it is missing on CentOS.
* Added the SSH server status to the System Information page, including the ability to stop and start it.
* Global template variables are now also available to pre- and post-domain creation commands, with the GLOBAL_ prefix.
* Added a script installer for Simple Invoices.
* Updated the Forwards, Passwd, Chora, Vacation and Gollem scripts from the Horde family to their latest versions.
* Updated the phpMyAdmin script installer to versions 3.1.3.2 and 2.11.9.5, OpenGoo to 1.3.1, Joomla to 1.5.10, Mantis to 1.1.6, Typo to 5.3, Django to 1.0.2, Zenphoto to 1.2.4, Twiki to 4.3.0, Bugzilla to 3.2.3, Magento to 1.3.1, OpenX to 2.8.0, PHPCoin to 1.6.0, PiWiki to 0.2.34, TikiWiki to 2.4, CMS Made Simple to 1.5.4, and Trac to 0.11.4.

#### Version 3.66
* Overall network traffic is now collected regularly, and can be displayed on the System Statistics page.
* Added a Module Config option to disallow switching to Usermin as a mailbox user by domain owners.
* Added an option on the Batch Create Users page to generate passwords randomly, and a --random-pass flag to create-user.pl.
* Added option to not add MX records for secondary mail servers.
* Link script names to their home pages.
* Added the --plan flag to the create-reseller API command, to copy limits from a plan.
* Allowed script installers can now be set at the plan level and on the Edit Owner Limits page. They can also be set on the command line with create-plan, modify-plan and modify-limits commands.
* Added support for migrating Plesk 9 backups, which have a different format to Plesk 7 and 8.
* Converted libraries to use Webmin's new WebminCore module, where available. This leads to a signficant improvement in memory use and speed.
* Re-factored code for deleting tables created by installed scripts, and better handle the case where a script's database is missing.
* Added a Module Config option for additional gzip command-line parameters, like --best or --rsyncable.
* Added a button to the Edit Account Plan page to create a new plan cloned from an existing one.
* Added --email-only flags to the list-users.pl and list-domains.pl API scripts.
* If a plan specifies features to be granted to domain owners, those features will be enabled on the Create Virtual Server page when the plan is selected. Otherwise, defaults set on the Features and Plugins page will be used.
* Mail files are now always included in backups and restores, even when under /var/mail.
* Added a Module Config option for an alternate command to use when moving a virtual server's home directory, instead of mv.
* The bandwidth limit and using variables in all email templates (BW_LIMIT and BW_USAGE) are now formatted in MB or GB, instead of just being a number of bytes.
* Updated the Drupal script installer to version 6.10, but only for upgrades.
* Added a script installer for Typo3 CMS, version 4.2.6.
* Added an installer for Vtiger CRM, version 5.0.4.
* Added a script installer for CMS Made Simple, version 1.5.3.
* Added an option to download the all-languages version of phpMyAdmin.
* Updated the DokuWiki script installer to version 2009-02-14, Radiant to 0.7.1, Trac to 0.11.4rc1, OpenGoo to 1.3, phpMyFAQ to 2.0.12, Piwik to 0.2.32, phpScheduleIt to 1.2.11, MediaWiki to 1.14.0, phpWebsite to 1.6.1, Magento to 1.2.1.2, Instiki to 0.16.5, Drupal to 5.16, phpMyAdmin to 3.1.3, Movable Type to 4.25, Mambo to 4.6.5, CopperMine to 1.4.21, Rails to 2.3.2, TikiWiki to 2.3, SugarCRM to 5.2.0c, and Nucleus to 3.41. Removed old phpMyAdmin versions, which are no longer available.

#### Version 3.65
* The master admin can select a reseller to own a new top-level virtual server when it is created.
* Extracted all settings related to default quotas and limits from templates, and moved them into the new Account Plan objects. These can be created by both the master admin and resellers, and selected for new or existing virtual servers. Also added a command-line API for plan management.
* Added an option for email-based ticket submission to the eTicket installer.
* Added a Module Config field under Advanced options for specifying the path to an alternate tar command.
* Backups and restores to S3 buckets in Europe are now fully supported.
* Added an option to the Script Installers page to deny access to new script types by default.
* Added commands to be run before and after scheduled backups, settable on the Edit Scheduled Backup page.
* The default TTL for DNS domains (set using the $ttl line in the zone file) can now be configured in server templates.
* Moved the --dns-ip and --no-dns-ip options from the modify-dns.pl API script to modify-domain.pl and create-domain.pl.
* Moved the field for setting the external IP address (typically for use in DNS records) from the DNS Options page to Edit Virtual Server.
* External web, DNS and mail connectivity for virtual servers can now be checked by Virtualmin, to diagnose common networking and configuration problems.
* Added the get-dns.pl command-line script to dump DNS records for a virtual server.
* Add parameters to the modify-dns.pl command-line API to add and remove DNS records for multiple domains at once.
* When a domain is restore on a system with a different Apache log file location, its virtualhost is updated to use the target system's paths.
* Automatic spam and virus folder clearing now respects custom folder names.
* Links to per-domain SpamAssassin configurations now include the domain's config file, which allows each domain's settings to be separately managed.
* Added the info.pl command line script, for dumping general information about Virtualmin.
* Updated the phpMyAdmin script installer to version 3.1.2, TextPattern to 4.0.8, Magento to 1.2.1, Typo to 5.2, Moodle to 1.9.4 and 1.7.7, phpList to 2.10.9, SugarCRM to 5.2.0a, WordPress MU to 2.7, Wordpress to 2.7.1, Horde Webmail to 1.2.2, Horde to 3.3.3, IMP to 4.3.3, OpenX to 2.6.4, ZenPhoto to 1.2.3, Zikula to 1.1.1, Coppermine to 1.4.20, SMF to 1.1.8, MediaWiki to 1.13.4, Radiant to 0.7.0, Bugzilla to 3.2.2, MoinMoin to 1.8.2, PiWik to 0.2.29, and phpMyFAQ to 2.0.11.
* Added API commands to create, modify, delete and extract settings from virtual server templates.

#### Version 3.64
* Directories containing initial files for virtual servers (like /etc/skel) are now included in Virtualmin template backups.
* Plugins can now export content styles, allowing multiple styles to be easily installed from a single separate plugin.
* Added a script installer for Horde Webmail, version 1.2.1.
* Added a Module Config option to have down services automatically restarted by the regular status collection job.
* The Disk Quota Monitoring page can now also be used to find mailboxes that are approaching or over their quota, and can send email to domain owners and individual mailboxes as well as the master admin.
* For new Virtualmin installs, Apache logs are now stored under /var/log/virtualmin and just linked from the ~/logs directory. This avoids problems with Apache crashing when the logs directory is deleted.
* The delete-domain.pl command-line script now accepts multiple --domain parameters, and can also delete virtual servers by username with the --user parameter.
* Added an option on the Spam and Virus Delivery page to enable spamtrap and hamtrap aliases on a per-domain level, to which spam and non-spam can be forwarded by users for addition to SpamAssassin's learning engine. These can also be enabled for new domains in server templates, and changed using the modify-spam command-line API.
* Domain owners can now be granted permissions to edit the remote MySQL client hosts for the databases they manage.
* Added command-line scripts to list, generate and install SSL keys and certificates. These are list-certs.pl, generate-cert.pl and install-cert.pl respectively.
* When a virtual server with a self-signed SSL certificate is renamed, the certificate is re-generated to match the new domain name.
* When alias virtual servers are created, files from /etc/skel are no longer copied into their home directories as they are not needed.
* Script update notification, quota and backup emails now contain a link to Virtualmin, using a URL configurable on the Module Config page.
* If a script like Wordpress has been upgraded outside of Virtualmin, it's new version will be detected to prevent false warnings about needing to upgrade.
* Added validation to the configuration check to detect MySQL or disk quota synchronization that conflicts with Virtualmin.
* Mail files are now included by default in backups made and restored using backup-domain.pl and restore-domain.pl. This can be disabled with the --no-mailfiles parameter.
* Added a script installer for phpMyFAQ version 2.0.10.
* Updated the PHPlist script installer to version 2.10.8, bbPress to 0.9.0.3, Wordpress to 2.7, Drupal to 6.9 and 5.15, Horde to 3.3.2, IMP to 4.3.2, Turba to 2.3.1, SugarCRM to 5.2.0, phpBB to 3.0.4, LimeSurvey to 1.72 and 1.80RC2, phpPgAdmin to 4.2.2, MediaWiki to 1.13.3, Zikula to 1.1.0, MoinMoin to 1.8.1, PHP-Calendar to 1.0, Piwik to 0.2.28, OpenGoo to 1.1, Magento to 1.2.0.2, RoundCube to 0.2-stable, PHPcoin to 1.5.1, bbPress to 0.9.0.4, Typo to 5.1.98, Joomla to 1.5.9, Zpush to 1.2.1, and phpMyAdmin to 3.1.1.

#### Version 3.63
* When submitting a new SSL certificate and key, they are checked to ensure a modulus match, ensuring that they were generated and can be used together.
* Virtual server backups can now be in ZIP format, by changing the 'Backup compression format' option on the Module Config page. TAR format is still recommended though, as it better preserves Unix filesystem attributes.
* Shared IP addresses can now be listed, added and removed from the command line using the new list-shared-addresses.pl, create-shared-address.pl and delete-shared-address.pl scripts.
* Added a checkbox to the Shared IP Addresses page to allocate a new shared IP, if allocation ranges have been defined.
* Email sent to domain owners is now properly encoded so that non-ASCII characters can be included.
* Added a DNS template option to have a DNSSEC key generated for new domains, and records automatically signed. Requires Webmin 1.443 or later though.
* Validation now checks that each domain's Unix user and group quotas match what Virtualmin expects.
* If the post-modification or creation script for a domain fails, its output is now displayed as an error message.
* Added a field to the Website Options page for setting the maximum run-time for PHP scripts.
* The CPU time resource limit can now be entered in seconds, rather than minutes. However, this will be rounded down to the nearest minute when applied to SSH logins, due to the format of the /etc/security/limits.conf file.
* Custom nameservers can now be defined for resellers, so that domains they create can appear to be hosted on a server separate from other resellers or the master admin.
* FTP directory restrictions can now be included in Virtualmin configuration backups.
* Domain owners can now restore from files under their virtualmin-backup directory, subject to regular Unix permissions.
* UCC certificates and CSRs can now be created and displayed on the Manage SSL Certificate page.
* Multiple virtual servers with SSL enabled can now share the same IP address. However, Virtualmin will display a warning message if a new domain does not match the hostname in the certificate for an existing domain.
* Added a check to ensure that the Webalizer template configuration file actually exists.
* Optimized the spam and virus deletion screen to deal better with large folders, by processing only 100 messages at a time.
* When a virtual server with slave DNS zones is disabled, then will be removed from slave servers to properly prevent DNS resolution of the domain. When it is re-enabled, the slave zones will be re-created.
* On systems running Postfix with spam filtering enabled, the ownership and permissions on the procmail wrapper command are validated as part of the configuration check to ensure that it is setuid and setgid to root.
* Added a script installer for OpenGoo 1.0, a web-based office suite.
* Updated the TikiWiki script installer to version 2.2, Mantis to 1.1.4, Drupal to 6.6 and 5.12, WordPress to 2.6.5, WPMU to 2.6.5, PHPCoin to 1.4.5, Rails to 2.1.2, PHPList to 2.10.7, phpMyAdmin to 3.1.0, SugarCRM to 5.1.0b, MoinMoin to 1.8.0, PiWik to 0.2.26, OpenX to 2.6.3, Bugzilla to 3.2, SMF to 1.1.7, Trac to 0.11.2.1, Joomla to 1.5.8, phpBB to 3.0.3, Moodle to 1.9.3, ZenPhoto to 1.2.2, Squirrelmail to 1.4.7, TextPattern to 4.0.7, Movable Type to 4.23, TWiki to 4.2.4, and Gallery to 2.3 and 1.5.10.

#### Version 3.62
* The clamd-stream-client virus scanner can be selected to offload the actual scanning process to clamd on a remote system, if you have it installed.
* SSL keys with passphrases can now be installed on the Manage SSL Certificate page, and trying to use a key that needs a passphrase without one being entered will display an error.
* Mail aliases that forward to all users in a domain can now be created, using the Edit Mail Aliases page or create-simple-alias.pl.
* Changed the meaning of the 'Can choose database names?' server owner restriction to just prevent modification of the domain's default database, instead of blocking all database management.
* When setting up clamd, the provided example init script is copied instead of bring modified, so that it can be safely replaced by RPM upgrades.
* Re-try S3 bucket creation three times if at first it fails, to avoid temporary outages or network problems.
* When the user or group for a domain is changed, references to the old user or group in lgorotate.conf are updated to the new values.
* The master administrator can now grant themselves access to scripts disabled for regular users, with a new form on the Script Installers page.
* Plugins can now define additional inputs to appear on the Create Virtual Server page and accepted by create-domain.pl, for options specific to the plugin's feature.
* Ensure that resource limits (CPU, RAM and procesess) are never set for the Apache user, even when it is a member of a domain's group for which limits are set.
* Added the --source parameter to list-available-scripts.pl, and include script source in full output.
* Updated the Horde installer to version 3.3, and all related applications to their corresponding latest versions.
* Updated the TWiki script installer to version 4.2.3, TikiWiki to 2.1, Squirrelmail to 1.4.16, WebCalendar to 1.2.0, WordPress MU to 2.6.2, Magento to 1.1.6, Gallery to 2.3-rc-2, MediaWiki to 1.13.2, ZenPhoto to 1.2.1, SugarCRM to 5.1.0a, OpenX to 2.6.2, osCommerce to 2.2rc2a, Drupal to 5.11/6.5, Mantis to 1.1.3, and phpMyAdmin to 2.11.9.2.

#### Version 3.61
* S3 backups to date-based filenames are now supported, and can be properly purged.
* Added a Module Config option to have only one spamassassin process run at a time.
* Added the notify-domains.pl command line script, for sending email to some or all virtual server owners.
* When MySQL is on a remote system, the 'show table status' command is used to get an approximate size for each database.
* On FreeBSD, the Gnu tar command gtar is used in preference to regular tar when installed. This allows differential backups to be performed.
* Added a button to the Edit Mailbox page for logging into Usermin as a user without having to enter their password. Requires Webmin 1.440 or later though.
* Included domains for SPF for new virtual servers can now be set in server templates.
* Resellers can now read mail in all mailboxes under domains they control, if allowed on the Module Config page under 'Extra modules'.
* The frequency of script update notifications and whether to send the same notification twice can now be configured on the Script Installers configuration page.
* Added a new sort mode (used by default for new installs) to order virtual servers by domain name, but with sub-servers indented under them.
* The configuration check now detects a missing or incorrect suexec, to easier find problems with the base directory that will break PHP and CGI scripts.
* Added a button to edit pages as text (without the HTML editor) to the Edit Web Pages feature.
* Updated the Nucleus script installer to version 3.33, Xoops to 2.0.18.2, SugarCRM to 5.1.0, OpenX to 2.6.1, phpMyAdmin to 2.11.9.1, phpPgAdmin to 4.2.1, WordPress MU to 2.6.1, Magento to 1.0.19870.6, Django to 1.0, MediaWiki to 1.13.1, SMF to 1.1.6, Z-push to 1.2, WordPress to 2.6.1, Joomla to 1.5.7, Horde to 3.2.2, Gallery to 1.5.9, Rails to 2.1.1, Radiant to 0.6.9, and Movable Type to 4.21.

#### Version 3.60
* Re-organized the custom links page to move editing of each link into a separate form, and allow links to be limited to virtual servers with some feature enabled.
* Preserve encrypted passwords when backing up domains, in case they don't match the plaintext password stored by Virtualmin. Also, have validation report an error in the case of a mismatch.
* When a domain is restored on a new system, the MySQL socket file path and options that reference the home directory in its php.ini file are updated to match the new system.
* If a backup is taken on a system that uses ~/mail for user folders and restored on one using ~/Maildir, they will be properly converted during the restore (and vice-versa).
* The Website Options page now has a field to enable matching all sub-domains for the virtual server's website, via a *.domain.com DNS entry and Apache server alias directive. This can also be enabled for some or all domains using the modify-web.pl command-line API.
* When a virtual server's IP address is changed, the addresses of all alias domains are updated to match.
* Backups now include any custom template used to create virtual servers, which allow domains to be restored even on systems that do not yet have the original templates.
* Custom links can be limited to virtual servers with a specific template if you have any custom templates defined, for more control over when each link is displayed.
* Added the --default-ip flag to modify-domain.pl, to revert to a shared IP address.
* Third-party content styles can now be deleted by the master admin from the Content Styles page.
* Added a Module Config option in the advanced section to change the path for the API helper command, and improved automatic selection of a path if the default directory /usr/sbin is not writable.
* Extra administrators can now have contact email addresses, which can be used when sending email to all domain owners. These can be set via the web interface, or the command-line API.
* When the virtualmin --help command is run, it now outputs a list of all available API commands with short descriptions, broken down into categories.
* Updated the Piwik script installer to version 0.2.9, phpCOIN to 1.4.4, Joomla to 1.5.6, phpMyAdmin to 2.11.8.1, dotProject to 2.1.2, SugarCRM to 5.0.0g, Wordpress MU 2.6, Gallery to 2.3-rc-1 and 1.5.8, TWiki to 4.2.2, Coppermine to 1.4.19, Trac to 0.11.1, Bugzilla to 3.2rc1, Movable Type to 4.2, Zikula to 1.0.2, WordPress to 2.6.1, MediaWiki to 1.13.0, Drupal to 5.10 and 6.4, TikiWiki to 2.0, and ZenPhoto to 1.2.

#### Version 3.59
* If the virus scanner fails to return a response within 30 seconds, email will be delivered normally. This avoids problems with the procmail timeout, which can cause even non-infected email to be dropped if clamav is too slow.
* Added the Global Variables page under the System Customization category, for creating variables that can be used in all templates.
* DNS aliases named 'webmail' and 'admin' are now created in all new virtual servers by default, and Apache is configured to redirect requests for them to Usermin and Webmin by default.
* Added a script installer for Z-push, which implements the Microsoft activesync protocol.
* The default limit on the number of non-alias domains can now be set in server templates.
* Included domains can now be specified when editing SPF information, and IP networks can be entered.
* Added a Module Config field for a custom command to get memory and swap information.
* Updated the Piwik script installer to version 0.2.5, ZenPhoto to 1.1.7, eTicket to 1.7.2, Joomla to 1.5.4, Drupal to 6.3 and 6.8, phpBB to 3.0.2, phpMyAdmin to 2.11.7.1, WordPress to 2.6, Zikula to 1.0.1, phpScheduleIt to 1.2.10, OpenX to 2.6.0, PiWik to 0.2.7, MoinMoin to 1.7.1, MediaWiki to 1.12.0 and HelpCenter to 2.1.7.

#### Version 3.58
* Purging of old backups made to FTP or SSH servers is now supported, for FTP servers that use Unix directory listings and SSH servers that allow commands to be run.
* Added the Virtualmin API helper command /usr/sbin/virtualmin, which lets you more easily call API scripts with a command like "virtualmin list-domains --multiline". Help on commands can also be displayed with like "virtualmin help list-domains".
* Converted all command-line API scripts to use POD format documentation.
* Additional manually configured nameservers can now be more easily entered in server templates, in the BIND DNS domain section.
* Move some rarely-used options to the Advanced section of the Module Config page.
* The bandwidth usage graphs can be restricted to showing just servers that are over their limits, using a new mode link.
* Added a complete Spanish translation, contributed by Ignacio.
* Allow the default shell to be set on a per-template basis.
* Added a script installer for Zikula, a new content management system written in PHP.
* Updated the Piwik script installer to version 0.2.3, Magento to 1.0.19870.4, PHPCoin to 1.4.3, Gallery to 2.2.5, Horde to 3.2.1, Turba to 2.2.1, Mantis to 1.1.2, SugarCRM to 5.0.0f, Movable Type to 4.12, OpenX to 2.4.7, phpScheduleIt to 1.2.9, phpMyAdmin to 2.11.7, and Trac to version 0.11rc2.
* Plesk 7 backups can now be migrated as Virtualmin domains, using a new backup file type on the migration page.
* The PHP modules and Pear modules available for each domain are now displayed on the Website Options page.

#### Version 3.57
* Old local file and S3 backups created using date-based filenames can now be automatically deleted if older than a selected number of days, configurable on the Scheduled Backups page.
* The remote hosts from which connections to MySQL are allowed can be easily edited on a per-domain basis on the Edit Databases page, in the new 'Remote hosts' tab. These apply to the domain owner and any mailboxes with database access. The modify-database-hosts.pl command can also be used to edit them from the shell or API.
* All text in the Virtualmin user interface is now available in Dutch, thanks to Gandyman.
* By default, new DNS zones only allow localhost, hosts on the local network and known slaves to transfer records.
* Completely re-designed the Virtualmin backup UI, to support multiple backup schedules and allow domain owners and resellers to schedule their own backups (subject to limits configured by the master administrator). Domain owners can now also restore backups of their home directories and databases. Backups can either be full or differential, to speed up the process of backing up large but infrequently-changing sites.
* Fixed support for international domain names using non-european character sets (like Chinese and Cyrillic) in newer versions of Perl.
* Improved the migration of Plesk mailbox aliases and forwarding, and protected directories.
* When a domain's home directory is changed, update session.save_path in its php.ini files to match.
* The $DNS_SERIAL variable can be used in templates, as an initial serial for new domains.
* Updated the Horde script installer to version 3.2, and all its associated sub-applications to their latest releases.
* Plesk sub-domains are now imported as Virtualmin sub-servers.
* All Virtualmin command-line and remote API programs now participate in Webmin logging, so their invocation and changes can be viewed in the Webmin Actions Log module.
* All new SSL certificate and key files how have 700 permissions, so that only the domain owner and Apache (which starts as root) can read them.
* If a migrated domain needs features that are not supported by the system, a warning message is displayed.
* Added links from the Status section of the System Information page to the Webmin modules for their particular servers, and additional stats where available.
* The number of email messages delivered per minute and the number classified as spam or viruses can now be graphed on the System Statistics page.
* Modified the 'View website via Webmin' feature to not munge offsite links, only those to the same domain.
* Updated the SugarCRM installer to 5.0.0e, ZenPhoto to 1.1.6, Magento to 1.0.19870.1, Squirrelmail to 1.4.15, Rails to 2.1.0, Radiant to 0.6.7, LimeSurvey to 1.71, Plans to 7.10, and Piwik to 0.2.2.
* Mailbox users' passwords are now shown in a separate popup window, rather than on the Edit Mailbox page where anyone can see them.

#### Version 3.56
* Added script installers for Trac and MoinMoin, contributed by Jannis Leidel.
* When scheduled backups are sent to their domain owners as well, each owner only receives the backup messages related to the domains they own.
* When a script has dependencies, all are checked and reported at once rather than being displayed one at a time. This makes complex applications like Rails easier to setup.
* Limits on the number of processes and amount of RAM and CPU time a process can use can be defined for each virtual server. These apply to CGI and PHP scripts, and when the domain owner logs in via SSH. They are particularly useful for preventing fork bombs and other intentional or accidental denial of service attacks.
* AddHandler, FCGIWrapper and RemoveHandler directives not related to PHP versions Virtualmin knows about are not touched when changing PHP settings.
* If MySQL or PostgreSQL have no root password set, display a warning during the configuration check.
* Post-change scripts have access to the settings of a virtual server before it was changed in the VIRTUALSERVER_OLDSERVER_* environment variables.
* Added a script installer for Piwik, an open-source web analytics tool.
* Updated the Drupal script installer to support version 6.2.
* Added a script installer for phpLedMailer 1.8, a simple single-mailing-list manager.
* Added an alias for /media/ in the Django installer, so that CSS and images used by the admin servlet appear.
* Updated the eTicket script installer to version 1.5.7, WordPress to 2.5.1, bbPress to 0.9.0.2, Kronolith to 2.1.8, phpMyAdmin to 2.11.6, Joomla 1.5.3, SMF to 1.1.5, Magento to 1.0.19870, phpCOIN to 1.4.2, DokuWiki to 2008-05-05, Bugzilla to 3.1.4, OpenX to 2.4.6, WordPress MU to 1.5.1, Django to 0.96.2, and SugarCRM to 5.0.0d.

#### Version 3.55
* For virtual servers using fcgid to run PHP scripts, the IPCCommTimeout is set to the PHP maximum execution time, to avoid long-running scripts not being able to send their output.
* Multiple warning thresholds and an interval between sending a notification for each domain can now be configured on the Disk Quota Monitoring page.
* By default, new virtual servers will no longer have the PHP_FCGI_CHILDREN environment variable set in the fCGI wrapper files. This avoids a PHP bug that causes stale php-cgi processes to be left running, but may slightly reduce the performance of PHP applications.
* Added a script installer for Django, a development framework for Python applications.
* Changed the content style chooser to display thumbnail images in the drop-down menu.
* When migrating backups from Postfix-style ~/Maildir inboxes to Sendmail-style /var/mail, mail files are properly copied across.
* The default PHP version for one or more virtual servers can be changed with --php-version option to modify-web.pl.
* Cpanel sub-domains are now re-created when migrating their backups.
* The Virtualmin master administrator can now control which domains and users are limited to their home directories when logging in via FTP, using the new FTP Directory Restrictions page.
* When upgrading scripts in multiple domains at once, added a confirmation page top display and select the domains that will be effected.
* International domain names are now automatically converted to the IDN xn-- format when creating, and converted back for display.
* When creating a sub-server whose prefix is in use by another domain, a non-clashing prefix for users is automatically selected.
* Reduced the memory needed to migrated Plesk backups, by not reading the whole source file into RAM for parsing.
* Added a Module Config option to prevent creation of the deniedssh group.
* Updated the phpPgAdmin script installer to version 4.2, phpCOIN to 1.4.1, TikiWiki to 1.9.11, bbPress to 0.9.0.2, Coppermine to 1.4.18, Joomla to 1.5.2, OpenX to 2.4.5, WordPress to 2.5.1, and SugarCRM to 5.0.0c.
* The alias to bounce all mail to unknown addresses in a domain is no longer created when using Postfix, as it does not appear to be necessary.
* Wordpress, WPMU and bbPress are now downloaded from the Virtualmin website in preference to their developer's sites, as there is no way to fetch specific older versions from the original site.
* When a script does not get fully installed (perhaps due to Virtualmin not being able to call its setup wizard), it is marked as a partial failure rather than a complete failure. This allows it be easily removed without leaving files behind.
* Link from the Edit Database page to scripts that use the DB.
* Added a script insaller for poMMo, a new web-based mailing list manager.
* Added the list-mailbox.pl command-line script, for dumping a user's mail.

#### Version 3.54
* Users in domains with spam filtering enabled can have their auto-whitelists viewed and edited, using a new link on the Edit Mailbox page (which using Webmin 1.411 or later).
* The pre-change script now has access to the settings that will be applied in $VIRTUALSERVER_NEWSERVER_* variables, while the $VIRTUALSERVER_* variables always contain the domain's settings before the change is made.
* Leftover /tmp/clamav-* files older than 1 day are now periodically deleted by Virtualmin.
* Added the --name-only flag to all list-* command-line API programs, to output just object names for easier use in scripts.
* Added the Magento eCommerce package to Virtualmin's script installers, version 1.0.
* Added a script to change the Virtualmin license in all needed files on an already installed system.
* The background collectinfo.pl cron job can be run less frequently or disabled using a new Module Config page option.
* Plesk sub-domains are now included with migrating, including any users for managing their content.
* Added the --delete-existing flag to migrate-domain.pl, to remove any existing virtual server with the same name before re-migrating.
* Apache logs outside a domain's home directory are now included in backups and restores.
* Fixed the modification of Webalizer and Logrotate config files when a domain's Apache logs are outside it's home directory.
* For new installs, new features in older versions are not shown on the System Information page.
* When migrating a cPanel, Plesk or Ensim backup, the original domain name can now be worked out automatically, as long as the backup contains just one.
* Basic Exim support, thanks to Bill Moyers and John Gray.
* The path to the public_html and cgi-bin directories is now stored in each new domain's data file, so that they are correctly preserved when the path is changed in the template, or the domain is moved to another system with a different directory name.
* For alias domains whose virtusers are always copied from the target, no home directory is created (as it isn't needed).
* If the skeleton directory contains a public_html sub-directory, it is copied to a sub-domain's web pages directory when the domain is created.
* When migrating a domain from other control panel like Plesk, you can now select to have to downloaded directly from a remote FTP or SSH server. The migrate-domain.pl command-line script also allows use of ftp:// or ssh:// URLs for backup sources.
* When a script is installed into a path that is already served by a proxy (such as for a rails application on /), a negating proxy rule is added so that the script is accessible.
* New DNS domains have the localhost A record added, with an IP of 127.0.0.1.
* Updated the osTicket script installer to version 1.6.rc4, Instiki to 0.13.0, Flyspray to 0.9.9.5.1, WordPress to 2.5, phpMyadmin to 2.11.5.1, phpBB to 3.0.1, and Php-Wiki to 1.2.11. Also added the latest 1.70+ build of LimeSurvey.

#### Version 3.53
* Email to domain owners for over-bandwidth warnings, new script notifications and others can now come from their resellers' addresses, if set. This behaviour must be enabled using a new setting on the <b>Module Config</b> page, under <b>Actions upon server and user creation</b>.
* The list of new features includes the date Virtualmin was installed.
* When restoring a backup of a domain that doesn't exist on the system, it's IP address can be changed or re-allocated from the range available on your system. This makes migration of domains with private IP addresses between systems on different networks easier.
* When email is disabled for a domain, only MX and mail records pointing to the Virtualmin system or known secondaries are removed.
* When using Qmail, domains with the same name as the system's primary hostname (typically from the <tt>control/me</tt> file) are not longer allowed, as they break Virtualmin's use of the <tt>virtualdomains</tt> file.
* When a sub-domain is created with the same name as a record in the parent domain, the record is not removed whem the domain is deleted.
* Updated the b2evolution, DotProject, FAQMasterFlex, Advanced Guestbook, Help Center Live, Integramod, Nucleus, PHPwebsite and PollPHP script installers to support PHP version 5.
* Added a check for Sendmail not accepting email on the external interface, which is the default in some distributions.
* A default email template for status monitors can now be defined, when using Webmin 1.404 or later.
* When restoring a backup, switch to a supported PHP execution mode if the original Apache config used an un-supported mode.
* A domain's private IP and external IP for DNS are now also included in SPF records.
* Fixed bugs in Plesk migration, and added automatic detection of alias domains in the original backup. SSL certificates and keys from the backup are also migrated. Also added initial support for Windows Plesk backups.
* Updated the LimeSurvey script installer to version 1.70, ZenPhoto to 1.1.5, phpMyAdmin to 2.11.5, SugarCRM to 5.0.0b, Horde to 3.1.7, and Flyspray to 0.9.9.5.
* When your Virtualmin Pro license is within 7 days of expiry, a notification is displayed on the system information page when the master administrator logs in.

#### Version 3.52
* If a script package cannot be downloaded from the vendor's website, Virtualmin will fall back to using a copy from scripts.virtualmin.com. This protects against changes made to script vendor's websites or download repositories.
* Added the --features-from-template parameter to create-domain.pl, to use features based on limits defined in the template.
* When a DNS domain is disabled, all records in it that use the domain name are renamed too, to keep BIND happy.
* Vpopmail systems with so many domains that letter-suffix directories under /home/vpopmail/domains are needed are now handed by Virtualmin.
* The SpamAssassin version is validated as part of the configuration check, to ensure that it supports the needed --siteconfigpath parameter.
* The logrotate configuration is now validated by Virtualmin, to detect duplicate entries that can cause rotation to stop working.
* SSL can now be enabled for domains without a private IP address, for a single virtual server on each shared address. This means that on a typical single-IP system, you can have one SSL website. This replaces the --ip-primary flag to create-domain.pl.
* When the Apache virtual host *.domain exists and a new virtual host for something.domain is created, it is placed before *.domain in the Apache config file to give it precedence.
* Hitting Stop in the browser during the creation of a virtual server or some other action will no longer cancel it, which prevents domains from being half created.
* Apache log files outside a domain's home directory are renamed and deleted when appropriate.
* Added the check-config.pl command line script for validating the Virtualmin configuration.
* The --quota and --mail-quota parameters to create-user.pl are now optional. If missing the defaults for the domain or template will be used.
* Renamed the OpenAds installer to OpenX, and updated it to version 2.4.4.
* Updated the WordPress installer to version 2.3.3, WordPress MU to 1.3.3, Rails to 2.0.2, Typo to 5.0.2, Radiant to 0.6.4, Turba to h3-2.1.7, Xoops to 2.0.18.1, phpBB to 2.0.23, TikiWiki to 1.9.10.1, and Joomla to 1.5.1 and 1.0.15.

#### Version 3.51
* New features in this version of Virtualmin and any plugins are shown on the System Information page, if using the Virtualmin theme.
* The wrapper scripts for running PHP via CGI or fastCGI now have the immutable flag set on Linux, to prevent accidental deletion by domain owners.
* Moved the option that controls if mailbox users can have .procmailrc files to the Spam and Virus Delivery page, where it is easier to find and is applied immediately.
* Outgoing email relayed via the Virtualmin system is now counted towards the sender's domain's bandwidth limit, unless disabled on the Bandwidth Monitoring page.
* Re-wrote all code that locks configuration files managed by Virtualmin. This improves the coverage of Webmin logging, and makes it much safer to perform multiple operations on the same or different domains at once.
* Fixed bugs in the FAQMasterFlex installer that prevented it's config file from being setup properly.
* When a virtual server is moved under a new owner, the Apache directives that control which user CGIs and PHP scripts run as are properly updated.
* When a domain is restored to a system with a new IP address, the IP in the SPF record is updated. Also, any NS records are updated to match the new system.
* When editing a virtual server without a private IP address, one can be added that is associated with an existing interface on the system.
* When moving a virtual server to a new system via a restore, if any required PHP modules that were installed on the old system are missing on the new, they will be automatically installed (where possible). In addition, you will be notified if any required PHP versions are missing.
* Custom styles can use the nocontent=1 line in style.info to specify that no initial content needs to be entered.
* When restoring a virtual server that uses features not supported on the system, a warning will be displayed listing the missing or disabled features.
* Updated the Drupal installer to versions 5.7 and 4.7.11, OpenAds to 2.4.3, Mantis to 1.1.1, Joomla to 1.5.0, TWiki 4.2.0, Movable Type to 4.1, WordPress MU to 1.3.2, osTicket to 1.6.rc3, Nucleus to 3.32, Coppermine to 1.4.16, Plans to 7.9.9, ZenPhoto to 1.1.4, Bugzilla to 3.1.3, TextPattern to 4.0.6, and phpMyAdmin to 2.11.4.
* Updated the Horde script installer to version 3.1.6, and the versions of several other Horde-related scripts.

#### Version 3.50
* The system statistics graphs can now be displayed using IE, as well as Firefox.
* Added a script installer for eTicket version 1.5.6-RC4, a fork of the osTicket project.
* Put back the osTicket installer, now that it is available again, and updated it to version 1.6 RC2.
* Un-supported script versions can now be installed by the master admin .. but use this feature at your own risk!
* When an alias domain is created, the primary domain can now update its configuration as needed. This allows AWstats to work when accessed via the alias domain.
* Fixed a bug that prevented mail for users with @ in their names and mbox-format mail files from being properly displayed on systems using Postfix.
* Removed the modify-aliascopy.pl command-line program, as it's features have been included in modify-mail.pl.
* When using Postfix with the sender_bcc_maps directive, a new option on the Module Config page can be used to allow BCCing all sent email in some or all domains to a separate address. This can be set on the Email Settings page, or by default for new domains in Server Templates. It can also be changed on the command line with the new modify-mail.pl script.
* When installing a script that uses authentication, you can now enter a username and/or password instead of it being setup to use the domain's login details by default. Similarly, the install-script.pl command now has optional --user and --pass parameters.
* When selecting a database for a script, the default is now to use a new DB if possible.
* Shell special characters like ; and & are no longer allowed in mailbox usernames.
* Moved the default quota for mailboxes to the 'Mail for domain' section of templates.
* Added back the old one-file-per-domain backup format, which is more friendly to rsyncing the home directory separately.
* Added a script installer for RoundCube, a new IMAP webmail client with a nicer user interface than Squirrelmail.
* Include the total backup time in the scheduled backup email.
* Only run clamscan once to verify that it is working, rather than after every configuration change.
* Removed the Squirrelmail 1.5.1 version, as it is no longer available for download.
* Upgraded the ZenPhoto installer to version 1.1.3, and made it more automated.
* Upgraded the SquirrelMail script installer to version 1.4.13, phpBB to 3.0.0 (and fixed a module bug), TikiWiki to 1.9.9, Gallery to 2.2.4, Xoops to 2.0.18, WordPress to 2.3.2, and Mantis to 1.1.0.

#### Version 3.49
* Added the test-smtp.pl command for validating mail server relaying and logins.
* The size of the Webmin server process can be traded off against the speed of Virtualmin by adjusting the amount of library pre-loading done, using a new setting on the Module Config page.
* Added the list-available-shells.pl command-line program, and added the --shell parameter to create-user.pl and modify-user.pl. Also updated modify-limits.pl so that the --shell option can specify any defined shell.
* Shells for mailboxes and domain owners are now configured on the new Custom Shells page, linked under System Customization on the left menu. This allows you to define as many different shells as you like, for access levels like email only, FTP and SCP only. When editing mailboxes or domain owner limits, you can then select one of the defined shells.
* Added --mailfiles flag to backup-domain.pl and restore-domain.pl, to save and restore inboxes outside of the home directory.
* Added the modify-aliascopy.pl command-line program to change the email aliasing mode (from catchall to copying virtusers).
* Alias mail domains can now be implemented by copying virtusers into the alias rather than using a catchall. Under Postfix this allows email to invalid addresses in the alias domain to be rejected at the SMTP level. The default for this can be changed on the Server Templates page under Mail for domain, and it can be changed for existing domains on the Edit Virtual Server page.
* Virtualmin API scripts run via HTTP are now executed within the same process, which should make them about twice as fast.
* Cron jobs created by Virtualmin will still be recognized even if manually modified to redirect output or add other pre- and post-commands.
* Moved the Administration username field into the first (visible) section of the Create Virtual Server page.
* Added a Module Config option to make the Unix group name for a new domain always follow the username, and made group name selection more consistent across creation methods.
* When there are too many servers on the List Virtual Servers page to show in a table, buttons to update and delete them all are displayed along with the seach form.
* When re-sending the signup email for a server, the owner's email address can be entered.
* Advanced autoreply options are hidden by default, to make the alias form less confusing.
* The initial administration login and password is displayed after installing a script.
* Updated the phpMyAdmin script installer to 2.11.3, OpenAds to 2.4.2, phpBB to 3.0.RC8, ZenCart to 1.3.8, Plans Calendar to 7.9.8, Drupal to 5.5 and 4.7.10, Squirrelmail to 1.4.12, PHP-Calendar to 0.10.9, Flyspray to 0.9.9.4, and Instiki 0.12.0.
* Added the original website URLs for all script installers, displayed on the installation form and on the page showing details of an installed script.
* When used, the ClamAV server clamd can be stopped and started from the system information page, just like MySQL and Apache.

#### Version 3.48
* Added the --user and --all-domains parameters to list-scripts.pl, list-users.pl, list-aliases.pl and list-simple-aliases.pl, to list objects in multiple domains.
* Both the maximum and minimum versions for scripts can now be selected on the global Script Installers page.
* Added the --user option to disable-feature.pl and enable-feature.pl to turn features off and on in all domains owned by some user, and the list-domains.pl to fnd domains by user.
* Added a checkbox to the backup form to include sub-servers of those selected too. A similar option is also available to virtual server owners when backing up a single domain, to include all sub-servers with the same owner.
* Added the --user command-line option to backup-domain.pl to backup all domains owned by some Virtualmin user.
* Virtualin plugins can now export script installers, using the scripts_list function in virtual_feature.pl.
* Sub-domains in cPanel backups can now be properly imported.
* Errors when extracting cPanel, Plesk and Ensim backup files are reported in more detail.
* Current versions are shown in the script updates notification email.
* MySQL and LDAP sources for aliases and virtual addresses for Postfix can now be used by Virtualmin, when Webmin 1.380 or newer is installed and when they are setup properly in the Postfix module. This allows Virtualmin to effectively configure a remote mail server, assuming that domain Unix users and groups are also stored in LDAP.
* When a domain is renamed, generics or sender canonical maps are properly updated too.
* Reseller details can now be used in templates and email messages, with keys like RESELLER_NAME and RESELLER_EMAIL.
* Details of a virtual server's resellers are now made available to pre and post virtual server change commands in the RESELLER_ environment variables.
* Added 5 and 15 minute load averages to system statistics.
* Logging is now enabled when setting up clamd, and the socket directory created if needed.
* Added a warning about NSCD to the configuration check page.
* Upgraded the OpenAds script installer to 2.4.1, which uses a completely different installation wizard.
* Updated the phpMyAdmin script installer to 2.11.2.1, Nucleus to 3.31, SugarCRM to 4.5.1h, Plans calendar to 7.9.7, WordPress to 2.3.1, WordPress MU to 1.3, Drupal to 5.3 and 4.7.8, LimeSurvey to 1.53, ZenPhoto to 1.1.2, dotProject to 2.1.1, Advanced Guestbook to 2.4.3, Coppermine to 1.4.14, and TikiWiki to 1.9.8.3.

#### Version 3.47
* Added an option to the Edit Mailbox page to disable spam filtering for a user. Also added equivalent command-line flags to the user modify-user.pl and create-user.pl command-line scripts.
* Scripts that have a background server process (like Mongrel instances for Ruby on Rails) can now be stopped, started and restarted from the Manage Script page.
* When batch creating or mass deleting virtual servers, servers like Apache and BIND are not restarted to apply the changes until the entire batch is complete.
* Added an option to the proxy paths page to serve locally for some path (disable proxying). Also added a corresponding flag to the create-proxy.pl command-line API.
* Added --logo and --link parameters to create-reseller.pl and modify-reseller.pl, to set the logo their customers see, and updated list-resellers.pl to show the current logo for each reseller.
* The hosting provider's logo that appears in the top-left corner can now be customized on a per-reseller basis, so that customers of each reseller see a different logo when they login.
* Cleaned up the reseller editing page by breaking down fields into collapsible sections.
* On systems with the mod_proxy_balancer Apache module, Ruby-based script installers can run multiple Mongrel instances to handle higher loads. All needed proxy directives and server processes are setup automatically.
* Added a field to the Upgrade Notification section of the Script Installers page to specify a custom base URL for Webmin for email messages.
* Changed default PHPlist version to stable release 2.10.5.
* Updated the proxy paths page to allow proxying paths to a single URL, even on systems that don't have mod_proxy_balancer installed. For those with a module, the proxy can still be to multiple URLs.
* Virtualmin plugins and modules that are not installed but could be are now in the right-hand frame, with a link to the Package Updates module to install them.
* If the create of the Unix user or group for a virtual server fails, both are rolled back to avoid leaving half-created users in /etc/passwd or LDAP.
* Added the CA Certificate tab to the Manage SSL Certificate page, for uploading a chained cert from your CA.
* When re-creating a domain as part of a restore, the external DNS IP address is set to match the target system, rather than being copied from the source.
* Domains that don't have any databases but are allowed to create one can now install scripts that have the ability to create a database.
* Updated the Horde script installer to version 3.1.5, along with many Horde applications like IMP and Kronolith.
* Updated Xoops script installer to version 2.0.17.1, SugarCRM to 4.5.1f, TikiWiki to 1.9.8, Rails to 1.2.3, Radiant to 0.6.3, phpBB to 3.0.RC7, dotProject to 2.1, and SquirrelMail to version 1.4.11.

#### Version 3.46
* Added a button to the Spam and Virus Scanning page to configure and start clamd, so that the clamdscan virus scanner can be used to save on CPU.
* Removed the Plugin Modules page and the section for enabled features from the Module Config page, and merged them into a single Features and Plugins page where you can select which are enabled.
* The default number of alias servers that new virtual server owners can create can now be set on the Server Templates page.
* Plugin modules can now define additional sections to appear on the right-hand side of the framed theme, and new global options to appear in the System Settings categories on the left.
* Moved the buttons for disabling and enabling multiple virtual servers off the Update Virtual Servers page to the domains list where they are more visible, and added confirmation pages.
* Expanded the plugin API to allow plugins to add their own links to the System Settings menus.
* Added the set-spam.pl command-line program, which modifies the spam and virus scanners for all virtual servers at once.
* Removed the ability to select the SpamAssassin client program and ClamAV virus filter on a per-domain basis, or in templates. This is now configured using the new Spam and Virus Scanning page, which effects all virtual servers.
* If password quality restrictions are setup in the Webmin Users module, enforce them in Virtualmin too.
* Added an option to the Create alias websites by setting in server templates to use RedirectMatch instead of Redirect, which is more Google-friendly for parked domains.
* Updated the Xoops script installer to automate the database connection and administration user creation, so that you no longer have to go through the install wizard manually.
* The System Settings category on the left menu of the framed theme is now broken down into 5 smaller menus, to make things easier to find.
* The migration function will use the username and password from the original domain where possible, removing the need to specify them manually when on the migration form or as parameters to migrate-domain.pl. For Plesk backups the original username and password can be retrieved, while for Ensim and cPanel only the username can be found automatically.
* Added support for migrating domains from Plesk 8 backups.
* Updated the Wordpress script installer to version 2.3, Wordpress MU to version 1.2.5a, WebCalendar to 1.1.6, Coppermine to 1.4.13, Bugzilla to 3.1.2, Movable Type to version 4.01, phpMyAdmin to 2.11.1, SMF to 1.1.4 and TikiWiki to 1.9.8.

#### Version 3.45
* Added options on the Edit Server Template page to make some non-default template the one that is initially selected when adding new virtual servers, migrating them or creating from a batch file.
* Usage for previous months can be shown on the Bandwidth Monitoring page, using a month selector menu at the bottom of the table of domains or dates.
* Added a similar option to the restore form in the Virtualmin web interface.
* Added the --only-features parameter to restore-domain.pl, which tells Virtualmin to only enable features selected for restore when creating a new domain as part of the process.
* Creation of domains that match certain regular expressions can be denied using a new Module Config option in the Defaults for new domains section.
* In the Quota commands section of the Module Config page, added two new commands to get the quotas for a single user and group respectively. If defined, Virtualmin will use these when listing users in a domain or editing a single user, on the assumption that they are faster than the command which outputs quotas for all users.
* Added links from the CPU load, memory used, disk used and other information on the right-hand system information page to graphs showing their values over time. This is taken from data collected by Virtualmin starting with the installation of this new release.
* Fixed bugs on the batch creation form that allowed domain owners to add new top-level servers, or sub-servers under domains that they don't own!
* Added a Module Config option to control use of the batch domain creation form by domain owners.
* Better handle additional databases in domains that start with a number, by converting the first digit to a word.
* Added a field to the Update Virtual Servers page to change the virus scanner (clmscan or clamdscan) on multiple domains at once.
* Added a script installer for WordPress MU version 1.2.4. This is the multi-user version of the popular WordPress blogging engine.
* Renamed the phpSurveyor installer to Limesurvey, and updated the version 1.52.
* On the Upgrade Scripts page for upgrading across multiple domains at once, only show those actually used in the menu.
* Added a setting to control if virtual server owners can see mailboxes, on the Module Config page under Server administrator permissions.
* Updated the phpBB script installer to version 3.0.RC5, WebCalendar to 1.1.4, Gallery to 2.2.3, HelpCenter Live to 2.1.5, and Xoops to 2.0.17.

#### Version 3.44
* Added the --php-children parameter to the modify-web.pl command-line script, to change the number of PHP fCGId sub-processes. The current setting is also displayed in list-domains.pl.
* Added a field to the Website Options page to set the number of PHP sub-processes used for service fCGId requests. A default for this can also be set in the Server Templates section, and the setting can be changed for multiple domains at once on the Update Virtual Servers.
* The button to stop or restart ProFTPd is always displayed in the right frame, even if private IP-based FTP is not enabled.
* Added an option to the form for backing up a single virtual server to download the resulting file in the browser, rather than saving it to a file or sending to an SSH or FTP server.
* Re-factored the code in all script installers that extracts ZIP and TAR archives to better check for domains that are out of disk quota, to prevent partial installs.
* Added a new tab to the Script Installers page under System Settings to send daily emails to domain owners, resellers or the master administrator notifying them of scripts that have new versions available.
* When enabling or disabling proxying for a domain, existing Apache directives are no longer re-generated from the template.
* Updated the modify-domain.pl script to allow excluded directories to be managed with the --add-exclude and --remove-exclude parameters. Also updated list-domains.pl to show exclusions.
* Added the Excluded Directories page for entering directories not to include in backups for a virtual server.
* Added --alias, --toplevel, --subserver and --subdomain parameters to list-domains.pl to limit output.
* In the Server Templates section, separate template php.ini files can be specified for PHP versions 4 and 5.
* When an existing database is imported to a virtual server, the MySQL or PostgreSQL permissions to it are properly granted. Similarly, when a database is dis-associated, permissions to it and directory group permissions are properly removed.
* Added a script installer for the Movable Type blogging platform.
* Migrated cPanel users with forwarding have email also delivered to their inbox, to maintain consistency with cPanel.
* Removed the batch alias creation page, as it has be superceded by manual alias management.
* Added a link from the Mail Aliases page to manually edit aliases in a domain using a text box. This makes bulk changes and copies simpler.
* The real name of a virtual server's Unix user is updated when the server's description is changed.
* AWstats statistics are now included in cPanel migrations.
* Added a script installer for the PostNuke CMS.
* Added an option on the Edit Owner Limits page to prevent use of the HTML editor.
* Updated the Drupal script installer to versions 5.2 and 4.7.7, DokuWiki to 2007-06-26b, WordPress to 2.2.2, WebCalendar to 1.1.3, Gallery to 1.5.7, PHPMyAdmin to 2.11.0, phpScheduleIt to 1.2.8, Flyspray to 0.9.9.3, Bugzilla to 3.1.1, and PHP-Nuke to 8.0.
* Updated phpBB script installer to allow a choice of the 3.0 and 2.0 versions.

#### Version 3.43
* Added a Module Config option to delete aliases when email is disabled for a domain.
* Added fields to the autoreply section of the alias and user email forwarding pages to limit the date range on which replies are sent.
* Added a restriction to the Edit Owner Limits page to prevent the creation of catchall email aliases.
* Added checks for gcc and make to the Ruby on Rails script installers (needed to compile the MySQL driver), and make checking for commands by scripts more generic.
* When a virtual server is deleted, all Mongrel server processes for Ruby on Rails applications associated with it are stopped, and prevented from starting at boot time.
* Added an installer for Radiant, a Ruby on Rails content management system. Unfortunately it can only be reliably installed at the top level of a virtual server's web directory.
* Ruby on Rails script directories are now protected from regular web access via a .htaccess file, as they are always accessed via a proxy.
* Added a script installer for Mephisto, a Ruby on Rails Blog.
* Webalizer statistics are now included in cPanel migrations.
* Updated Coppermine script installer to version 1.4.12, PhpWiki to 1.3.14, TextPattern to 4.0.5, osCommerce to 2.2rc1, SugarCRM to 4.5.1e, phpPgAdmin to 4.1.3, phpMyAdmin to 2.10.3, Joomla to 10.0.13, and Mantis to 1.0.8.
* Added a Module Config option to have MySQL users and permissions added to multiple servers, for use with replication or NDBCluster.
* Added a script installer for Instiki, a Ruby on Rails Wiki.
* Added a script installer for the Textpattern Blog.

#### Version 3.42
* Added the status of the Dovecot IMAP/POP3 server to the server status section of the right frame.
* Fixed a bug that can prevent per-domain PHP configurations from working when running PHP via CGI scripts.
* Added a script installer for Typo, which makes use of the Ruby on Rails framework but is a full blogging application.
* Added a script installer for Ruby on Rails. Unlike others, this does not setup a full working application - instead, it just installs the environment needed for developing Rails applications.
* Password changes to mail / FTP users from the Users and Groups modules now correctly update all the various passwords maintained by Virtualmin, such as MySQL and SVN - if the option to update in other modules is checked.
* Updated the Batch Create Servers page to allow alias domains to be created, by specifying an extra field for the alias domain name.
* Added a page for creating multiple email aliases at once from a batch file, linked from the Mail Aliases list.
* Added an option to the Edit Reseller page to force all virtual servers they create to be under a specified parent domain. Also updated the create-reseller.pl, modify-reseller.pl and list-resellers.pl scripts to edit and show this setting.
* Added script installers for phpScheduleIt, PHP-Calendar and Plans, and created a new script category for calendars.
* Added an option to the DNS section of server templates for specifying the hostname to use in the primary NS record for new DNS domains, rather than the system's hostname.
* Updated the phpMyAdmin script installer to version 2.10.2, WordPress to 2.2.1, SMF to 1.1.3, DokuWiki to 2007-06-26, and Gallery to 2.2.2.
* The Change Domain Name page can be used to modify the administrative username and home directory for a virtual server, without changing the domain name.

#### Version 3.41
* The Manage Script page now shows more information about an installed scripts, such as the install directory, database and possibly login and password. The list-scripts.pl command also displays the same information.
* Logins and passwords for using installed scripts are now recorded.
* Changed the layout of the Plugin Modules page to make it easier to see what is selected, and added a checkbox to have plugins available but not active by default.
* Virtual servers now have separate php.ini files for each PHP version (4 and 5), under ~/etc/php*. This allows different extensions to be loaded for each PHP version, and for different settings to exist.
* Under Apache 2.2, add NameVirtualHost *:80 instead of just *.
* Globally disabled features are no longer shown greyed-out on the virtual server creation and editing forms.
* Added the --default-features option to create-domain.pl, to avoid the need to specify feature flags manually.
* PHP modules are now automatically installed from CSW packages on Solaris.
* Added a Module Config option to make the DNS client configuration check optional.
* Website validation now includes a check for PHP wrapper scripts.
* Added additional warning when deleting scripts from ~/public_html.
* In the server templates pages under Default domain owner limits, added a section for specifying the features that can be used by the server owner. Previously, these were always automatically determined based on the features initially enabled when the domain was created.
* Updated the Flyspray script installer to version 0.9.9.2, and phpPgAdmin to 4.1.2.
* When a virtual server with a private IP is added, ping is now used to check if the IP is already in use.
* Added a new template section for defining your own PHP wrapper scripts, for use when PHP is run via CGI or FastCGI.

#### Version 3.40
* Added a Cron job to periodically update per-domain SpamAssassin config files from the global configuration, so that configs added by a SpamAssassin upgrade are not missing from the per-domain directories.
* Added a Module Config setting for the number of days of processed mail logs to keep, implemented an index cache file to speed up searches, and created a Cron job to periodically update the logs.
* Script installers that require Perl modules will now automatically install them, if possible.
* Added script installers for the Bugzilla, Flyspray and Mantis issue trackers.
* Added a search box to the list of scripts, to more easily find the one you want in the current huge list.
* Added checkboxes to the mail log search form to exclude spam and viruses from the results.
* When a virtual server with anonymous FTP is created, the ProFTPd user (typically ftp) is added to the domain's Unix group. This allows anonymous FTP to work even when the domain's home directory is not world-readable.
* Added an option to the scheduled backup page to only send an email report when the backup fails, and an option to send email to domain owners as well.
* Added a regular check for ophan php-cgi processes left around by Apache restarts on some systems, and kill any found.
* The configuration check process now ensures that the system is setup to use itself as a DNS server, so that newly created domains will resolve.
* The display of mailbox sizes is now off by default.
* If the system has a bonded interface but no ethernet, it will be detected as the primary interface.
* Added an option to the Edit Virtual Server page to turn off disabling when the bandwidth limit is reached, or a per-domain basis. Also added corresponding --bw-disable and --bw-no-disable options to the modify-domain.pl command-line script.
* When SSL is enabled for a virtual server, all Apache directives are copied from the non-SSL virtualhost section. This ensures that directives added by plugins or PHP configuration are preserved.
* Added a button on the Install Scripts for upgrading several to the latest version at once.
* The PHP module mcrypt is now only recommended when installing phpMyAdmin, but not strictly required.
* Added Module Config options for choosing different locations for servers' SSL certificate and key files.
* Added a Module Config option to change the default SSL key size, and increased the default to 1024 bits.
* When a virtual server with a website and private IP address is deleted, any Listen directives added for its IP are removed from the Apache configuration.
* Updated the modify-spam.pl program to add the --use-clamscan and --use-clamdscan program.
* Added a section to the Spam and Virus Delivery page for changing the virus scanner to use for existing domains, for choosing between clamscan and clamdscan. Also made it easier to change the default for this on the Module Config page.
* Updated the TWiki script install to redirect /twiki (or whatever path is selected) to /cgi-bin/twiki/view, which actually shows the Wiki. 
* Webmin libraries are not pre-loaded into memory for performance if the system has less than 256M RAM.
* Password restrictions set in the Users and Groups module are now checked when creating or saving a domain.
* Updated the SugarCRM script installer to version 4.5.1d, and WordPress to version 2.2.

#### Version 3.39
* Optimized the collectinfo.pl program, which generates the right-side system information frame.
* The old one file per directory backup format is no longer available, unless already selected.
* Added a link for copying the default settings template, rather than creating an empty template which inherits from it.
* When editing server templates, fields that are not used because they are inheriting from the Default Settings are now greyed out.
* When creating a virtual server inside a Solaris zone, existing virtual IPs in the zone can be selected for domains that need a private IP.
* Added Module Config options for external quota commands to use, instead of the standard Unix commands. This allows a different quota system (such as ZFS or on an NFS server) to be used instead.
* All script installers now check that they can connect to the selected database bbefore proceeding with the install, just in case the login is invalid. This prevents odd errors later on.
* Added a Module Config option to control of sub-domains can be created. This is disabled by default unless the system already has some sub-domains, as they are confusing and rarely used.
* Added a script installer for SugarCRM 4.5.1b.
* Added a button on the Bandwidth Monitoring page for re-generating bandwidth stats from the original log files.
* Added a link on the Manage SSL Certificate page for downloading a domain's cert in PEM format.
* Updated all script installers to check for the mysql and possibly pgsql PHP modules, if needed.
* Added the list-features.pl script, for finding available features for new virtual servers.
* The number of days to keep old bandwidth data can now be configured on the Bandwidth Monitoring page.
* Added a server templates option to set the default timeout for the HTTP status monitor feature.
* Added script installer for Simple Machines Forum.
* Added the list-bandwidth.pl command-line script for displaying usage by domain, date and feature.
* The stats web directory is now password-protected by default.
* If a domain with the same TLD already exists as one you are creating, the automatically generated group name will be the new full domain name, to avoid clashes.
* Updated Gallery script installer to 1.5.6, Mambo to 4.6.2 and phpMyAdmin to 2.10.1.

#### Version 3.38
* Added a server template option to make virtual servers' php.ini files non-editable by the server owner.
* Added an option in the Apache website section of the server templates for specifying a php.ini file to copy into new virtual servers' ~/etc directory, instead of the global default. This .ini file can also contain substitions like ${DOM} and ${HOME}.
* Added a new section to the Custom Links page for defining categories, and menus for assiging links into categories.
* Added arrows to the Custom Links page to move them up and down.
* Added a Module Config option for a Unix group to add all domain owners to.
* Removed the 'All virtual servers are name-based' Module Config option, as this function has been superceded by support for multiple shared IP addresses (and was confusing to boot).
* Added the search-maillogs.pl command-line script, with the same functionality as the web-based mail search.
* Added the Search Mail Logs page, which can show the destination of email to your system regardless of the final delivery method (local, autoreply, spam, virus, or forwarded). To support this, Virtualmin configures Procmail to log the destination file for all email it processes, to /var/log/procmail.log.
* Change the Module Config option for new domain passwords to add an option to require the password to be entered twice.
* Added the virtusertable plugin to the Squirrelmail script installer, so that users can login with their email addresses.
* Email to all domain owners and all mailboxes in a domain can now use substitions like ${DOM} and ${QUOTA}.
* Added Prev/Next buttons to template form, for easily navigating through sections.
* Fixed the cPanel migration code to handle new Maildir++ format mailboxes.
* Re-factored all code for displaying quota fields, so that the text box is greyed out when 'Unlimited' is selected.
* Fixed bugs that prevent owner limits from being mass-updated, and caused bandwidth limits to be un-necessarily changed.
* Updated the Wordpress script installer to version 2.1.3, and Gallery to 2.2.1.
* Added Module Config options for a hosting provider logo.
* Added the resend-email.pl command-line script for re-sending a domain's signup email.
* Added plaintext password to list-users.pl output.
* Validation of MySQL and PostgreSQL features now check that the database user exists too.
* Added a star rating system (out of 5) for script installers. Users can rate installed scripts, and ratings for those available are collated based on submissions from Virtualmin Pro users and displayed in the list of scripts available.
* Added a column to the list of installed scripts to show if it is the latest version or not.
* Added the --template option to modify-domain.pl.
* Improved the layout of the Disk Usage page, using tabs.

#### Version 3.37
* The spam and virus filtering features are now enabled by default for new virtual servers.
* Domain owners who cannot login via SSH are automatically added to the deniedssh group, which the SSH server is configured to deny even before checking their shell.
* Added preview images for content styles, visible via the Preview.. link next to the style menu.
* Added the Less Antique content style.
* Fixed bugs related to renaming autoresponder files when renaming a domain.
* Added the list-simple-aliases.pl and create-simple-alias.pl programs for easy alias management from the command line.
* Moved options for sending email to new and updated mailboxes from the Module Config page to the form for editing the actual messages.
* Improved the IntegraMod and dotProject script installers to configure the database connection automatically.
* Split the Edit Virtual Server page into more sections.
* When configuring email notification for new mailboxes, resellers and domains, you can now enter a Bcc address as well as a Cc address.
* Added a page for installing third-party content styles, which can then be used for new websites exactly like the built-in styles.
* Don't allow extra admins to switch to the domain owner.
* Updated the Drupal script installer to support version 5.1, phpPgAdmin to 4.1.1, and all the Horde scripts to their latest versions.
* Removed old versions from the PHPmyAdmin script installer.

#### Version 3.36
* Added a button to the Edit Web Pages page to replace existing content with that generated from a style. Also added the --style option to modify-web.pl.
* Added several new initial website content styles, such as Refresh, Dreamy, Rounded and Integral. All of these create multiple pages which can then be easily edited with the Edit Web Pages feature.
* Added tabs and more help text to the Script Installers page.
* Added caching to make lookups of domains by parent and user faster.
* Added the 'Hide limits from server owners' option to the reseller page, which prevents their customers from seeing the reseller's limits (although they are still enforced). Also updated the create-reseller.pl and modify-reseller.pl programs to all --hide options.
* Added the 'User-configured mail forwarding' section to the Edit Mailbox page, to show forwarding setup by the user in their .procmailrc file (using the Mail Filters module in Usermin).
* Added tabs to the Manage SSL Certificate page.
* Plugin modules can now have help links on the virtual server creation and editing pages.
* Autoreply message recipient tracking files are now stored in /var/virtualmin-autoreply, so that they can be accessed by the mail server when a virtual server's home is not world-readable.
* Updated the 'Show system information on main page?' Module Config option to allow display for resellers too.
* Added a new page for regularly updating a dynamic IP address, for systems where the primary IP is not static.
* Broke the Bandwidth Monitoring page down into collapsible sections.
* Replaced the HTMLarea widget for editing web pages with Xinha, when using Webmin 1.332 or later.
* Change the Module Config option for the Upload and Download module to limit to uploads only.
* Increased version of Gallery script installer to 2.2-rc-2, ZenPhoto to 1.0.8.2, WebCalendar to 1.0.5, Integramod to 1.4.1, and TWiki to 4.1.2.

#### Version 3.35
* Fixed the b2evolution script installer to correctly use it's built-in scripts for setting up the config files and database.
* Fixed the Nucleus script installer so that it actually works, and increased version to 3.24.
* Fixed bug that prevented autoresponders from being updated properly when renaming or moving virtual servers.
* Fixed bug that broke renaming of virtual servers when using debian-style sites-enabled directory for the Apache config.
* All autoreply email message files are now hard linked to from /var/virtualmin-autoreply, and this path is used in the autoresponders. This allows them to continue working even when a domain's home directory is not world-readable.
* Updated many script installers to support PHP 5.
* Added the --email parameter to create-reseller.pl and modify-reseller.pl scripts.
* Added the New Reseller Email page, for setting up a message to be sent to new reseller accounts.
* Added the Shared IP Addresses page under System Configuration for defining additional shared addresses that can be selected when creating servers without a private IP. Also updated the server creation page to allow selection of one of these shared IPs, and the create-domain.pl program to use one with the --shared-ip parameter.
* Added the --primary-ip option to create-domain.pl, to create an SSL domain on the primary IP.
* Added a button to the Edit Extra Administrator page for switching to their Webmin login without needing to know the password.
* Updated DaDaBiK script installer to version 4.2, WordPress to 2.1.1, phpMyAdmin to 2.10.0, phpList to 2.11.3, and MediaWiki to version 1.9.3.
* Improved detection of multiple scripts being accidentally installed into the same path.
* Changed pages with tabs and hidden sections to be usable by the mobile device theme.
* Updated the PHProjekt and MediaWiki script installers to setup the database configuration automatically.
* Updated the lookup-domain.pl script (which is called from Procmail) to communicate with a permanent server process, rather than performing all processing on its own. This will reduce the load when email to multiple recipients arrives at once.
* Added support for enabling Ruby scripts in a virtual server. This can be done on the Website Options page, with the modify-web.pl script, on the mass domain update page, and set by default in server templates. Both execution via mod_ruby and CGI scripts are supported, assuming that the required software is installed.
* PHP and Pear modules needed by script installers are now automatically installed when needed, if supported by the underlying operating system's update service (APT or YUM).

#### Version 3.34
* Added new pages for easily editing HTML in a virtual server's website.
* When a mailbox user's password is changed in other modules, it is also updated in Virtualmin's plain-text password file.
* Updated the MediaWiki script installer to version 1.9.2, and TWiki to version 4.1.1.

#### Version 3.33
* IMAP passwords for Usermin users are automatically updated when changed in Usermin.
* Fixed the PHP Support script installer to automatically setup the database connection details for version 2.2.
* Changed the script installer process to automatically use the correct PHP version required by the script, if available.
* Updated the Update Virtual Servers page to allow the default PHP version and PHP execution mode to be changed on multiple servers at once.
* Added the list-php-directories.pl, set-php-directory.pl and delete-php-directory.pl scripts for changing PHP version from the command line or remote API.
* Added the PHP Versions page (under Server Configuration on the left menu) for selecting the version of PHP to run for a virtual server. This can also be configured differently on a per-directory basis.
* Added a link from the Edit Virtual Server page to show a server's current password.
* Removed redundant creation buttons from main page, when using the framed theme.
* Broke the Update Virtual Servers page down into more readable collapsed sections.
* When a mailbox or domain owner is deleted, all of their Cron jobs will be removed too. Similarly, the owner of any Cron jobs will be correctly updated when a useris renamed.
* Added --spamclear-days, --spamclear-size and --spamclear-none options to modify-spam.pl.
* Added a new section to the Spam and Virus Delivery page for configuring automatic clearing of mailbox users' spam and virus folders. Also added an option in the server templates for setting the default for new servers, and an input on the page for updating multiple servers.
* Enhanced the validation for SSL virtual servers to check for the certificate files.
* Updated MediaWiki script installer to 1.9.1, ZenPhoto to 1.0.6, Drupal to 4.7.6, and phpAdsNew to 2.0.11 (and changed its name to Openads).
* Fixed bug that prevented the email for new sub-servers from being disabled, and added an option to inherit it from the parent template.

#### Version 3.32
* Added a section to the virtual server creation form for selecting an initial style and message for a new website. Also added --style and --content options to create-domain.pl, for the same purpose.
* Cleaned up Edit Virtual Server and Virtual Server Details pages to use collapsible sections and more consitent layout.
* Added a help link in the top-left corner on the server creation form.
* Changed all rows of links to put a | between them, increasing readability.
* Changed the mail / FTP user page to hide infrequently used options in collapsed sections, and to use Javascript to select simple / advanced mail forwarding modes.
* Changed the mail alias creation page to use Javascript to select simple / advanced mode forms.
* Hid most options on the virtual server creation form in an expandable sections.
* After saving a virtual server, a page showing a confirmation message and common links is displayed, rather than the (slow) Edit Virtual Server screen.
* Added an option to the Edit Owner Limits page for controlling if a domain owner can login via FTP, SSH or neither. Also added a corresponding option to the mass server change form, and the modify-limits.pl command-line script.
* Added a new Custom Links global configuration page, for defining extra links that appear on the left menu.
* Added support for running PHP scripts via FCGId, which combines speed and domain-level user security.
* Updated MediaWiki script installer to 1.9.0, DaDaBiK to 4.1, WordPress to 2.1, bbPress to 0.75, phpMyAdmin to 2.9.2, TWiki to 4.1.0, phpPgAdmin to 4.1, and phpWiki to 1.3.13rc1.

#### Version 3.31
* Added support for migrating Ensim backups into Virtualmin domains. Includes website, DNS, MySQL, mail aliases and mailbox migration capabilities.
* Virtual server owners using the Apache module are now limited to their home directory for alias targets and other Apache directives that specifiy directories.
* Changed the 'Add Apache user to Unix group for new servers?' option in the server template to add a working No option.
* Updated the phpBB script installer to version 2.0.22, phpProjekt to 5.2, Joomla to 1.0.12, phpList to 2.11.2, ZenCart to 1.3.7, Gallery to 2.2-rc-1, Drupal to 4.7.5/4.6.11, WordPress to 2.0.6, bbPress to 0.74, and ZenPhoto to 1.0.6.
* When PHP via CGI is enabled for a virtual server, the session save path in ~/etc/php.ini is set to ~/tmp.
* Changed most instances of the word 'Unix' to 'Administrator' in user interface.
* Fixed bug that prevents custom ports from being entered for FTP and SSH backups.
* Owners of domains that have virtual FTP enabled are now able to view their FTP server logs.
* Fixed a bug that prevents backups from a system using /var/mail for email storage being fully restored on a system that uses ~/Maildir.
* Validation of the mail feature now also checks to ensure that any secondary mail servers are actually receiving email for the domain.
* Added a field to the Website Options page to enable or disable suexec on a per-domain basis. Also added equivalent flags to modify-web.pl.
* Updated the Default domain owner limits section of the Server Templates page to add defaults for the 'Can choose database names', 'Can rename domains' and 'Allow sub-servers not under this domain' options.
* When changing the home directory of a virtual server, all references to the old home in its Webalizer configuration files are updated to the new location. Similarly, when restoring a backup from a server that uses a different home base, the Weblizer configuration is updated to use the new home.

#### Version 3.30
* Added a field to the DNS section of server templates for specifying BIND directives to be added to the named.conf entry for new domains.
* Email is now also sent when a new alias virtual server is created.
* Database backups and restores are done by calling functions in the Webmin 1.310 MySQL and PostgreSQL modules, rather than using duplicate built-in code. This prevents the PostgreSQL login prompt from appearing when doing a command-line restore.
* Added install-time checks to ensure that the Apache mod_suexec and mod_actions modules are enabled.
* Added an option on the Edit Reseller page to lock a reseller's account. Also added --lock and --unlock parameters to create-reseller.pl and modify-reseller.pl.
* Backups of mail / FTP users now include their Cron jobs, such as scheduled emails and automatic mail folder clearing.
* Fixed the Change IP Address page so that alias domain IPs are changed in sync with their targets.
* Changed the default mail forwarding inputs on the Edit User page to use the same simple layout as the Edit Alias page.
* Re-designed the Edit User page to use a cleared sectional layout.
* Password quality restrictions set in the Users and Groups module are not properly enforced.
* The simple mail alias page can now be used to forward to multiple addresses.
* Added a section to the Edit Databases page for changing the MySQL and PostgreSQL passwords for a virtual server, to make them independent of the main administration password.
* Added a new link under Administrative Options for switching to the login of a virtual server owner. This is only available for resellers and the master administrator.
* Improved the TikiWiki script installer so that the admin no longer has to enter database connection details.
* Added script installers for Zenphoto 1.0.3 and bbPress 0.73.
* Updated the TikiWiki script installer to version 1.9.7, ZenCart to 1.3.6, Xoops to 2.0.16, Kronolith to h3-2.1.4, Turba to h3-2.1.3, Nag to h3-2.1.2, Mnemo to h3-2.1.1, DokuWiki to 2006-11-06, Gallery to 1.5.5-pl1, Squirrelmail to 1.4.9a, phpAdsNew to 2.0.9-pr1, DaDaBiK to 4.1_rc1, ZenPhoto to 1.0.5, and phpMyAdmin to 2.9.1.1.
* Added a warning when installing a script into a directory that already contains other files, as they will be deleted when it is removed.
* Updated the Disk Usage page to include the top 10 databases by space used.
* Added a server template option (enabled by default) to set group ownership on each domain's MySQL database files, so that they are properly counted towards the domain's quota.

#### Version 3.29
* The change IP address page can now modify the IP of name-based servers, if more than one possibility is available (such as from a reseller IP). Similar, the modify-domain.pl program now takes a --shared-ip option to do the same thing.
* Each reseller can have an IP address specified for virtual servers with shared address websites under their ownership to be set up on. All DNS records in the servers' domains will use that IP, which allows resellers to appear to have a dedicated server for their customer domains.
* Virtual server backups can now be made to Amazon's S3 service, which provides online storage (at a price). Similarly, restores can be made from the same service. Before you can use this feature, you must sign up for an account with S3 and get an access key and secret key.
* Fixed the osCommerce script installer, so that the admin module works.
* Added checkboxes and a button on the Server Templates page to delete several at once.
* When restoring template backups, existing templates are no longer deleted. This makes copying templates to new servers easier.
* Changed the 'PHP Options' page to 'Website Options', and added a field for enabling log writing via a program (to protect against a missing ~/logs directory).
* Added an option to use Spanish to the Joomla script installer.
* A city or locality name can be entered when generating a certificate.
* When renaming a virtual server, an option is available to rename any mailboxes in the domain that contain the old server name.
* The cache file used by the lookup-domain.pl program to determine if a mailbox is close to its disk quota is automatically flushed when a user's or domain's quota is changed, which increases the speed at which such changes are detected.

#### Version 3.28
* When a virtual server uses spamc for spam processing, mailbox users' quotas are not checked at delivery time, as there is no danger of spamassassin failing if a user is close to their quota.
* The DNS IP address for an existing virtual server can also be set using the DNS Options page, or the modify-dns.pl program.
* An SPF record can be added to and configured in an existing virtual server using the DNS Options entry in the left menu, or the modify-dns.pl command-line script.
* In the virtual server list, servers that are using proxy or frame web forwarding have (P) or (F) next to their names.
* A warning is displayed for users who are within 5 MB of their disk quota in domains with spam filtering, indicating that filtering is disabled.
* When adding a MySQL database through the web and command-line interfaces, the default character set can be selected.

#### Version 3.27
* Fixed bug in System Logs module access that allows viewing of all logs.

#### Version 3.26
* On systems that have a php-cgi program, it will be used instead of php when PHP scripts are run as CGIs.
* Added --proxy and --framefwd options to the modify-web.pl script, to configure proxying and frame forwarding from the command line.
* Added the ability to switch the PHP execution mode (mod_php vs. CGI) on a per-domain basis, using the new PHP Options link on the left menu. This can also be done using the modify-web.pl command line script.
* Database name restrictions now apply when creating virtual servers too.
* Password quality restrictions set in the Users and Groups module now apply to mailboxes.
* Updated the phpBB script installer to do database configuration automatically.
* Added a new Spam filtering section to the Server Templates page, for selecting whether to use spamassassin or spamd for spam classification. Also updated the Spam and Virus Delivery page to allow this to be modified on a per-domain basis, and the modify-spam.pl script to do the same.
* Removed action buttons from the Edit Domain and View Domain pages when using the framed theme, as they are already available on the left menu.
* When PHP scripts are run as the domain owner, session.save_path is set to ~/tmp in the domain's PHP configuration, to ensure that session temp files can be written.
* Added a new page for checking user and group disk quotas.
* Changed the name of the NMS script installer to NMS::FormMail, to be more descriptive of its purpose.
* Moved download site for Civicspace script installer to download.webmin.com, as the original site is unavailable.
* Website FTP users can be created with home directories under ~/public_html, which allows the easy creation of users who can manage only part of a website.
* Updated the global Script Installers page available to the master administrator to control which versions can be installed, and to simplify and categorize the user interface.
* When using the Virtualmin framed theme, the module's main menu now only lists domains, rather than showing buttons and icons which already exist in the theme's left menu.
* Domain owners can now view their apache access and error logs, via links on the left menu.
* Updated script installer for Drupal to versions 4.7.4 and 4.6.10, DaDaBIK to 4.1_beta, Wordpress to 2.0.5, Coppermine to 1.4.10, and MediaWiki to 1.8.2.
* Added an option in the server templates in the Webmin login section to specify a Webmin group to which the domain owner is added. This can add new modules and override ACLs on existing ones.
* Forwarding addresses in users created from batch files are now actually used.
* Creating virtual servers on existing private IPs that are already used by another domain is no longer allowed.

#### Version 3.25
* Fixed a bug that caused server templates to disappear.
* Updated script installer for Ingo to 1.1.2.
* Update the Disk Usage page to include a separate per-directory count of disk space used by the domain owner (versus other users like root or httpd).
* Added text fields to the single and multiple domain disable forms for entering a reason why the disable was done. Also updated disable-domain.pl with a new --why flag.

#### Version 3.24
* Changed default Apache log format to combined.
* Added options to the Spam and Virus Delivery page to write spam to ~/Maildir/spam/.
* When log rotation is set to always enabled, it will follow the virtual website setting.
* The licence expired message is only displayed to the master administrator, rather than all users.
* MySQL backups are now compressed with gzip, to save on disk space from the original SQL format.
* The creation date and creator (if available) is shown when editing a virtual server.
* Added preloading for the main virtual-server-lib.pl library, to speed up Virtualmin CGI programs.
* Added a Module Config option to control categorization for domain owner's Webmin modules.
* Updated phpMyAdmin script installer to 2.9.0.2, DaDaBiK to 4.0, PHPlist to 2.10.3, MediaWiki to 1.8.0, and Mambo to 4.6.1.

#### Version 3.23
* The Disk Usage page now shows mailbox in sub-domains too.
* Updated phpMyAdmin script installer to 2.9.0.1.
* Added upload fields on the SSL certificate form, for using an existing certificate in a file.

#### Version 3.22
* Added a new left-side Disk Usage link which shows usage for each directory, mailbox and sub-server under a virtual server.
* Displayed disk usage for virtual servers is now taken from the group quota (when enabled), to ensure consistency.
* Added the --mail-size option to the list-users.pl program.
* User mail directory sizes are now displayed correctly.
* Outgoing address mapping (generics) entries are added for new domain owners.
* Fixed bugs that prevented suexec PHP from working properly in sub-domains.
* Bandwidth limits can now be imposed on resellers, which limits the total amount of bandwidth the reseller can allocate to their customer's domains.
* When removing a secondary mail server, all secondary domains that were created on it will be removed, and all MX records referring to it deleted.
* When adding a secondary mail server, all existing mail domains can be optionally added to the server. This will update MX records as well.
* Updated Mambo script installer to 4.6, phpMyAdmin to 2.9.0, and PHP-Nuke to 7.9.

#### Version 3.21
* Added an option to the Spam and Virus Delivery page to automatically whitelist all mailboxes in a domain. Also update the modify-spam.pl script to be able to set this same setting.
* Added a section to the limits section of the server templates for selecting what capabilities are enabled by default for new domains (like being able to manage aliases, databases and so on).
* Added a checkbox to the email section of the server templates to bounce email to new domains that does not match a specific alias or user.
* Added the list-templates.pl command-line script.
* Added the --limits-from-template option to create-domain.pl, to inherit default limits from template settings.
* Added a Save and Next button to the server template page, for easily moving to the next section.
* Access to the default templates can be denied to virtual server owners, just as it can be for other templates.
* The start and stop buttons for MySQL and PostgreSQL are not shown when it is not running locally.
* The 'Full path to clamscan command' option on the Module Config page can now take a command with arguments.
* Updated ZenCart script installer to 1.3.5, PHPCoin to v124, and TikiWiki to 1.9.5.

#### Version 3.20
* On the script installers page, available scripts are listed by category (such as Email, Blog, etc.) to make them easier to find.
* Added a Module Config option to compress backups using the bzip2 format, which is more efficient.
* Added the --newdb option to the install-script.pl program, for creating a database for use by a newly installed script.
* When installing a script that requires a database, an option is available from the databases menu to create a new one specifically for the script (if permitted by the users' limits).
* When adding a DNS zone inside a view that uses an include statement, the included file will be used if specified in the BIND module configuration.
* Domain owners can now perform backups to the virtualmin-backup directory under their home (which does not get included in future backups).
* Updated the 'Default delivery for spam' and virus options on the Module Config page to allow an arbitrary file or email address to be entered.
* On the Secondary Mail Servers page, you can now specify a hostname to use in the MX record for each server (like secmx.yourdomain.com) instead of having Virtualmin just use the server's hostname.
* Quota in email messages to domain owners and mailboxes (using the $QUOTA variable) now use nicer units, like 300 MB.
* Added script installers for the Horde applications MIMP, Chora and Passwd, Forwards and Vacation.
* Updated all script installers for Horde and related applications to their latest stable versions.
* Updated CivicSpace script installer to version 0.8.5, Coppermine to 1.4.9, dotProject to 2.0.4, Drupal to 4.7.3 and 4.6.9, Gallery to 1.5.4 and 2.1.2, HelpCenter to 2-1-2, Mambo to 4.5.4, MediaWiki to 1.7.1 and 1.6.8, Moodle to 1.5.4, osCommerce to 2.2ms2-060817, phpAdsNew to 2.0.8, phpCOIN to 1.2.3, PHPlist to 2.10.2, phpMyAdmin to 2.8.2.4, PHP-Nuke to 7.8, PHPsupport to 2.2, PHPsurveyor to 1.0, TWiki to 4.0.4, Xoops to 2.0.15, and ZenCart to 1.3.0.2.

#### Version 3.19
* Virtusers associated with mailboxes are not un-necessarily removed and re-added when no email related changes are made.
* Added an option on the Backup Virtual Servers page to have each server's backup file transfered by SCP or FTP after it is created, rather than doing them all at the end of the backup. This saves on temporary local disk space on the server running Virtualmin.
* Improved support for running within a Solaris zone (thanks to Textdrive).
* Added check for a global SpamAssassin call in /etc/procmailrc, which can interfere with Virtualmin's per-domain SpamAssassin settings.
* Added a script installer for AROUNDMe 0.6.9.
* Removed un-needed code to support versions of Webmin below 1.290.
* The server template editing page is now broken down into sections, selectable using a menu. This reduces the size of the form, and makes it easier to find settings that you are interested in.
* Sub-domains with DNS enabled are now added by default as records in the parent DNS zone, rather than as a completely new zone.
* Updated script installers for Drupal to versions 4.7.2 and 4.6.8, phpMyAdmin to 2.8.2 and WordPress to 2.0.4.
* For scripts that have more than one version available, a description of the meaning of each version (such as stable or development) is displayed.
* Changed the layout of the script installers page to show more information, and added checkboxes and a button for un-installing several at once.
* Fixed a bug that prevented DNS zones from being added to a file other than named.conf, even if specified in the BIND module.
* Added script installed for DaDaBiK 4.0 beta 2.
* When a domain owner is granted access to the Webmin Actions Log module, they can also view actions taken by extra admins.
* Added Module Config options for commands to run before and after an alias is created, modified or deleted.
* When email is set to a new or modified mailbox, the From: address is that of the domain owner.
* Comments on mail aliases can be edited, and will appear in the list on the Mail Aliases page. The create-alias.pl program has also been updated to allow comments to be set, and the list-aliases.pl program to show them.

#### Version 3.18
* Fixed a bug that caused mail bandwidth usage to be counted more than once.
* Added checkboxes and a button to the reseller list page for deleting several at once.
* Merged the code base with Virtualmin GPL (this should not have any effect on Virtualmin Pro features).
* Added a simpler form for setting up mail aliases which only forward to another address, deliver locally and/or send an auto-reply. The old form is still available though.
* Added a script installed for DaDaBIK 3.2.
* The licensed domains limit no longer includes alias domains.
* Updated Squirrelmail installer to version 1.4.7.

#### Version 3.17
* Optimized the writelogs.pl program to use less memory.
* Added options on the New Mailbox Email page to have the message sent to the domain owner and reseller as well.
* Non-standard ports for SCP and FTP backups can be specified by putting :port after the hostname on the backup form.
* Added a field to the Edit Server page and an option to modify-domain.pl for changing the mailbox username prefix for servers that don't have any mailboxes yet.
* Updated Squirrelmail installer to version 1.4.6, DokuWiki to to 2006-03-09, MediaWiki to 1.6.7, phpMyAdmin to 2.6.4-pl4, phpPgAdmin to 4.0.1, phpWiki to 1.2.10 and 1.3.12p2, TikiWiki to 1.9.4, WebCalendar to 1.0.4, and Joomla to 1.0.10.
* Made the bandwidth usage page visible to resellers (for their managed domains).
* Extra administrators for a virtual server cannot change the server owner's password in the Change Passwords module.
* Domain owners and resellers can now view actions they have taken in the Webmin Actions Log module (if enabled on the Module Config page).
* Added a script installer for NMS, a FormMail replacement.
* If an extra administrator username does not match the prefix specified in the domain's template, the master administrator is now allowed to change it.
* Mailbox, alias, databases and domains limits are set from the template if not specified explicitly in create-domain.pl.
* Added an option to create destination directories to the single-domain backup page.
* When adding a virtual server with a website, a root-owned file is created in ~/logs to prevent deletion of that directory.
* Added --user parameter to list-users.pl.

#### Version 3.16
* Added a checkbox on the backup page to have the destination directory automatically created.
* Optimized the bandwidth accounting code for email to only scan the maillog once for all domains, which should speed up the bw.pl process on systems with large mail logs.
* Updated Joomla installer to 1.0.9, and phpBB to 2.0.21.
* Added a check for new-format backups of domains without home directories (such as aliases), which previously failed.

#### Version 3.15
* When backing up a virtual server, the cron jobs for the Unix user are included too.
* Added support for phpMyAdmin 2.8.1.
* Added a template option to have PHP scripts run as the domain owner, via a CGI wrapper script.
* Added caching to the lookup-domain.pl script, to speed up processing when mail is delivered.

#### Version 3.14
* Fixed bug with spamassassin command.

#### Version 3.13
* Added highlighting to all tables, when using the latest theme.
* Fixed incorrect URLs in the PHPSupport script installer, and added support for version 2.1.
* Added a new Batch Create Users page for creating multiple mail / FTP users at once from a simple text batch file.
* The rarely-used 'Group for Unix user' option on the server creation page is now hidden by default.
* Fixed a bug that could cause mailbox users' home directories to be owned by the server administrator.
* When importing a virtual server, users can be found by a regular expression as well as just matching by primary group.
* New and modified mailbox messages can use blocks like $IF-VIRTUALMIN-DAV to display different messages depending on whether or not plugin features like DAV are enabled.
* The virtual server validation function now checks to ensure that mail user home directories exist and have the correct ownerships.
* Added a new Batch Create Servers page for creating multiple virtual servers at once from a simple text batch file.
* Adde a section to the List Databases page for changing the database login name for an existing virtual server. This allows servers whose default database names would clash to be more easily created.

#### Version 3.12
* Added the --force-dir option to install-script.pl.
* MySQL database names containing the _ or % characters are now properly escaped in the db table, to prevent their owners from accessing or creating other databases.
* Added an option when creating a virtual server with a private IP address to enter an IP that is already active on the system.
* When deleting a virtual server, its webalizer config files are removed too.
* Fixed a bug that prevented suEXEC directives from being added to sub-server Apache configurations.
* If a mailbox user's password is changed by the passwd command or some other program, Virtualmin will detect this and realize that the plain-text password stored for the user is no longer valid.
* All script installers that use a database will now be configured to connect to the correct remote database server, if one has been setup in the MySQL or PostgreSQL modules.
* When making a backup to a remote server, the connection is tested before the backup is actually started.
* Resellers and server owners without editing access can now change their passwords through the Virtualmin interface.
* Added support for finding the mail log from syslog-ng, if using Webmin 1.270.

#### Version 3.11
* A custom prefix can be specified when importing or migrating a virtual server.
* The Running Processes extra modules config option now allows you to choose if a domain admin can see other users' processes.
* Added the modify-spam.pl program for changing the spam and virus delivery actions from the command line, and updated the list-domains.pl program to show the current delivery settings.
* Added a new Spam and Virus Delivery page for modifying the destinations for messages classified as spam or containing viruses, after a virtual server has been created.

#### Version 3.10
* Fixed a bug that caused an error message about postfix_installed to be displayed at install time.

#### Version 3.09
* Added a Module Config option to validate the Apache configuration before applying it, to prevent config errors from halting the web server.
* Added the command-line script validate-domains.pl, for checking the configuration of virtual server features.
* When moving a server, if a vital feature fails (like the home directory or Unix user), the entire process is halted.
* Added script installer for IntegraMOD.
* Added checks for ownership to directory validation.
* Changed the way ClamAV is called from Procmail so that it doesn't reject mail when some error occurs, such as a shortage of disk space for scanning.
* Virtual server owners are no longer allowed to change the Apache server name or aliases for their websites, as this can confuse Virtualmin.
* When email is enabled or disabled for an existing virtual server, MX records are added to or removed from the DNS domain.
* When moving a sub-server, you now have the option to convert it to a top-level server with a new username and password.
* Proxying to SSL websites now works when using Apache 2 or later.

#### Version 3.08
* Removed the Logrotate and Webalizer features for sub-domains, which share log files with the parent domain.
* The Command Shell module is now available to server owners - but can be disabled on the Module Config page.
* Added a link to the left-side frame for viewing a domain's website, using a HTTP request tunnelled through Webmin. This is useful if the domain name has not been fully registered in the DNS yet.
* Updated the installer to have Webmin pre-load several Virtualmin and Webmin libraries, speeding up the user interface.
* Added a button the server template pages for viewing scripts associated with a template, for installation when a server is created. This allows common third-party scripts to be automatically setup for new servers.
* Added a new page available to the master administator for validating virtual servers, by checking that all enabled features are actually properly configured.
* Updated the function for moving virtual servers to allow a parent server to be converted to a sub-server, and create a command-line script for moving servers.
* Added script installer for osCommerce.
* When a process (such as a domain setup) requires Apache to be restarted, it will not be re-configured as well.
* Added a button to the Edit Server page for moving sub-servers to a different owner.
* Added a script installer for phpWebSite.

#### Version 3.07
* Fixed a bug that prevented mailbox user quotas from being backed up.
* Bandwidth stats are now included in backups.
* Added script installers for Mambo and Joomla, thanks to Kevin Rauth.
* Plugin modules data can now be included in Virtualmin backups, such as Mailman mailing lists, AWstats config files and SVN repositories.
* Added a server template option to force extra administrator usernames to begin with some prefix, such as the virtual server's username.
* Webmin ACL files for Virtual server owners and extra admins can now be included in backups.
* The CGI directory for sub-domains is now set to be a sub-directory of the parents cgi-bin, and the log files are set to be the same as the parent server's.

#### Version 3.06
* Added a work-around for the problem of mail being delivered with ownership root by the procmail wrapper.
* Added online help for the Server Owner Limits page.
* Added command-line programs for listing, installing and removing third-party scripts.
* Added a script installer for phpAdsNew.
* Added a script installer for Moodle (thanks to Kevin Rauth).
* The size of mailboxes is calculated from the number of blocks used rather than the byte file sizes, which is more accurate as it reflects the true quota usage.
* The displayed mailbox size for users with Maildir format inboxes includes all sub-folders and other files within the directory.
* Fixed a bug that prevented additional database access for mail users from being properly restored.
* Added a script installer for DokuWiki.
* Added script installers for the Turba, Ingo, Nag and Mnemo Horde components.

#### Version 3.05
* Webmin users created by Virtualmin are marked as non-editable, and so cannot be manually modified in the Webmin Users module.
* Added script installers for MediaWiki and TWiki.
* Added PHP module checking to the Horde script installer, and updated it and other dependent scripts to the latest versions.

#### Version 3.04
* Plain text passwords are stored for all new and modified mailbox/FTP users, which allows MySQL, DAV and SVN access to be enabled for users without their passwords needing to be reset.
* Long domain names are now shortened when displayed in lists and menus, to a length settable on the Module Config page.
* Added Restart buttons when using the new Virtualmin theme.

#### Version 3.03
* Added script installers for FormMail and cgiemail.

#### Version 3.02
* Mail users in the user@domain format are now supported when using Postfix, by creating extra Unix users without the @ for mail delivery.
* Added a script installed for CivicSpace.

#### Version 3.01
* If the Apache module has been configured to create a symlink for a new virtual host's file in a separate directory (sites-enabled on Debian), Virtualmin will too.
* When restoring a backup, the home directory of any virtual servers created is re-allocated to use the directory and rules defined on the destination system.
* The email addreses to send status monitoring messages to can be set on the Server Templates page.
* Server owner limits can be updated for multiple users at once on the Update Virtual Servers page.

#### Version 3.00
* When renaming a domain that has users in user@domain format, the users will be renamed too.

#### Version 2.99
* Added command-line programs to list and manage extra administrators.
* Limits can be set at the server owner and reseller levels on the number of alias and non-alias servers, which are imposed in addition to the overall limit on servers. This allows users to be given separate higher limits on alias servers.
* Extra administration logins can be created for virtual servers, who have a subset of the permissions granted to the main administrator. This allows server owners to delegate some of their powers to other people, without giving out the main password for the virtual server.
* Plugins can now define additional inputs to display on the Server Template page, such as defaults for limits on the number of mailing lists, repositories and so on.
* When adding or removing Sendmail domains to accept email for, comments in the local domains file in /etc/mail are now preserved.
* Updated the modify-limits.pl command line program to allow setting of editing limits and maximum aliases.
* Multiple databases can be deleted at once from a virtual server.

#### Version 2.98
* The FTP server can be stopped and started, like the mail, DNS and web servers.

#### Version 2.97
* Added a new configuration page available to the master administrator for specifying Webmin servers with Virtualmin installed to be used as secondary MX's. Once this is done, any new mail domains will be relayable through those servers.
* Extra PHP variables to be added to a server's Apache config when a third-party script is installed can be set on the Server Templates page.
* Added buttons to the list of virtual servers for deleting several at once, and updating settings such as the quota, bandwidth limit and enabled features on several at once. The same form can be also used to disable or enable multiple virtual servers.

#### Version 2.96
* When backing up virtual servers, you can also include core Virtualmin configuration settings, such as templates, resellers, the module configuration and so on. The restore page also has options to extract these from a backup. This new feature allows all data relevant to Virtualmin to be backed up from a single place.
* A new server template option allows disabled websites to redirect the browser to a different URL, rather than service a local HTML page.
* The message displayed on the website of a disabled virtual server is now configurable on the server template page, rather than being fixed.

#### Version 2.94
* By default, settings that used to be on the Create Server page with are set in the template (such as the quota, bandwidth limit and mailbox/alias/database limits) are no longer displayed. Instead, the settings from the selected template are used. The old behaviour can be restored using a setting on the Module Config page.
* Added a button for creating a sub-domain, which is like a sub-server but is always under the parent domain, and uses a sub-directory of its web files directory as the document root.
* Server owners can be prevented from editing the schedule and directory for their Webalizer reports, using a new option on the Server Template page.
* Added a section to the Server Template page for specifiying the logrotate directives for a new server, rather than always using Virtualmin's automatically generated directives.
* Feature selection when adding or editing a virtual server is now done using checkboxes rather than Yes/No radio buttons.

#### Version 2.92
* Added a new type of mail/FTP user who can manage the virtual server's website files. This user has the same permissions as the server owner, but is restricted to it's web files directory.
* When restoring a single virtual server, you can select to restore just one mail/FTP user instead of all of them. You can also choose to just re-import a server whose /etc/webmin/virtual-server/domains file is missing.
* Added a template option to have an alias server under another domain when a server is created. This can be useful when a new domain has not yet been registered, to allow it to be accessed under the provider's domain.
* Resellers can now have their own IP allocation ranges defined, which will apply to all virtual servers that they create or manage.
* Virtual server functions that a server own can access (like databases, scripts, users and aliases) can now be individually controlled on the Edit Owner Limits page, rather than being automatically determined based on their ability to create servers.
* Extra Webmin modules can be specified for server owners on the Edit Owner Limits page.
* Added a form to the Script Installers page for upgrading some script on several virtual servers at once.
* Added an option to email a mailbox user with their new account details upon saving, and a template page for editing the message sent.

#### Version 2.90
* Added support for plugins that define new database types.
* Plugins can now define their own limits to be configured on the Edit Owner Limits form, such as a restriction on the number of mailing lists a server can have.
* The method by which the domain name is appended or prepended to a mail user's name can now be set on a per-template basis.
* Limits can now be placed on the number of aliases a virtual server can have, at the server owner and reseller levels. In addition, plugins can specify that certain aliases should not count towards this limit (or be displayed to the user).
* Mail users can have their logins temporarily enabled or disabled, using the web or command-line interfaces.
* Added a button for re-checking the licence immediately if a problem was detected during a regularly scheduled check.
* The 'Home directory' and 'Unix users' are now always enabled, unless you select to make them optional on the Module Config page. These are needed for almost all virtual servers, so it makes little sense to show the option.
* When disabling a virtual server, the accounts for any mail users are locked too.

#### Version 2.89
* Added a button below the user list, which brings up a page for defining defaults for new users in that virtual server. This can be used to define initial quotas, FTP access, databases and mail forwarding.
* When importing a virtual server, a parent server can be specified to control the new domain in Virtualmin.

#### Version 2.88
* Moved the option for hard or soft quotas to the server templates page, so that different types of quotas can be used for different domains.
* Added a button on the user list page for updating quotas and email in multiple users at once.
* The default mail user quota is now settable on a per-template basis.
* Fixed bug in new backup format that prevents PostgreSQL dumps from working.

#### Version 2.87
* Fixed some messages and small bugs reported by users.
* Added help on the Backup Virtual Servers page.

#### Version 2.85
* Added a new backup format that doesn't create files in /tmp when not needed, instead using only each server's home directory.
* Network interfaces are now identified by address rather than name, to avoid problems with interface numbers changing on operating systems like Gentoo and FreeBSD.

#### Version 2.84
* Virtual server mail/FTP/database users can also be assigned to arbitrary secondary groups, defined on the Server Templates page.
* Added an option on the Server Templates page for setting secondary groups that users with email, ftp and database access will be granted to. This can be useful for controlling their visible modules in Usermin.

#### Version 2.83
* Added script installers for Horde, IMP, Kronolith and Gollem.

#### Version 2.80
* Added buttons to the user and alias lists for deleting several of each at once.
* Added the Disk Quota Monitoring page, for setting up automatic email notification on servers that are approaching or have reached their disk quota.
* The import feature now supports SSL Apache virtual servers too.
* Proxying and frame forwarding can be enabled, disabled and configured more easily for existing web virtual servers using the Edit Proxy Website and Edit Forwarding Frame buttons on the Edit Server page.

#### Version 2.60
* Space used by databases is now included in the disk quota displays, although it is not actually enforced.
* The template for an existing virtual server can now be changed. However, this does not immediately effect any of its settings.
* The Change IP Address page can now also be used to set a different port for a server's normal and SSL websites. This can be useful for running an SSL server on a non-standard port, without needing a private IP.
* On Sendmail systems, you can specify the bounce message for aliases whose destination is set to Bounce mail.
* Added a Module Config option to add an /etc/procmailrc entry to force delivery to the default destination, to prevent mailbox users from running commands via .procmailrc files.
* Added the migrate-domain.pl command-line program for importing a backup from another control panel, such as Plesk.
* Added command-line programs for listing and setting custom fields.
* Added the modify-limits.pl command-line program, for setting a server owner's limits.
* Created a method for executing Virtualmin command-line programs via HTTP requests, by calling virtual-server/remote.cgi
* Added command-line programs for listing, creating and deleting resellers.
* Added command-line programs for listing, creating and deleting databases.
* Database names can now be restricted to start with the server's domain name, using a new option on the server template page.
* Added command-line programs for listing and modifying users.
* Added command-line programs for listing, creating and deleting mail aliases.
* Added help pages for the template, reseller, IP allocation, plugin and custom fields pages.
* A virtual server with a private IP address can now have it removed on the Edit Server page (assuming that it doesn't have an SSL website or virtual FTP server).
* Added a system information display to the main page, showing the versions of the various programs that Virtualmin uses.
* Added the modify-domain.pl command-line program, for changing various attributes of a virtual server.
* Added command-line programs for deleting virtual servers and users, and disabling and enabling servers.
* Third-party script installers can now be added using the Script Installers icon on the module's main page.
* Added a new feature - status monitoring for a virtual server's website, which will notify the server owner if it is down.
* Server owners can backup their own virtual servers, but only to a remote FTP or SSH server.
* Virtual servers without mail enabled can now create and manage users, for database and FTP access purposes.
* On the Server Template page, added an option to create an SPF DNS record in new domains.
* Added a new option on the Edit Owner Limits page, to put a server into demo mode. In this mode, the owner cannot make changes to any settings, only view them.
* All quota fields now have an option for selecting the units, rather than always being entered in kB.
* Templates can now be restricted to some, all or no resellers.
* Added built-in support for granting mail/FTP users access to MySQL databases.
* Ranges for automatic IP allocation can now be defined in a more user-friendly way on the Server Templates page.
* Added an icon on the main page and a button on the Edit Server page for emailing all server owners and all mailboxes in a domain respectively.
* Added a similar feature for per-domain Virus filtering using ClamAV.
* Created a new feature - per-domain Spam filtering using SpamAssassin and Procmail. Each server can have its own SpamAssassin settings and spam delivery action.
* Added support for third-party script installation, such as PHP-Nuke, Formmail and other common web tools. These can be installed and managed using the Install Scripts button on the Edit Server page.
* Added support for resellers, which are users who can create top-level virtual servers up to limits imposed by the master administrator. Each reseller can be limited in the number of servers, mailboxes and databases they can own, and the total quota they can assign to all owned servers.
* Quotas and bandwidth limits on the templates page now have proper units like kB or MB, rather than being in bytes.
* Added command-line programs called enable-writelogs.pl and disable-writelogs.pl to turning on or off logging via a program for existing domains, or all domains.
* When a server's home directory is renamed, any protected web directories within it will be properly updated too.
* Slave zones can now be added to multiple servers, when using Webmin version 1.203 or later.
* The IP address for a private virtual server can now be changed using the Change IP Address button on the Edit Server page.
* Created a page for updating the IP addresses for all non-private virtual servers at once, for use when a system's primary IP address changes.
* Added a button to the Edit Server page for re-sending the signup email.

#### Version 2.50
* Added an option on the template page for defining default mail aliases for new servers.
* Made available an option on the template page for turning off the automatic synchronization between a server's password and that of its MySQL login.
* When Webmin 1.201 or later is installed, there is an additional option on the Server Templates page to have Webmin and Usermin per-IP SSL certificates added to match those used for the Apache SSL virtual server.
* Added an option to the Bandwidth Monitoring page to disable it for selected servers, such as those that have extremely large logs.
* The Webalizer statistics directory can now be password protected, via an option on the Server Templates page.
* Added an option on the template page for doing web logging via a program, which silently ignores problems writing to the logs. This prevents Apache from failing to re-start if a user deletes their ~/logs directory.
* The permissions on the public_html directory can now be edited on the server template page.
* Domain names and usernames can now start with a number.
* Added an option to the domain creation form to generate a password randomly.
* Add file writes now use the new Webmin API to prevent truncation if a disk space shortage or other error occurs.
* Creation of an initial MySQL or PostgreSQL database for a server is now optional. Instead, you can choose to just have a login created instead.
* Usage graphs now show bandwidth used by each feature in a different colour, and can show usage by day or month as well as by domain.
* Mail server logs (in Sendmail, Postfix or Qmail formats) can now be checked to include mail sent to mailboxes and aliases in a domain in bandwidth totals.
* FTP server logs can now be used for bandwidth accounting as well, so that anonymous downloads and files downloaded by domain owners count towards bandwidth usage totals. Thanks to Olimont.com for sponsoring this feature, and the mail log support.
* Added support for the VPOPMail autoresponder program.
* Default quotas and other limits for a new domain can now be specified in templates, instead of globally.
* When using VPOPMail as the mail server and a domain uses an existing Unix group, no extra group for mailboxes is created.

#### Version 2.40
* Added options on the restore page to fix up the DNS and Apache IP addresses when restoring. Useful when transferring a domain from another server.
* Added a Module Config option to have domain and mailbox users created in other modules.
* The create-domain.pl script can now create sub-servers and alias servers too.
* A virtual server can now have more than one MySQL or PostgreSQL database, which can be managed using the Edit Databases button on the Edit Server page. Thanks to Olimont for sponsoring this feature, and the backup changes.
* The default MySQL database name, wildcard and allowed hosts can now be set on the server templates page.
* Added an option to exclude the logs directory from backups.
* On the server template page, default aliases for new users in domains using that template can be specified.
* When editing the forwarding destinations for email to a user, the user's mailbox can be explicitly selected as a destination.
* Added support for Qmail+VPOPMail as a new mail system. When enabled, all mailboxes and aliases are created in VPOPMail instead of using Unix users. Thanks to Linulex for sponsoring this one.
* Added extra domain owner limits to force sub-domains to be under parent domains, and to prevent renaming.
* Added support for Qmail+LDAP as a new mail system. If selected, all mail users and aliases will be stored in LDAP automatically. Thanks to Omar Amas for sponsoring this feature.
* Fixed bug related to multiple IF- blocks for the same variable in templates.

#### Version 2.30
* Added a new limit for domain owners to prevent them from choosing the name for new domain databases.
* Added a button to the Edit Server page for displaying just the usage for that server. This is available to server owners as well as the master administrator.
* Created the Custom Fields page, for defining your own fields that can be edited for each virtual server.
* Added the enable-limit.pl and disable-limit.pl scripts, for updating server owner limits from the command line.
* Added the enable-feature.pl and disable-feature.pl script, for activating and turning off features for a virtual server from the command line.
* Added form on plugins page for editing the configuration of plugins that have a config.info file.
* A database name can be specified when creating a server, rather than the default which is computed from the domain name.
* Similarly, when deleting a server any failure will be ignored, to avoid the problem of features being left around when the server has been removed from Virtualmin.
* When creating a server, if a feature fails for some reason the rest will still be processed. This avoids the problem of a server being partially created and unknown to Virtualmin.
* Clash checking is now done when enabling new features for an existing server.
* Implemented support for using LDAP to store domain and mailbox users and groups, by calling functions in Webmin's LDAP user management module. Requires that the system be set up to use LDAP for NSS and PAM.
* Added button to domain editing page for viewing latest Webalizer report.
* Added the command-line backup-domain.pl script.
* Moved bandwidth graphs to separate page, and added mode to show sub-domain usage.
* Fixed several bugs related to creating and restoring backups.

#### Version 2.10
* Added a Module Config option for a jailed FTP shell.
* Fixed a bug when attempting to rename a PostgreSQL user on older versions that don't allow it.
* Added a restore.pl script to restore domains and features from the command line.
* Added support for mailbox user plugins, which can add additional inputs and capabilities to a mail user.
* Added support for third-party plugin feature modules.
* Added an option to send an email message when a server is approaching (within some percentage) its bandwidth limit.
* Added an option to automatically disable a server when it reaches its bandwidth limit.
* On systems like FreeBSD in which the username length is limited, the prefix for mailbox usernames is now selectable when creating a server.
* The home directory for a virtual server can now be enabled separate from its Unix user.
* Moved all template-related settings into the 'Server Templates' section, including directives for Apache websites, FTP virtual servers and DNS domains. Multiple templates can now be defined, and a template can be selected when creating a virtual server.
* Added the ability to easily edit the forwarding destination for proxy-only or frame forwarding websites, along with the forwarding frame page title or HTML.
* Added an additional way to proxy a virtual server to another URL - frame forwarding.
* A virtual server can now be created without a Unix user, as long as it only has a DNS domain or MySQL or PostgreSQL databases. For other features, the Unix user is required.
* When a mailbox is created, its empty mail file or directory is automatically created, in a location determined by the configuration of the mail server in use.
* The Qmail mail server is now fully supported, with all the same capabilities as Postfix and Sendmail. Only a stock install of Qmail is required by Virtualmin - vpopmail or other similar patches are not needed.
* Added a new format for mailbox usernames - mailbox@domain, the same as the email address. This only works when using Sendmail as the mail server though.
* Added the ability to use new functions in the BIND module to speed up the process of creating slave zones on a remote DNS server.
* Email messages send when a virtual server or mailbox is created can now be also Cc'd to additional configurable addresses.
* The subject lines for emails sent when a new virtual server, sub-server and mailbox are created can now be edited, and can include template variables.
* Added a new feature - the ability to setup Logrotate to automatically truncate and compress a virtual server's log files, so that they don't consume too much disk space.
* Added a new Bandwidth Monitoring page for setting up regular checking of virtual server web bandwidth usage, and inputs on the server creation and editing forms to specify the amount of bandwidth each can use. When the limit is exceeded, a configurable email is sent to the domain owner and other optional addresses. The monitoring page also displays usage and limits by all servers as a bar graph.
* Aliases for an existing virtual server can now be created. An alias is a server that simply forwards all web, mail and DNS requests to another server. Alias websites can be created as a virtual server that simply redirects requests or by adding additional ServerAlias directives to the target website.

#### Version 2.00
* When restoring a virtual server, if it no longer exists it will be automatically re-created with all the original features before the restore is done.
* Added Change Domain Name page for modifying the name of an existing virtual server. This can also update the server's Unix login and home directory at the same time, if needed. All sub-servers of the modified server are also updated, where appropriate.
* Added Manage SSL Certificate page for creating a CSR and installing a signed SSL certificate using simple forms.
* Added Module Config options to have features disabled by default for new servers.
* Added an option to the Apache Website Template page for entering an Apache user to be added to the group for all new servers. This can be useful for getting suexec to work.
* A Virtualmin server owner can now create and own multiple domains, if allowed by the master administrator. All such servers are owned by the same Unix user and share the same quota, and any sub-servers are stored in the domains subdirectory of the parent server's home directory. Each server can have its own independent set of features. When a limit on the number of mailboxes has been set, it will apply to the master server and all sub-servers.
* Added automatic IP address allocation for virtual servers, out of ranges defined on the Module Config page.
* Added an option to the BIND DNS Template page for selecting a view to add new zones to.

#### Version 1.91
* Added a new feature for Virtualmin domains - virtual FTP hosting with ProFTPd. Like Apache virtual hosts, these will be created when the feature is enabled for domain, using directives taken from an editable template. Due to limitations in the FTP protocol, a domain can only have a virtual FTP server if it has its own private IP.
* Added the ability to backup and restore to via SSH, as well as FTP.
* Added Module Config option to specify an different IP address to use in the DNS domain, versus the one used for the webserver.
* Added a Module Config option to set the subdirectory used for mailbox user home directories, instead of always using ~/homes.
* Added checks to prevent an alias or mailbox being created which clashes with an existing Sendmail or Postfix alias.
* Added module configuration options to prevent domain owners from being given access to feature-related modules like Apache Webserver, BIND DNS Server and so on.
* Catchall mail aliases can now forward mail for any mailbox at their domain to the same mailbox at another domain.

#### Version 1.81
* Webalizer configuration files and schedule can now be included in backups.
* IP address clash checking for new servers now actually works.
* Virtualmin now participates in Webmin action logging, so you can see what actions were taken and which files they changed.
* Username length and other restrictions are now checked by the create-domain.pl script.
* A new configuration option has been added for sites that use multiple IP addresses, but always use name-based Apache virtual hosts.
* The MySQL feature now properly supports usernames longer that 16 characters.
* Backups can also be restored from these tar.gz files, again locally or from an FTP server.
* Virtual servers can now be backed up to one or many tar.gz files, either locally or on a remote FTP server.
* The port to use for normal and SSL virtual websites can now be set on the Apache Website Template page.
* Domain owners can be granted access to the Read User Mail module, for reading mailboxe's mail.
* The directory for Webalizer statistics can be set on the Apache Website Template page.
* A Sendmail genericstable or Postfix canonical mapping file can be automatically updated with login name to email address mappings. This is useful for programs like Usermin, which can read such a file to work out From: addresses.
