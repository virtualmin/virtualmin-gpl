#!/usr/local/bin/perl
#
# login_phpmyadmin.cgi
#
# Auto-login to phpMyAdmin for a Virtualmin domain without changing any
# phpMyAdmin configuration.

require './virtual-server-lib.pl';
&ReadParse();

# Get domain and check permissions
my $d = &get_domain($in{'dom'});
&domain_has_website($d) && $d->{'dir'} ||
	&error($text{'databases_login_pma_eweb'});
&can_edit_databases($d) || &error($text{'databases_ecannot'});

# Find phpMyAdmin installation details for this domain or its subdomains
my @phpmyadmin = grep { $_->{'name'} eq 'phpmyadmin' } &list_domain_scripts($d);

# Perhaps a subdomain has it installed?
if (!@phpmyadmin && $d->{'parent'}) {
	$d = &get_domain($d->{'parent'});
	@phpmyadmin = grep { $_->{'name'} eq 'phpmyadmin' }
		&list_domain_scripts($d);
	}

# Perhaps global is available?
my $src_dom = $d;
if (!@phpmyadmin) {
	my @all_glob = &list_all_global_def_scripts_cached();
	@phpmyadmin = grep { $_->{'name'} eq 'phpmyadmin' } @all_glob;
	$src_dom = &get_domain($phpmyadmin[0]->{'dom_id'}) if (@phpmyadmin);
	}
@phpmyadmin || &error($text{'databases_login_pma_enopma'});
@phpmyadmin = sort { ($b->{'time'} || 0) <=> ($a->{'time'} || 0) } @phpmyadmin;
my $pma = $phpmyadmin[0];
my $pma_dir = $pma->{'opts'}->{'dir'} ||
	&error($text{'databases_login_pma_einfo'});
$pma_dir =~ /^\// || &error($text{'databases_login_pma_einfo'});

# Use the recorded canonical URL for this install
my $pma_url = $pma->{'url'} || &error($text{'databases_login_pma_eurl'});
$pma_url =~ /^https?:\/\/.+/ || &error($text{'databases_login_pma_badurl'});
$pma_url =~ s/\s+//g;
$pma_url =~ s/\/+$/\//;

# Domain MySQL credentials always come from the parent domain unless already
$d = &get_domain($d->{'parent'}) if ($d->{'parent'});
my $dbuser = $d->{'mysql_user'} || &error($text{'databases_login_pma_euser'});
my $dbpass = $d->{'mysql_pass'} || &error($text{'databases_login_pma_epass'});

# Optional database to open after login
my $dbname = $in{'dbname'} || '';
if ($dbname) {
	$dbname =~ /^[A-Za-z0-9_.-]+$/ ||
		&error(&text('databases_login_pma_baddb', $dbname));
	}

# Private directory under the domain home
my $home = $src_dom->{'home'} || &error($text{'databases_login_pma_ehome'});
$home =~ /^\// || &error($text{'databases_login_pma_ehome'});

my $privdir = "$home/.pma-login";
$privdir =~ s/([^:])\/\//$1\//g;

# Random helper filename and one-shot nonce
my $rid = &substitute_pattern('[a-f0-9]{40}');
my $non = &substitute_pattern('[a-f0-9]{40}');
my $php_filename = "pma-login-$rid.php";
my $php_fullpath = "$pma_dir/$php_filename";
$php_fullpath =~ s/([^:])\/\//$1\//g;
my $credfile = "$privdir/login-phpmyadmin-$rid.cred";
$credfile =~ s/([^:])\/\//$1\//g;

# Create the private directory as the domain user so PHP can traverse it
if (!-d $privdir) {
	&make_dir_as_domain_user($src_dom, $privdir, 0700) ||
		&error(&text('databases_login_pma_emkdirhome', $privdir));
	}

# Store credentials outside the web directory
my $u64 = &encode_base64($dbuser); $u64 =~ s/\s+//g;
my $p64 = &encode_base64($dbpass); $p64 =~ s/\s+//g;

# Write the credential file as the domain user so PHP can read it
eval { &write_as_domain_user($src_dom, sub {
		&write_file_contents($credfile, join("\n",
			"u64=$u64",
			"p64=$p64",
			"db=$dbname",
			"nonce=$non",
			"")."");
		chmod(0600, $credfile);
	});
};
$@ && &error($text{'databases_login_pma_ecredwrite'});

# One-shot PHP helper content
my $php = <<'EOF';
<?php
declare(strict_types=1);

/* Template placeholders */
const NONCE    = '__NONCE__';
const PMAURL   = '__PMAURL__';
const CREDFILE = '__CREDFILE__';

/* Write debug info into the standard PHP error log */
function log_msg(string $msg): void
{
	error_log('Virtualmin phpMyAdmin autologin: '.$msg);
}

/* Log the reason, return a status code, and exit */
function fail(int $code, string $msg): void
{
	log_msg($msg);
	http_response_code($code);
	exit;
}

/* Remove secrets and remove this helper file and its directory if empty */
function cleanup(): void
{
	@unlink(CREDFILE);
	@rmdir(dirname(CREDFILE));
	@unlink(__FILE__);
}

/* Build the phpMyAdmin index URL */
function pma_index_url(): string
{
	return rtrim(PMAURL, '/').'/index.php';
}

/* Read key/value credentials from the credential file */
function read_creds(): array
{
	if (!is_file(CREDFILE)) {
		fail(500, 'credfile missing');
	}
	if (!is_readable(CREDFILE)) {
		fail(500, 'credfile not readable');
	}
	$mt = @filemtime(CREDFILE);
	if ($mt === false) {
		fail(500, 'failed to stat credfile');
	}
	if ($mt < time() - 30) {
		@unlink(CREDFILE);
		@rmdir(dirname(CREDFILE));
		fail(410, 'credential file expired');
	}

	$lines = @file(CREDFILE, FILE_IGNORE_NEW_LINES);
	if (!is_array($lines)) {
		fail(500, 'failed to read credfile');
	}
	@unlink(CREDFILE);
	@rmdir(dirname(CREDFILE));

	$vals = [];
	foreach ($lines as $ln) {
		$ln = rtrim($ln, "\r\n");
		$pos = strpos($ln, '=');
		if ($pos === false) {
			continue;
		}

		$key = substr($ln, 0, $pos);
		$val = substr($ln, $pos + 1);

		if ($key === 'u64' || $key === 'p64' ||
		    $key === 'db' || $key === 'nonce') {
			$vals[$key] = $val;
		}
	}

	if (empty($vals['u64']) || empty($vals['p64']) ||
	    empty($vals['nonce'])) {
		fail(500, 'credfile missing keys');
	}

	return $vals;
}

/* Create a cookie jar file for cURL */
function cookiejar_path(): string
{
	$fn = tempnam(sys_get_temp_dir(), 'pma_');
	if ($fn === false) {
		fail(500, 'failed to create temp file');
	}
	return $fn;
}

register_shutdown_function('cleanup');

/* Enforce the one-shot nonce to prevent guessing the helper URL */
$n = (string)($_GET['n'] ?? '');
if ($n === '' || !hash_equals(NONCE, $n)) {
	fail(403, 'bad nonce');
}

$vals = read_creds();

/* The cred file also contains the nonce, so a reused helper URL won't work */
if (!hash_equals($vals['nonce'], NONCE)) {
	fail(403, 'nonce mismatch against credfile');
}

/* Decode credentials derived from a temp file */
$user = base64_decode($vals['u64'], true);
$pass = base64_decode($vals['p64'], true);
if ($user === false || $pass === false) {
	fail(500, 'failed to decode credentials');
}

/* Optional database to open after login */
$db = isset($vals['db']) ? (string)$vals['db'] : '';

/* phpMyAdmin login URL */
$login_idx = pma_index_url();

/* After login, optionally open a database page */
$dest = $login_idx;
if ($db !== '') {
	$dest .= '?route=/database/structure&db='.rawurlencode($db);
}

/* phpMyAdmin login emulation needs cURL */
if (!function_exists('curl_init')) {
	fail(500, 'PHP ext-curl not available');
}

$cookiejar = cookiejar_path();

/* Remove the cookie jar on exit */
register_shutdown_function(static function () use ($cookiejar): void {
	@unlink($cookiejar);
});

/* Fetch the phpMyAdmin login page so we get cookies and the CSRF token */
$ch = curl_init();
curl_setopt_array($ch, [
	CURLOPT_RETURNTRANSFER => true,
	CURLOPT_HEADER => true,
	CURLOPT_FOLLOWLOCATION => false,
	CURLOPT_COOKIEJAR => $cookiejar,
	CURLOPT_COOKIEFILE => $cookiejar,
	CURLOPT_TIMEOUT => 10,
]);

curl_setopt($ch, CURLOPT_URL, $login_idx);
curl_setopt($ch, CURLOPT_HTTPGET, true);

$res = curl_exec($ch);
if ($res === false) {
	fail(502, 'GET failed: '.curl_error($ch));
}

$hsz  = (int)curl_getinfo($ch, CURLINFO_HEADER_SIZE);
$body = substr($res, $hsz);

if (!preg_match('/name="token"\s+value="([^"]+)"/', $body, $m)) {
	fail(502, 'CSRF token not found on login page');
}
$token = html_entity_decode($m[1], ENT_QUOTES | ENT_HTML5);

/* Submit the login form with the token and credentials */
$post = http_build_query([
	'pma_username' => $user,
	'pma_password' => $pass,
	'server'       => '1',
	'token'        => $token,
], '', '&');

curl_setopt_array($ch, [
	CURLOPT_URL => $login_idx,
	CURLOPT_POST => true,
	CURLOPT_POSTFIELDS => $post,
	CURLOPT_HTTPHEADER => [ 'Content-Type: application/x-www-form-urlencoded' ],
]);

$res2 = curl_exec($ch);
if ($res2 === false) {
	fail(502, 'POST failed: '.curl_error($ch));
}

/* Forward session cookies to the browser so it is actually logged in */
$hsz2 = (int)curl_getinfo($ch, CURLINFO_HEADER_SIZE);
$hdrs = substr($res2, 0, $hsz2);

curl_close($ch);

foreach (preg_split("/\r\n|\n|\r/", $hdrs) as $h) {
	if (stripos($h, 'Set-Cookie:') === 0) {
		header($h, false);
	}
}

/* Enter phpMyAdmin */
header('Location: '.$dest);
exit;
EOF

# Escape a string for embedding in single-quoted PHP
my $php_sq = sub {
	my ($s) = @_;
	$s =~ s/\r|\n//g;
	$s =~ s/\\/\\\\/g;
	$s =~ s/'/\\'/g;
	return $s;
};

$php =~ s/__NONCE__/$non/g;
$php =~ s/__PMAURL__/$php_sq->($pma_url)/ge;
$php =~ s/__CREDFILE__/$php_sq->($credfile)/ge;

# Write helper inside the phpMyAdmin directory as the domain user
eval { &write_as_domain_user($src_dom, sub {
		&write_file_contents($php_fullpath, $php);
		chmod(0600, $php_fullpath); }) };
if ($@) {
	unlink($credfile);
	&error($text{'databases_login_pma_ephpwrite'});
	}

print "Location: $pma_url$php_filename?n=$non\n\n";
