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
  - PHP configuration and multiple version support (including PHP7)
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

### Getting Support

Virtualmin has active forums at https://forum.virtualmin.com

For commercial support, Virtualmin Professional subscriptions are available starting at $6/month, and include unlimited support tickets in our issue tracker. Hands-on support, custom development, etc. is also available at hourly or project rates.

### Reporting Bugs

Bugs can be reported here at github in the issue tracker or at the ticket tracker on Virtualmin.com.

### Extending Virtualmin

The best way to extend Virtualmin is usually through plugins. Virtualmin plugins are merely Webmin modules, with a few extra files, and some hooks into the Virtualmin API. Webmin module development is documented in the [Webmin Wiki](http://doxfer.webmin.com/Webmin/ModuleDevelopment), and lots of example plugins exist in our other repos (e.g. virtualmin-nginx is a good example of extending core functionality with plugins).

Virtualmin is mostly built in Perl 5.10.1+, with the frontend built in JavaScript and HTML5. It is possible to build Virtualmin components or to interact with Virtualmin in other languages, either via the CLI or remote API, or through reproducing the necessary pieces of the Webmin library in your preferred language (partial implementations of this exist in Python and PHP).

# Maintainers

Our current list of [Maintainers](MAINTAINERS.md).

# Contributors

Virtualmin exists thanks to [all the people who contribute](https://github.com/virtualmin/virtualmin-gpl/graphs/contributors).

[How To Contribute](CONTRIBUTING.rst).

<a href="https://github.com/virtualmin/virtualmin-gpl/graphs/contributors"><img src="https://opencollective.com/virtualmin-gpl/contributors.svg?width=890" /></a>


# Backers

Thank you to all our backers!   [Become a backer](https://opencollective.com/virtualmin-gpl#backer)

<a href="https://opencollective.com/virtualmin-gpl#backers" target="_blank"><img src="https://opencollective.com/virtualmin-gpl/backers.svg?width=890"></a>


# Sponsors

Support Virtualmin by becoming a sponsor. Your logo will show up here with a link to your website.

[Become A Sponsor of Virtualmin.](https://opencollective.com/virtualmin-gpl#sponsor)

<a href="https://opencollective.com/virtualmin-gpl/sponsor/0/website" target="_blank"><img src="https://opencollective.com/virtualmin-gpl/sponsor/0/avatar.svg"></a>
<a href="https://opencollective.com/virtualmin-gpl/sponsor/1/website" target="_blank"><img src="https://opencollective.com/virtualmin-gpl/sponsor/1/avatar.svg"></a>
<a href="https://opencollective.com/virtualmin-gpl/sponsor/2/website" target="_blank"><img src="https://opencollective.com/virtualmin-gpl/sponsor/2/avatar.svg"></a>
<a href="https://opencollective.com/virtualmin-gpl/sponsor/3/website" target="_blank"><img src="https://opencollective.com/virtualmin-gpl/sponsor/3/avatar.svg"></a>
<a href="https://opencollective.com/virtualmin-gpl/sponsor/4/website" target="_blank"><img src="https://opencollective.com/virtualmin-gpl/sponsor/4/avatar.svg"></a>
<a href="https://opencollective.com/virtualmin-gpl/sponsor/5/website" target="_blank"><img src="https://opencollective.com/virtualmin-gpl/sponsor/5/avatar.svg"></a>
<a href="https://opencollective.com/virtualmin-gpl/sponsor/6/website" target="_blank"><img src="https://opencollective.com/virtualmin-gpl/sponsor/6/avatar.svg"></a>
<a href="https://opencollective.com/virtualmin-gpl/sponsor/7/website" target="_blank"><img src="https://opencollective.com/virtualmin-gpl/sponsor/7/avatar.svg"></a>
<a href="https://opencollective.com/virtualmin-gpl/sponsor/8/website" target="_blank"><img src="https://opencollective.com/virtualmin-gpl/sponsor/8/avatar.svg"></a>
<a href="https://opencollective.com/virtualmin-gpl/sponsor/9/website" target="_blank"><img src="https://opencollective.com/virtualmin-gpl/sponsor/9/avatar.svg"></a>
