import oids, strutils, endians

type
  WkbByteOrder* = enum
    wkbXDR  # Big Endian
    wkbNDR  # Little Endian

  # fix the size: 4byte, write directly
  WkbGeometryType*{.size: sizeof(cint).} = enum 
    wkbNull
    wkbPoint
    wkbLineString
    wkbPolygon
    wkbMultiPoint
    wkbMultiLineString
    wkbMultiPolygon
    wkbGeometryCollection

  Coord* = ref CoordObj
  CoordObj* = object
    x*: float64
    y*: float64

  Point* = ref PointObj
  PointObj* = object
    srid*: uint32
    coord*: Coord

  LineString* = ref LineStringObj
  LineStringObj* = object
    srid*: uint32
    coords*: seq[Coord]

  Polygon* = ref PolygonObj
  PolygonObj* = object
    srid*: uint32
    rings*: seq[seq[Coord]]

  MultiPoint* = object
    srid*: uint32
    points: seq[Point]

  Geometry* = ref GeometryObj
  GeometryObj* = object
    case kind*: WkbGeometryType
    of wkbPoint:
      pt*: Point
    of wkbLineString:
      ls*: LineString
    of wkbPolygon:
      pg*: Polygon
    else: discard

proc `==`*(a, b: Coord): bool =
  return (a.x == b.x) and (a.y == b.y)

proc `==`*(a, b: Point): bool =
  return (a.srid == b.srid) and (a.coord.x == b.coord.x) and (a.coord.y == b.coord.y)

proc `==`*(a, b: LineString): bool =
  return (a.srid == b.srid) and (a.coords == b.coords)

proc `==`*(a, b: Polygon): bool =
  return (a.srid == b.srid) and (a.rings == b.rings)

proc `==`*(a, b: Geometry): bool =
  result = a.kind == b.kind
  case a.kind:
    of wkbPoint: result = result and (a.pt == b.pt)
    of wkbLineString: result = result and (a.ls == b.ls)
    of wkbPolygon: result = result and (a.pg == b.pg)
    else: discard

proc swapEndian32(p: pointer) =
  var o = cast[cstring](p)
  (o[0], o[1], o[2], o[3]) = (o[3], o[2], o[1], o[0])

proc swapEndian64(p: pointer) =
  var o = cast[cstring](p)
  (o[0], o[1], o[2], o[3], o[4], o[5], o[6], o[7]) = (o[7], o[6], o[5], o[4], o[3], o[2], o[1], o[0])

proc parseEndian(str: cstring): WkbByteOrder =
  return WkbByteOrder((hexbyte(str[0]) shl 4) or hexbyte(str[1]))

proc parseGeometryType(str: cstring, bswap: bool): (WkbGeometryType, bool) =
  var bytes = cast[cstring](addr result[0]) 
  for i in 1..5:
    bytes[i - 1] = chr((hexbyte(str[2 * i]) shl 4) or hexbyte(str[2 * i + 1]))

  if bswap: swapEndian32(bytes)
  # check has srid
  if bytes[3] == chr(0x20):
    bytes[3] = chr(0x00)
    result[1] = true
  else:
    result[1] = false

proc parseuint32(str: cstring, pos: var int, bswap: bool): uint32 =
  var bytes = cast[cstring](addr result)
  for i in 0..3:
    bytes[i] = chr((hexbyte(str[2 * pos]) shl 4) or hexbyte(str[2 * pos + 1]))
    inc pos
  
  if bswap:
    swapEndian32(bytes)

proc parseCoord(str: cstring, pos: var int, bswap: bool): Coord =
  new(result)
  var bytes = cast[cstring](result)
  for i in 0..15:
    bytes[i] = chr((hexbyte(str[2 * pos]) shl 4) or hexbyte(str[2 * pos + 1]))
    inc pos

  if bswap:
    swapEndian64(addr result.x)
    swapEndian64(addr result.y)

proc parseCoords(str: cstring, pos: var int, bswap: bool): seq[Coord] =
  let n = parseuint32(str, pos, bswap)
  for i in 1..n:
    let coord = parseCoord(str, pos, bswap)
    result.add(coord)

proc parseRings(str: cstring, pos: var int, bswap: bool): seq[seq[Coord]] =
  let ringnum = parseuint32(str, pos, bswap)
  for i in 1..ringnum:
    let coords = parseCoords(str, pos, bswap)
    result.add(coords)

proc parseWkbPoint(str: cstring, pos: var int, bswap: bool): Point =
  new(result)
  result.coord = parseCoord(str, pos, bswap)

proc parseWkbLineString(str: cstring, pos: var int, bswap: bool): LineString =
  new(result)
  result.coords = parseCoords(str, pos, bswap)

proc parseWkbPolygon(str: cstring, pos: var int, bswap: bool): Polygon =
  new(result)
  result.rings = parseRings(str, pos, bswap)

proc parseWkb*(str: cstring): Geometry =
  let endian = parseEndian(str)
  # echo endian
  let bswap = (endian == WkbByteOrder(system.cpuEndian)) # littleEndian = 0, but wkbNDR = 1
  # echo bswap
  let (wkbType, hasSrid) = parseGeometryType(str, bswap)
  # echo hasSrid
  var pos = 5 # 解析的起点
  var srid: uint32
  if hasSrid: srid = parseuint32(str, pos, bswap)

  case wkbType:
  of wkbPoint:
    var pt = parseWkbPoint(str, pos, bswap)
    if hasSrid: pt.srid = srid
    result = Geometry(kind: wkbPoint, pt: pt)
  of wkbLineString:
    var ls = parseWkbLineString(str, pos, bswap)
    if hasSrid: ls.srid = srid
    result = Geometry(kind:  wkbLineString, ls: ls)
  of wkbPolygon:
    var pg = parseWkbPolygon(str, pos, bswap)
    if hasSrid: pg.srid = srid
    result = Geometry(kind: wkbPolygon, pg: pg)
  else: discard
