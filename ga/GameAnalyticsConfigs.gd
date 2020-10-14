class_name GameAnalyticsConfigs
extends Resource

# GA configs
export(String) var build
export(String) var custom1
export(String) var custom2
export(String) var custom3

# Add-on configs
export(bool) var auto_init = true
export(bool) var auto_submit = true
export(bool) var verbose_log = false
export(String) var log_name = 'GA'
export(bool) var encrypt_local_data = true
export(float) var session_check_interval = 5
export(float) var event_submit_interval = 10
export(bool) var archive_submited_events = false
