extends RefCounted
## Offline USGS 3DEP samples, UTM zone 60N. +X east, +Z south, metres.
const LIMIT=24576.0
const SIZE=1025
const SPACING=48.0
var samples: PackedFloat32Array

func _init() -> void:
	var bytes=FileAccess.get_file_as_bytes("res://data/terrain/kiska.f32")
	assert(bytes.size()==SIZE*SIZE*4,"Missing Kiska elevation data; run tools/import_kiska.py")
	samples=bytes.to_float32_array()

func height_at(x: float,z: float) -> float:
	var u=clampf((x+LIMIT)/SPACING,0,SIZE-1.00001)
	var v=clampf((z+LIMIT)/SPACING,0,SIZE-1.00001)
	var ix=int(u)
	var iz=int(v)
	var a=iz*SIZE+ix
	return lerpf(lerpf(samples[a],samples[a+1],u-ix),lerpf(samples[a+SIZE],samples[a+SIZE+1],u-ix),v-iz)
