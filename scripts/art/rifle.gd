extends Node3D
## Original RX-24 silhouette: machined receiver, vented handguard, rail and optic.
const P = preload("res://scripts/art/mesh_parts.gd")
func _ready() -> void:
	var steel := P.material("242c32", 0.8, 0.32)
	var polymer := P.material("343d3c", 0.1)
	var trim := P.material("747b78", 0.75, 0.3)
	var black := P.material("101719", 0.1)
	var tan := P.material("a4916d", 0.15)
	P.box(self, Vector3(0,0,0), Vector3(.075,.105,.30), steel)
	P.box(self, Vector3(0,.035,-.22), Vector3(.068,.07,.18), polymer)
	P.cylinder(self, Vector3(0,.02,-.39), .014,.19,steel,Vector3(PI/2,0,0))
	P.cylinder(self, Vector3(0,.02,-.49), .021,.055,black,Vector3(PI/2,0,0))
	P.box(self, Vector3(0,-.10,.065), Vector3(.048,.15,.065),polymer,Vector3(-.3,0,0))
	P.box(self, Vector3(0,-.14,-.045), Vector3(.05,.19,.085),tan,Vector3(.15,0,0))
	P.box(self, Vector3(0,.005,.21), Vector3(.055,.065,.15),steel)
	P.box(self, Vector3(0,-.015,.30), Vector3(.07,.13,.095),polymer)
	P.box(self, Vector3(0,-.02,.355), Vector3(.075,.145,.018),black)
	for i in range(15):
		P.box(self, Vector3(0,.064,-.29+i*.025),Vector3(.085,.012,.012),trim)
	for side in [-1,1]:
		for i in range(6):
			P.box(self,Vector3(side*.035,.025,-.29+i*.025),Vector3(.005,.025,.012),black)
		for i in range(4):
			P.box(self,Vector3(side*.026,-.14+i*.028,-.046),Vector3(.004,.007,.077),polymer)
		for z in [-.08,.08]:
			P.cylinder(self,Vector3(side*.039,0,z),.008,.004,trim,Vector3(0,0,PI/2))
	P.box(self,Vector3(.043,.014,.045),Vector3(.015,.024,.09),black)
	P.box(self,Vector3(.055,.02,.065),Vector3(.035,.014,.015),trim)
	# Open reflex sight frame; no opaque lens obstructs ADS.
	P.box(self,Vector3(0,.078,.02),Vector3(.075,.025,.07),polymer)
	for side in [-1,1]:
		P.box(self,Vector3(side*.034,.112,.02),Vector3(.009,.055,.018),steel)
	P.box(self,Vector3(0,.14,.02),Vector3(.075,.009,.018),steel)
	P.box(self,Vector3(0,-.098,.015),Vector3(.052,.012,.075),steel)
	P.merge_static(self)
