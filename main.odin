package main
import "core:math"
import la "core:math/linalg"
import "core:math/rand"


Vec3 :: [3]f64
Color :: Vec3
Point3 :: Vec3

Ray :: struct {
	origin:    Point3,
	direction: Vec3,
	time:      f64,
}

Simple_Material :: struct {}

Lambertian_Material :: struct {
	albedo: Color,
}

Metal_Material :: struct {
	albedo: Color,
	fuzz:   f64,
}

Dielectric_Material :: struct {
	refraction_index: f64,
}

Material :: union {
	Simple_Material,
	Lambertian_Material,
	Metal_Material,
	Dielectric_Material,
}

Sphere :: struct {
	center:   Ray,
	radius:   f64,
	material: Material,
	bbox:     AABB,
}

make_static_sphere :: proc(center: Point3, radius: f64, material: Material) -> Sphere {
	rvec := Vec3{radius, radius, radius}
	bbox := make_aabb(center - rvec, center + rvec)
	return {{center, {0, 0, 0}, 0}, max(0, radius), material, bbox}
}

make_moving_sphere :: proc(center1, center2: Point3, radius: f64, material: Material) -> Sphere {
	rvec := Vec3{radius, radius, radius}
	center := Ray{center1, center2 - center1, 0}
	bbox1 := make_aabb(ray_at(center, 0) - rvec, ray_at(center, 0) + rvec)
	bbox2 := make_aabb(ray_at(center, 1) - rvec, ray_at(center, 1) + rvec)
	bbox := merge_aabbs(bbox1, bbox2)
	return {center, max(0, radius), material, bbox}
}

Hit_Info :: struct {
	point:      Point3,
	normal:     Vec3,
	t:          f64,
	front_face: bool,
	material:   Material,
}

Hittable :: union {
	Sphere,
	Bvh_node,
}


set_face_normal :: proc(record: ^Hit_Info, ray: Ray, outward_normal: Vec3) {
	// `outward_normal` is assumed to have unit length
	record.front_face = la.dot(ray.direction, outward_normal) < 0
	record.normal = outward_normal if record.front_face else -outward_normal
}

ray_at :: proc(ray: Ray, t: f64) -> Point3 {
	return ray.origin + t * ray.direction
}

random_vec :: proc() -> Vec3 {
	return {rand.float64(), rand.float64(), rand.float64()}
}

random_vec_2 :: proc(min, max: f64) -> Vec3 {
	return {
		rand.float64_range(min, max),
		rand.float64_range(min, max),
		rand.float64_range(min, max),
	}
}

unit_vector :: proc(v: Vec3) -> Vec3 {
	return v / la.vector_length(v)
}


random_unit_vector :: proc() -> Vec3 {
	for {
		p := random_vec_2(-1, 1)
		lensq := la.dot(p, p)
		if (1e-160 < lensq && lensq <= 1) {
			return p / math.sqrt(lensq)
		}
	}
}

random_on_hemisphere :: proc(normal: Vec3) -> Vec3 {
	on_unit_sphere := random_unit_vector()
	if (la.dot(on_unit_sphere, normal) > 0.0) {
		return on_unit_sphere
	} else {
		return -on_unit_sphere
	}
}

random_in_unit_disk :: proc() -> Vec3 {
	for {
		p := Vec3{rand.float64_range(-1, 1), rand.float64_range(-1, 1), 0}
		lensq := la.dot(p, p)
		if (1e-160 < lensq && lensq < 1) {
			return p
		}
	}
}

is_near_zero :: proc(vec: Vec3) -> bool {
	s := 1e-8
	return abs(vec.x) < s && abs(vec.y) < s && abs(vec.z) < s
}

reflect :: proc(v, n: Vec3) -> Vec3 {
	return v - 2 * la.dot(v, n) * n
}

refract :: proc(uv, n: Vec3, etai_over_etat: f64) -> Vec3 {
	cos_theta := min(la.dot(-uv, n), 1)
	r_out_perp := etai_over_etat * (uv + cos_theta * n)
	r_out_parallel := -math.sqrt(abs(1 - la.dot(r_out_perp, r_out_perp))) * n
	return r_out_perp + r_out_parallel
}

reflectance :: proc(cosine, refraction_index: f64) -> f64 {
	r0 := (1 - refraction_index) / (1 + refraction_index)
	r0 = r0 * r0
	return r0 + (1 - r0) * math.pow(1 - cosine, 5)
}

hit_sphere :: proc(sphere: Sphere, ray: Ray, ray_t: Interval) -> (bool, Hit_Info) {
	current_center := ray_at(sphere.center, ray.time)
	oc := current_center - ray.origin
	a := la.dot(ray.direction, ray.direction)
	h := la.dot(ray.direction, oc)
	c := la.dot(oc, oc) - sphere.radius * sphere.radius
	discriminant := h * h - a * c
	if discriminant < 0 {
		return false, {}
	}
	sqrtd := math.sqrt(discriminant)
	root := (h - sqrtd) / a
	if !interval_surrounds(ray_t, root) {
		root = (h + sqrtd) / a
		if !interval_surrounds(ray_t, root) {
			return false, {}
		}
	}
	t := root
	p := ray_at(ray, t)
	n := (p - current_center) / sphere.radius
	info := Hit_Info{p, n, t, false, sphere.material}
	set_face_normal(&info, ray, n)
	return true, info
}

hit_object :: proc(hittable: Hittable, ray: Ray, ray_t: Interval) -> (hit: bool, info: Hit_Info) {
	switch object in hittable {
	case Sphere:
		hit, info = hit_sphere(object, ray, ray_t)
	case Bvh_node:
		hit, info = hit_bvh_node(object, ray, ray_t)
	}
	return
}

hit_list :: proc(list: Hittable_List, ray: Ray, ray_t: Interval) -> (bool, Hit_Info) {
	info := Hit_Info{}
	hit_anything: bool
	closest_so_far := ray_t.max

	hit: bool
	temp_info: Hit_Info
	for hittable in list.list {
		hit, temp_info = hit_object(hittable, ray, {ray_t.min, closest_so_far})
		if hit {
			hit_anything = true
			closest_so_far = temp_info.t
			info = temp_info
		}
	}
	return hit_anything, info
}

Hittable_List :: struct {
	list: [dynamic]Hittable,
	bbox: AABB,
}

get_bbox :: proc(hittable: Hittable) -> AABB {
	switch object in hittable {
	case Sphere:
		return object.bbox
	case Bvh_node:
		return object.bbox
	}
	unreachable()
}

append_to_world :: proc(world: ^Hittable_List, object: Hittable) {
	append(&world.list, object)
	world.bbox = merge_aabbs(world.bbox, get_bbox(object))
}

main :: proc() {
	world := Hittable_List{make([dynamic]Hittable), {}}

	ground_material := Lambertian_Material{{0.5, 0.5, 0.5}}
	append_to_world(&world, make_static_sphere({0, -1000, 0}, 1000, ground_material))
	for a in -11 ..< 11 {
		for b in -11 ..< 11 {
			choose_mat := rand.float64()
			center := Point3{f64(a) + 0.9 * rand.float64(), 0.2, f64(b) + 0.9 * rand.float64()}
			if la.vector_length(center - {4, 0.2, 0}) > 0.9 {
				sphere_material: Material
				if (choose_mat < 0.8) {
					// diffuse
					albedo := random_vec() * random_vec()
					center2 := center + {0, rand.float64_range(0, 0.5), 0}
					sphere_material := Lambertian_Material{albedo}
					append_to_world(
						&world,
						make_moving_sphere(center, center2, 0.2, sphere_material),
					)
				} else if (choose_mat < 0.95) {
					// metal
					albedo := random_vec_2(0.5, 1)
					fuzz := rand.float64_range(0, 0.5)
					sphere_material := Metal_Material{albedo, fuzz}
					append_to_world(&world, make_static_sphere(center, 0.2, sphere_material))
				} else {
					// glass
					sphere_material = Dielectric_Material{1.5}
					append_to_world(&world, make_static_sphere(center, 0.2, sphere_material))
				}
			}
		}
	}
	material1 := Dielectric_Material{1.5}
	append_to_world(&world, make_static_sphere({0, 1, 0}, 1.0, material1))
	material2 := Lambertian_Material{{0.4, 0.2, 0.1}}
	append_to_world(&world, make_static_sphere({-4, 1, 0}, 1.0, material2))
	material3 := Metal_Material{{0.7, 0.6, 0.5}, 0}
	append_to_world(&world, make_static_sphere({4, 1, 0}, 1.0, material3))

	world_bvh := make_bvh_node(world.list[:], 0, len(world.list))
	world_list := make([dynamic]Hittable)
	world = Hittable_List{world_list, {}}
	append_to_world(&world, world_bvh)

	cam := make_camera(16.0 / 9.0, 20, {13, 2, 3}, {0, 0, 0}, {0, 1, 0}, 0.6, 10, 400, 100, 50)
	render(cam, world)
}

// material_ground := Lambertian_Material{{0.8, 0.8, 0}}
// material_center := Lambertian_Material{{0.1, 0.2, 0.5}}
// material_left := Dielectric_Material{1.5}
// material_bubble := Dielectric_Material{1 / 1.5}
// material_right := Metal_Material{{0.8, 0.6, 0.2}, 1}
// append(&world, make_static_sphere({0.0, -100.5, -1.0}, 100.0, material_ground))
// append(&world, make_static_sphere({0.0, 0.0, -1.2}, 0.5, material_center))
// append(&world, make_static_sphere({-1.0, 0.0, -1.0}, 0.5, material_left))
// append(&world, make_static_sphere({-1.0, 0.0, -1.0}, 0.4, material_bubble))
// append(&world, make_static_sphere({1.0, 0.0, -1.0}, 0.5, material_right))
