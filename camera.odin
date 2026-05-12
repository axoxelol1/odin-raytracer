package main

import "core:fmt"
import "core:math"
import la "core:math/linalg"
import "core:math/rand"
import "core:os"
import "core:sync"
import "core:thread"

Camera :: struct {
	aspect_ratio:                   f64,
	image_width:                    int,
	image_height:                   int,
	center:                         Point3,
	pixel_delta_u:                  Vec3,
	pixel_delta_v:                  Vec3,
	pixel00_loc:                    Point3,
	samples_per_pixel:              int,
	max_depth:                      int,
	vfov:                           f64,
	lookfrom, lookat:               Point3,
	vup:                            Vec3,
	u, v, w:                        Vec3,
	defocus_angle, focus_dist:      f64,
	defocus_disc_u, defocus_disc_v: Vec3,
}

make_camera :: proc(
	aspect_ratio, vfov: f64,
	lookfrom, lookat: Point3,
	vup: Vec3,
	defocus_angle, focus_dist: f64,
	image_width, samples_per_pixel, max_depth: int,
) -> Camera {
	cam: Camera
	cam.aspect_ratio = aspect_ratio
	cam.vfov = vfov
	cam.image_width = image_width
	cam.image_height = max(1, int(f64(cam.image_width) / cam.aspect_ratio))
	cam.samples_per_pixel = samples_per_pixel
	cam.max_depth = max_depth
	cam.lookfrom = lookfrom
	cam.lookat = lookat
	cam.vup = vup
	cam.defocus_angle = defocus_angle
	cam.focus_dist = focus_dist

	cam.center = cam.lookfrom

	theta := cam.vfov * la.RAD_PER_DEG
	h := la.tan(theta / 2)
	viewport_height: f64 = 2 * h * cam.focus_dist
	viewport_width := viewport_height * f64(cam.image_width) / f64(cam.image_height)

	cam.w = unit_vector(cam.lookfrom - cam.lookat)
	cam.u = unit_vector(la.cross(cam.vup, cam.w))
	cam.v = la.cross(cam.w, cam.u)

	viewport_u := viewport_width * cam.u
	viewport_v := viewport_height * -cam.v

	cam.pixel_delta_u = viewport_u / f64(cam.image_width)
	cam.pixel_delta_v = viewport_v / f64(cam.image_height)

	viewport_upper_left := cam.center - (cam.focus_dist * cam.w) - viewport_u / 2 - viewport_v / 2
	cam.pixel00_loc = viewport_upper_left + 0.5 * (cam.pixel_delta_u + cam.pixel_delta_v)

	defocus_radius := focus_dist * la.tan(cam.defocus_angle / 2 * la.RAD_PER_DEG)
	cam.defocus_disc_u = cam.u * defocus_radius
	cam.defocus_disc_v = cam.v * defocus_radius
	return cam
}

render :: proc(cam: Camera, world: Hittable_List) {
	pool: thread.Pool
	colors := make([dynamic]Color, cam.image_width * cam.image_height)
	task_data := make([dynamic]Thread_Data, cam.image_height)
	// Threads make to initializations so non-thread safe context.allocator should be fine
	thread.pool_init(&pool, context.allocator, os.get_processor_core_count())
	defer thread.pool_destroy(&pool)
	defer delete(task_data)
	done_count: int

	Thread_Data :: struct {
		cam:        Camera,
		colors:     []Color,
		world:      Hittable_List,
		j:          int,
		done_count: ^int,
	}

	thread_work :: proc(t: thread.Task) {
		data := cast(^Thread_Data)t.data
		cam := data.cam
		colors := data.colors
		world := data.world
		j := data.j
		done_count := data.done_count
		context.random_generator = rand.default_random_generator({})

		for i in 0 ..< cam.image_width {
			color: Color
			for sample in 0 ..< cam.samples_per_pixel {
				color += ray_color(get_ray(cam, i, j), cam.max_depth, world)
			}
			colors[j * cam.image_width + i] = color
		}
		sync.atomic_add(done_count, 1)
		fmt.fprintf(os.stderr, "Scanlines left: {}     \r", cam.image_height - done_count^)
	}

	for j in 0 ..< cam.image_height {
		task_data[j] = Thread_Data{cam, colors[:], world, j, &done_count}
		thread.pool_add_task(&pool, context.allocator, thread_work, &task_data[j], j)
	}
	thread.pool_start(&pool)
	thread.pool_finish(&pool)
	fmt.printf("P3\n{} {}\n255\n", cam.image_width, cam.image_height)
	for color in colors {
		write_color(os.stdout, color / f64(cam.samples_per_pixel))
	}
}


ray_color :: proc(ray: Ray, depth: int, world: Hittable_List) -> Color {
	if (depth <= 0) {
		return {0, 0, 0}
	}
	hit, info := hit_list(world, ray, Interval{0.001, math.inf_f64(1)})
	if hit {
		scattered_dir: Vec3
		absorbed: bool
		attenuation := Color{0.5, 0.5, 0.5}
		switch material in info.material {
		case Simple_Material:
			scattered_dir = random_on_hemisphere(info.normal)
			absorbed = false
		case Lambertian_Material:
			scattered_dir = info.normal + random_unit_vector()
			if is_near_zero(scattered_dir) {
				scattered_dir = info.normal
			}
			absorbed = false
			attenuation = material.albedo
		case Metal_Material:
			scattered_dir = reflect(ray.direction, info.normal)
			scattered_dir = unit_vector(scattered_dir) + (material.fuzz * random_unit_vector())
			absorbed = la.dot(scattered_dir, info.normal) <= 0
			attenuation = material.albedo
		case Dielectric_Material:
			attenuation = {1, 1, 1}
			ri := info.front_face ? 1 / material.refraction_index : material.refraction_index
			unit_direction := unit_vector(ray.direction)
			cos_theta := min(la.dot(-unit_direction, info.normal), 1)
			sin_theta := la.sqrt(1 - cos_theta * cos_theta)
			if (ri * sin_theta > 1 || reflectance(cos_theta, ri) > rand.float64()) {
				scattered_dir = reflect(unit_direction, info.normal)
			} else {
				scattered_dir = refract(unit_direction, info.normal, ri)
			}
			absorbed = false
		}

		if !absorbed {
			return attenuation * ray_color({info.point, scattered_dir, ray.time}, depth - 1, world)
		} else {
			return {0, 0, 0}
		}
	}

	unit_dir := unit_vector(ray.direction)
	a := 0.5 * (unit_dir.y + 1)
	return (1 - a) * Color{1, 1, 1} + a * Color{0.5, 0.7, 1.0}
}

write_color :: proc(out: ^os.File, color: Color) {
	intensity := Interval{0, 0.999}
	ir := int(255.999 * clamp_to_interval(intensity, linear_to_gamma(color.r)))
	ig := int(255.999 * clamp_to_interval(intensity, linear_to_gamma(color.g)))
	ib := int(255.999 * clamp_to_interval(intensity, linear_to_gamma(color.b)))
	fmt.fprintf(out, "{} {} {}\n", ir, ig, ib)
}

get_ray :: proc(cam: Camera, i, j: int) -> Ray {
	offset := Vec3{rand.float64() - 0.5, rand.float64() - 0.5, 0}
	pixel_sample :=
		cam.pixel00_loc +
		((f64(i) + offset.x) * cam.pixel_delta_u) +
		((f64(j) + offset.y) * cam.pixel_delta_v)
	ray_origin := (cam.defocus_angle <= 0) ? cam.center : defocus_disk_sample(cam)
	ray_time := rand.float64()
	return {ray_origin, pixel_sample - ray_origin, ray_time}
}

defocus_disk_sample :: proc(cam: Camera) -> Point3 {
	p := random_in_unit_disk()
	return cam.center + (p.x * cam.defocus_disc_u) + (p.y * cam.defocus_disc_v)
}

linear_to_gamma :: proc(linear_component: f64) -> f64 {
	if linear_component > 0 {
		return la.sqrt(linear_component)
	}
	return 0
}
