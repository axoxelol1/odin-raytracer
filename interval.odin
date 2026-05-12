package main

import "core:math"

Interval :: struct {
	min: f64,
	max: f64,
}

interval_size :: proc(interval: Interval) -> f64 {
	return interval.max - interval.min
}

interval_contains :: proc(interval: Interval, x: f64) -> bool {
	return interval.min <= x && x <= interval.max
}

interval_surrounds :: proc(interval: Interval, x: f64) -> bool {
	return interval.min < x && x < interval.max
}

clamp_to_interval :: proc(interval: Interval, x: f64) -> f64 {
	if x < interval.min {
		return interval.min
	}
	if x > interval.max {
		return interval.max
	}
	return x
}

interval_pad :: proc(interval: Interval, delta: f64) -> Interval {
	padding := delta / 2
	return {interval.min - padding, interval.max + padding}
}

merge_intervals :: proc(a, b: Interval) -> Interval {
	min, max: f64
	if a.min <= b.min {
		min = a.min
	} else {
		min = b.min
	}
	if a.max >= b.max {
		max = a.max
	} else {
		max = b.max
	}
	return {min, max}
}

empty_interval := Interval{math.inf_f64(1), math.inf_f64(-1)}
universe_interval := Interval{math.inf_f64(-1), math.inf_f64(1)}
