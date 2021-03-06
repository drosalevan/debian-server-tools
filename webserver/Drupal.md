# Drupal setup

http://drushcommands.com/

## Prerequisites

- drush, see: /debian-setup.sh
- `sites/default/drushrc.php`: `<?php $options['uri'] = "http://DOMAIN.TLD/";`
- Configuration: https://github.com/drush-ops/drush/blob/master/examples/example.drushrc.php
- PHP-FPM pool: `php_admin_value[allow_url_fopen] = On`
- first run: `udrush status`

## Modules

### Browse modules

`udrush pmi --format=yaml`

### Enable module

`udrush en <MODULE-NAME> -y`

### Caches

#### APC cache backend.

`udrush en apc -y`

`settings.php`:

```php
$conf['cache_backends'][] = 'sites/all/modules/apc/drupal_apc_cache.inc';
$conf['cache_default_class'] = 'DrupalAPCCache';
//$conf['apc_show_debug'] = TRUE;  // Remove the slashes to use debug mode.
```

#### Object cache

`udrush en entitycache -y`

Entity caching is supported in Drupal 8.

#### Preload page cache

See: ${D}/webserver/preload-cache.sh

### Fail2ban

https://github.com/szepeviktor/wordpress-fail2ban

### Mollom

```ini
suhosin.get.max_array_index_length = 128
suhosin.post.max_array_index_length = 128
suhosin.request.max_array_index_length = 128
```

### Automatic translation updates

`udrush en l10n_update -y`

admin/config/regional/translate/update

### Sitemap

Enable inclusion per content type.

`udrush en xmlsitemap -y`

## Drupal menus

- All options: admin/config
- admin/config/media/file-system
- JPEG qulite: 90% admin/config/media/image-toolkit
- admin/config/development/performance
- admin/config/regional
- Backup settings.php && database

### General website tasks

- logging/tmp/upload/session + gc
- mail from
- root files

### Cron

- http://cgit.drupalcode.org/drush/plain/docs/cron.html
- /usr/local/bin/drush --quiet --root=/home/webuser/website/html core-cron
- /usr/bin/wget -qO- "http://www.website.net/cron.php?cron_key=AAAAAAAAAAAAAAAAAA1111111111111111111111111"
