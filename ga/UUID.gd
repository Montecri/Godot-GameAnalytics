class_name UUID
static func get_random_int(max_value, randomize_=false):
	var rand = RandomNumberGenerator.new()
	if randomize_:
		rand.randomize()
	return rand.randi() % max_value

static func random_bytes(n, randomize_=false):
	var r = []
	for i in range(0, n):
		r.append(get_random_int(256, randomize_))
	return r

static func uuid_bin(randomize_=false):
	var b = random_bytes(16, randomize_)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return b

static func v4(randomize_=true):
	var b = uuid_bin(randomize_)
	var low = '%02x%02x%02x%02x' % [b[0], b[1], b[2], b[3]]
	var mid = '%02x%02x' % [b[4], b[5]]
	var hi = '%02x%02x' % [b[6], b[7]]
	var clock = '%02x%02x' % [b[8], b[9]]
	var node = '%02x%02x%02x%02x%02x%02x' % [b[10], b[11], b[12], b[13], b[14], b[15]]
	return '%s-%s-%s-%s-%s' % [low, mid, hi, clock, node]
