extends RefCounted

const MIN_HEIGHT = 1.0
const MAX_HEIGHT = 30.0
const HEIGHT_STEP = 0.125
const DEFAULT_HEIGHT = 2.0
const SEGMENT_HEIGHT = 0.5

static func normalized(config: Dictionary) -> Dictionary:
	var result=config.duplicate(true)
	var requested=config.get("support_height",DEFAULT_HEIGHT)
	if not (requested is float or requested is int) or not is_finite(float(requested)): requested=DEFAULT_HEIGHT
	result.support_height=clampf(snappedf(float(requested),HEIGHT_STEP),MIN_HEIGHT,MAX_HEIGHT)
	result.support_double_top=bool(config.get("support_double_top",false))
	return result

static func sections(family: String, config: Dictionary) -> Array[Dictionary]:
	var settings=normalized(config)
	var result: Array[Dictionary]=[]
	var bottom=load("res://resources/pieces/"+family+"-bottom.tres") as PieceDefinition
	var middle=load("res://resources/pieces/"+family+"-middle.tres") as PieceDefinition
	var top=load("res://resources/pieces/"+family+("-top-double.tres" if settings.support_double_top else "-top.tres")) as PieceDefinition
	result.append({"definition":bottom,"transform":Transform3D.IDENTITY,"name":"Bottom"})
	var remaining: float=settings.support_height-1.0
	var elevation=SEGMENT_HEIGHT
	var index=0
	while remaining>0.001:
		var segment=minf(SEGMENT_HEIGHT,remaining)
		var placement=Transform3D(Basis.from_scale(Vector3(1,segment/SEGMENT_HEIGHT,1)),Vector3(0,elevation,0))
		result.append({"definition":middle,"transform":placement,"name":"Middle%d" % index})
		remaining-=segment
		elevation+=segment
		index+=1
	result.append({"definition":top,"transform":Transform3D(Basis.IDENTITY,Vector3(0,settings.support_height-0.5,0)),"name":"Top"})
	return result

static func configured(source: PieceDefinition, config: Dictionary) -> PieceDefinition:
	var result=source.duplicate(false) as PieceDefinition
	var cells=PackedVector3Array()
	var initialized=false
	for section in sections(String(source.id),config):
		var box: AABB=section.transform*section.definition.bounds
		result.bounds=box if not initialized else result.bounds.merge(box)
		initialized=true
		for cell in section.definition.surface_cells: cells.append(section.transform*cell)
	result.surface_cells=cells
	return result
