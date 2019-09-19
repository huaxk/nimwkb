import endians

import geometry

type
  WkbWriter* = ref object
    data: seq[byte]
    pos: int
    bytesOrder: WkbByteOrder

##  write to wkb

proc toByte*(x: uint32, byteOrder: WkbByteOrder): array[4, byte] =
  var
    x = x
    y = x
  if cpuEndian != byteOrder:
    if cpuEndian == littleEndian:
      bigEndian32(addr y, addr x)
    else:
      littleEndian32(addr y, addr x)
  return cast[array[4, byte]](y)

proc toByte*(x: float64, byteOrder: WkbByteOrder): array[8, byte] =
  var
    x = x
    y = x
  #  TODO: 代码与前面重复，因为pointer不能赋值，重构成有问题
  if cpuEndian != byteOrder:        
    if cpuEndian == littleEndian:
      bigEndian64(addr y, addr x)
    else:
      littleEndian64(addr y, addr x)
  return cast[array[8, byte]](y)

proc toByte*(coord: Coord, byteOrder: WkbByteOrder): seq[byte] =
  result &= coord.x.toByte(byteOrder)
  result &= coord.y.toByte(byteOrder)

proc toByte(typ: WkbGeometryType, byteOrder: WkbByteOrder, hasSrid: bool):
            array[4, byte] =
  result = typ.uint32.toByte(byteorder)
  if hasSrid:
    if byteOrder == wkbNDR:
      result[3] = 0x20
    else:
      result[0] = 0x20
    
proc bytehex*(byt: byte): string =
  const HexChars = "0123456789ABCDEF"
  let lower = byt and 0b00001111
  let height = (byt and 0b11110000) shr 4
  return HexChars[height] & HexChars[lower]

proc toHex*(bytes: seq[byte]): string =
  result = newString(2*bytes.len)
  var i = 0
  for b in bytes:
    let hex = bytehex(b)
    result[i] = hex[0]
    result[i+1] = hex[1]
    i += 2

proc newWkbWriter*(bytesOrder: WkbByteOrder): WkbWriter =
  new(result)
  result.bytesOrder = bytesOrder

proc write(w: WkbWriter, pt: Point, bytesOrder: WkbByteOrder) =
  let
    typ = wkbPoint
    hasSrid = pt.srid != 0
  w.data &= bytesOrder.byte
  w.data &= typ.toByte(bytesOrder, hasSrid)
  if hasSrid:
    w.data &= pt.srid.toByte(bytesOrder)
  w.data &= pt.coord.toByte(bytesOrder)

proc write(w: WkbWriter, ls: LineString, bytesOrder: WkbByteOrder) =
  let
    typ = wkbLineString
    hasSrid = ls.srid != 0
    length = ls.coords.len
  w.data &= bytesOrder.byte
  w.data &= typ.toByte(bytesOrder, hasSrid)
  if hasSrid:
    w.data &= ls.srid.toByte(bytesOrder)
  w.data &= length.uint32.toByte(bytesOrder)
  for i in countup(0, length-1):
    w.data &= ls.coords[i].toByte(bytesOrder)

proc write(w: WkbWriter, pg: Polygon, bytesOrder: WkbByteOrder) =
  let
    typ = wkbPolygon
    hasSrid = pg.srid != 0
    ringnum = pg.rings.len
  w.data &= bytesOrder.byte
  w.data &= typ.toByte(bytesOrder, hasSrid)
  if hasSrid:
    w.data &= pg.srid.toByte(bytesOrder)
  w.data &= ringnum.uint32.toByte(bytesOrder)
  for i in countup(0, ringnum-1):
    let
      coords = pg.rings[i]
      coordnum = coords.len
    w.data &= coordnum.uint32.toByte(bytesOrder)
    for j in countup(0, coordnum-1):
      w.data &= coords[j].toByte(bytesOrder)

proc write(w: WkbWriter, geo: Geometry, byteOrder: WkbByteOrder) =
  let kind = geo.kind
  case kind:
  of wkbPoint:
    w.write(geo.pt, byteOrder)
  of wkbLineString:
    w.write(geo.ls, byteOrder)
  of wkbPolygon:
    w.write(geo.pg, byteOrder)
  else: discard

proc toWkb*(geo: Geometry, byteOrder: WkbByteOrder = wkbNDR): string =
  var wkbWriter = newWkbWriter(byteOrder)
  wkbWriter.write(geo, byteOrder)
  return wkbWriter.data.toHex()