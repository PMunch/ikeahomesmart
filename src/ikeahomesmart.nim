import asyncdispatch, os, json, options
import coap

type
  DeviceId* = distinct int
  GroupId* = distinct int
  Info* = object
    manufacturer*: string
    product*: string
    firmware*: string
    battery*: Option[int]
  DeviceKind* = enum
    Switch = 0, Bulb = 2
  Device* = object
    id*: DeviceId
    name*: string
    created*: int
    lastSeen*: int
    reachable*: bool
    info*: Info
    case kind*: DeviceKind
    of Switch: discard
    of Bulb:
      bulbData*: BulbData
  BulbKind* = enum Invalid = 0, Dimmable = 2, Color = 3, ColorTemp = 5
  BulbData* = object
    on*: bool
    brightness*: int
    color*: string
    colorX*: int
    colorY*: int
    unknown*: int
    case kind*: BulbKind
    of Invalid: discard
    of Color:
      hue*: int
      saturation*: int
    of ColorTemp:
      temperature*: int
      u2*: int
    of Dimmable:
      u3*: int
  Group* = object
    name*: string
    id*: GroupId
    created*: int
    on*: bool
    brightness*: int
    devices*: seq[DeviceId]
  IkeaError* = object of CatchableError

proc `$`*(did: DeviceId): string = $did.int
proc `$`*(gid: GroupId): string = $gid.int

proc getAllDevices*(session: Session): Future[seq[DeviceId]] {.async.} =
  let reply = await session.getMessage("15001")
  if reply.code != Coapresponsecodecontent:
    raise newException(IkeaError, "Unable to get devices")
  for device in cast[string](reply.data).parseJson:
    result.add device.getInt.DeviceId

proc getAllGroups*(session: Session): Future[seq[GroupId]] {.async.} =
  let reply = await session.getMessage("15004")
  if reply.code != Coapresponsecodecontent:
    raise newException(IkeaError, "Unable to get groups")
  for group in cast[string](reply.data).parseJson:
    result.add group.getInt.GroupId

proc getDeviceInfo*(session: Session, did: DeviceId): Future[Device] {.async.} =
  let reply = await session.getMessage("15001/" & $did)
  if reply.code != Coapresponsecodecontent:
    raise newException(IkeaError, "Unable to get device info")
  let data = cast[string](reply.data).parseJson
  #echo data.pretty
  result = Device(kind: data["5750"].getInt.DeviceKind)
  result.id = data["9003"].getInt.DeviceId
  result.name = data["9001"].getStr
  result.created = data["9002"].getInt
  result.lastSeen = data["9020"].getInt
  result.reachable = data["9019"].getInt == 1
  result.info.manufacturer = data["3"]["0"].getStr
  result.info.product = data["3"]["1"].getStr
  result.info.firmware = data["3"]["3"].getStr
  if data["3"].hasKey("9"):
    result.info.battery = some(data["3"]["9"].getInt)
  case result.kind:
  of Bulb:
    result.bulbData = BulbData(kind: data["3"]["8"].getInt.BulbKind)
    result.bulbData.on = data["3311"][0]["5850"].getInt == 1
    result.bulbData.brightness = data["3311"][0]["5851"].getInt
    result.bulbData.unknown = data["3311"][0]["5849"].getInt
    if result.bulbData.kind in {Color, ColorTemp}:
      result.bulbData.color = data["3311"][0]["5706"].getStr
      result.bulbData.colorX = data["3311"][0]["5709"].getInt
      result.bulbData.colorY = data["3311"][0]["5710"].getInt
    case result.bulbData.kind:
    of Color:
      result.bulbData.hue = data["3311"][0]["5707"].getInt
      result.bulbData.saturation = data["3311"][0]["5708"].getInt
    of ColorTemp:
      result.bulbData.temperature = data["3311"][0]["5711"].getInt
      result.bulbData.u2 = data["3311"][0]["5717"].getInt
    of Dimmable:
      result.bulbData.u3 = data["3311"][0]["9003"].getInt
    of Invalid: discard
  of Switch: discard

proc getGroupInfo*(session: Session, gid: GroupId): Future[Group] {.async.} =
  let reply = await session.getMessage("15004/" & $gid)
  if reply.code != Coapresponsecodecontent:
    raise newException(IkeaError, "Unable to get group info: " & $reply.code)
  let data = cast[string](reply.data).parseJson
  #echo data.pretty
  result.name = data["9001"].getStr
  result.id = data["9003"].getInt.GroupId
  result.created = data["9002"].getInt
  result.on = data["5850"].getInt == 1
  result.brightness = data["5851"].getInt
  for device in data["9018"]["15002"]["9003"]:
    result.devices.add device.getInt.DeviceId

proc setBrightness*(session: Session, device: DeviceId, value: int): Future[void] {.async.} =
  let reply = await session.putMessage("15001/" & $device, $(%*{"3311": [{"5851": value}]}))
  #echo reply
  if reply.code != Coapresponsecodechanged:
    raise newException(IkeaError, "Unable to set device brightness")
  let data = cast[string](reply.data)

proc setWarmth*(session: Session, device: DeviceId, temp: int): Future[void] {.async.} =
  let reply = await session.putMessage("15001/" & $device, $(%*{"3311": [{"5711": temp}]}))
  #echo reply
  if reply.code != Coapresponsecodechanged:
    raise newException(IkeaError, "Unable to set device temperature")
  let data = cast[string](reply.data)

proc setColor*(session: Session, device: DeviceId, x, y: int): Future[void] {.async.} =
  let reply = await session.putMessage("15001/" & $device, $(%*{"3311": [{"5709": x, "5710": y}]}))
  #echo reply
  if reply.code != Coapresponsecodechanged:
    raise newException(IkeaError, "Unable to set device color")
  let data = cast[string](reply.data)

when isMainModule:
  var
    address = newAddress("192.168.1.69", "5684")
    context = newContext()
    session = newClientSession(context, address, Dtls, "myuser", "yourkeygoeshere")

  let groups = waitFor session.getAllGroups()
  for group in groups:
    let groupInfo = waitFor session.getGroupInfo(group.GroupId)
    echo groupInfo.name, ":"
    var devices: seq[Future[Device]]
    for device in groupInfo.devices:
      devices.add session.getDeviceInfo(device)
    for device in waitFor all(devices):
      if device.kind == Bulb:
        echo "\t", device.id, " ", device.name, " ", device.bulbData.kind
