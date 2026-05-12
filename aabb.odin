package main

AABB :: struct {
	x, y, z: Interval,
}

make_aabb :: proc(a, b: Point3) -> AABB {
	x, y, z: Interval
	if (a.x < b.x) {
		x = Interval{a.x, b.x}
	} else {
		x = Interval{b.x, a.x}
	}
	if (a.y < b.y) {
		y = Interval{a.y, b.y}
	} else {
		y = Interval{b.y, a.y}
	}
	if (a.z < b.z) {
		z = Interval{a.z, b.z}
	} else {
		z = Interval{b.z, a.z}
	}
	return {x, y, z}
}

merge_aabbs :: proc(box1, box2: AABB) -> AABB {
	x := merge_intervals(box1.x, box2.x)
	y := merge_intervals(box1.y, box2.y)
	z := merge_intervals(box1.z, box2.z)
	return {x, y, z}
}

axis_interval :: proc(aabb: AABB, n: int) -> Interval {
	if (n == 1) {
		return aabb.y
	}
	if (n == 2) {
		return aabb.z
	}
	return aabb.x
}

hit_aabb :: proc(aabb: AABB, r: Ray, ray_t: Interval) -> bool {
	ray_t := ray_t
	ray_orig := r.origin
	ray_dir := r.direction
	for axis in 0 ..= 2 {
		ax := axis_interval(aabb, axis)
		adinv := 1 / ray_dir[axis]
		t0 := (ax.min - ray_orig[axis]) * adinv
		t1 := (ax.max - ray_orig[axis]) * adinv

		if t0 < t1 {
			if t0 > ray_t.min {
				ray_t.min = t0
			}
			if t1 < ray_t.max {
				ray_t.max = t1
			}
		} else {
			if t1 > ray_t.min {
				ray_t.min = t1
			}
			if t0 < ray_t.max {
				ray_t.max = t0
			}
		}

		if ray_t.max <= ray_t.min {
			return false
		}
	}
	return true
}
