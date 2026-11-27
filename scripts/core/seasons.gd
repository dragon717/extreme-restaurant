extends RefCounted
## Chapter days, restored games and title previews share this calendar.
const NAMES := ["春季","夏季","秋季","冬季"]
const DAYS_PER_SEASON := 7
const COLORS := [Color("f6cfbb"),Color("d0e5aa"),Color("cf9158"),Color("c7dfeb")]

static func at_day(day: int) -> int:
	@warning_ignore("integer_division")
	return ((maxi(day,1)-1) / DAYS_PER_SEASON) % NAMES.size()

static func weights(index: int) -> Vector3:
	return Vector3(float(index == 1),float(index == 2),float(index == 3))
