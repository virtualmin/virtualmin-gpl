## Virtualmin

Virtualmin virtual-server web hosting control panel module for Webmin.


[![Quick UI overview 2021](https://user-images.githubusercontent.com/4426533/114315538-120fc880-9b08-11eb-9cd6-b6a5f8420235.png)](https://www.youtube.com/watch?v=daYG6O4AsEw&feature=emb_logo)

Virtualmin is a full-featured open source web hosting control panel for Linux and \*BSD systems. This is the core virtual-server module, and there are a couple dozen additional plugins for Virtualmin, to provide additional features, like nginx support, SQLite and Oracle database support, support for other DNS and mail servers, etc. You'll need a full LAMP (or LEMP) stack, plus Webmin, to make this useful. There is an easy to use install script available from [Virtualmin.com](https://www.virtualmin.com/download) that will install everything you need on supported platforms (CentOS, Ubuntu, and Debian, at this time).

We *strongly* recommend you run Virtualmin on one of these Linux distros, and start with the install script. Setting up a full-featured virtual hosting system is extremely complex, with dozens of packages and configuration files. Even if you *can* do it, you probably shouldn't. That said, we welcome help adding support for other distros and versions. Check out the [Virtualmin Install](http://github.com/virtualmin/virtualmin-install) project for details on development.

Virtualmin includes the following features (and more):

  - Web server virtual host configuration (VirtualHost in Apache)
  - Let's Encrypt! SSL certificate support
  - Mailboxes with spam and AV scanning using Postfix, Sendmail, or QMail (Postfix recommended)
  - Webmail (our own Usermin, RoundCube, and others)
  - Database management (MySQL, MariaDB, PostgreSQL, with optional modules for SQLite and Oracle)
  - FTP/ssh users
  - Web application installation and upgrades (more applications available in Virtualmin Pro)
  - PHP configuration and multiple version support (including PHP7 and PHP8)
  - PHP-FPM and mod_fcgid execution modes, with suexec
  - Ruby Gems, PHP Pear, and Perl CPAN package installation
  - System analytics
  - Log analysis
  - Domain backup and restoration
  - Easy import of cPanel, Plesk, and DirectAdmin domain backups
  - Modern, friendly, responsive, and beautiful web UI, with many color schemes and options
  - Comprehensive CLI and remote API
  - Powerful HTML5/JS file manager
  - Tons of plugins
  - Big community of users (over 100,000 active installations)
  - Based on Webmin! (over a million installations worldwide!)

Virtualmin has been under consistent development since ~2003, averaging a new release every couple of months.

### Contributing Translations

If you'd like to help improve Virtualmin translations, please see our [translation contribution guide](https://www.virtualmin.com/docs/development/translations/) first.

The following languages are currently supported for Virtualmin:

| Language | Human | Machine | Missing | Coverage (Human vs. Total) |
|----------|-------|---------|---------|----------------------------|
| cs       | 1198  | 6992    | 18      |  14.6%   /   99.8%         |
| de       | 4025  | 4165    | 18      |  49.0%   /   99.8%         |
| en       | 8207  | 0       | 0       |  100.0%  /  100.0%         |
| es       | 4188  | 4002    | 18      |  51.0%   /   99.8%         |
| fr       | 2581  | 5609    | 18      |  31.4%   /   99.8%         |
| it       | 1356  | 6834    | 18      |  16.5%   /   99.8%         |
| ja       | 0     | 8190    | 18      |   0.0%   /   99.8%         |
| nl       | 5110  | 3080    | 18      |  62.3%   /   99.8%         |
| no       | 5641  | 2549    | 18      |  68.7%   /   99.8%         |
| pl       | 7815  | 375     | 18      |  95.2%   /   99.8%         |
| pt_BR    | 270   | 7920    | 18      |   3.3%   /   99.8%         |
| ru       | 1303  | 6887    | 18      |  15.9%   /   99.8%         |
| sk       | 0     | 8190    | 18      |   0.0%   /   99.8%         |
| tr       | 2496  | 5694    | 18      |  30.4%   /   99.8%         |
| zh       | 2970  | 5220    | 18      |  36.2%   /   99.8%         |
| zh_TW    | 2970  | 5220    | 18      |  36.2%   /   99.8%         |


### Getting Support

Virtualmin has active forums at https://forum.virtualmin.com

For commercial support, Virtualmin Professional subscriptions are available starting at $7.50/month, and include unlimited support tickets in our issue tracker. Hands-on support, custom development, etc. may also available at hourly or project rates, depending on developer availability.

### Reporting Bugs

Bugs can be reported here at github in the issue tracker. Please email security-related bug reports to security@webmin.com.

### Extending Virtualmin

The best way to extend Virtualmin is usually through plugins. Virtualmin plugins are merely Webmin modules, with a few extra files, and some hooks into the Virtualmin API. Webmin module development is documented in the [Webmin Wiki](http://doxfer.webmin.com/Webmin/ModuleDevelopment), and lots of example plugins exist in our other repos (e.g. virtualmin-nginx is a good example of extending core functionality with plugins).

Virtualmin is mostly built in Perl 5.16+, with the frontend built in JavaScript and HTML5. It is possible to build Virtualmin components or to interact with Virtualmin in other languages, either via the CLI or remote API, or through reproducing the necessary pieces of the Webmin library in your preferred language (partial implementations of this exist in Python and PHP).
