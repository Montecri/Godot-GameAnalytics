class_name GameAnalytics
extends Node
# GameAnalytics <https://gameanalytics.com/> GDScript REST API implementation

signal init(status_code)

# Platform remaps
const PLATFORMS = {
	'Windows': 'windows',
	'X11': 'linux',
	'OSX': 'mac_osx',
	'Android': 'android',
	'iOS': 'ios',
	'HTML5': 'webgl',
}

# Available API endpoints
const INIT_ENDPOINT = '/v2/%s/init'
const EVENTS_ENDPOINT = '/v2/%s/events'

const api_version = 2
const plugin_version = '1.0'
const sdk_version = 'rest api v2'
var engine_version = 'godot {major}.{minor}.{patch}'.format(Engine.get_version_info())
var platform
var os_version
var device
var manufacturer
var user_id

var DEBUG = OS.is_debug_build()
var _connected
var _connecting = false

const archive_path = "user://.archive.ga"
const event_queue_path = "user://.eventqueue.ga"
const session_path = "user://.session.ga"

var session_events = {
	0: [],
}
var submitting_events = {}
var submitting = false
var session = {
	'session_num': 0,
	'session_id': '',
	'session_length': 0,
}

var session_start :int
var session_check_timer = 0
var event_submit_timer = 0
var ts_offset = 0
var default_annotations :Dictionary

const HTTP_CONNECTING = [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]
var HTTP = HTTPClient.new()
var DIR = Directory.new()


var _api = GameAnalyticsAPI.new()
var _configs = GameAnalyticsConfigs.new()


func _init():
	_init_platform_info()
	initialize()

func _enter_tree():
	_load_event_queue()
	_load_session()

func _process(delta):
	session_check_timer += delta
	if session_check_timer >= _configs.session_check_interval:
		session_check_timer = 0
		session.session_length = OS.get_unix_time() - session_start
		_save_session()
	if _configs.auto_submit and not submitting:
		event_submit_timer += delta
		if event_submit_timer >= _configs.event_submit_interval:
			event_submit_timer = 0
			call_deferred('submit_events')

func initialize():
	pass

func debug_log(arg):
	if DEBUG:
		print('[%s] ' % _configs.log_name, arg)

func verbose_log(arg):
	if _configs.verbose_log:
		print_debug('[%s] ' % _configs.log_name, arg)

func error_log(arg):
	push_error('[%s] %s' % [_configs.log_name, arg])

func configure(api=null, configs=null):
	if api:
		_api = api
	if configs:
		_configs = configs
	_init_default_annotations()
	if _configs.auto_init:
		if not is_inside_tree():
			yield(self, "tree_entered")
		call_deferred("request_init")

func _init_platform_info():
	# Defaults
	platform = PLATFORMS[OS.get_name()]
	os_version = platform + ' 0.0.0'
	device = OS.get_model_name().to_lower()
	manufacturer = 'unknown'
	user_id = OS.get_unique_id().to_lower()

	if platform == "android":
		var output = []
		OS.execute("getprop", ["ro.build.version.release"], true, output)
		os_version = platform + " " + output[0].strip_edges()
	elif platform == 'windows':
		manufacturer = 'microsoft'
		var rg = RegEx.new()
		var win_version
		# NOTE: Trying to get version using the File API to avoid OS.execute()
		var setupapi_log = OS.get_environment('SystemRoot')+'\\inf\\setupapi.dev.log'
		if DIR.file_exists(setupapi_log):
			var f = File.new()
			f.open(setupapi_log, File.READ)
			# Output example: OS Version = 10.0.18363
			rg.compile('OS\\s?Version\\s?=\\s?(\\d+\\.\\d+(\\.\\d+)?)')
			var line_count = 0
			while line_count < 10:
				var line = f.get_line()
				var line_rg = rg.search(line)
				if line_rg:
					win_version = line_rg.get_string(1)
					break
				line_count += 1
		if not win_version:
			var output = []
			# Executing shell script `ver` (cmd.exe only)
			OS.execute('cmd', ['/c', 'ver'], true, output)
			if not output.empty():
				# Output example: `Microsoft Windows [Version 10.0.18362.388]`
				rg.compile("(\\d+\\.\\d+\\.\\d+)")
				var result = rg.search(output[0])
				if result:
					win_version = result.get_string(1).strip_edges()
		os_version = platform + ' ' + win_version
	elif platform == 'linux':
		var rg = RegEx.new()
		var f = File.new()
		f.open('/proc/version', File.READ)
		var proc_version = f.get_as_text()
		f.close()
		# Output example: Linux version 5.4.0-28-generic (user@host) [...]
		rg.compile("\\s(\\d+\\.\\d+(\\.\\d+)?)")
		var kernel_version = '0.0.0'
		var kernel_version_rg = rg.search(proc_version)
		if kernel_version_rg:
			kernel_version = kernel_version_rg.get_string(1)
		f.open('/etc/os-release', File.READ)
		var os_release = f.get_as_text()
		f.close()
		# Output example: ID=ubuntu
		rg.compile("\\bID=(.+)\\b")
		var distro_id = 'linux'
		var distro_id_rg = rg.search(os_release)
		if distro_id_rg:
			distro_id = distro_id_rg.get_string(1).strip_edges().replace('"', '').to_lower()
		# Output example: VERSION_ID="20.04"
		rg.compile("\\bVERSION_ID=\\D?(\\d+\\.\\d+(\\.\\d+)?)")
		var distro_version = '0.0.0'
		var distro_version_rg = rg.search(os_release)
		if distro_version_rg:
			distro_version = distro_version_rg.get_string(1)
		elif DIR.file_exists('/etc/lsb-release'):
			f.open('/etc/lsb-release', File.READ)
			var lsb_release = f.get_as_text()
			f.close()
			# Output example: DISTRIB_RELEASE=20.04
			rg.compile("\\bDISTRIB_RELEASE=\\D?(\\d+\\.\\d+(\\.\\d+)?)")
			distro_version_rg = rg.search(lsb_release)
			if distro_version_rg:
				distro_version = distro_version_rg.get_string(1)
		os_version = platform + ' ' + kernel_version
		manufacturer = distro_id + ' ' + distro_version
	elif platform == 'webgl':
		user_id = UUID.v4(false) # FIXME: HTML5 doesn't have support for device uuid
		var f = File.new()
		var base_path = 'res://ga/' # TODO: Improve javascript code storage
		f.open(base_path.plus_file('get_browser.js'), File.READ)
		var js_get_browser = f.get_as_text()
		f.close()
		var browser = JavaScript.eval(js_get_browser, false)
		if browser:
			browser = parse_json(browser.to_lower())
			if browser:
				var video_driver = 1 if OS.get_current_video_driver() == OS.VIDEO_DRIVER_GLES2 else 2
				os_version = '%s %s' % [platform, video_driver]
				manufacturer = '%s %s' % [browser.get('name', 'unknown'), browser.get('version', '0.0.0')]
	debug_log('PLATFORM:%s - %s' % [os_version, manufacturer])

func _init_default_annotations():
	default_annotations = {
		'v': api_version, # (required: Yes)
		'user_id': user_id, # (required: Yes)
		'os_version': os_version, # (required: Yes)
		'manufacturer': manufacturer, # (required: Yes)
		'device': device, # (required: Yes - if not possible set "unknown")
		'platform': platform, # (required: Yes)
		'sdk_version': sdk_version, # (required: Yes)
		'engine_version': engine_version, # (required: No - send if set by an engine)
		# 'ios_idfa': idfa, # (required: No - required on iOS)
		# 'ios_idfv': idfv, # (required: No - send if found)
		# 'google_aid' # (required: No - required on Android)
		# 'android_id', # (required: No - send if set)
		# 'googleplus_id', # (required: No - send if set)
		# 'facebook_id', # (required: No - send if set)
		# 'limit_ad_tracking', # (required: No - send if true)
		# 'logon_gamecenter', # (required: No - send if true)
		# 'logon_googleplay # (required: No - send if true)
		# 'gender': 'male', # (required: No - send if set)
		# 'birth_year # (required: No - send if set)
		# 'progression # (required: No - send if a progression attempt is in progress)                         # (required: No - send if set)
		# 'connection_type': 'wifi', # (required: No - send if available)
		# 'jailbroken # (required: No - send if true)
	}
	if _configs.build:
		default_annotations['build'] = _configs.build
	if _configs.custom1:
		default_annotations['custom_01'] = _configs.custom1
	if _configs.custom2:
		default_annotations['custom_02'] = _configs.custom2
	if _configs.custom3:
		default_annotations['custom_03'] = _configs.custom3

func _load_session():
	if DIR.file_exists(session_path):
		var f = File.new()
		if _configs.encrypt_local_data:
			f.open_encrypted_with_pass(session_path, File.READ, _api.secret_key)
		else:
			f.open(session_path, File.READ)
		session = f.get_var(true)
		end_session()
	new_session()

func _load_event_queue():
	if DIR.file_exists(event_queue_path):
		var f = File.new()
		if _configs.encrypt_local_data:
			f.open_encrypted_with_pass(event_queue_path, File.READ, _api.secret_key)
		else:
			f.open(event_queue_path, File.READ)
		session_events = f.get_var(true)
		debug_log('EVENTS:Loaded events in queue')
		verbose_log(session_events)

func _save_session():
	var f = File.new()
	if _configs.encrypt_local_data:
		f.open_encrypted_with_pass(session_path, File.WRITE, _api.secret_key)
	else:
		f.open(session_path, File.WRITE)
	f.store_var(session)
	f.close()

func _save_event_queue():
	var f = File.new()
	if _configs.encrypt_local_data:
		f.open_encrypted_with_pass(event_queue_path, File.WRITE, _api.secret_key)
	else:
		f.open(event_queue_path, File.WRITE)
	f.store_var(session_events, true)
	f.close()

func _parse_header(json_data):
	return [
		"Authorization: " + Marshalls.raw_to_base64(_hmac_sha256(json_data, _api.secret_key)),
		"Content-Type: application/json",
		"Content-Encoding: gzip",
	]

func request_init():
	if _connecting:
		return yield(self, "init")
	_connecting = true
	var endpoint = INIT_ENDPOINT % _api.game_key
	var payload = {
		'platform': platform,
		'os_version': os_version,
		'sdk_version': sdk_version
	}
	var payload_bytes = to_json(payload).to_utf8().compress(File.COMPRESSION_GZIP)
	var headers = _parse_header(payload_bytes)

	verbose_log('INIT:Connecting')
	HTTP.connect_to_host(_api.base_url, 80)
	while HTTP.get_status() in HTTP_CONNECTING:
		HTTP.poll()
		yield(get_tree(), "idle_frame")
	assert(HTTP.get_status() == HTTPClient.STATUS_CONNECTED)

	verbose_log('INIT:Requesting')
	HTTP.request_raw(HTTPClient.METHOD_POST, endpoint, headers, payload_bytes)
	while HTTP.get_status() == HTTPClient.STATUS_REQUESTING:
		HTTP.poll()
		yield(get_tree(), "idle_frame")

	var response_code = HTTP.get_response_code()
	verbose_log('INIT:Response %s' % response_code)
	var response_data = PoolByteArray()
	while HTTP.get_status() == HTTPClient.STATUS_BODY:
		HTTP.poll()
		var chunk = HTTP.read_response_body_chunk()
		if chunk.size() != 0:
			response_data = response_data + chunk
			yield(get_tree(), "idle_frame")
	var info = parse_json(response_data.get_string_from_utf8())
	_connecting = false
	if response_code == 200:
		verbose_log('INIT:Body #%s#' % info)
		if info:
			var server_ts = info.get('server_ts')
			if server_ts != null:
				_update_server_ts(server_ts)
		emit_signal("init", response_code)
		_connected = true
		debug_log("INIT:Successfully initialized.")
		return OK
	debug_log('INIT:Body #%s#' % info)
	error_log("INIT:Initialization failed.")
	return FAILED

func _update_server_ts(server_ts):
	# I still don't know how this is supposed to work...
	ts_offset = OS.get_unix_time() - server_ts

func _add_to_event_queue(event_dict):
	session_events[session.session_num].append(event_dict)
	_save_event_queue()

func submit_events():
	if _connected == null:
		yield(request_init(), "completed")
	#if not _connected:
	#	debug_log('Not connected - Not implemented')
	#	return
	var has_events = false
	for i in session_events:
		if not session_events[i].empty():
			has_events = true
			break
	if has_events:
		submitting_events = session_events.duplicate(true)
		submitting = true
		for i in session_events:
			session_events[i].clear()
		_submit_events()
	else:
		verbose_log('EVENTS:No events to submit')

func _submit_events():
	var endpoint = EVENTS_ENDPOINT % _api.game_key
	var event_list = []
	for i in submitting_events:
		if not submitting_events[i].empty():
			event_list += submitting_events[i]
	var events_bytes = to_json(event_list).to_utf8().compress(File.COMPRESSION_GZIP)
	var headers = _parse_header(events_bytes)
	
	verbose_log('EVENTS:Connecting')
	var err = HTTP.connect_to_host(_api.base_url, 80)
	while HTTP.get_status() in HTTP_CONNECTING:
		HTTP.poll()
		yield(get_tree(), "idle_frame")
	
	verbose_log('EVENTS:Requesting')
	HTTP.request_raw(HTTPClient.METHOD_POST, endpoint, headers, events_bytes)
	while HTTP.get_status() == HTTPClient.STATUS_REQUESTING:
		HTTP.poll()
		yield(get_tree(), "idle_frame")
	
	var response_code = HTTP.get_response_code()
	verbose_log('EVENTS:Response %s' % response_code)
	var response_data = PoolByteArray()
	while HTTP.get_status() == HTTPClient.STATUS_BODY:
		HTTP.poll()
		var chunk = HTTP.read_response_body_chunk()
		if chunk.size() != 0:
			response_data = response_data + chunk
			yield(get_tree(), "idle_frame")
	var info = parse_json(response_data.get_string_from_utf8())
	if response_code == 200:
		verbose_log('EVENTS:Body #%s#' % [info])
		debug_log('EVENTS:All events were successfully submitted.')
		_clear_event_queue()
	else:
		debug_log('EVENTS:Body #%s#' % [info])
		error_log('EVENTS:Failed to send events.')
		_restore_event_queue()
	submitting = false

func _clear_event_queue():
	if _configs.archive_submited_events:
		# Not implemented yet.
		pass
	var empty_keys = []
	for s in session_events:
		if s != session.session_num and session_events[s].empty():
			# Dictionary.erase() does not erase elements while iterating over the dictionary.
			empty_keys.append(s)
	for k in empty_keys:
		session_events.erase(k)
	_save_event_queue()

func _restore_event_queue():
	for i in submitting_events:
		session_events[i] += submitting_events[i]
		submitting_events[i].clear()
	_save_event_queue()

func _generate_session_id():
	return UUID.v4()

func _set_session(id, num):
	session.session_num = num
	session.session_id = id
	if not num in session_events:
		session_events[num] = []

func add_event(event_dict, add_annotations=true):
	if add_annotations:
		_merge_dict(event_dict, default_annotations)
	_merge_dict(event_dict, _get_ts())
	_merge_dict(event_dict, _get_session_info())
	_add_to_event_queue(event_dict)

func new_session():
	session_start = OS.get_unix_time()
	_set_session(_generate_session_id(), session.session_num+1)
	_add_user_event()

func end_session():
	_add_session_end_event(session.session_length)

func _add_user_event():
	var event_dict = {
		'category': 'user',
	}
	add_event(event_dict)

func _add_session_end_event(session_length=0):
	var event_dict = {
		'category': 'session_end',
		'length': session_length,
	}
	add_event(event_dict)

func add_progression_event(status, event_id, score=0, attempt_num=1):
	status = status.capitalize()
	if OS.is_debug_build():
		var status_valid = status in ['Start', 'Fail', 'Complete']
		if not status_valid:
			error_log("PROGRESSION: %s is not a valid status." % status)
			assert(0)
	var event_dict = {
		'category': 'progression',
		'event_id': status+':'+_parse_event_id(event_id),
		'score': score,
		'attempt_num': attempt_num,
	}
	add_event(event_dict)

func add_design_event(event_id, value=0):
	var event_dict = {
		'category': 'design',
		'event_id': _parse_event_id(event_id),
		'value': value,
	}
	add_event(event_dict)

func _parse_event_id(event_id):
	if typeof(event_id) in [TYPE_ARRAY, TYPE_STRING_ARRAY]:
		return PoolStringArray(event_id).join(':')
	return event_id

func _merge_dict(target, patch):
	for key in patch:
		target[key] = patch[key]

func _get_ts():
	return {
		'client_ts': OS.get_unix_time() + ts_offset
	}

func _get_session_info():
	return {
		'session_id': session.session_id,
		'session_num': session.session_num,
	}

func _hmac_sha256(p_message, p_key):
	var hash_ctx = HashingContext.new()
	var message = p_message.to_utf8() if typeof(p_message) == TYPE_STRING else p_message
	var key
	if p_key.length() <= 64:
		key = p_key.to_utf8()
	# Hash key if length > 64
	if p_key.length() > 64:
		key =  p_key.sha256_buffer()
	# Right zero padding if key length < 64
	while key.size() < 64:
		key.append('0x00'.hex_to_int())
	var inner = "".to_utf8()
	var o = "".to_utf8()
	for i in range(64):
		o.append(key[i] ^ 0x5c)
		inner.append(key[i] ^ 0x36)
	inner += message
	hash_ctx.start(HashingContext.HASH_SHA256)
	hash_ctx.update(inner)
	var z = hash_ctx.finish()
	var outer = "".to_utf8()
	for i in z:
		outer.append(i)
	outer = o + outer
	hash_ctx.start(HashingContext.HASH_SHA256)
	hash_ctx.update(outer)
	z = hash_ctx.finish()
	outer = "".to_utf8()
	for i in z:
		outer.append(i)
	return outer
