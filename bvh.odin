package main

import "core:math/rand"
import "core:slice"
Bvh_node :: struct {
	left, right: ^Hittable,
	bbox:        AABB,
}

hit_bvh_node :: proc(node: Bvh_node, r: Ray, ray_t: Interval) -> (bool, Hit_Info) {
	if !hit_aabb(node.bbox, r, ray_t) {
		return false, {}
	}

	hit_left, left_info := hit_object(node.left^, r, ray_t)
	hit_right, right_info := hit_object(
		node.right^,
		r,
		{ray_t.min, hit_left ? left_info.t : ray_t.max},
	)

	// right hit will be closer, so use that
	if hit_right {
		return true, right_info
	}
	if hit_left {
		return true, left_info
	}
	return false, {}
}

alloc_hittable :: proc(h: Hittable) -> ^Hittable {
	p := new(Hittable)
	p^ = h
	return p
}

make_bvh_node :: proc(objects: []Hittable, start, end: int) -> Bvh_node {
	node: Bvh_node
	axis := rand.int_range(0, 2)

	comparator := (axis == 0) ? box_x_compare : (axis == 1) ? box_y_compare : box_z_compare

	object_span := end - start

	if (object_span == 1) {
		temp := alloc_hittable(objects[start])
		node.left = temp
		node.right = temp
	} else if (object_span == 2) {
		node.left = alloc_hittable(objects[start])
		node.right = alloc_hittable(objects[start + 1])
	} else {
		slice.sort_by(objects[start:end], comparator)
		mid := start + object_span / 2
		node.left = alloc_hittable(make_bvh_node(objects, start, mid))
		node.right = alloc_hittable(make_bvh_node(objects, mid, end))
	}
	node.bbox = merge_aabbs(get_bbox(node.left^), get_bbox(node.right^))
	return node
}

box_compare :: proc(a, b: Hittable, axis_index: int) -> bool {
	a_axis_interval := axis_interval(get_bbox(a), axis_index)
	b_axis_interval := axis_interval(get_bbox(b), axis_index)
	return a_axis_interval.min < b_axis_interval.min
}

box_x_compare :: proc(a, b: Hittable) -> bool {
	return box_compare(a, b, 0)
}

box_y_compare :: proc(a, b: Hittable) -> bool {
	return box_compare(a, b, 1)
}

box_z_compare :: proc(a, b: Hittable) -> bool {
	return box_compare(a, b, 2)
}
