#!/usr/local/bin/perl
# Convert all Virtualmin API POD docs into Wiki format, and upload them to
# virtualmin.com.

$wiki_pages_host = "virtualmin.com";
$wiki_pages_user = "virtualmin";
$wiki_pages_dir = "/home/virtualmin/domains/jdev.virtualmin.com/public_html/components/com_openwiki/data/pages";
@api_categories = (
	[ "Virtual servers", "*-domain.pl", "*-domains.pl",
			     "enable-feature.pl", "disable-feature.pl" ],
	[ "Mail and FTP users", "*-user.pl", "*-users.pl" ],
	[ "Mail aliases", "*-alias.pl", "*-aliases.pl",
			  "create-simple-alias.pl", "list-simple-aliases.pl" ],
	[ "Server owner limits", "*-limit.pl", "*-limits.pl" ],
	[ "Backup and restore", "backup-domain.pl", "list-scheduled-backups.pl",
				"restore-domain.pl" ],
	[ "Extra administrators", "*-admin.pl", "*-admins.pl" ],
	[ "Custom fields", "*-custom.pl" ],
	[ "Databases", "*-database.pl", "*-databases.pl",
		       "modify-database-hosts.pl" ],
	[ "Reseller accounts", "*-reseller.pl", "*-resellers.pl" ],
	[ "Script installers", "install-script.pl", "delete-script.pl",
			       "list-scripts.pl", "list-available-scripts.pl" ],
	[ "Proxies and balancers", "*-proxy.pl", "*-proxies.pl" ],
	[ "PHP versions", "*-php-directory.pl", "*-php-directories.pl" ],
	[ "Other scripts", "*.pl" ],
	);

# Go to script's directory
if ($0 =~ /^(.*\/)[^\/]+$/) {
	chdir($1);
	}
chop($pwd = `pwd`);

# Build category mappings
my %catmap;
foreach my $c (@api_categories) {
	my ($cname, @cglobs) = @$c;
	foreach my $cglob (@cglobs) {
		foreach $f (glob($cglob)) {
			$catmap{$f} ||= $cname;
			}
		}
	}

# Find all API scripts
@apis = ( );
opendir(DIR, $pwd);
foreach my $f (readdir(DIR)) {
	if ($f =~ /\.pl$/) {
		local $/ = undef;
		open(FILE, "$pwd/$f");
		my $data = <FILE>;
		close(FILE);
		if ($data =~ /=head1/) {
			push(@apis, { 'file' => $f,
				      'path' => "$pwd/$f",
				      'data' => $data,
				      'cat' => $catmap{$f} });
			}
		}
	}

# XXX identify categories (domains, users, etc..)
# XXX category summaries?

# XXX convert to wiki format

# XXX extract command-line args summary

# XXX upload

# XXX create index pages and upload
