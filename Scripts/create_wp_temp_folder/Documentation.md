# Ensure WP_TEMP_DIR Definition for WordPress Apps

This script ensures all WordPress applications hosted under `/home/runcloud/webapps` have a `WP_TEMP_DIR` defined in their `wp-config.php`. This is necessary to prevent the common error: **"Missing a Temporary Folder"** during media uploads.

## 🛠 What It Does

- Iterates through each subdirectory in `/home/runcloud/webapps`
- Checks for the presence of a `wp-config.php` file
- If found:
    - Verifies if `WP_TEMP_DIR` is already defined
    - If not, appends the following line to the bottom of `wp-config.php`:

      ```php
      define('WP_TEMP_DIR', dirname(__FILE__) . '/wp-content/temp/');
      ```

- (Optional enhancement) Ensures the `/wp-content/temp/` directory exists


## 📬 Author

GrowME DevOps – Dmytro Kovalenko
